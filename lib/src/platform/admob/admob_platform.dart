import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../core/ad_config.dart';
import '../../core/ad_enums.dart';
import '../../core/ad_models.dart';
import '../../utils/ad_logger.dart';
import '../../utils/ad_reporter.dart';
import '../ad_adapter.dart';
import '../ad_registry.dart';

void _reportPaidEvent({
  required AdEventReporter reporter,
  required PlacementType placement,
  String? placementLabel,
  required String eventName,
  required AdType adType,
  required AdSource source,
  required String adUnitId,
  required double valueMicros,
  required String currencyCode,
}) {
  _reportLifecycleEvent(
    reporter,
    AdEvent(
      eventType: AdEventType.income,
      placement: placement,
      placementLabel: placementLabel,
      adType: adType,
      source: source,
      adUnitId: adUnitId,
      revenue: valueMicros,
      currency: currencyCode,
      timestamp: DateTime.now(),
      eventName: eventName,
    ),
  );
}

void _reportLifecycleEvent(AdEventReporter reporter, AdEvent event) {
  log.event(event);
  reporter.report(event);
}

/// AdMob SDK 初始化器
class AdmobSdkInitializer implements AdSourceSdkInitializer {
  @override
  AdSource get source => AdSource.admob;

  @override
  Future<void> init() async {
    await MobileAds.instance.initialize();
  }
}

/// AdMob 开屏广告适配器。
///
/// show() 通过 Completer 实现：在 onAdShowedFullScreenContent 中上报展示成功，
/// 但 completer 仅在 onAdDismissedFullScreenContent（用户关闭）或
/// onAdFailedToShowFullScreenContent（展示失败）时 complete。
/// 因此 await show() 会等到广告关闭后才返回。
class AdmobOpenAdapter implements AdTypeAdapter {
  @override
  AdSource get source => AdSource.admob;

  @override
  AdType get type => AdType.open;

  @override
  Future<AdLoadResult<Object>> load({
    required PlacementType placement,
    required AdUnitConfig unit,
    required Duration timeout,
    required AdEventReporter reporter,
    required String eventName,
    void Function(Object ad, AdType type, String adUnitId)? onLateAdLoaded,
  }) async {
    log.v(
      '📥 [adapter_load] start: source=${source.name} type=${type.name} '
      'placement=${placement.name} id=${unit.id} timeout=${timeout.inSeconds}s '
      'event=$eventName',
    );
    final completer = Completer<AdLoadResult<Object>>();

    Timer(timeout, () {
      if (!completer.isCompleted) {
        log.v(
          '❌ [adapter_load] timeout: source=${source.name} type=${type.name} '
          'placement=${placement.name} id=${unit.id} timeout=${timeout.inSeconds}s',
        );
        completer.complete(
          AdLoadResult.failure(
            type: type,
            adUnitId: unit.id,
            error: TimeoutException('open ad load timeout'),
          ),
        );
      }
    });

    await AppOpenAd.load(
      adUnitId: unit.id,
      request: const AdRequest(),
      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: (ad) {
          log.v(
            '✅ [adapter_load] loaded: source=${source.name} type=${type.name} '
            'placement=${placement.name} id=${unit.id}',
          );
          if (!completer.isCompleted) {
            completer.complete(
              AdLoadResult.success(ad: ad, type: type, adUnitId: unit.id),
            );
          } else {
            if (onLateAdLoaded != null) {
              onLateAdLoaded(ad, type, unit.id);
            } else {
              ad.dispose();
            }
          }
        },
        onAdFailedToLoad: (error) {
          log.v(
            '❌ [adapter_load] failed: source=${source.name} type=${type.name} '
            'placement=${placement.name} id=${unit.id} code=${error.code} '
            'message=${error.message}',
          );
          if (!completer.isCompleted) {
            completer.complete(
              AdLoadResult.failure(type: type, adUnitId: unit.id, error: error),
            );
          }
        },
      ),
    );
    return completer.future;
  }

  @override
  Future<AdShowResult> show({
    required PlacementType placement,
    String? placementLabel,
    required String eventName,
    required Object ad,
    required AdEventReporter reporter,
    VoidCallback? onAdShowed,
    VoidCallback? onClosed,
  }) async {
    final appOpenAd = ad as AppOpenAd;
    final completer = Completer<AdShowResult>();
    appOpenAd.onPaidEvent = (ad, valueMicros, precision, currencyCode) {
      _reportPaidEvent(
        reporter: reporter,
        placement: placement,
        placementLabel: placementLabel,
        eventName: eventName,
        adType: type,
        source: source,
        adUnitId: ad.adUnitId,
        valueMicros: valueMicros,
        currencyCode: currencyCode,
      );
    };
    appOpenAd.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (ad) {
        onAdShowed?.call();
        _reportLifecycleEvent(
          reporter,
          AdEvent(
            eventType: AdEventType.showSuccess,
            placement: placement,
            placementLabel: placementLabel,
            adType: type,
            source: source,
            adUnitId: ad.adUnitId,
            timestamp: DateTime.now(),
            eventName: eventName,
          ),
        );
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        completer.complete(AdShowResult.failure(error));
        _reportLifecycleEvent(
          reporter,
          AdEvent(
            eventType: AdEventType.showFail,
            placement: placement,
            placementLabel: placementLabel,
            adType: type,
            source: source,
            adUnitId: ad.adUnitId,
            errorCode: error.code,
            errorReason: error.message,
            timestamp: DateTime.now(),
            eventName: eventName,
          ),
        );
      },
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        onClosed?.call();
        if (!completer.isCompleted) completer.complete(AdShowResult.success());
        _reportLifecycleEvent(
          reporter,
          AdEvent(
            eventType: AdEventType.close,
            placement: placement,
            placementLabel: placementLabel,
            adType: type,
            source: source,
            adUnitId: ad.adUnitId,
            timestamp: DateTime.now(),
            eventName: eventName,
          ),
        );
      },
      onAdClicked: (ad) {
        _reportLifecycleEvent(
          reporter,
          AdEvent(
            eventType: AdEventType.clicked,
            placement: placement,
            placementLabel: placementLabel,
            adType: type,
            source: source,
            adUnitId: ad.adUnitId,
            timestamp: DateTime.now(),
            eventName: eventName,
          ),
        );
      },
    );

    await appOpenAd.show();
    return completer.future;
  }

  @override
  void dispose(Object ad) => (ad as AppOpenAd).dispose();
}

/// AdMob 插屏广告适配器
class AdmobInterstitialAdapter implements AdTypeAdapter {
  @override
  AdSource get source => AdSource.admob;
  @override
  AdType get type => AdType.interstitial;

  @override
  Future<AdLoadResult<Object>> load({
    required PlacementType placement,
    required AdUnitConfig unit,
    required Duration timeout,
    required AdEventReporter reporter,
    required String eventName,
    void Function(Object ad, AdType type, String adUnitId)? onLateAdLoaded,
  }) async {
    log.v(
      '📥 [adapter_load] start: source=${source.name} type=${type.name} '
      'placement=${placement.name} id=${unit.id} timeout=${timeout.inSeconds}s '
      'event=$eventName',
    );
    final completer = Completer<AdLoadResult<Object>>();

    Timer(timeout, () {
      if (!completer.isCompleted) {
        log.v(
          '❌ [adapter_load] timeout: source=${source.name} type=${type.name} '
          'placement=${placement.name} id=${unit.id} timeout=${timeout.inSeconds}s',
        );
        completer.complete(
          AdLoadResult.failure(
            type: type,
            adUnitId: unit.id,
            error: TimeoutException('interstitial ad load timeout'),
          ),
        );
      }
    });

    await InterstitialAd.load(
      adUnitId: unit.id,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          log.v(
            '✅ [adapter_load] loaded: source=${source.name} type=${type.name} '
            'placement=${placement.name} id=${unit.id}',
          );
          if (!completer.isCompleted) {
            completer.complete(
              AdLoadResult.success(ad: ad, type: type, adUnitId: unit.id),
            );
          } else {
            if (onLateAdLoaded != null) {
              onLateAdLoaded(ad, type, unit.id);
            } else {
              ad.dispose();
            }
          }
        },
        onAdFailedToLoad: (error) {
          log.v(
            '❌ [adapter_load] failed: source=${source.name} type=${type.name} '
            'placement=${placement.name} id=${unit.id} code=${error.code} '
            'message=${error.message}',
          );
          if (!completer.isCompleted) {
            completer.complete(
              AdLoadResult.failure(type: type, adUnitId: unit.id, error: error),
            );
          }
        },
      ),
    );
    return completer.future;
  }

  @override
  Future<AdShowResult> show({
    required PlacementType placement,
    String? placementLabel,
    required String eventName,
    required Object ad,
    required AdEventReporter reporter,
    VoidCallback? onAdShowed,
    VoidCallback? onClosed,
  }) async {
    final interstitialAd = ad as InterstitialAd;
    final completer = Completer<AdShowResult>();
    interstitialAd.onPaidEvent = (ad, valueMicros, precision, currencyCode) {
      _reportPaidEvent(
        reporter: reporter,
        placement: placement,
        placementLabel: placementLabel,
        eventName: eventName,
        adType: type,
        source: source,
        adUnitId: ad.adUnitId,
        valueMicros: valueMicros,
        currencyCode: currencyCode,
      );
    };
    interstitialAd.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (ad) {
        onAdShowed?.call();
        _reportLifecycleEvent(
          reporter,
          AdEvent(
            eventType: AdEventType.showSuccess,
            placement: placement,
            placementLabel: placementLabel,
            adType: type,
            source: source,
            adUnitId: ad.adUnitId,
            timestamp: DateTime.now(),
            eventName: eventName,
          ),
        );
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        completer.complete(AdShowResult.failure(error));
        _reportLifecycleEvent(
          reporter,
          AdEvent(
            eventType: AdEventType.showFail,
            placement: placement,
            placementLabel: placementLabel,
            adType: type,
            source: source,
            adUnitId: ad.adUnitId,
            errorCode: error.code,
            errorReason: error.message,
            timestamp: DateTime.now(),
            eventName: eventName,
          ),
        );
      },
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        onClosed?.call();
        if (!completer.isCompleted) completer.complete(AdShowResult.success());
        _reportLifecycleEvent(
          reporter,
          AdEvent(
            eventType: AdEventType.close,
            placement: placement,
            placementLabel: placementLabel,
            adType: type,
            source: source,
            adUnitId: ad.adUnitId,
            timestamp: DateTime.now(),
            eventName: eventName,
          ),
        );
      },
      onAdClicked: (ad) {
        _reportLifecycleEvent(
          reporter,
          AdEvent(
            eventType: AdEventType.clicked,
            placement: placement,
            placementLabel: placementLabel,
            adType: type,
            source: source,
            adUnitId: ad.adUnitId,
            timestamp: DateTime.now(),
            eventName: eventName,
          ),
        );
      },
    );
    await interstitialAd.show();
    return completer.future;
  }

  @override
  void dispose(Object ad) => (ad as InterstitialAd).dispose();
}

/// AdMob 激励广告适配器
class AdmobRewardedAdapter implements AdTypeAdapter {
  @override
  AdSource get source => AdSource.admob;
  @override
  AdType get type => AdType.rewarded;

  @override
  Future<AdLoadResult<Object>> load({
    required PlacementType placement,
    required AdUnitConfig unit,
    required Duration timeout,
    required AdEventReporter reporter,
    required String eventName,
    void Function(Object ad, AdType type, String adUnitId)? onLateAdLoaded,
  }) async {
    log.v(
      '📥 [adapter_load] start: source=${source.name} type=${type.name} '
      'placement=${placement.name} id=${unit.id} timeout=${timeout.inSeconds}s '
      'event=$eventName',
    );
    final completer = Completer<AdLoadResult<Object>>();

    Timer(timeout, () {
      if (!completer.isCompleted) {
        log.v(
          '❌ [adapter_load] timeout: source=${source.name} type=${type.name} '
          'placement=${placement.name} id=${unit.id} timeout=${timeout.inSeconds}s',
        );
        completer.complete(
          AdLoadResult.failure(
            type: type,
            adUnitId: unit.id,
            error: TimeoutException('rewarded ad load timeout'),
          ),
        );
      }
    });

    await RewardedAd.load(
      adUnitId: unit.id,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          log.v(
            '✅ [adapter_load] loaded: source=${source.name} type=${type.name} '
            'placement=${placement.name} id=${unit.id}',
          );
          if (!completer.isCompleted) {
            completer.complete(
              AdLoadResult.success(ad: ad, type: type, adUnitId: unit.id),
            );
          } else {
            if (onLateAdLoaded != null) {
              onLateAdLoaded(ad, type, unit.id);
            } else {
              ad.dispose();
            }
          }
        },
        onAdFailedToLoad: (error) {
          log.v(
            '❌ [adapter_load] failed: source=${source.name} type=${type.name} '
            'placement=${placement.name} id=${unit.id} code=${error.code} '
            'message=${error.message}',
          );
          if (!completer.isCompleted) {
            completer.complete(
              AdLoadResult.failure(type: type, adUnitId: unit.id, error: error),
            );
          }
        },
      ),
    );
    return completer.future;
  }

  @override
  Future<AdShowResult> show({
    required PlacementType placement,
    String? placementLabel,
    required String eventName,
    required Object ad,
    required AdEventReporter reporter,
    VoidCallback? onAdShowed,
    VoidCallback? onClosed,
  }) async {
    final rewardedAd = ad as RewardedAd;
    final completer = Completer<AdShowResult>();
    rewardedAd.onPaidEvent = (ad, valueMicros, precision, currencyCode) {
      _reportPaidEvent(
        reporter: reporter,
        placement: placement,
        placementLabel: placementLabel,
        eventName: eventName,
        adType: type,
        source: source,
        adUnitId: ad.adUnitId,
        valueMicros: valueMicros,
        currencyCode: currencyCode,
      );
    };

    rewardedAd.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (ad) {
        onAdShowed?.call();
        _reportLifecycleEvent(
          reporter,
          AdEvent(
            eventType: AdEventType.showSuccess,
            placement: placement,
            placementLabel: placementLabel,
            adType: type,
            source: source,
            adUnitId: ad.adUnitId,
            timestamp: DateTime.now(),
            eventName: eventName,
          ),
        );
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        completer.complete(AdShowResult.failure(error));
        _reportLifecycleEvent(
          reporter,
          AdEvent(
            eventType: AdEventType.showFail,
            placement: placement,
            placementLabel: placementLabel,
            adType: type,
            source: source,
            adUnitId: ad.adUnitId,
            errorCode: error.code,
            errorReason: error.message,
            timestamp: DateTime.now(),
            eventName: eventName,
          ),
        );
      },
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        onClosed?.call();
        if (!completer.isCompleted) {
          completer.complete(AdShowResult.success());
        }
        _reportLifecycleEvent(
          reporter,
          AdEvent(
            eventType: AdEventType.close,
            placement: placement,
            placementLabel: placementLabel,
            adType: type,
            source: source,
            adUnitId: ad.adUnitId,
            timestamp: DateTime.now(),
            eventName: eventName,
          ),
        );
      },
      onAdClicked: (ad) {
        _reportLifecycleEvent(
          reporter,
          AdEvent(
            eventType: AdEventType.clicked,
            placement: placement,
            placementLabel: placementLabel,
            adType: type,
            source: source,
            adUnitId: ad.adUnitId,
            timestamp: DateTime.now(),
            eventName: eventName,
          ),
        );
      },
    );

    await rewardedAd.show(onUserEarnedReward: (ad, item) {});

    return completer.future;
  }

  @override
  void dispose(Object ad) => (ad as RewardedAd).dispose();
}

/// AdMob 原生广告适配器
class AdmobNativeAdapter implements AdTypeAdapter {
  @override
  AdSource get source => AdSource.admob;
  @override
  AdType get type => AdType.native;

  static final Map<NativeAd, NativeAdAttribution> _attributions = {};

  static void updateAttribution({
    required Object ad,
    required PlacementType placement,
    String? placementLabel,
    required String eventName,
  }) {
    if (ad is! NativeAd) {
      return;
    }
    final attribution = _attributions[ad];
    if (attribution == null) {
      _attributions[ad] = NativeAdAttribution(
        placement: placement,
        placementLabel: placementLabel,
        eventName: eventName,
      );
      return;
    }
    attribution
      ..placement = placement
      ..placementLabel = placementLabel
      ..eventName = eventName;
  }

  @override
  Future<AdLoadResult<Object>> load({
    required PlacementType placement,
    required AdUnitConfig unit,
    required Duration timeout,
    required AdEventReporter reporter,
    required String eventName,
    void Function(Object ad, AdType type, String adUnitId)? onLateAdLoaded,
  }) async {
    log.v(
      '📥 [adapter_load] start: source=${source.name} type=${type.name} '
      'placement=${placement.name} id=${unit.id} timeout=${timeout.inSeconds}s '
      'template=${unit.templateType ?? 'medium'} event=$eventName',
    );
    final completer = Completer<AdLoadResult<Object>>();

    Timer(timeout, () {
      if (!completer.isCompleted) {
        log.v(
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

    final templateType = unit.templateType?.toLowerCase() == 'small'
        ? TemplateType.small
        : TemplateType.medium;

    final ad = NativeAd(
      adUnitId: unit.id,
      nativeTemplateStyle: NativeTemplateStyle(templateType: templateType),
      request: const AdRequest(),
      listener: NativeAdListener(
        onAdLoaded: (ad) {
          log.v(
            '✅ [adapter_load] loaded: source=${source.name} type=${type.name} '
            'placement=${placement.name} id=${unit.id}',
          );
          final nativeAd = ad as NativeAd;
          _attributions[nativeAd] = NativeAdAttribution(
            placement: placement,
            eventName: eventName,
          );
          if (!completer.isCompleted) {
            completer.complete(
              AdLoadResult.success(ad: nativeAd, type: type, adUnitId: unit.id),
            );
          } else {
            if (onLateAdLoaded != null) {
              onLateAdLoaded(nativeAd, type, unit.id);
            } else {
              nativeAd.dispose();
            }
          }
        },
        onAdFailedToLoad: (ad, error) {
          log.v(
            '❌ [adapter_load] failed: source=${source.name} type=${type.name} '
            'placement=${placement.name} id=${unit.id} code=${error.code} '
            'message=${error.message}',
          );
          ad.dispose();
          if (!completer.isCompleted) {
            completer.complete(
              AdLoadResult.failure(type: type, adUnitId: unit.id, error: error),
            );
          }
        },
        onAdClicked: (ad) {
          _reportLifecycleEvent(
            reporter,
            AdEvent(
              eventType: AdEventType.clicked,
              placement: placement,
              adType: type,
              source: source,
              adUnitId: unit.id,
              timestamp: DateTime.now(),
              eventName: eventName,
            ),
          );
        },
        onPaidEvent: (ad, valueMicros, precision, currencyCode) {
          final attribution = _attributions[ad];
          final reportPlacement = attribution?.placement ?? placement;
          _reportPaidEvent(
            reporter: reporter,
            placement: reportPlacement,
            placementLabel: attribution?.placementLabel,
            eventName: attribution?.eventName ?? eventName,
            adType: type,
            source: source,
            adUnitId: unit.id,
            valueMicros: valueMicros,
            currencyCode: currencyCode,
          );
        },
      ),
    );
    await ad.load();
    return completer.future;
  }

  @override
  Future<AdShowResult> show({
    required PlacementType placement,
    String? placementLabel,
    required String eventName,
    required Object ad,
    required AdEventReporter reporter,
    VoidCallback? onAdShowed,
    VoidCallback? onClosed,
  }) async => AdShowResult.success();

  @override
  void dispose(Object ad) {
    if (ad is NativeAd) {
      _attributions.remove(ad);
      ad.dispose();
    }
  }
}
