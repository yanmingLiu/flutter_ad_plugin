import 'dart:async';

import 'package:flutter/widgets.dart';

import 'models.dart';

final log = AppLogger();

class AppLogger {
  AppLogger({this.verboseEnabled = true});

  final bool verboseEnabled;

  void d(Object message) {
    debugPrint('[ad] $message');
  }

  void event(AdEvent event) {
    final type = event.eventType;
    final placement = (event.placement?.name ?? '-').padRight(14);
    final adType = (event.adType?.name ?? '-').padRight(13);
    final adId = _formatAdUnitId(event.adUnitId).padRight(12);
    final eventName = (event.eventName ?? '-').padRight(14);

    if (!verboseEnabled && !(type?._printsByDefault ?? false)) {
      return;
    }

    final label = type == null ? 'EVENT' : _labelFor(type);
    final extra = _extraFields(event);

    debugPrint('[ad] $label $placement $adType $adId $eventName$extra');
  }

  void v(Object message) {
    if (verboseEnabled) {
      debugPrint('[ad] $message');
    }
  }

  void e(Object message) {
    debugPrint('[ad] $message');
  }
}

extension on AdEventType {
  bool get _printsByDefault {
    return this == AdEventType.loadFailed || this == AdEventType.showFail;
  }
}

String _labelFor(AdEventType type) {
  switch (type) {
    case AdEventType.loadRequested:
      return 'REQ  ';
    case AdEventType.loadSucceeded:
      return 'OK   ';
    case AdEventType.loadFailed:
      return 'ERR  ';
    case AdEventType.show:
      return 'SHOW ';
    case AdEventType.showSuccess:
      return 'DONE ';
    case AdEventType.showFail:
      return 'FAIL ';
    case AdEventType.clicked:
      return 'CLICK';
    case AdEventType.income:
      return 'PAID ';
    case AdEventType.close:
      return 'CLOSE';
    case AdEventType.reward:
      return 'REWARD';
  }
}

String _extraFields(AdEvent event) {
  final buf = StringBuffer();
  final r = event.revenue;
  if (r != null) {
    final currency = event.currency ?? '';
    buf.write(' revenue=$r $currency');
  }
  final rewardAmount = event.rewardAmount;
  if (rewardAmount != null) {
    final label = event.rewardLabel;
    buf.write(' reward=$rewardAmount');
    if (label != null && label.isNotEmpty) {
      buf.write(' ($label)');
    }
  }
  final err = event.errorReason;
  if (err != null && err.isNotEmpty) {
    buf.write(' error=$err');
  }
  final net = event.network;
  if (net != null && net.isNotEmpty) {
    buf.write(' network=$net');
  }
  final requested = event.requestedPlacement;
  if (requested != null && requested != event.placement) {
    buf.write(' request=${requested.name}');
  }
  return buf.toString();
}

String _formatAdUnitId(String? adUnitId) {
  if (adUnitId == null || adUnitId.isEmpty) {
    return '-';
  }
  final idx = adUnitId.lastIndexOf('/');
  if (idx >= 0 && idx < adUnitId.length - 1) {
    return '...${adUnitId.substring(idx + 1)}';
  }
  if (adUnitId.length > 12) {
    return '...${adUnitId.substring(adUnitId.length - 8)}';
  }
  return adUnitId;
}

/// A lightweight cancellation token for aborting in-flight ad loads.
///
/// Used to cancel a pending load when a new request supersedes it or when
/// `AdPlugin.dispose` is called.
///
/// ---
/// 轻量级取消令牌，用于中止正在进行的广告加载。
class CancellationToken {
  bool _cancelled = false;
  final Set<void Function()> _listeners = {};

  bool get isCancelled => _cancelled;

  /// Registers a callback and returns a function that removes it.
  void Function() addListener(void Function() listener) {
    if (_cancelled) {
      listener();
      return () {};
    }
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    final listeners = List<void Function()>.of(_listeners);
    _listeners.clear();
    for (final listener in listeners) {
      listener();
    }
  }
}

/// Shared contract for every SDK adapter.
///
/// Adapters only own SDK objects and SDK lifecycle translation. Placement
/// selection, caching, timeout policy, attribution, and reporting stay in the
/// core engine.
abstract interface class AdAdapter {
  AdSource get source;

  AdType get type;

  /// Releases an SDK object previously returned by this adapter.
  void dispose(Object ad);
}

/// Fullscreen ad lifecycle.
///
/// Flow: `load -> ready -> show -> closed/failed`.
///
/// Implementations must keep `show()` pending until the SDK reports that the
/// fullscreen content was dismissed or failed to display. A successful load
/// returns a ready SDK object that can be cached and shown later.
abstract interface class FullscreenAdAdapter implements AdAdapter {
  /// Loads an ad and returns the ready SDK object.
  ///
  /// [onCallback] receives lifecycle events such as impression, click, paid,
  /// and reward. The engine converts them to [AdEvent]s.
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

  /// Shows a ready SDK object.
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
}

/// Inline ad lifecycle.
///
/// Flow: `prepare -> attach widget -> loading -> ready/failed -> detach/dispose`.
///
/// Inline adapters do not own the host widget tree. They prepare an SDK object
/// or view handle, then the platform renders it as a Flutter widget. This is
/// intentionally separate from [FullscreenAdAdapter] because MAX and TopOn
/// native/banner views depend on widget attachment and cannot share the
/// fullscreen `load -> show` contract.
///
/// A successful [prepare] means the returned object is ready to be attached to
/// the widget tree. Some SDKs (notably MAX Native) cannot start their real
/// network request until that attachment happens, so `prepare` success is not a
/// guarantee that the SDK has already reported an ad loaded. The platform
/// package owns and reports that widget-bound state through its handle.
abstract interface class InlineAdAdapter implements AdAdapter {
  /// Prepares an inline ad handle for later widget attachment.
  ///
  /// The returned object is owned by the adapter and must be released through
  /// [dispose]. It may be a native ad object, a preloaded view handle, or an
  /// adapter-defined result token. For widget-bound SDKs, the returned handle
  /// may still be loading internally after this future completes.
  Future<AdLoadResult<Object>> prepare({
    required PlacementType placement,
    required AdUnitConfig unit,
    required Duration timeout,
    required String eventName,
    bool renderAsFullscreen = false,
    CancellationToken? cancellationToken,
    void Function(AdRawCallback callback)? onCallback,
    void Function(Object ad, AdType type, String adUnitId)? onLateAdLoaded,
  });
}

/// Raw ad lifecycle callbacks emitted by adapters.
///
/// Adapters emit these callbacks through their lifecycle callback parameter.
/// calling [AdEventReporter] directly. The engine layer converts them to
/// [AdEvent] through [AdEventMapper] before reporting.
sealed class AdRawCallback {
  final Object ad;
  const AdRawCallback(this.ad);
}

class AdImpressionCallback extends AdRawCallback {
  final String? network;
  const AdImpressionCallback(super.ad, this.network);
}

class AdPaidCallback extends AdRawCallback {
  final double valueMicros;
  final String currencyCode;
  final String? network;
  const AdPaidCallback(
    super.ad,
    this.valueMicros,
    this.currencyCode,
    this.network,
  );
}

class AdClickedCallback extends AdRawCallback {
  final String? network;
  const AdClickedCallback(super.ad, this.network);
}

class AdClosedCallback extends AdRawCallback {
  final String? network;
  const AdClosedCallback(super.ad, this.network);
}

class AdRewardedCallback extends AdRawCallback {
  final int amount;
  final String? label;
  final String? network;
  const AdRewardedCallback(super.ad, this.amount, this.label, this.network);
}

class AdShowedCallback extends AdRawCallback {
  final String? network;
  const AdShowedCallback(super.ad, this.network);
}

class AdShowFailedCallback extends AdRawCallback {
  final int? errorCode;
  final String? errorMessage;
  final String? network;
  const AdShowFailedCallback(
    super.ad,
    this.errorCode,
    this.errorMessage,
    this.network,
  );
}

/// Mixin providing a common load-with-timeout pattern for ad adapters.
///
/// Extracts the duplicated Completer + Timer logic from all adapter
/// `load()` implementations into a single reusable mixin.
///
/// Usage in an adapter:
/// ```dart
/// class MyAdapter with CommonLoaderMixin<MyAdType> implements FullscreenAdAdapter {
///   @override
///   Future<AdLoadResult<Object>> load({...}) {
///     return loadWithCompleter(
///       unit: unit, timeout: timeout,
///       loadTimeoutLabel: 'my_type',
///       sourceName: source.name, typeName: type.name,
///       cancellationToken: cancellationToken,
///       startLoad: (onLoaded, onFailed) async { ... },
///     );
///   }
/// }
/// ```
///
/// ---
/// 公共加载超时模式 Mixin。将各适配器重复的 Completer+Timer 逻辑提取为
/// 单一可复用 mixin。
mixin CommonLoaderMixin<TAd extends Object> {
  /// Wraps an async load operation with timeout and cancellation support.
  Future<AdLoadResult<Object>> loadWithCompleter({
    required AdUnitConfig unit,
    required Duration timeout,
    required String loadTimeoutLabel,
    required String sourceName,
    required String typeName,
    AppLogger? logger,
    required Future<void> Function(
      void Function(TAd ad) onLoaded,
      void Function(Object error) onFailed,
    )
    startLoad,
    CancellationToken? cancellationToken,
    void Function(TAd ad)? onLateAdLoaded,
  }) async {
    final effectiveLogger = logger ?? log;
    final completer = Completer<AdLoadResult<Object>>();

    final timer = Timer(timeout, () {
      if (!completer.isCompleted) {
        effectiveLogger.v(
          '❌ [adapter_load] timeout: source=$sourceName type=$typeName '
          'id=${unit.id} timeout=${timeout.inSeconds}s',
        );
        completer.complete(
          AdLoadResult.failure(
            type: AdType(unit.type.name),
            adUnitId: unit.id,
            error: TimeoutException('$loadTimeoutLabel ad load timeout'),
          ),
        );
      }
    });

    if (cancellationToken?.isCancelled ?? false) {
      timer.cancel();
      return AdLoadResult.failure(
        type: AdType(unit.type.name),
        adUnitId: unit.id,
        error: 'cancelled',
      );
    }

    final removeCancellationListener = cancellationToken?.addListener(() {
      if (!completer.isCompleted) {
        completer.complete(
          AdLoadResult.failure(
            type: AdType(unit.type.name),
            adUnitId: unit.id,
            error: 'cancelled',
          ),
        );
      }
    });

    try {
      await startLoad(
        (ad) {
          if (!completer.isCompleted) {
            if (cancellationToken?.isCancelled ?? false) {
              completer.complete(
                AdLoadResult.failure(
                  type: AdType(unit.type.name),
                  adUnitId: unit.id,
                  error: 'cancelled',
                ),
              );
              onLateAdLoaded?.call(ad);
              return;
            }
            completer.complete(
              AdLoadResult.success(
                ad: ad,
                type: AdType(unit.type.name),
                adUnitId: unit.id,
              ),
            );
          } else {
            onLateAdLoaded?.call(ad);
          }
        },
        (error) {
          effectiveLogger.v(
            '❌ [adapter_load] failed: source=$sourceName type=$typeName '
            'id=${unit.id} error=$error',
          );
          if (!completer.isCompleted) {
            completer.complete(
              AdLoadResult.failure(
                type: AdType(unit.type.name),
                adUnitId: unit.id,
                error: error,
              ),
            );
          }
        },
      );
    } catch (e) {
      effectiveLogger.v(
        '❌ [adapter_load] failed: source=$sourceName type=$typeName '
        'id=${unit.id} error=$e',
      );
      if (!completer.isCompleted) {
        completer.complete(
          AdLoadResult.failure(
            type: AdType(unit.type.name),
            adUnitId: unit.id,
            error: e,
          ),
        );
      }
    }

    return completer.future.whenComplete(() {
      timer.cancel();
      removeCancellationListener?.call();
    });
  }
}

class AdAdapterRegistry {
  final Map<String, FullscreenAdAdapter> _fullscreenAdapters = {};
  final Map<String, InlineAdAdapter> _inlineAdapters = {};

  AdAdapterRegistry({
    Iterable<FullscreenAdAdapter> fullscreenAdapters = const [],
    Iterable<InlineAdAdapter> inlineAdapters = const [],
  }) {
    for (final adapter in fullscreenAdapters) {
      _fullscreenAdapters[_key(adapter.source, adapter.type)] = adapter;
    }
    for (final adapter in inlineAdapters) {
      _inlineAdapters[_key(adapter.source, adapter.type)] = adapter;
    }
  }

  String _key(AdSource source, AdType type) => '${source.name}_${type.name}';

  FullscreenAdAdapter getFullscreen(AdSource source, AdType type) {
    final adapter = tryGetFullscreen(source, type);
    if (adapter == null) {
      throw StateError(
        'No fullscreen adapter registered for '
        'source=${source.name}, type=${type.name}',
      );
    }
    return adapter;
  }

  FullscreenAdAdapter? tryGetFullscreen(AdSource source, AdType type) =>
      _fullscreenAdapters[_key(source, type)];

  InlineAdAdapter getInline(AdSource source, AdType type) {
    final adapter = tryGetInline(source, type);
    if (adapter == null) {
      throw StateError(
        'No inline adapter registered for source=${source.name}, '
        'type=${type.name}',
      );
    }
    return adapter;
  }

  InlineAdAdapter? tryGetInline(AdSource source, AdType type) =>
      _inlineAdapters[_key(source, type)];

  AdAdapter? tryGet(AdSource source, AdType type) =>
      tryGetFullscreen(source, type) ?? tryGetInline(source, type);

  AdAdapter get(AdSource source, AdType type) {
    final adapter = tryGet(source, type);
    if (adapter == null) {
      throw StateError(
        'No adapter registered for source=${source.name}, type=${type.name}',
      );
    }
    return adapter;
  }

  /// Disposes an SDK object when the owning adapter is still registered.
  ///
  /// Cleanup is intentionally best-effort so a late SDK callback cannot throw
  /// after the plugin has started shutting down.
  void dispose(AdSource source, AdType type, Object ad) {
    tryGet(source, type)?.dispose(ad);
  }
}

/// A self-contained bundle that wires one ad SDK into the plugin.
///
/// Each SDK integration (`AdmobPlatform`, `MaxPlatform`, `TopOnPlatform`, ...)
/// exposes exactly one [AdPlatform] implementation so host apps register
/// platforms instead of hand-assembling dozens of adapters and initializers.
///
/// The core never imports an ad SDK directly; it only sees the abstractions
/// returned here.
///
/// ---
/// 单个广告平台的装配单元。每个 SDK 集成只暴露一个 [AdPlatform] 实现，
/// 宿主注册平台即可，无需手工拼装大量 Adapter 与 Initializer。
/// 核心层始终不直接依赖任何广告 SDK。
///
/// Ownership boundary:
/// - Core owns placement selection, caching, timeout, display policy, and
///   cross-platform reporting.
/// - A platform owns SDK initialization, global listeners, callback routing,
///   SDK handles, and widget rendering.
abstract class AdPlatform {
  /// Ad source this platform provides (for example [AdSource.max]).
  AdSource get source;

  /// Initializes the SDK and any platform-scoped listeners.
  Future<void> init();

  /// Fullscreen adapters owned by this platform.
  List<FullscreenAdAdapter> get fullscreenAdapters;

  /// Inline adapters owned by this platform.
  List<InlineAdAdapter> get inlineAdapters;

  /// Returns a banner widget for [ad], or `null` when this platform does not
  /// own the ad object.
  Widget? bannerWidget(Object ad) => null;

  /// Returns a native widget for [ad], or `null` when this platform does not
  /// own the ad object.
  Widget? nativeWidget(Object ad, {double height = 280, bool expand = false}) =>
      null;

  /// Releases platform-scoped resources such as SDK stream subscriptions.
  void dispose() {}
}
