import 'package:flutter/widgets.dart';

import '../core/ad_config.dart';
import '../core/ad_enums.dart';
import '../core/ad_models.dart';
import '../utils/cancellation_token.dart';
import 'ad_callback.dart';

/// Abstract interface for ad type adapters (AdMob, MAX, TopOn, etc.).
///
/// Each ad platform provides one implementation per ad type
/// (open/interstitial/rewarded/native/banner). The engine discovers
/// adapters via [AdAdapterRegistry] by source + type pair.
///
/// ## Raw Callbacks (callback externalization)
/// Adapters emit [AdRawCallback] via [onCallback] instead of calling
/// [AdEventReporter] directly. The engine layer converts callbacks to
/// [AdEvent] through [AdEventMapper] and reports them.
/// This keeps adapters pure (load/show only) and decouples reporting.
///
/// ## show() 的 await 行为
/// [show] 应阻塞直到用户关闭广告（或展示失败）才返回 [AdShowResult]。
/// 这样可以实现连续调用两次 show() 逐个弹出的效果。
///
/// ---
/// 广告类型适配器的抽象接口。每个平台为每种广告类型提供一个实现。
/// 适配器通过 [onCallback] 发出 [AdRawCallback]，而非直接调用
/// [AdEventReporter]。引擎层通过 [AdEventMapper] 转换为 [AdEvent] 后上报。
abstract class AdTypeAdapter {
  AdSource get source;
  AdType get type;

  /// Loads an ad and returns the result.
  ///
  /// [onCallback] receives raw lifecycle events (impression, click, paid, etc.)
  /// that fire during the ad's lifetime. The engine wraps this to convert
  /// callbacks to [AdEvent] and report them.
  ///
  /// [cancellationToken] can be used to abort the load before it completes.
  ///
  /// [eventName] is passed through for context-aware callbacks.
  Future<AdLoadResult<Object>> load({
    required PlacementType placement,
    required AdUnitConfig unit,
    required Duration timeout,
    required String eventName,
    bool renderAsFullscreen = false,
    CancellationToken? cancellationToken,
    void Function(AdRawCallback callback)? onCallback,
    void Function(Object ad, AdType type, String adUnitId)? onLateAdLoaded,
  });

  /// Shows a previously loaded ad.
  ///
  /// [onCallback] receives show-time callbacks (showed, dismissed, click, paid,
  /// show-failed). The engine converts them to [AdEvent].
  Future<AdShowResult> show({
    required PlacementType placement,
    BuildContext? context,
    required String eventName,
    required Object ad,
    VoidCallback? onAdShowed,
    VoidCallback? onClosed,
    int closePassThroughPercent = 0,
    void Function(AdRawCallback callback)? onCallback,
  });

  /// Disposes the ad object. Called when the ad is no longer needed.
  void dispose(Object ad);
}
