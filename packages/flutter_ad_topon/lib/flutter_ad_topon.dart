/// TopOn SDK initialization and adapter registration.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:secmtp_sdk/at_index.dart';

import 'package:flutter_ad_core/models.dart';
import 'package:flutter_ad_core/platform.dart';

export 'package:flutter_ad_core/flutter_ad_core.dart';

/// TopOn platform bundle.
///
/// TopOn installs a process-global MethodChannel handler, so only one live
/// [TopOnPlatform] may exist per process.
class TopOnPlatform implements AdPlatform {
  TopOnPlatform({
    required this.appId,
    required this.appKey,
    this.debugKey,
    this.logEnabled = false,
    AppLogger? logger,
  }) : _logger = logger ?? log {
    if (appId.trim().isEmpty) {
      throw ArgumentError.value(appId, 'appId', 'TopOn app id is required');
    }
    if (appKey.trim().isEmpty) {
      throw ArgumentError.value(appKey, 'appKey', 'TopOn app key is required');
    }
    if (_active != null) {
      throw StateError(
        'Only one live TopOnPlatform is supported per process because '
        'secmtp_sdk installs a process-global MethodChannel handler.',
      );
    }

    _active = this;
    _eventHub = TopOnEventHub(logger: _logger);
  }

  static TopOnPlatform? _active;

  final String appId;
  final String appKey;
  final String? debugKey;
  final bool logEnabled;
  final AppLogger _logger;
  late final TopOnEventHub _eventHub;

  /// Opens the TopOn Debugger UI when a debug key is configured.
  Future<void> showDebugger() {
    final key = debugKey?.trim();
    if (key == null || key.isEmpty) {
      throw StateError('TopOn debugKey is required to open the Debugger UI.');
    }
    return ATInitManger.showDebuggerUI(debugKey: key);
  }

  @override
  AdSource get source => AdSource.topon;

  @override
  Future<void> init() async {
    _eventHub.install();
    await ATInitManger.setLogEnabled(logEnabled: logEnabled);
    final result = await ATInitManger.initSDK(
      appidStr: appId,
      appidkeyStr: appKey,
    );
    // Android acknowledges the init call with an empty string; iOS returns
    // 'succeed' or an error description through the same success channel.
    if (result.isNotEmpty && result != 'succeed') {
      throw StateError('TopOn initialization failed: $result');
    }
  }

  @override
  List<FullscreenAdAdapter> get fullscreenAdapters => [
    TopOnFullscreenAdapter(
      type: AdType.open,
      eventHub: _eventHub,
      logger: _logger,
    ),
    TopOnFullscreenAdapter(
      type: AdType.interstitial,
      eventHub: _eventHub,
      logger: _logger,
    ),
    TopOnFullscreenAdapter(
      type: AdType.rewarded,
      eventHub: _eventHub,
      logger: _logger,
    ),
  ];

  @override
  List<InlineAdAdapter> get inlineAdapters => [
    TopOnBannerAdapter(eventHub: _eventHub, logger: _logger),
    TopOnNativeAdapter(eventHub: _eventHub, logger: _logger),
  ];

  @override
  Widget? bannerWidget(Object ad) {
    return ad is TopOnBannerHandle ? TopOnBannerView(handle: ad) : null;
  }

  @override
  Widget? nativeWidget(Object ad, {double height = 280, bool expand = false}) {
    return ad is TopOnNativeHandle
        ? TopOnNativeView(handle: ad, height: height, expand: expand)
        : null;
  }

  @override
  void dispose() {
    _eventHub.dispose();
    if (identical(_active, this)) _active = null;
  }
}

/// Fullscreen options read from [AdUnitConfig.options].
class TopOnFullscreenOptions {
  const TopOnFullscreenOptions({required this.extraMap, this.sceneId});

  final Map<String, Object> extraMap;
  final String? sceneId;

  factory TopOnFullscreenOptions.fromUnit(AdUnitConfig unit) {
    return TopOnFullscreenOptions(
      sceneId: unit.options['sceneID'] as String?,
      extraMap: topOnExtraMap(unit.options),
    );
  }
}

/// Banner options read from [AdUnitConfig.options].
class TopOnBannerOptions {
  const TopOnBannerOptions({
    required this.extraMap,
    required this.size,
    this.sceneId,
  });

  final Map<String, Object> extraMap;
  final Map<String, Object> size;
  final String? sceneId;

  factory TopOnBannerOptions.fromUnit(AdUnitConfig unit) {
    final options = unit.options;
    final extraMap = topOnExtraMap(options);
    final sizeKey = ATCommon.getAdSizeKey();
    final size = Map<String, Object>.from(
      extraMap[sizeKey] as Map? ??
          ATBannerManager.createLoadBannerAdSize(320, 50),
    );
    extraMap[sizeKey] = size;

    return TopOnBannerOptions(
      sceneId: options['sceneID'] as String?,
      extraMap: extraMap,
      size: size,
    );
  }
}

/// Native options read from [AdUnitConfig.options].
class TopOnNativeOptions {
  const TopOnNativeOptions({
    required this.extraMap,
    required this.isAdaptiveHeight,
    this.sceneId,
  });

  final Map<String, Object> extraMap;
  final bool isAdaptiveHeight;
  final String? sceneId;

  factory TopOnNativeOptions.fromUnit(AdUnitConfig unit) {
    final options = unit.options;
    final extraMap = topOnExtraMap(options)
      ..[ATCommon.isNativeShow()] = false
      ..putIfAbsent(
        ATCommon.getAdSizeKey(),
        () => ATNativeManager.createNativeSubViewAttribute(300, 250),
      );

    return TopOnNativeOptions(
      sceneId: options['sceneID'] as String?,
      isAdaptiveHeight: extraMap[ATNativeManager.isAdaptiveHeight()] == true,
      extraMap: extraMap,
    );
  }
}

/// Copies the SDK's load parameters from [AdUnitConfig.options].
Map<String, Object> topOnExtraMap(Map<String, Object?> options) {
  final extraMap = options['extraMap'] as Map?;
  return Map<String, Object>.from(extraMap ?? const {});
}

/// Callback used by SDK handles to emit core lifecycle events.
typedef TopOnAdCallback = void Function(AdRawCallback callback);

/// Base state shared by every TopOn handle.
abstract class TopOnCallbackHandle {
  TopOnCallbackHandle({required this.placementId});

  final String placementId;
  TopOnAdCallback? onCallback;
  double? estimatedRevenue;
  String? _loadedNetwork;
  bool disposed = false;

  void Function(Object response)? onLoaded;
  void Function(Object error)? onLoadFailed;
  void Function(Object response)? onDisplayed;
  bool failed = false;

  Future<void> _readLoadedAdInfo(AdType type) async {
    try {
      final query = switch (type) {
        AdType.interstitial => ATInterstitialManager.getInterstitialValidAds(
          placementID: placementId,
        ),
        AdType.rewarded => ATRewardedManager.getRewardedVideoValidAds(
          placementID: placementId,
        ),
        AdType.open => ATSplashManager.getSplashValidAds(
          placementID: placementId,
        ),
        AdType.banner => ATBannerManager.getBannerValidAds(
          placementID: placementId,
        ),
        AdType.native => ATNativeManager.getNativeValidAds(
          placementID: placementId,
        ),
        _ => throw UnsupportedError('TopOn does not support type=$type'),
      };
      final ads = jsonDecode(await query);
      if (disposed || ads is! List || ads.isEmpty) return;
      final firstAd = ads.first;
      if (firstAd is! Map) return;

      _loadedNetwork = firstAd['network_name']?.toString().trim();
      final revenue = double.tryParse('${firstAd['publisher_revenue'] ?? 0}');
      if (revenue != null && revenue.isFinite && revenue >= 0) {
        estimatedRevenue = revenue * 1000000.0;
      }
    } catch (_) {
      // Cached ad metadata is optional. The ad has already loaded.
    }
  }

  void emitPaid(Map extraMap) {
    if (disposed) return;
    final callback = topOnPaidCallback(
      this,
      extraMap,
      estimatedRevenue: estimatedRevenue,
    );
    if (callback != null) onCallback?.call(callback);
  }

  void emitClicked(String? network) {
    if (disposed) return;
    onCallback?.call(AdClickedCallback(this, network));
  }

  void emitCloseCallback(String? network) {
    if (disposed) return;
    onCallback?.call(AdClosedCallback(this, network));
  }

  void emitRewarded() {
    if (disposed) return;
    onCallback?.call(AdRewardedCallback(this, 1, null, null));
  }

  void disposeCallbackHandle() {
    disposed = true;
    onCallback = null;
    failed = false;
    onLoaded = null;
    onLoadFailed = null;
    onDisplayed = null;
  }
}

/// Handle returned by a TopOn fullscreen load.
class TopOnFullscreenHandle extends TopOnCallbackHandle {
  TopOnFullscreenHandle({
    required this.type,
    required super.placementId,
    required this.extraMap,
    this.sceneId,
  });

  final AdType type;
  final Map<String, Object> extraMap;
  final String? sceneId;

  void Function(Object error)? onDisplayFailed;
  void Function(Object response)? onClosed;

  bool ready = false;
  bool displayed = false;
  bool closed = false;

  void emitLoaded(Object response) {
    if (disposed || ready || failed) return;
    ready = true;
    onLoaded?.call(response);
  }

  void emitLoadFailed(Object error) {
    if (disposed || ready || failed) return;
    failed = true;
    onLoadFailed?.call(error);
  }

  void emitDisplayed(Object response) {
    if (disposed || closed || displayed) return;
    displayed = true;
    onDisplayed?.call(response);
  }

  void emitDisplayFailed(Object error) {
    if (disposed || closed) return;
    ready = false;
    onDisplayFailed?.call(error);
  }

  void emitClosed(Object response) {
    if (disposed || closed) return;
    closed = true;
    ready = false;
    onClosed?.call(response);
  }

  void dispose() {
    if (disposed) return;
    disposeCallbackHandle();
    ready = false;
    displayed = false;
    closed = false;
    onDisplayFailed = null;
    onClosed = null;
  }
}

/// Shared state for banner and native handles.
abstract class TopOnInlineHandle extends TopOnCallbackHandle {
  TopOnInlineHandle({required super.placementId});

  bool loaded = false;

  void emitLoaded(Object response) {
    if (disposed || loaded) return;
    loaded = true;
    failed = false;
    onLoaded?.call(response);
  }

  void emitLoadFailed(Object error) {
    if (disposed || loaded || failed) return;
    failed = true;
    onLoadFailed?.call(error);
  }

  void emitDisplayed(Object response) {
    if (disposed) return;
    onDisplayed?.call(response);
  }

  void dispose() {
    if (disposed) return;
    disposeCallbackHandle();
    loaded = false;
  }
}

/// Handle returned by a TopOn banner prepare call.
class TopOnBannerHandle extends TopOnInlineHandle {
  TopOnBannerHandle({
    required super.placementId,
    required this.extraMap,
    required this.size,
    this.sceneId,
  });

  final Map<String, Object> extraMap;
  final Map<String, Object> size;
  final String? sceneId;
}

/// Handle returned by a TopOn native prepare call.
class TopOnNativeHandle extends TopOnInlineHandle {
  TopOnNativeHandle({
    required super.placementId,
    required this.extraMap,
    required this.isAdaptiveHeight,
    this.sceneId,
  });

  final Map<String, Object> extraMap;
  final bool isAdaptiveHeight;
  final String? sceneId;
}

/// Converts a TopOn revenue payload into an [AdPaidCallback].
AdPaidCallback? topOnPaidCallback(
  Object ad,
  Map extraMap, {
  double? estimatedRevenue,
}) {
  final value = double.tryParse('${extraMap['publisher_revenue']}');
  if (value == null || !value.isFinite || value <= 0) return null;

  final currency = extraMap['currency'];
  if (currency is! String || currency.isEmpty) return null;

  return AdPaidCallback(
    ad,
    value * 1000000,
    currency,
    extraMap['network_name']?.toString().trim(),
    estimatedRevenue: estimatedRevenue,
  );
}

/// Normalized error passed through TopOn adapters.
class TopOnAdError {
  const TopOnAdError(this.message, {this.code});

  final String message;
  final int? code;

  @override
  String toString() => message;
}

/// Owns TopOn's process-global event streams and routes callbacks by placement.
class TopOnEventHub {
  TopOnEventHub({AppLogger? logger}) : _logger = logger ?? log;

  final AppLogger _logger;
  final Map<(AdType, String), TopOnFullscreenHandle> _fullscreen = {};
  final Map<String, TopOnBannerHandle> _banners = {};
  final Map<String, TopOnNativeHandle> _natives = {};
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  bool _installed = false;
  bool _disposed = false;

  void install() {
    if (_installed || _disposed) return;
    _installed = true;

    _subscriptions.addAll([
      ATListenerManager.interstitialEventHandler.listen(_onInterstitial),
      ATListenerManager.rewardedVideoEventHandler.listen(_onRewarded),
      ATListenerManager.splashEventHandler.listen(_onSplash),
      ATListenerManager.bannerEventHandler.listen(_onBanner),
      ATListenerManager.nativeEventHandler.listen(_onNative),
      ATListenerManager.commonAdEventHandler.listen(_onCommon),
    ]);

    _logger.v('✅ [topon] global listeners installed');
  }

  void registerFullscreen(TopOnFullscreenHandle handle) {
    if (_disposed) return;
    _fullscreen[(handle.type, handle.placementId)] = handle;
  }

  void releaseFullscreen(TopOnFullscreenHandle handle) {
    if (handle.disposed) return;
    _unregisterFullscreen(handle);
    handle.dispose();
  }

  void registerBanner(TopOnBannerHandle handle) {
    if (_disposed) return;
    _banners[handle.placementId] = handle;
  }

  void releaseBanner(TopOnBannerHandle handle) {
    if (handle.disposed) return;
    if (identical(_banners[handle.placementId], handle)) {
      _banners.remove(handle.placementId);
    }
    unawaited(ATBannerManager.removeBannerAd(placementID: handle.placementId));
    handle.dispose();
  }

  void registerNative(TopOnNativeHandle handle) {
    if (_disposed) return;
    _natives[handle.placementId] = handle;
  }

  void releaseNative(TopOnNativeHandle handle) {
    if (handle.disposed) return;
    if (identical(_natives[handle.placementId], handle)) {
      _natives.remove(handle.placementId);
    }
    unawaited(ATNativeManager.removeNativeAd(placementID: handle.placementId));
    handle.dispose();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();

    for (final handle in _banners.values.toSet()) {
      unawaited(
        ATBannerManager.removeBannerAd(placementID: handle.placementId),
      );
      handle.dispose();
    }
    for (final handle in _natives.values.toSet()) {
      unawaited(
        ATNativeManager.removeNativeAd(placementID: handle.placementId),
      );
      handle.dispose();
    }
    for (final handle in _fullscreen.values.toSet()) {
      handle.dispose();
    }

    _banners.clear();
    _natives.clear();
    _fullscreen.clear();
    _logger.v('🧹 [topon] global listeners disposed');
  }

  void _onInterstitial(ATInterstitialResponse response) {
    final handle = _fullscreen[(AdType.interstitial, response.placementID)];
    if (handle == null) return;

    switch (response.interstatus) {
      case InterstitialStatus.interstitialAdDidFinishLoading:
        handle.emitLoaded(response);
        break;
      case InterstitialStatus.interstitialAdFailToLoadAD:
        _unregisterFullscreen(handle);
        handle.emitLoadFailed(_errorFor(response, 'interstitial load failed'));
        break;
      case InterstitialStatus.interstitialDidShowSucceed:
        handle.emitDisplayed(response);
        break;
      case InterstitialStatus.interstitialFailedToShow:
      case InterstitialStatus.interstitialDidFailToPlayVideo:
        handle.emitDisplayFailed(
          _errorFor(response, 'interstitial display failed'),
        );
        break;
      case InterstitialStatus.interstitialAdDidClick:
        handle.emitClicked(
          response.extraMap['network_name']?.toString().trim(),
        );
        break;
      case InterstitialStatus.interstitialAdDidClose:
        handle.emitClosed(response);
        break;
      case InterstitialStatus.interstitialAdDidReward:
        handle.emitRewarded();
        break;
      default:
        break;
    }
  }

  void _onRewarded(ATRewardResponse response) {
    final handle = _fullscreen[(AdType.rewarded, response.placementID)];
    if (handle == null) return;

    switch (response.rewardStatus) {
      case RewardedStatus.rewardedVideoDidFinishLoading:
        handle.emitLoaded(response);
        break;
      case RewardedStatus.rewardedVideoDidFailToLoad:
        _unregisterFullscreen(handle);
        handle.emitLoadFailed(_errorFor(response, 'rewarded load failed'));
        break;
      case RewardedStatus.rewardedVideoDidStartPlaying:
        handle.emitDisplayed(response);
        break;
      case RewardedStatus.rewardedVideoDidFailToPlay:
      case RewardedStatus.rewardedVideoDidAgainFailToPlay:
        handle.emitDisplayFailed(
          _errorFor(response, 'rewarded display failed'),
        );
        break;
      case RewardedStatus.rewardedVideoDidRewardSuccess:
      case RewardedStatus.rewardedVideoDidAgainRewardSuccess:
        handle.emitRewarded();
        break;
      case RewardedStatus.rewardedVideoDidClick:
      case RewardedStatus.rewardedVideoDidAgainClick:
        handle.emitClicked(
          response.extraMap['network_name']?.toString().trim(),
        );
        break;
      case RewardedStatus.rewardedVideoDidClose:
        handle.emitClosed(response);
        break;
      default:
        break;
    }
  }

  void _onSplash(ATSplashResponse response) {
    final handle = _fullscreen[(AdType.open, response.placementID)];
    if (handle == null) return;

    switch (response.splashStatus) {
      case SplashStatus.splashDidFinishLoading:
        handle.emitLoaded(response);
        break;
      case SplashStatus.splashDidFailToLoad:
      case SplashStatus.splashDidTimeout:
        _unregisterFullscreen(handle);
        handle.emitLoadFailed(_errorFor(response, 'splash load failed'));
        break;
      case SplashStatus.splashDidShowSuccess:
        handle.emitDisplayed(response);
        break;
      case SplashStatus.splashDidShowFailed:
        handle.emitDisplayFailed(_errorFor(response, 'splash display failed'));
        break;
      case SplashStatus.splashDidClick:
        handle.emitClicked(
          response.extraMap['network_name']?.toString().trim(),
        );
        break;
      case SplashStatus.splashDidClose:
        handle.emitClosed(response);
        break;
      case SplashStatus.splashAdDidReward:
        handle.emitRewarded();
        break;
      default:
        break;
    }
  }

  void _onBanner(ATBannerResponse response) {
    final handle = _banners[response.placementID];
    if (handle == null) return;

    switch (response.bannerStatus) {
      case BannerStatus.bannerAdDidFinishLoading:
        handle.emitLoaded(response);
        break;
      case BannerStatus.bannerAdFailToLoadAD:
        _banners.remove(response.placementID);
        handle.emitLoadFailed(_errorFor(response, 'banner load failed'));
        break;
      case BannerStatus.bannerAdDidShowSucceed:
        handle.emitDisplayed(response);
        break;
      case BannerStatus.bannerAdDidClick:
        handle.emitClicked(
          response.extraMap['network_name']?.toString().trim(),
        );
        break;
      case BannerStatus.bannerAdTapCloseButton:
        final network = response.extraMap['network_name']?.toString().trim();
        handle.emitCloseCallback(network);
        break;
      default:
        break;
    }
  }

  void _onNative(ATNativeResponse response) {
    final handle = _natives[response.placementID];
    if (handle == null) return;

    switch (response.nativeStatus) {
      case NativeStatus.nativeAdDidFinishLoading:
        handle.emitLoaded(response);
        break;
      case NativeStatus.nativeAdFailToLoadAD:
        _natives.remove(response.placementID);
        handle.emitLoadFailed(_errorFor(response, 'native load failed'));
        break;
      case NativeStatus.nativeAdDidShowNativeAd:
        handle.emitDisplayed(response);
        break;
      case NativeStatus.nativeAdDidClick:
        handle.emitClicked(
          response.extraMap['network_name']?.toString().trim(),
        );
        break;
      case NativeStatus.nativeAdDidActRewardSuccess:
      case NativeStatus.nativeAdDidActReward:
        handle.emitRewarded();
        break;
      case NativeStatus.nativeAdDidTapCloseButton:
        final network = response.extraMap['network_name']?.toString().trim();
        handle.emitCloseCallback(network);
        break;
      default:
        break;
    }
  }

  void _onCommon(ATCommonAdResponse response) {
    if (response.status != ATCommonAdStatus.adShowRevenuePaid) return;
    _callbackHandleForPlacement(
      response.placementID,
    )?.emitPaid(response.extraMap);
  }

  void _unregisterFullscreen(TopOnFullscreenHandle handle) {
    final key = (handle.type, handle.placementId);
    if (identical(_fullscreen[key], handle)) _fullscreen.remove(key);
  }

  TopOnCallbackHandle? _callbackHandleForPlacement(String placementId) {
    for (final handle in _fullscreen.values) {
      if (!handle.disposed && handle.placementId == placementId) return handle;
    }
    for (final handle in _banners.values) {
      if (!handle.disposed && handle.placementId == placementId) return handle;
    }
    for (final handle in _natives.values) {
      if (!handle.disposed && handle.placementId == placementId) return handle;
    }
    return null;
  }

  TopOnAdError _errorFor(BaseResponse response, String fallback) {
    final message = response.requestMessage.trim();
    return TopOnAdError(message.isEmpty ? fallback : message);
  }
}

mixin _TopOnLoader<T extends TopOnCallbackHandle> on CommonLoaderMixin<T> {
  AdType get type;
  AdSource get source;
  AppLogger get _logger;

  Future<AdLoadResult<Object>> _loadHandle({
    required T handle,
    required AdUnitConfig unit,
    required Duration timeout,
    required CancellationToken? cancellationToken,
    required void Function(Object ad, AdType type, String adUnitId)?
    onLateAdLoaded,
    required void Function(T) release,
    required Future<void> Function() loadSdk,
  }) async {
    final result = await loadWithCompleter(
      unit: unit,
      timeout: timeout,
      loadTimeoutLabel: type.name,
      sourceName: source.name,
      typeName: type.name,
      logger: _logger,
      cancellationToken: cancellationToken,
      networkOf: (ad) => ad._loadedNetwork,
      onLateAdLoaded: (lateHandle) {
        if (onLateAdLoaded != null) {
          onLateAdLoaded(lateHandle, type, unit.id);
        } else {
          release(lateHandle);
        }
      },
      startLoad: (onLoaded, onFailed) async {
        handle.onLoaded = (_) async {
          await handle._readLoadedAdInfo(type);
          if (!handle.disposed) onLoaded(handle);
        };
        handle.onLoadFailed = (error) {
          onFailed(error);
          release(handle);
        };
        await loadSdk();
      },
    );

    if (!result.isSuccess && result.error is! TimeoutException) {
      release(handle);
    }
    return result;
  }
}

/// Fullscreen adapter for TopOn interstitial, rewarded, and splash/open ads.
class TopOnFullscreenAdapter
    with
        CommonLoaderMixin<TopOnFullscreenHandle>,
        _TopOnLoader<TopOnFullscreenHandle>
    implements FullscreenAdAdapter {
  TopOnFullscreenAdapter({
    required this.type,
    required TopOnEventHub eventHub,
    AppLogger? logger,
  }) : _eventHub = eventHub,
       _logger = logger ?? log;

  @override
  final AdType type;

  final TopOnEventHub _eventHub;
  @override
  final AppLogger _logger;

  @override
  AdSource get source => AdSource.topon;

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
    final options = TopOnFullscreenOptions.fromUnit(unit);
    final handle = TopOnFullscreenHandle(
      type: type,
      placementId: unit.id,
      extraMap: options.extraMap,
      sceneId: options.sceneId,
    )..onCallback = onCallback;

    _eventHub.registerFullscreen(handle);

    return _loadHandle(
      handle: handle,
      unit: unit,
      timeout: timeout,
      cancellationToken: cancellationToken,
      onLateAdLoaded: onLateAdLoaded,
      release: _eventHub.releaseFullscreen,
      loadSdk: () => _loadSdkAd(handle),
    );
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
    if (ad is! TopOnFullscreenHandle || ad.disposed || !ad.ready) {
      return AdShowResult.failure(
        error: StateError('Invalid or not ready TopOn fullscreen handle'),
        errorReason: 'invalid_topon_fullscreen_handle',
      );
    }

    final handle = ad;
    final completer = Completer<AdShowResult>();

    void complete(AdShowResult result) {
      if (completer.isCompleted) return;
      _eventHub.releaseFullscreen(handle);
      completer.complete(result);
    }

    void fail(Object error) {
      if (completer.isCompleted) return;
      final reason = error.toString();
      onCallback?.call(AdShowFailedCallback(handle, null, reason, null));
      complete(AdShowResult.failure(error: error, errorReason: reason));
    }

    String? networkFor(Object response) {
      final extraMap = switch (response) {
        ATInterstitialResponse() => response.extraMap,
        ATRewardResponse() => response.extraMap,
        ATSplashResponse() => response.extraMap,
        _ => const {},
      };
      final name = extraMap['network_name']?.toString().trim();
      return name == null || name.isEmpty ? handle._loadedNetwork : name;
    }

    _eventHub.registerFullscreen(handle);
    handle.onCallback = onCallback;
    handle.onDisplayed = (response) {
      onAdShowed?.call();
      onCallback?.call(AdShowedCallback(handle, networkFor(response)));
    };
    handle.onDisplayFailed = fail;
    handle.onClosed = (response) {
      onClosed?.call();
      onCallback?.call(AdClosedCallback(handle, networkFor(response)));
      complete(AdShowResult.success());
    };

    try {
      await _showSdkAd(handle);
    } catch (error) {
      fail(error);
    }

    return completer.future;
  }

  @override
  void dispose(Object ad) {
    if (ad is TopOnFullscreenHandle) _eventHub.releaseFullscreen(ad);
  }

  Future<void> _loadSdkAd(TopOnFullscreenHandle handle) async {
    switch (type) {
      case AdType.open:
        await ATSplashManager.loadSplash(
          placementID: handle.placementId,
          extraMap: handle.extraMap,
        );
        break;
      case AdType.rewarded:
        await ATRewardedManager.loadRewardedVideo(
          placementID: handle.placementId,
          extraMap: handle.extraMap,
        );
        break;
      case AdType.interstitial:
        await ATInterstitialManager.loadInterstitialAd(
          placementID: handle.placementId,
          extraMap: handle.extraMap,
        );
        break;
      default:
        throw UnsupportedError('TopOn does not support fullscreen type=$type');
    }
  }

  Future<void> _showSdkAd(TopOnFullscreenHandle handle) async {
    final sceneId = handle.sceneId;
    switch (type) {
      case AdType.open:
        if (sceneId != null) {
          await ATSplashManager.showSceneSplash(
            placementID: handle.placementId,
            sceneID: sceneId,
          );
        } else {
          await ATSplashManager.showSplash(placementID: handle.placementId);
        }
        break;
      case AdType.rewarded:
        if (sceneId != null) {
          await ATRewardedManager.showSceneRewardedVideo(
            placementID: handle.placementId,
            sceneID: sceneId,
          );
        } else {
          await ATRewardedManager.showRewardedVideo(
            placementID: handle.placementId,
          );
        }
        break;
      case AdType.interstitial:
        if (sceneId != null) {
          await ATInterstitialManager.showSceneInterstitialAd(
            placementID: handle.placementId,
            sceneID: sceneId,
          );
        } else {
          await ATInterstitialManager.showInterstitialAd(
            placementID: handle.placementId,
          );
        }
        break;
      default:
        throw UnsupportedError('TopOn does not support fullscreen type=$type');
    }
  }
}

abstract class _TopOnInlineAdapter<T extends TopOnInlineHandle>
    with CommonLoaderMixin<T>, _TopOnLoader<T>
    implements InlineAdAdapter {
  _TopOnInlineAdapter({
    required this.type,
    required TopOnEventHub eventHub,
    AppLogger? logger,
  }) : _eventHub = eventHub,
       _logger = logger ?? log;

  @override
  final AdType type;

  final TopOnEventHub _eventHub;
  @override
  final AppLogger _logger;

  @override
  AdSource get source => AdSource.topon;

  T createHandle(AdUnitConfig unit);
  void register(T handle);
  void release(T handle);
  Future<void> loadSdk(T handle);

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
    final handle = createHandle(unit)..onCallback = onCallback;
    register(handle);

    return _loadHandle(
      handle: handle,
      unit: unit,
      timeout: timeout,
      cancellationToken: cancellationToken,
      onLateAdLoaded: onLateAdLoaded,
      release: release,
      loadSdk: () => loadSdk(handle),
    );
  }

  @override
  void dispose(Object ad) {
    if (ad is T) release(ad);
  }
}

/// Inline adapter for TopOn banner ads.
class TopOnBannerAdapter extends _TopOnInlineAdapter<TopOnBannerHandle> {
  TopOnBannerAdapter({required super.eventHub, super.logger})
    : super(type: AdType.banner);

  @override
  TopOnBannerHandle createHandle(AdUnitConfig unit) {
    final options = TopOnBannerOptions.fromUnit(unit);
    return TopOnBannerHandle(
      placementId: unit.id,
      extraMap: options.extraMap,
      size: options.size,
      sceneId: options.sceneId,
    );
  }

  @override
  void register(TopOnBannerHandle handle) => _eventHub.registerBanner(handle);

  @override
  void release(TopOnBannerHandle handle) => _eventHub.releaseBanner(handle);

  @override
  Future<void> loadSdk(TopOnBannerHandle handle) {
    return ATBannerManager.loadBannerAd(
      placementID: handle.placementId,
      extraMap: handle.extraMap,
    );
  }
}

/// Inline adapter for TopOn native ads.
class TopOnNativeAdapter extends _TopOnInlineAdapter<TopOnNativeHandle> {
  TopOnNativeAdapter({required super.eventHub, super.logger})
    : super(type: AdType.native);

  @override
  TopOnNativeHandle createHandle(AdUnitConfig unit) {
    final options = TopOnNativeOptions.fromUnit(unit);
    return TopOnNativeHandle(
      placementId: unit.id,
      extraMap: options.extraMap,
      isAdaptiveHeight: options.isAdaptiveHeight,
      sceneId: options.sceneId,
    );
  }

  @override
  void register(TopOnNativeHandle handle) => _eventHub.registerNative(handle);

  @override
  void release(TopOnNativeHandle handle) => _eventHub.releaseNative(handle);

  @override
  Future<void> loadSdk(TopOnNativeHandle handle) {
    return ATNativeManager.loadNativeAd(
      placementID: handle.placementId,
      extraMap: handle.extraMap,
    );
  }
}

/// Renders a TopOn banner handle returned by the banner adapter.
class TopOnBannerView extends StatelessWidget {
  const TopOnBannerView({super.key, required this.handle});

  final TopOnBannerHandle handle;

  @override
  Widget build(BuildContext context) {
    final width = handle.size['width'];
    final height = handle.size['height'];
    return SizedBox(
      width: width is num ? width.toDouble() : null,
      height: height is num ? height.toDouble() : null,
      child: PlatformBannerWidget(handle.placementId, sceneID: handle.sceneId),
    );
  }
}

/// Renders a TopOn native handle returned by the native adapter.
class TopOnNativeView extends StatelessWidget {
  const TopOnNativeView({
    super.key,
    required this.handle,
    this.height = 280,
    this.expand = false,
  });

  final TopOnNativeHandle handle;
  final double height;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final view = PlatformNativeWidget(
      handle.placementId,
      handle.extraMap,
      sceneID: handle.sceneId,
      isAdaptiveHeight: handle.isAdaptiveHeight,
    );

    if (expand) return SizedBox.expand(child: view);
    return SizedBox(width: double.infinity, height: height, child: view);
  }
}
