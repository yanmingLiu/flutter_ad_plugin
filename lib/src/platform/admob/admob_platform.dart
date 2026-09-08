import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../api/fullscreen_native_presenter.dart';
import '../../core/ad_config.dart';
import '../../core/ad_enums.dart';
import '../../core/ad_models.dart';
import '../../utils/ad_logger.dart';
import '../../utils/cancellation_token.dart';
import '../ad_adapter.dart';
import '../ad_callback.dart';
import '../ad_loader_mixin.dart';
import '../ad_registry.dart';

/// Helper: extract the network name from an ad response.
String? _networkName(AdWithoutView ad) =>
    ad.responseInfo?.loadedAdapterResponseInfo?.adSourceName;

String? _nativeNetworkName(Ad ad) =>
    (ad as NativeAd).responseInfo?.loadedAdapterResponseInfo?.adSourceName;

/// AdMob SDK 初始化器
class AdmobSdkInitializer implements AdSourceSdkInitializer {
  @override
  AdSource get source => AdSource.admob;

  @override
  Future<void> init() async => MobileAds.instance.initialize();
}

/// AdMob 全屏广告适配器基类。
///
/// Uses [CommonLoaderMixin] to eliminate duplicated Completer+Timer boilerplate.
/// Emits [AdRawCallback] via [onCallback] instead of calling [AdEventReporter].
abstract class _AdmobFullscreenAdapter<TAd extends AdWithoutView>
    with CommonLoaderMixin<TAd>
    implements AdTypeAdapter {
  _AdmobFullscreenAdapter({AppLogger? logger}) : _logger = logger ?? log;

  final AppLogger _logger;

  @override
  AdSource get source => AdSource.admob;

  String get _loadTimeoutName;

  Future<void> _loadSdkAd({
    required String adUnitId,
    required void Function(TAd ad) onLoaded,
    required void Function(LoadAdError error) onFailed,
  });

  void _setFullScreenContentCallback(
    TAd ad,
    FullScreenContentCallback<TAd> callback,
  );

  Future<void> _showSdkAd(TAd ad);

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
    return loadWithCompleter(
      unit: unit,
      timeout: timeout,
      loadTimeoutLabel: _loadTimeoutName,
      sourceName: source.name,
      typeName: type.name,
      cancellationToken: cancellationToken,
      logger: _logger,
      onLateAdLoaded: (ad) {
        if (onLateAdLoaded != null) {
          onLateAdLoaded(ad, type, unit.id);
        } else {
          ad.dispose();
        }
      },
      startLoad: (onLoaded, onFailed) async {
        await _loadSdkAd(
          adUnitId: unit.id,
          onLoaded: onLoaded,
          onFailed: onFailed,
        );
      },
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
    final fullscreenAd = ad as TAd;
    final completer = Completer<AdShowResult>();

    fullscreenAd.onPaidEvent = (ad, valueMicros, precision, currencyCode) {
      onCallback?.call(
        AdPaidCallback(
          ad,
          valueMicros,
          currencyCode,
          _networkName(fullscreenAd),
        ),
      );
    };

    _setFullScreenContentCallback(
      fullscreenAd,
      FullScreenContentCallback<TAd>(
        onAdShowedFullScreenContent: (ad) {
          onAdShowed?.call();
          onCallback?.call(AdShowedCallback(ad, _networkName(ad)));
        },
        onAdFailedToShowFullScreenContent: (ad, error) {
          ad.dispose();
          if (!completer.isCompleted) {
            completer.complete(
              AdShowResult.failure(error: error, errorReason: error.message),
            );
          }
          onCallback?.call(
            AdShowFailedCallback(
              ad,
              error.code,
              error.message,
              _networkName(ad),
            ),
          );
        },
        onAdDismissedFullScreenContent: (ad) {
          ad.dispose();
          onClosed?.call();
          if (!completer.isCompleted) {
            completer.complete(AdShowResult.success());
          }
          onCallback?.call(AdClosedCallback(ad, _networkName(ad)));
        },
        onAdClicked: (ad) {
          onCallback?.call(AdClickedCallback(ad, _networkName(ad)));
        },
      ),
    );

    try {
      await _showSdkAd(fullscreenAd);
    } catch (e) {
      fullscreenAd.dispose();
      if (!completer.isCompleted) {
        completer.complete(
          AdShowResult.failure(error: e, errorReason: e.toString()),
        );
      }
      onCallback?.call(
        AdShowFailedCallback(fullscreenAd, null, e.toString(), null),
      );
    }

    return completer.future;
  }

  @override
  void dispose(Object ad) => (ad as TAd).dispose();
}

/// AdMob 开屏广告适配器。
class AdmobOpenAdapter extends _AdmobFullscreenAdapter<AppOpenAd> {
  AdmobOpenAdapter({super.logger});

  @override
  AdType get type => AdType.open;

  @override
  String get _loadTimeoutName => 'open';

  @override
  Future<void> _loadSdkAd({
    required String adUnitId,
    required void Function(AppOpenAd ad) onLoaded,
    required void Function(LoadAdError error) onFailed,
  }) {
    return AppOpenAd.load(
      adUnitId: adUnitId,
      request: const AdRequest(),
      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: onLoaded,
        onAdFailedToLoad: onFailed,
      ),
    );
  }

  @override
  void _setFullScreenContentCallback(
    AppOpenAd ad,
    FullScreenContentCallback<AppOpenAd> callback,
  ) => ad.fullScreenContentCallback = callback;

  @override
  Future<void> _showSdkAd(AppOpenAd ad) => ad.show();
}

/// AdMob 插屏广告适配器。
class AdmobInterstitialAdapter extends _AdmobFullscreenAdapter<InterstitialAd> {
  AdmobInterstitialAdapter({super.logger});

  @override
  AdType get type => AdType.interstitial;

  @override
  String get _loadTimeoutName => 'interstitial';

  @override
  Future<void> _loadSdkAd({
    required String adUnitId,
    required void Function(InterstitialAd ad) onLoaded,
    required void Function(LoadAdError error) onFailed,
  }) {
    return InterstitialAd.load(
      adUnitId: adUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: onLoaded,
        onAdFailedToLoad: onFailed,
      ),
    );
  }

  @override
  void _setFullScreenContentCallback(
    InterstitialAd ad,
    FullScreenContentCallback<InterstitialAd> callback,
  ) => ad.fullScreenContentCallback = callback;

  @override
  Future<void> _showSdkAd(InterstitialAd ad) => ad.show();
}

/// AdMob 激励广告适配器。
class AdmobRewardedAdapter extends _AdmobFullscreenAdapter<RewardedAd> {
  AdmobRewardedAdapter({super.logger});

  @override
  AdType get type => AdType.rewarded;

  @override
  String get _loadTimeoutName => 'rewarded';

  @override
  Future<void> _loadSdkAd({
    required String adUnitId,
    required void Function(RewardedAd ad) onLoaded,
    required void Function(LoadAdError error) onFailed,
  }) {
    return RewardedAd.load(
      adUnitId: adUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: onLoaded,
        onAdFailedToLoad: onFailed,
      ),
    );
  }

  @override
  void _setFullScreenContentCallback(
    RewardedAd ad,
    FullScreenContentCallback<RewardedAd> callback,
  ) => ad.fullScreenContentCallback = callback;

  @override
  Future<void> _showSdkAd(RewardedAd ad) {
    return ad.show(onUserEarnedReward: (ad, item) {});
  }
}

/// AdMob 插页式激励广告适配器。
class AdmobRewardedInterstitialAdapter
    extends _AdmobFullscreenAdapter<RewardedInterstitialAd> {
  AdmobRewardedInterstitialAdapter({super.logger});

  @override
  AdType get type => AdType.rewardedInterstitial;

  @override
  String get _loadTimeoutName => 'rewarded_interstitial';

  @override
  Future<void> _loadSdkAd({
    required String adUnitId,
    required void Function(RewardedInterstitialAd ad) onLoaded,
    required void Function(LoadAdError error) onFailed,
  }) {
    return RewardedInterstitialAd.load(
      adUnitId: adUnitId,
      request: const AdRequest(),
      rewardedInterstitialAdLoadCallback: RewardedInterstitialAdLoadCallback(
        onAdLoaded: onLoaded,
        onAdFailedToLoad: onFailed,
      ),
    );
  }

  @override
  void _setFullScreenContentCallback(
    RewardedInterstitialAd ad,
    FullScreenContentCallback<RewardedInterstitialAd> callback,
  ) => ad.fullScreenContentCallback = callback;

  @override
  Future<void> _showSdkAd(RewardedInterstitialAd ad) {
    return ad.show(onUserEarnedReward: (ad, item) {});
  }
}

/// AdMob 原生广告适配器
///
/// No longer maintains static attribution maps. Attribution is managed by
/// the engine's [AdCacheService]. Emits [AdRawCallback] via [onCallback].
class AdmobNativeAdapter implements AdTypeAdapter, NativeAdClickTracker {
  AdmobNativeAdapter({AppLogger? logger}) : _logger = logger ?? log;

  final AppLogger _logger;

  static const _fullScreenFactoryId = 'fullScreenNative';
  static const _homeFactoryId = 'homeListTile';

  final Map<NativeAd, _NativeAdContext> _contexts = {};
  final Map<NativeAd, Set<VoidCallback>> _clickListeners = {};

  @override
  AdSource get source => AdSource.admob;

  @override
  AdType get type => AdType.native;

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
  }) async {
    if (cancellationToken?.isCancelled ?? false) {
      return AdLoadResult.failure(
        type: type,
        adUnitId: unit.id,
        error: 'cancelled',
      );
    }
    final completer = Completer<AdLoadResult<Object>>();

    final timer = Timer(timeout, () {
      if (!completer.isCompleted) {
        _logger.v(
          '❌ [adapter_load] timeout: source=${source.name} type=${type.name} '
          'placement=${placement.name} id=${unit.id} timeout=${timeout.inSeconds}s',
        );
        completer.complete(
          AdLoadResult.failure(
            type: type,
            adUnitId: unit.id,
            error: TimeoutException('native ad load timeout'),
          ),
        );
      }
    });

    final adContext = _NativeAdContext();
    late final NativeAd ad;
    var adDisposed = false;
    void disposeAd(NativeAd nativeAd) {
      if (adDisposed) return;
      adDisposed = true;
      _contexts.remove(nativeAd);
      _clickListeners.remove(nativeAd);
      nativeAd.dispose();
    }

    final listener = NativeAdListener(
      onAdLoaded: (ad) {
        final nativeAd = ad as NativeAd;
        if (adDisposed) return;
        if (!completer.isCompleted) {
          completer.complete(
            AdLoadResult.success(ad: nativeAd, type: type, adUnitId: unit.id),
          );
          return;
        }
        if (onLateAdLoaded != null) {
          onLateAdLoaded(nativeAd, type, unit.id);
        } else {
          disposeAd(nativeAd);
        }
      },
      onAdFailedToLoad: (ad, error) {
        _logger.v(
          '❌ [adapter_load] failed: source=${source.name} type=${type.name} '
          'placement=${placement.name} id=${unit.id} code=${error.code} '
          'message=${error.message}',
        );
        if (ad is NativeAd) disposeAd(ad);
        if (!completer.isCompleted) {
          completer.complete(
            AdLoadResult.failure(type: type, adUnitId: unit.id, error: error),
          );
        }
      },
      onAdClicked: (ad) {
        if (ad is NativeAd) {
          final context = _contexts.putIfAbsent(ad, _NativeAdContext.new);
          context.clicked = true;
          final listeners = _clickListeners[ad];
          if (listeners != null) {
            for (final listener in List<VoidCallback>.of(listeners)) {
              listener();
            }
          }
        }
        onCallback?.call(AdClickedCallback(ad, _nativeNetworkName(ad)));
      },
      onAdImpression: (ad) {
        onCallback?.call(AdImpressionCallback(ad, _nativeNetworkName(ad)));
      },
      onPaidEvent: (ad, valueMicros, precision, currencyCode) {
        onCallback?.call(
          AdPaidCallback(ad, valueMicros, currencyCode, _nativeNetworkName(ad)),
        );
      },
    );

    if (renderAsFullscreen) {
      ad = NativeAd(
        adUnitId: unit.id,
        factoryId: unit.factoryId ?? _fullScreenFactoryId,
        nativeAdOptions: NativeAdOptions(
          adChoicesPlacement: AdChoicesPlacement.topLeftCorner,
        ),
        request: const AdRequest(),
        listener: listener,
      );
    } else {
      ad = NativeAd(
        adUnitId: unit.id,
        factoryId: unit.factoryId ?? _homeFactoryId,
        request: const AdRequest(),
        listener: listener,
      );
    }
    _contexts[ad] = adContext;
    final removeCancellationListener = cancellationToken?.addListener(() {
      if (!completer.isCompleted) {
        completer.complete(
          AdLoadResult.failure(
            type: type,
            adUnitId: unit.id,
            error: 'cancelled',
          ),
        );
        disposeAd(ad);
      }
    });
    try {
      await ad.load();
    } catch (error) {
      disposeAd(ad);
      if (!completer.isCompleted) {
        completer.complete(
          AdLoadResult.failure(type: type, adUnitId: unit.id, error: error),
        );
      }
    }
    return completer.future.whenComplete(() {
      timer.cancel();
      removeCancellationListener?.call();
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
    onAdShowed?.call();
    return AdShowResult.success();
  }

  @override
  void dispose(Object ad) {
    if (ad is NativeAd) {
      _contexts.remove(ad);
      _clickListeners.remove(ad);
      ad.dispose();
    }
  }

  @override
  bool hasClicked(Object ad) {
    return ad is NativeAd && (_contexts[ad]?.clicked ?? false);
  }

  @override
  void addClickListener(Object ad, VoidCallback listener) {
    if (ad is! NativeAd) {
      return;
    }
    _clickListeners.putIfAbsent(ad, () => <VoidCallback>{}).add(listener);
  }

  @override
  void removeClickListener(Object ad, VoidCallback listener) {
    if (ad is! NativeAd) {
      return;
    }
    final listeners = _clickListeners[ad];
    if (listeners == null) {
      return;
    }
    listeners.remove(listener);
    if (listeners.isEmpty) {
      _clickListeners.remove(ad);
    }
  }
}

class _NativeAdContext {
  bool clicked = false;
}

/// AdMob Banner 广告适配器。
///
/// Banner ads are inline widgets rendered via [AdWidget].
/// No longer maintains static attribution maps.
class AdmobBannerAdapter implements AdTypeAdapter {
  AdmobBannerAdapter({AppLogger? logger}) : _logger = logger ?? log;

  final AppLogger _logger;

  @override
  AdSource get source => AdSource.admob;

  @override
  AdType get type => AdType.banner;

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
  }) async {
    if (cancellationToken?.isCancelled ?? false) {
      return AdLoadResult.failure(
        type: type,
        adUnitId: unit.id,
        error: 'cancelled',
      );
    }
    final completer = Completer<AdLoadResult<Object>>();

    final timer = Timer(timeout, () {
      if (!completer.isCompleted) {
        _logger.v(
          '❌ [adapter_load] timeout: source=${source.name} type=${type.name} '
          'placement=${placement.name} id=${unit.id} timeout=${timeout.inSeconds}s',
        );
        completer.complete(
          AdLoadResult.failure(
            type: type,
            adUnitId: unit.id,
            error: TimeoutException('banner ad load timeout'),
          ),
        );
      }
    });

    late final BannerAd ad;
    var adDisposed = false;
    void disposeAd() {
      if (adDisposed) return;
      adDisposed = true;
      ad.dispose();
    }

    ad = BannerAd(
      adUnitId: unit.id,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          final bannerAd = ad as BannerAd;
          if (adDisposed) return;
          if (!completer.isCompleted) {
            completer.complete(
              AdLoadResult.success(ad: bannerAd, type: type, adUnitId: unit.id),
            );
            return;
          }
          if (onLateAdLoaded != null) {
            onLateAdLoaded(bannerAd, type, unit.id);
          } else {
            disposeAd();
          }
        },
        onAdFailedToLoad: (ad, error) {
          _logger.v(
            '❌ [adapter_load] failed: source=${source.name} type=${type.name} '
            'placement=${placement.name} id=${unit.id} code=${error.code} '
            'message=${error.message}',
          );
          disposeAd();
          if (!completer.isCompleted) {
            completer.complete(
              AdLoadResult.failure(type: type, adUnitId: unit.id, error: error),
            );
          }
        },
        onAdClicked: (ad) {
          onCallback?.call(
            AdClickedCallback(
              ad,
              ad.responseInfo?.loadedAdapterResponseInfo?.adSourceName,
            ),
          );
        },
        onAdImpression: (ad) {
          onCallback?.call(
            AdImpressionCallback(
              ad,
              ad.responseInfo?.loadedAdapterResponseInfo?.adSourceName,
            ),
          );
        },
        onPaidEvent: (ad, valueMicros, precision, currencyCode) {
          onCallback?.call(
            AdPaidCallback(
              ad,
              valueMicros,
              currencyCode,
              ad.responseInfo?.loadedAdapterResponseInfo?.adSourceName,
            ),
          );
        },
      ),
    );
    final removeCancellationListener = cancellationToken?.addListener(() {
      if (!completer.isCompleted) {
        completer.complete(
          AdLoadResult.failure(
            type: type,
            adUnitId: unit.id,
            error: 'cancelled',
          ),
        );
        disposeAd();
      }
    });

    try {
      await ad.load();
    } catch (e) {
      _logger.v(
        '❌ [adapter_load] failed: source=${source.name} type=${type.name} '
        'id=${unit.id} error=$e',
      );
      disposeAd();
      if (!completer.isCompleted) {
        completer.complete(
          AdLoadResult.failure(type: type, adUnitId: unit.id, error: e),
        );
      }
    }

    return completer.future.whenComplete(() {
      timer.cancel();
      removeCancellationListener?.call();
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
    onAdShowed?.call();
    return AdShowResult.success();
  }

  @override
  void dispose(Object ad) {
    if (ad is BannerAd) {
      ad.dispose();
    }
  }
}
