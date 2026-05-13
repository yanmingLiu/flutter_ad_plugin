import '../core/ad_config.dart';
import '../core/ad_enums.dart';

enum AdGuardBlockReason {
  fullscreenShowing,
  samePlacementCooldown,
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

class AdDisplayGuard {
  final Map<PlacementType, DateTime> _lastShownByPlacement = {};
  DateTime? _lastGlobalShownAt;
  PlacementType? _lastGlobalPlacement;
  bool _isFullscreenShowing = false;

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

  void markShowStarted(PlacementType placement, PlacementPolicy policy) {
    if (policy.isFullscreen) {
      _isFullscreenShowing = true;
    }
  }

  void markShowCompleted(PlacementType placement, PlacementPolicy policy) {
    final now = DateTime.now();
    _lastShownByPlacement[placement] = now;

    if (policy.contributesToGlobalCooldown) {
      _lastGlobalShownAt = now;
      _lastGlobalPlacement = placement;
    }
    _isFullscreenShowing = false;
  }

  void markShowFailed(PlacementType placement, PlacementPolicy policy) {
    if (policy.isFullscreen) {
      _isFullscreenShowing = false;
    }
  }
}
