import '../core/ad_config.dart';
import '../core/ad_enums.dart';

/// 广告展示被拦截的原因。
enum AdGuardBlockReason {
  /// 当前已有全屏广告正在展示（互斥）
  fullscreenShowing,

  /// 同一广告位的 CD 冷却未结束
  samePlacementCooldown,

  /// 跨广告位的全局 CD 冷却未结束
  differentPlacementCooldown,
}

class AdGuardResult {
  const AdGuardResult.allowed()
    : allowed = true,
      reason = null,
      retryAfterSeconds = null,
      relatedPlacement = null;

  const AdGuardResult.blocked({
    required this.reason,
    this.retryAfterSeconds,
    this.relatedPlacement,
  }) : allowed = false;

  final bool allowed;
  final AdGuardBlockReason? reason;
  final int? retryAfterSeconds;
  final PlacementType? relatedPlacement;
}

/// 广告展示策略守卫。
///
/// 负责 CD 冷却（Same CD / Global CD）和全屏互斥检查。
/// 所有检查由 JSON 配置中的 [PlacementPolicy] 驱动，不经代码硬编码。
///
/// ## 冷却逻辑
/// - 同广告位冷却：同一个 placement 在 `same_placement_cd` 秒内重复触发会被拦截
/// - 跨广告位冷却：刚展示过其他全屏 placement 后，`different_placement_cd` 秒内展示当前 placement 会被拦截
/// - 全屏互斥：同一时间只允许一个全屏广告展示
class AdDisplayGuard {
  final Map<PlacementType, DateTime> _lastShownByPlacement = {};
  DateTime? _lastGlobalShownAt;
  PlacementType? _lastGlobalPlacement;
  bool _isFullscreenShowing = false;

  /// 检查是否可以展示指定广告位的广告。
  Future<AdGuardResult> canShow({
    required PlacementType placement,
    required AdConfigRepository configRepository,
  }) async {
    final config = await configRepository.getConfig();
    final policy = config.getPolicy(placement);
    if (!policy.isFullscreen) {
      return const AdGuardResult.allowed();
    }

    if (_isFullscreenShowing) {
      return const AdGuardResult.blocked(
        reason: AdGuardBlockReason.fullscreenShowing,
      );
    }

    final now = DateTime.now();
    if (policy.applySamePlacementCd) {
      final last = _lastShownByPlacement[placement];
      if (last != null) {
        final elapsed = now.difference(last).inSeconds;
        if (elapsed < config.samePlacementCdSeconds) {
          return AdGuardResult.blocked(
            reason: AdGuardBlockReason.samePlacementCooldown,
            retryAfterSeconds: config.samePlacementCdSeconds - elapsed,
            relatedPlacement: placement,
          );
        }
      }
    }

    if (policy.applyDifferentPlacementCd) {
      final lastGlobalShownAt = _lastGlobalShownAt;
      final lastGlobalPlacement = _lastGlobalPlacement;
      if (lastGlobalShownAt != null &&
          lastGlobalPlacement != null &&
          lastGlobalPlacement != placement &&
          now.difference(lastGlobalShownAt).inSeconds <
              config.differentPlacementCdSeconds) {
        final elapsed = now.difference(lastGlobalShownAt).inSeconds;
        return AdGuardResult.blocked(
          reason: AdGuardBlockReason.differentPlacementCooldown,
          retryAfterSeconds: config.differentPlacementCdSeconds - elapsed,
          relatedPlacement: lastGlobalPlacement,
        );
      }
    }

    return const AdGuardResult.allowed();
  }

  /// 广告开始展示时调用，标记全屏互斥状态。
  void markShowStarted(PlacementType placement, PlacementPolicy policy) {
    if (policy.isFullscreen) {
      _isFullscreenShowing = true;
    }
  }

  /// 广告正常关闭时调用，记录 CD 时间并清除互斥标记。
  void markShowCompleted(PlacementType placement, PlacementPolicy policy) {
    final now = DateTime.now();
    _lastShownByPlacement[placement] = now;

    if (policy.contributesToGlobalCooldown) {
      _lastGlobalShownAt = now;
      _lastGlobalPlacement = placement;
    }
    _isFullscreenShowing = false;
  }

  /// 广告展示失败时调用，仅清除互斥标记，不记录 CD 时间。
  void markShowFailed(PlacementType placement, PlacementPolicy policy) {
    if (policy.isFullscreen) {
      _isFullscreenShowing = false;
    }
  }
}
