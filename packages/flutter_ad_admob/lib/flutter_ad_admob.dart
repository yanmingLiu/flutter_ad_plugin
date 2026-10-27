/// AdMob 平台实现。
///
/// 一个平台一个文件：SDK 初始化、广告适配器和 widget 渲染都在这里，
/// 宿主只需要注册对应的 Platform 对象。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'package:flutter_ad_core/models.dart';
import 'package:flutter_ad_core/platform.dart';

export 'package:flutter_ad_core/flutter_ad_core.dart';

///
/// ---
/// 一步注册全部 AdMob 适配器。宿主只需在 `platforms` 中放入
/// `AdmobPlatform()`，无需手工拼装 Adapter。
class AdmobPlatform implements AdPlatform {
  AdmobPlatform({AppLogger? logger}) : _logger = logger ?? log;

  final AppLogger _logger;

  @override
  AdSource get source => AdSource.admob;

  @override
  Future<void> init() async {
    final status = await MobileAds.instance.initialize();
    for (final entry in status.adapterStatuses.entries) {
      _logger.d(
        '[admob] adapter=${entry.key} state=${entry.value.state.name} '
        'latency=${entry.value.latency}s description=${entry.value.description}',
      );
    }
  }

  /// Opens the Google Mobile Ads inspector for mediation diagnostics.
  ///
  /// This is intended for debug builds and requires a test device configured
  /// with [testDeviceIds] before ads are requested.
  void openAdInspector() {
    MobileAds.instance.openAdInspector((error) {
      if (error != null) {
        _logger.e(
          '[admob] inspector closed with error code=${error.code} '
          'domain=${error.domain} message=${error.message}',
        );
      }
    });
  }

  @override
  List<FullscreenAdAdapter> get fullscreenAdapters => [
    AdmobOpenAdapter(logger: _logger),
    AdmobInterstitialAdapter(logger: _logger),
    AdmobRewardedAdapter(logger: _logger),
    AdmobRewardedInterstitialAdapter(logger: _logger),
  ];

  @override
  List<InlineAdAdapter> get inlineAdapters => [
    AdmobNativeAdapter(logger: _logger),
    AdmobBannerAdapter(logger: _logger),
  ];

  @override
  Widget? bannerWidget(Object ad) {
    if (ad is BannerAd) {
      return SizedBox(
        width: ad.size.width.toDouble(),
        height: ad.size.height.toDouble(),
        child: AdWidget(ad: ad),
      );
    }
    return null;
  }

  @override
  Widget? nativeWidget(Object ad, {double height = 280, bool expand = false}) {
    if (ad is NativeAd) {
      return NativeAdView(ad: ad, height: height, expand: expand);
    }
    return null;
  }

  @override
  void dispose() {}
}

/// Helper: extract the network name from an ad response.
String? _networkName(AdWithoutView ad) =>
    ad.responseInfo?.loadedAdapterResponseInfo?.adSourceName;

String? _nativeNetworkName(Ad ad) =>
    (ad as NativeAd).responseInfo?.loadedAdapterResponseInfo?.adSourceName;

/// AdMob 全屏广告适配器基类。
///
/// Uses [CommonLoaderMixin] to eliminate duplicated Completer+Timer boilerplate.
/// Emits [AdRawCallback] via [onCallback] instead of calling [AdEventReporter].
abstract class _AdmobFullscreenAdapter<TAd extends AdWithoutView>
    with CommonLoaderMixin<TAd>
    implements FullscreenAdAdapter {
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

  void Function(int amount, String? label)? _rewardCallback;

  void _emitRewarded(int amount, String? label) {
    _rewardCallback?.call(amount, label);
  }

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

    _rewardCallback = (amount, label) {
      onCallback?.call(
        AdRewardedCallback(
          fullscreenAd,
          amount,
          label,
          _networkName(fullscreenAd),
        ),
      );
    };

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
    } finally {
      _rewardCallback = null;
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
    return ad.show(
      onUserEarnedReward: (ad, item) {
        _emitRewarded(item.amount.toInt(), item.type);
      },
    );
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
    return ad.show(
      onUserEarnedReward: (ad, item) {
        _emitRewarded(item.amount.toInt(), item.type);
      },
    );
  }
}

/// AdMob 原生广告适配器
///
/// No longer maintains static attribution maps. Attribution is managed by
/// the engine's [AdCacheService]. Emits [AdRawCallback] via [onCallback].
class AdmobNativeAdapter implements InlineAdAdapter {
  AdmobNativeAdapter({AppLogger? logger}) : _logger = logger ?? log;

  final AppLogger _logger;

  static const _fullScreenFactoryId = 'fullScreenNative';
  static const _homeFactoryId = 'homeListTile';

  @override
  AdSource get source => AdSource.admob;

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

    late final NativeAd ad;
    var adDisposed = false;
    void disposeAd(NativeAd nativeAd) {
      if (adDisposed) return;
      adDisposed = true;
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
  void dispose(Object ad) {
    if (ad is NativeAd) {
      ad.dispose();
    }
  }
}

/// AdMob Banner 广告适配器。
///
/// Banner ads are inline widgets rendered via [AdWidget].
/// No longer maintains static attribution maps.
class AdmobBannerAdapter implements InlineAdAdapter {
  AdmobBannerAdapter({AppLogger? logger}) : _logger = logger ?? log;

  final AppLogger _logger;

  @override
  AdSource get source => AdSource.admob;

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
  void dispose(Object ad) {
    if (ad is BannerAd) {
      ad.dispose();
    }
  }
}

class NativeAdView extends StatelessWidget {
  const NativeAdView({
    super.key,
    required this.ad,
    this.height = 280,
    this.expand = false,
  });

  /// 原始广告对象（AdMob NativeAd 或其他平台的广告对象）
  final Object ad;
  final double? height;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    if (ad is NativeAd) {
      final adWidget = AdWidget(ad: ad as NativeAd);
      if (expand) {
        return SizedBox.expand(child: adWidget);
      }
      return SizedBox(height: height, child: adWidget);
    }

    // 如果将来有其他平台，在这里继续扩展 else if (ad is MaxNativeAd) ...

    return const SizedBox.shrink();
  }
}
