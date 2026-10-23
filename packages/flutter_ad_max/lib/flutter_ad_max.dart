/// AppLovin MAX 平台实现。
///
/// 一个平台一个文件：SDK 初始化、广告适配器和 widget 渲染都在这里，
/// 宿主只需要注册对应的 Platform 对象。
library;

import 'dart:async';

import 'package:applovin_max/applovin_max.dart';
import 'package:flutter/widgets.dart';

import 'package:flutter_ad_core/models.dart';
import 'package:flutter_ad_core/platform.dart';

/// Callback type used by MAX handles to emit SDK-agnostic lifecycle events.
typedef MaxAdCallback = void Function(AdRawCallback callback);

/// Common fullscreen placement options read from [AdUnitConfig.options].
class MaxFullscreenOptions {
  const MaxFullscreenOptions({this.placement, this.customData});

  final String? placement;
  final String? customData;

  factory MaxFullscreenOptions.fromUnit(AdUnitConfig unit) {
    return MaxFullscreenOptions(
      placement: maxStringOption(unit.options, 'placement'),
      customData: maxStringOption(unit.options, 'custom_data'),
    );
  }
}

/// Common inline placement options read from [AdUnitConfig.options].
class MaxInlineOptions {
  const MaxInlineOptions({
    required this.adFormat,
    this.placement,
    this.customData,
    this.extraParameters,
    this.localExtraParameters,
    this.isAdaptive = true,
    this.autoRefresh = true,
    this.width,
    this.height,
  });

  final AdFormat adFormat;
  final String? placement;
  final String? customData;
  final Map<String, String?>? extraParameters;
  final Map<String, dynamic>? localExtraParameters;
  final bool isAdaptive;
  final bool autoRefresh;
  final double? width;
  final double? height;

  factory MaxInlineOptions.fromUnit(AdUnitConfig unit) {
    final rawFormat = maxStringOption(unit.options, 'ad_format');
    return MaxInlineOptions(
      adFormat: rawFormat?.toLowerCase() == AdFormat.mrec.value
          ? AdFormat.mrec
          : AdFormat.banner,
      placement: maxStringOption(unit.options, 'placement'),
      customData: maxStringOption(unit.options, 'custom_data'),
      extraParameters: _stringMapOption(unit.options, 'extra_parameters'),
      localExtraParameters: _dynamicMapOption(
        unit.options,
        'local_extra_parameters',
      ),
      isAdaptive: maxBoolOption(
        unit.options,
        'is_adaptive',
        defaultValue: true,
      ),
      autoRefresh: maxBoolOption(
        unit.options,
        'auto_refresh',
        defaultValue: true,
      ),
      width: maxDoubleOption(unit.options, 'width'),
      height: maxDoubleOption(unit.options, 'height'),
    );
  }
}

/// Handle returned by a MAX fullscreen load.
///
/// MAX fullscreen events are addressed by `adUnitId`, not by a request id.
/// This handle is the stable object cached by the core and later passed back to
/// the fullscreen adapter's `show` method. The platform event hub uses it to
/// bind SDK callbacks to the request that produced it.
class MaxFullscreenHandle {
  MaxFullscreenHandle({
    required this.type,
    required this.adUnitId,
    required this.placement,
    required this.customData,
  });

  final AdType type;
  final String adUnitId;
  final String? placement;
  final String? customData;

  MaxAd? lastAd;
  MaxAdCallback? onCallback;
  void Function(MaxAd ad)? onLoaded;
  void Function(MaxError error)? onLoadFailed;
  void Function(MaxAd ad)? onDisplayed;
  void Function(MaxAd ad, MaxError error)? onDisplayFailed;
  void Function(MaxAd ad)? onHidden;
  void Function(MaxReward reward)? onRewarded;
  bool ready = false;
  bool loadFailed = false;
  bool disposed = false;

  void emitLoaded(MaxAd ad) {
    if (disposed || ready) return;
    loadFailed = false;
    lastAd = ad;
    ready = true;
    onLoaded?.call(ad);
  }

  void emitLoadFailed(MaxError error) {
    if (disposed || loadFailed) return;
    loadFailed = true;
    ready = false;
    onLoadFailed?.call(error);
  }

  void emitDisplayed(MaxAd ad) {
    if (disposed) return;
    lastAd = ad;
    onDisplayed?.call(ad);
  }

  void emitDisplayFailed(MaxAd ad, MaxError error) {
    if (disposed) return;
    ready = false;
    lastAd = ad;
    onDisplayFailed?.call(ad, error);
  }

  void emitHidden(MaxAd ad) {
    if (disposed) return;
    ready = false;
    lastAd = ad;
    onHidden?.call(ad);
  }

  void emitRewarded(MaxReward reward) {
    if (disposed) return;
    onRewarded?.call(reward);
  }

  void emitPaid(MaxAd ad) {
    if (disposed) return;
    lastAd = ad;
    onCallback?.call(
      AdPaidCallback(this, ad.revenue * 1000000, 'USD', ad.networkName),
    );
  }

  void emitClicked(MaxAd ad) {
    if (disposed) return;
    lastAd = ad;
    onCallback?.call(AdClickedCallback(this, ad.networkName));
  }

  void dispose() {
    if (disposed) return;
    disposed = true;
    ready = false;
    loadFailed = false;
    lastAd = null;
    onCallback = null;
    onLoaded = null;
    onLoadFailed = null;
    onDisplayed = null;
    onDisplayFailed = null;
    onHidden = null;
    onRewarded = null;
  }
}

/// Handle returned by a MAX banner prepare call.
class MaxBannerHandle {
  MaxBannerHandle({
    required this.adUnitId,
    required this.adFormat,
    required this.isAdaptive,
    required this.autoRefresh,
    required this.placement,
    required this.customData,
    required this.extraParameters,
    required this.localExtraParameters,
    required this.width,
    required this.height,
  });

  final String adUnitId;
  final AdFormat adFormat;
  final bool isAdaptive;
  final bool autoRefresh;
  final String? placement;
  final String? customData;
  final Map<String, String?>? extraParameters;
  final Map<String, dynamic>? localExtraParameters;
  final double? width;
  final double? height;

  AdViewId? adViewId;
  MaxAd? lastAd;
  MaxAdCallback? onCallback;
  void Function(MaxAd ad)? onLoaded;
  void Function(MaxError error)? onLoadFailed;
  bool loaded = false;
  bool failed = false;
  bool disposed = false;

  void emitLoaded(MaxAd ad) {
    if (disposed || loaded) return;
    loaded = true;
    failed = false;
    lastAd = ad;
    onLoaded?.call(ad);
  }

  void emitLoadFailed(MaxError error) {
    if (disposed || loaded || failed) return;
    failed = true;
    onLoadFailed?.call(error);
  }

  void emitPaid(MaxAd ad) {
    if (disposed) return;
    lastAd = ad;
    onCallback?.call(
      AdPaidCallback(this, ad.revenue * 1000000, 'USD', ad.networkName),
    );
  }

  void emitClicked(MaxAd ad) {
    if (disposed) return;
    lastAd = ad;
    onCallback?.call(AdClickedCallback(this, ad.networkName));
  }

  void dispose() {
    if (disposed) return;
    disposed = true;
    final adViewId = this.adViewId;
    if (adViewId != null) {
      unawaited(AppLovinMAX.destroyWidgetAdView(adViewId));
    }
    loaded = false;
    failed = false;
    lastAd = null;
    onCallback = null;
    onLoaded = null;
    onLoadFailed = null;
  }
}

/// Handle returned by a MAX native prepare call.
///
/// MAX has no headless native load API. The actual request starts when
/// [MaxNativeView] attaches the [MaxNativeAdViewController] to the widget tree.
/// Consequently loading is reported through callbacks after the core already
/// accepted this handle. This is an explicit platform capability limitation:
/// MAX native ads cannot complete the core's `prepare -> loaded` contract
/// before widget attachment.
class MaxNativeHandle {
  MaxNativeHandle({
    required this.adUnitId,
    required this.controller,
    required this.placement,
    required this.customData,
    required this.extraParameters,
    required this.localExtraParameters,
  });

  final String adUnitId;
  final MaxNativeAdViewController controller;
  final String? placement;
  final String? customData;
  final Map<String, String?>? extraParameters;
  final Map<String, dynamic>? localExtraParameters;

  MaxAdCallback? onCallback;
  void Function(MaxAd ad)? onLoaded;
  void Function(MaxError error)? onLoadFailed;
  MaxAd? lastAd;
  bool loaded = false;
  bool failed = false;
  bool disposed = false;

  void emitLoaded(MaxAd ad) {
    if (disposed || loaded) return;
    failed = false;
    loaded = true;
    lastAd = ad;
    onLoaded?.call(ad);
  }

  void emitLoadFailed(MaxError error) {
    if (disposed || failed) return;
    failed = true;
    loaded = false;
    onLoadFailed?.call(error);
  }

  void emitPaid(MaxAd ad) {
    if (disposed) return;
    lastAd = ad;
    onCallback?.call(
      AdPaidCallback(this, ad.revenue * 1000000, 'USD', ad.networkName),
    );
  }

  void emitClicked(MaxAd ad) {
    if (disposed) return;
    lastAd = ad;
    onCallback?.call(AdClickedCallback(this, ad.networkName));
  }

  void dispose() {
    if (disposed) return;
    disposed = true;
    loaded = false;
    failed = false;
    lastAd = null;
    onCallback = null;
    onLoaded = null;
    onLoadFailed = null;
    controller.dispose();
  }
}

String? maxStringOption(Map<String, Object?> options, String key) {
  final value = options[key];
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  return null;
}

bool maxBoolOption(
  Map<String, Object?> options,
  String key, {
  required bool defaultValue,
}) {
  final value = options[key];
  return value is bool ? value : defaultValue;
}

double? maxDoubleOption(Map<String, Object?> options, String key) {
  final value = options[key];
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

Map<String, String?>? _stringMapOption(
  Map<String, Object?> options,
  String key,
) {
  final raw = options[key];
  if (raw is! Map) return null;
  return <String, String?>{
    for (final entry in raw.entries)
      if (entry.key is String) entry.key as String: entry.value?.toString(),
  };
}

Map<String, dynamic>? _dynamicMapOption(
  Map<String, Object?> options,
  String key,
) {
  final raw = options[key];
  if (raw is! Map) return null;
  return <String, dynamic>{
    for (final entry in raw.entries)
      if (entry.key is String) entry.key as String: entry.value,
  };
}

/// Owns MAX's process-global listeners and multiplexes them by request.
///
/// AppLovin MAX only permits one listener per ad class. The event hub is the
/// platform-local equivalent of capsule's global maps, but it keeps generation
/// and routing details out of the core package.
class MaxEventHub {
  MaxEventHub({AppLogger? logger}) : _logger = logger ?? log;

  final AppLogger _logger;
  final MaxRequestRegistry _registry = MaxRequestRegistry();
  bool _installed = false;
  bool _disposed = false;

  void install() {
    if (_installed || _disposed) return;
    _installed = true;

    AppLovinMAX.setInterstitialListener(
      InterstitialListener(
        onAdLoadedCallback: (ad) => _loaded(AdType.interstitial, ad),
        onAdLoadFailedCallback: (adUnitId, error) =>
            _loadFailed(AdType.interstitial, adUnitId, error),
        onAdDisplayedCallback: (ad) => _displayed(AdType.interstitial, ad),
        onAdDisplayFailedCallback: (ad, error) =>
            _displayFailed(AdType.interstitial, ad, error),
        onAdClickedCallback: (ad) => _clicked(AdType.interstitial, ad),
        onAdHiddenCallback: (ad) => _hidden(AdType.interstitial, ad),
        onAdRevenuePaidCallback: (ad) => _paid(AdType.interstitial, ad),
      ),
    );

    AppLovinMAX.setRewardedAdListener(
      RewardedAdListener(
        onAdLoadedCallback: (ad) => _loaded(AdType.rewarded, ad),
        onAdLoadFailedCallback: (adUnitId, error) =>
            _loadFailed(AdType.rewarded, adUnitId, error),
        onAdDisplayedCallback: (ad) => _displayed(AdType.rewarded, ad),
        onAdDisplayFailedCallback: (ad, error) =>
            _displayFailed(AdType.rewarded, ad, error),
        onAdClickedCallback: (ad) => _clicked(AdType.rewarded, ad),
        onAdHiddenCallback: (ad) => _hidden(AdType.rewarded, ad),
        onAdRevenuePaidCallback: (ad) => _paid(AdType.rewarded, ad),
        onAdReceivedRewardCallback: (ad, reward) =>
            _rewarded(AdType.rewarded, ad, reward),
      ),
    );

    AppLovinMAX.setAppOpenAdListener(
      AppOpenAdListener(
        onAdLoadedCallback: (ad) => _loaded(AdType.open, ad),
        onAdLoadFailedCallback: (adUnitId, error) =>
            _loadFailed(AdType.open, adUnitId, error),
        onAdDisplayedCallback: (ad) => _displayed(AdType.open, ad),
        onAdDisplayFailedCallback: (ad, error) =>
            _displayFailed(AdType.open, ad, error),
        onAdClickedCallback: (ad) => _clicked(AdType.open, ad),
        onAdHiddenCallback: (ad) => _hidden(AdType.open, ad),
        onAdRevenuePaidCallback: (ad) => _paid(AdType.open, ad),
      ),
    );

    AppLovinMAX.setWidgetAdViewAdListener(
      WidgetAdViewAdListener(
        onAdLoadedCallback: (ad) => _registry.bannerForAd(ad)?.emitLoaded(ad),
        onAdLoadFailedCallback: (adUnitId, error) {
          final handle = _registry.bannerForFailure(adUnitId, error);
          if (handle == null) return;
          _registry.unregisterBanner(handle);
          handle.emitLoadFailed(error);
        },
      ),
    );

    _logger.v('✅ [max] global listeners installed');
  }

  MaxRequestRegistry get registry => _registry;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    AppLovinMAX.setInterstitialListener(null);
    AppLovinMAX.setRewardedAdListener(null);
    AppLovinMAX.setAppOpenAdListener(null);
    AppLovinMAX.setWidgetAdViewAdListener(null);
    _registry.dispose();
    _logger.v('🧹 [max] global listeners disposed');
  }

  void _loaded(AdType type, MaxAd ad) {
    _registry.fullscreenFor(type, ad.adUnitId)?.emitLoaded(ad);
  }

  void _loadFailed(AdType type, String adUnitId, MaxError error) {
    final handle = _registry.fullscreenFor(type, adUnitId);
    if (handle == null) return;
    _registry.unregisterFullscreen(handle);
    handle.emitLoadFailed(error);
  }

  void _displayed(AdType type, MaxAd ad) {
    _registry.fullscreenFor(type, ad.adUnitId)?.emitDisplayed(ad);
  }

  void _displayFailed(AdType type, MaxAd ad, MaxError error) {
    _registry.fullscreenFor(type, ad.adUnitId)?.emitDisplayFailed(ad, error);
  }

  void _hidden(AdType type, MaxAd ad) {
    _registry.fullscreenFor(type, ad.adUnitId)?.emitHidden(ad);
  }

  void _clicked(AdType type, MaxAd ad) {
    _registry.fullscreenFor(type, ad.adUnitId)?.emitClicked(ad);
  }

  void _paid(AdType type, MaxAd ad) {
    _registry.fullscreenFor(type, ad.adUnitId)?.emitPaid(ad);
  }

  void _rewarded(AdType type, MaxAd ad, MaxReward reward) {
    _registry.fullscreenFor(type, ad.adUnitId)?.emitRewarded(reward);
  }
}

/// Routes MAX callbacks to the request that owns the SDK event.
///
/// MAX fullscreen listeners are global and only carry an `adUnitId`. Widget
/// preload listeners carry an `adViewId` after preload starts. This registry is
/// the single place that translates those SDK identifiers back into our
/// stable handles.
class MaxRequestRegistry {
  final Map<String, MaxFullscreenHandle> _fullscreen = {};
  final Map<AdViewId, MaxBannerHandle> _bannersById = {};
  final Map<String, MaxBannerHandle> _bannersByKey = {};
  bool _disposed = false;

  void registerFullscreen(MaxFullscreenHandle handle) {
    if (_disposed) return;
    // A newer request for the same ad unit is the only request MAX can report
    // reliably. Keep the old handle alive for a pending show, but route future
    // load callbacks to the newest request.
    _fullscreen[_fullscreenKey(handle.type, handle.adUnitId)] = handle;
  }

  void activateFullscreen(MaxFullscreenHandle handle) {
    if (_disposed) return;
    _fullscreen[_fullscreenKey(handle.type, handle.adUnitId)] = handle;
  }

  MaxFullscreenHandle? fullscreenFor(AdType type, String adUnitId) {
    return _fullscreen[_fullscreenKey(type, adUnitId)];
  }

  void unregisterFullscreen(MaxFullscreenHandle handle) {
    final key = _fullscreenKey(handle.type, handle.adUnitId);
    if (identical(_fullscreen[key], handle)) {
      _fullscreen.remove(key);
    }
  }

  void registerBanner(MaxBannerHandle handle) {
    if (_disposed) return;
    _bannersByKey[_bannerKey(handle.adUnitId, handle.adFormat.value)] = handle;
  }

  void bindBannerId(MaxBannerHandle handle, AdViewId adViewId) {
    if (_disposed) return;
    _bannersByKey.remove(_bannerKey(handle.adUnitId, handle.adFormat.value));
    _bannersById[adViewId] = handle;
  }

  MaxBannerHandle? bannerForAd(MaxAd ad) {
    final adViewId = ad.adViewId;
    if (adViewId != null) {
      final byId = _bannersById[adViewId];
      if (byId != null) return byId;
    }
    return _bannersByKey[_bannerKey(ad.adUnitId, ad.adFormat)];
  }

  MaxBannerHandle? bannerForFailure(String adUnitId, MaxError error) {
    final adViewId = error.adViewId;
    if (adViewId != null) {
      final byId = _bannersById[adViewId];
      if (byId != null) return byId;
    }
    // MAX may report a failure without an adViewId, or after a handle was
    // already unregistered. Routing is best-effort: an unknown callback must
    // never crash the host app.
    for (final handle in _bannersByKey.values) {
      if (handle.adUnitId == adUnitId) return handle;
    }
    for (final handle in _bannersById.values) {
      if (handle.adUnitId == adUnitId) return handle;
    }
    return null;
  }

  void unregisterBanner(MaxBannerHandle handle) {
    final adViewId = handle.adViewId;
    if (adViewId != null && identical(_bannersById[adViewId], handle)) {
      _bannersById.remove(adViewId);
    }
    final key = _bannerKey(handle.adUnitId, handle.adFormat.value);
    if (identical(_bannersByKey[key], handle)) {
      _bannersByKey.remove(key);
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final handle in _fullscreen.values.toSet()) {
      handle.dispose();
    }
    for (final handle in _bannersById.values.toSet()) {
      handle.dispose();
    }
    for (final handle in _bannersByKey.values.toSet()) {
      handle.dispose();
    }
    _fullscreen.clear();
    _bannersById.clear();
    _bannersByKey.clear();
  }

  String _fullscreenKey(AdType type, String adUnitId) {
    return '${type.name}:$adUnitId';
  }

  String _bannerKey(String adUnitId, String adFormat) {
    return '$adUnitId:$adFormat';
  }
}

/// Inline adapter for MAX banner and MREC preloading.
class MaxBannerAdapter
    with CommonLoaderMixin<MaxBannerHandle>
    implements InlineAdAdapter {
  MaxBannerAdapter({required MaxEventHub eventHub, AppLogger? logger})
    : _eventHub = eventHub,
      _logger = logger ?? log;

  final MaxEventHub _eventHub;
  final AppLogger _logger;

  @override
  AdSource get source => AdSource.max;

  @override
  AdType get type => AdType.banner;

  @override
  Future<AdLoadResult<Object>> prepare({
    required PlacementType placement,
    required AdUnitConfig unit,
    required Duration timeout,
    required String eventName,
    bool renderAsFullscreen = false,
    CancellationToken? cancellationToken,
    void Function(AdRawCallback callback)? onCallback,
    void Function(Object ad, AdType type, String adUnitId)? onLateAdLoaded,
  }) {
    final options = MaxInlineOptions.fromUnit(unit);
    final handle = MaxBannerHandle(
      adUnitId: unit.id,
      adFormat: options.adFormat,
      isAdaptive: options.isAdaptive,
      autoRefresh: options.autoRefresh,
      placement: options.placement,
      customData: options.customData,
      extraParameters: options.extraParameters,
      localExtraParameters: options.localExtraParameters,
      width: options.width,
      height: options.height,
    );
    handle.onCallback = onCallback;
    _eventHub.registry.registerBanner(handle);

    final result = loadWithCompleter(
      unit: unit,
      timeout: timeout,
      loadTimeoutLabel: 'banner',
      sourceName: source.name,
      typeName: type.name,
      logger: _logger,
      cancellationToken: cancellationToken,
      onLateAdLoaded: (lateHandle) {
        if (onLateAdLoaded != null) {
          onLateAdLoaded(lateHandle, type, unit.id);
        } else {
          _eventHub.registry.unregisterBanner(lateHandle);
          lateHandle.dispose();
        }
      },
      startLoad: (onLoaded, onFailed) async {
        handle.onLoaded = (ad) {
          onLoaded(handle);
        };
        handle.onLoadFailed = (error) {
          _eventHub.registry.unregisterBanner(handle);
          onFailed(error);
        };

        final adViewId = await AppLovinMAX.preloadWidgetAdView(
          unit.id,
          options.adFormat,
          isAdaptive: options.isAdaptive,
          placement: options.placement,
          customData: options.customData,
          extraParameters: options.extraParameters,
          localExtraParameters: options.localExtraParameters,
        );

        if (handle.disposed || cancellationToken?.isCancelled == true) {
          if (adViewId != null) {
            await AppLovinMAX.destroyWidgetAdView(adViewId);
          }
          return;
        }
        if (adViewId == null) {
          throw StateError('MAX did not return an adViewId for ${unit.id}');
        }

        handle.adViewId = adViewId;
        _eventHub.registry.bindBannerId(handle, adViewId);
      },
    );

    return result.then((value) {
      if (!value.isSuccess && value.error is! TimeoutException) {
        _eventHub.registry.unregisterBanner(handle);
        handle.dispose();
      }
      return value;
    });
  }

  @override
  void dispose(Object ad) {
    if (ad is! MaxBannerHandle) return;
    _eventHub.registry.unregisterBanner(ad);
    ad.dispose();
  }
}

/// Fullscreen adapter for MAX interstitial, rewarded, and app-open ads.
///
/// MAX reports fullscreen events through process-global listeners. This adapter
/// keeps the SDK identifier mapping and show lifecycle inside the MAX package.
class MaxFullscreenAdapter
    with CommonLoaderMixin<MaxFullscreenHandle>
    implements FullscreenAdAdapter {
  MaxFullscreenAdapter({
    required this.type,
    required MaxEventHub eventHub,
    AppLogger? logger,
  }) : _eventHub = eventHub,
       _logger = logger ?? log;

  @override
  final AdType type;

  final MaxEventHub _eventHub;
  final AppLogger _logger;

  @override
  AdSource get source => AdSource.max;

  @override
  Future<AdLoadResult<Object>> load({
    required PlacementType placement,
    required AdUnitConfig unit,
    required Duration timeout,
    required String eventName,
    bool renderAsFullscreen = false,
    CancellationToken? cancellationToken,
    void Function(AdRawCallback callback)? onCallback,
    void Function(Object ad, AdType type, String adUnitId)? onLateAdLoaded,
  }) {
    final options = MaxFullscreenOptions.fromUnit(unit);
    final handle = MaxFullscreenHandle(
      type: type,
      adUnitId: unit.id,
      placement: options.placement,
      customData: options.customData,
    );
    handle.onCallback = onCallback;
    _eventHub.registry.registerFullscreen(handle);

    final result = loadWithCompleter(
      unit: unit,
      timeout: timeout,
      loadTimeoutLabel: type.name,
      sourceName: source.name,
      typeName: type.name,
      logger: _logger,
      cancellationToken: cancellationToken,
      onLateAdLoaded: (lateHandle) {
        if (onLateAdLoaded != null) {
          onLateAdLoaded(lateHandle, type, unit.id);
        } else {
          _eventHub.registry.unregisterFullscreen(lateHandle);
          lateHandle.dispose();
        }
      },
      startLoad: (onLoaded, onFailed) async {
        handle.onLoaded = (ad) {
          onLoaded(handle);
        };
        handle.onLoadFailed = (error) {
          _eventHub.registry.unregisterFullscreen(handle);
          onFailed(error);
        };

        _startSdkLoad(unit.id);
      },
    );

    return result.then((value) {
      // A timeout is allowed to leave the handle registered so a late MAX
      // callback can still be routed through onLateAdLoaded. Immediate SDK
      // failures unregister themselves in onLoadFailed.
      if (!value.isSuccess && value.error is! TimeoutException) {
        _eventHub.registry.unregisterFullscreen(handle);
        handle.dispose();
      }
      return value;
    });
  }

  @override
  Future<AdShowResult> show({
    required PlacementType placement,
    BuildContext? context,
    required String eventName,
    required Object ad,
    VoidCallback? onAdShowed,
    VoidCallback? onClosed,
    int closePassThroughPercent = 0,
    void Function(AdRawCallback callback)? onCallback,
  }) async {
    if (ad is! MaxFullscreenHandle || ad.disposed) {
      return AdShowResult.failure(
        error: StateError('Invalid MAX fullscreen handle'),
        errorReason: 'invalid_max_fullscreen_handle',
      );
    }

    final handle = ad;
    final completer = Completer<AdShowResult>();
    var completed = false;

    void cleanup() {
      _eventHub.registry.unregisterFullscreen(handle);
      handle.dispose();
    }

    void completeFailure(
      Object error, {
      String? errorReason,
      AdShowFailedCallback? callback,
    }) {
      if (callback != null) onCallback?.call(callback);
      if (completed) return;
      completed = true;
      cleanup();
      completer.complete(
        AdShowResult.failure(
          error: error,
          errorReason: errorReason ?? error.toString(),
        ),
      );
    }

    _eventHub.registry.activateFullscreen(handle);
    handle.onCallback = onCallback;
    handle.onDisplayed = (maxAd) {
      onAdShowed?.call();
      onCallback?.call(AdShowedCallback(handle, maxAd.networkName));
    };
    handle.onDisplayFailed = (maxAd, error) {
      completeFailure(
        error,
        errorReason: error.message,
        callback: AdShowFailedCallback(
          handle,
          error.code.value,
          error.message,
          maxAd.networkName,
        ),
      );
    };
    handle.onHidden = (maxAd) {
      onClosed?.call();
      onCallback?.call(AdClosedCallback(handle, maxAd.networkName));
      if (completed) return;
      completed = true;
      cleanup();
      completer.complete(AdShowResult.success());
    };
    handle.onRewarded = (reward) {
      onCallback?.call(
        AdRewardedCallback(
          handle,
          reward.amount,
          reward.label,
          handle.lastAd?.networkName,
        ),
      );
    };

    try {
      _showSdkAd(handle);
    } catch (error) {
      completeFailure(
        error,
        callback: AdShowFailedCallback(handle, null, error.toString(), null),
      );
    }

    return completer.future;
  }

  @override
  void dispose(Object ad) {
    if (ad is! MaxFullscreenHandle) return;
    _eventHub.registry.unregisterFullscreen(ad);
    ad.dispose();
  }

  void _startSdkLoad(String adUnitId) {
    switch (type) {
      case AdType.open:
        AppLovinMAX.loadAppOpenAd(adUnitId);
        return;
      case AdType.rewarded:
        AppLovinMAX.loadRewardedAd(adUnitId);
        return;
      default:
        AppLovinMAX.loadInterstitial(adUnitId);
        return;
    }
  }

  void _showSdkAd(MaxFullscreenHandle handle) {
    switch (type) {
      case AdType.open:
        AppLovinMAX.showAppOpenAd(
          handle.adUnitId,
          placement: handle.placement,
          customData: handle.customData,
        );
        return;
      case AdType.rewarded:
        AppLovinMAX.showRewardedAd(
          handle.adUnitId,
          placement: handle.placement,
          customData: handle.customData,
        );
        return;
      default:
        AppLovinMAX.showInterstitial(
          handle.adUnitId,
          placement: handle.placement,
          customData: handle.customData,
        );
        return;
    }
  }
}

/// Inline adapter for MAX native ads.
///
/// MAX has no headless native load API. The SDK starts loading only after a
/// [MaxNativeAdView] is attached, so this adapter returns a controller-backed
/// handle immediately and reports the real load state from the widget listener.
class MaxNativeAdapter implements InlineAdAdapter {
  MaxNativeAdapter({AppLogger? logger}) : _logger = logger ?? log;

  final AppLogger _logger;

  @override
  AdSource get source => AdSource.max;

  @override
  AdType get type => AdType.native;

  @override
  Future<AdLoadResult<Object>> prepare({
    required PlacementType placement,
    required AdUnitConfig unit,
    required Duration timeout,
    required String eventName,
    bool renderAsFullscreen = false,
    CancellationToken? cancellationToken,
    void Function(AdRawCallback callback)? onCallback,
    void Function(Object ad, AdType type, String adUnitId)? onLateAdLoaded,
  }) async {
    if (cancellationToken?.isCancelled ?? false) {
      return AdLoadResult.failure(
        type: type,
        adUnitId: unit.id,
        error: 'cancelled',
      );
    }

    final options = MaxInlineOptions.fromUnit(unit);
    final handle = MaxNativeHandle(
      adUnitId: unit.id,
      controller: MaxNativeAdViewController(),
      placement: options.placement,
      customData: options.customData,
      extraParameters: options.extraParameters,
      localExtraParameters: options.localExtraParameters,
    );
    handle.onCallback = onCallback;
    _logger.v(
      '📥 [max-native] prepared id=${unit.id} '
      'placement=${placement.name}; load starts on widget attach',
    );
    return AdLoadResult.success(ad: handle, type: type, adUnitId: unit.id);
  }

  @override
  void dispose(Object ad) {
    if (ad is MaxNativeHandle) {
      ad.dispose();
    }
  }
}

/// AppLovin MAX platform bundle.
///
/// MAX uses process-global listeners for fullscreen and preloaded widget ads.
/// Only one live [MaxPlatform] may therefore exist in a process. Constructing
/// a second live instance fails fast instead of silently stealing callbacks.
class MaxPlatform implements AdPlatform {
  MaxPlatform({
    required this.sdkKey,
    this.testDeviceAdvertisingIds = const [],
    AppLogger? logger,
  }) : _logger = logger ?? log {
    if (sdkKey.trim().isEmpty) {
      throw ArgumentError.value(sdkKey, 'sdkKey', 'MAX SDK key is required');
    }
    if (_active != null) {
      throw StateError(
        'Only one live MaxPlatform is supported per process because the MAX '
        'SDK exposes process-global listeners.',
      );
    }

    _active = this;
    _eventHub = MaxEventHub(logger: _logger);
  }

  static MaxPlatform? _active;

  final String sdkKey;
  final List<String> testDeviceAdvertisingIds;
  final AppLogger _logger;
  late final MaxEventHub _eventHub;

  @override
  AdSource get source => AdSource.max;

  /// Opens the AppLovin MAX Mediation Debugger.
  void showMediationDebugger() {
    AppLovinMAX.showMediationDebugger();
  }

  @override
  Future<void> init() async {
    final testDeviceIds = testDeviceAdvertisingIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    if (testDeviceIds.isNotEmpty) {
      AppLovinMAX.setTestDeviceAdvertisingIds(testDeviceIds);
    }
    await AppLovinMAX.initialize(sdkKey);
    _eventHub.install();
  }

  @override
  List<FullscreenAdAdapter> get fullscreenAdapters => [
    MaxFullscreenAdapter(
      type: AdType.open,
      eventHub: _eventHub,
      logger: _logger,
    ),
    MaxFullscreenAdapter(
      type: AdType.interstitial,
      eventHub: _eventHub,
      logger: _logger,
    ),
    MaxFullscreenAdapter(
      type: AdType.rewarded,
      eventHub: _eventHub,
      logger: _logger,
    ),
  ];

  @override
  List<InlineAdAdapter> get inlineAdapters => [
    MaxBannerAdapter(eventHub: _eventHub, logger: _logger),
    MaxNativeAdapter(logger: _logger),
  ];

  @override
  Widget? bannerWidget(Object ad) {
    return ad is MaxBannerHandle ? MaxBannerView(handle: ad) : null;
  }

  @override
  Widget? nativeWidget(Object ad, {double height = 280, bool expand = false}) {
    return ad is MaxNativeHandle
        ? MaxNativeView(handle: ad, height: height, expand: expand)
        : null;
  }

  @override
  void dispose() {
    _eventHub.dispose();
    if (identical(_active, this)) {
      _active = null;
    }
  }
}

/// Renders a MAX banner or MREC handle returned by [MaxBannerAdapter].
class MaxBannerView extends StatelessWidget {
  const MaxBannerView({super.key, required this.handle});

  final MaxBannerHandle handle;

  @override
  Widget build(BuildContext context) {
    return MaxAdView(
      adUnitId: handle.adUnitId,
      adFormat: handle.adFormat,
      adViewId: handle.adViewId,
      placement: handle.placement,
      customData: handle.customData,
      extraParameters: handle.extraParameters,
      localExtraParameters: handle.localExtraParameters,
      isAutoRefreshEnabled: handle.autoRefresh,
      isAdaptiveBannerEnabled: handle.isAdaptive,
      width: handle.width,
      height: handle.height,
      listener: AdViewAdListener(
        onAdLoadedCallback: handle.emitLoaded,
        onAdLoadFailedCallback: (_, error) => handle.emitLoadFailed(error),
        onAdClickedCallback: handle.emitClicked,
        onAdRevenuePaidCallback: handle.emitPaid,
        onAdExpandedCallback: (_) {},
        onAdCollapsedCallback: (_) {},
      ),
    );
  }
}

/// Renders a MAX native ad handle.
///
/// MAX starts loading a native ad only after [MaxNativeAdView] is attached to
/// the widget tree. The handle is therefore prepared by the adapter first and
/// the real load state is reported by this widget's SDK listener.
class MaxNativeView extends StatefulWidget {
  const MaxNativeView({
    super.key,
    required this.handle,
    this.height = 280,
    this.expand = false,
  });

  final MaxNativeHandle handle;
  final double height;
  final bool expand;

  @override
  State<MaxNativeView> createState() => _MaxNativeViewState();
}

class _MaxNativeViewState extends State<MaxNativeView> {
  static const double _defaultMediaAspectRatio = 16 / 9;

  double _mediaAspectRatio = _defaultMediaAspectRatio;

  @override
  void didUpdateWidget(covariant MaxNativeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.handle, widget.handle)) {
      _mediaAspectRatio = _defaultMediaAspectRatio;
    }
  }

  @override
  Widget build(BuildContext context) {
    final adView = MaxNativeAdView(
      adUnitId: widget.handle.adUnitId,
      controller: widget.handle.controller,
      placement: widget.handle.placement,
      customData: widget.handle.customData,
      extraParameters: widget.handle.extraParameters,
      localExtraParameters: widget.handle.localExtraParameters,
      width: double.infinity,
      height: double.infinity,
      listener: NativeAdListener(
        onAdLoadedCallback: (ad) {
          if (mounted) {
            setState(() {
              _mediaAspectRatio =
                  ad.nativeAd?.mediaContentAspectRatio ??
                  _defaultMediaAspectRatio;
            });
          }
          widget.handle.emitLoaded(ad);
        },
        onAdLoadFailedCallback: (_, error) =>
            widget.handle.emitLoadFailed(error),
        onAdClickedCallback: widget.handle.emitClicked,
        onAdRevenuePaidCallback: widget.handle.emitPaid,
      ),
      child: _MaxNativeAssetLayout(mediaAspectRatio: _mediaAspectRatio),
    );

    if (widget.expand) {
      return SizedBox.expand(child: adView);
    }
    return SizedBox(height: widget.height, child: adView);
  }
}

class _MaxNativeAssetLayout extends StatelessWidget {
  const _MaxNativeAssetLayout({required this.mediaAspectRatio});

  final double mediaAspectRatio;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MaxNativeAdIconView(width: 48, height: 48),
              SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MaxNativeAdTitleView(
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 2),
                    MaxNativeAdAdvertiserView(
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11),
                    ),
                    SizedBox(height: 4),
                    MaxNativeAdStarRatingView(size: 10),
                  ],
                ),
              ),
              SizedBox(width: 8),
              MaxNativeAdOptionsView(width: 20, height: 20),
            ],
          ),
          const SizedBox(height: 6),
          const MaxNativeAdBodyView(
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: mediaAspectRatio,
                child: const MaxNativeAdMediaView(),
              ),
            ),
          ),
          const SizedBox(height: 6),
          const SizedBox(
            width: double.infinity,
            child: MaxNativeAdCallToActionView(),
          ),
        ],
      ),
    );
  }
}
