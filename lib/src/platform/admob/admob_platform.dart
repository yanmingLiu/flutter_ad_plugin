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

/// AdMob SDK 初始化器
class AdmobSdkInitializer implements AdSourceSdkInitializer {
  @override
  AdSource get source => AdSource.admob;

  @override
  Future<void> init() async {
    await MobileAds.instance.initialize();
  }
}

/// AdMob 开屏广告适配器
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
    String? eventName,
    void Function(Object ad, AdType type, String adUnitId)? onLateAdLoaded,
  }) async {
    log.d('📥 load:open:${placement.name} id=${unit.id}');
    final completer = Completer<AdLoadResult<Object>>();

    Timer(timeout, () {
      if (!completer.isCompleted) {
        log.d('❌ timeout:open:${placement.name}');
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
          log.d('✅ loaded:open:${placement.name}');
          if (!completer.isCompleted) {
            completer.complete(
              AdLoadResult.success(ad: ad, type: type, adUnitId: unit.id),
            );
          } else {
            log.d('📥 late_load:open:${placement.name} (cached)');
            if (onLateAdLoaded != null) {
              onLateAdLoaded(ad, type, unit.id);
            } else {
              ad.dispose();
            }
          }
        },
        onAdFailedToLoad: (error) {
          log.d('❌ failed:open:${placement.name} code=${error.code}');
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
    String? eventName,
    required Object ad,
    required AdEventReporter reporter,
    VoidCallback? onAdShowed,
    VoidCallback? onClosed,
  }) async {
    final appOpenAd = ad as AppOpenAd;
    final completer = Completer<AdShowResult>();
    appOpenAd.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (ad) {
        onAdShowed?.call();
        reporter.report(
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
        reporter.report(
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
        reporter.report(
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
        reporter.report(
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
    String? eventName,
    void Function(Object ad, AdType type, String adUnitId)? onLateAdLoaded,
  }) async {
    log.d('📥 load:interstitial:${placement.name} id=${unit.id}');
    final completer = Completer<AdLoadResult<Object>>();

    Timer(timeout, () {
      if (!completer.isCompleted) {
        log.d('❌ timeout:interstitial:${placement.name}');
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
          log.d('✅ loaded:interstitial:${placement.name}');
          if (!completer.isCompleted) {
            completer.complete(
              AdLoadResult.success(ad: ad, type: type, adUnitId: unit.id),
            );
          } else {
            log.d('📥 late_load:interstitial:${placement.name} (cached)');
            if (onLateAdLoaded != null) {
              onLateAdLoaded(ad, type, unit.id);
            } else {
              ad.dispose();
            }
          }
        },
        onAdFailedToLoad: (error) {
          log.d('❌ failed:interstitial:${placement.name} code=${error.code}');
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
    String? eventName,
    required Object ad,
    required AdEventReporter reporter,
    VoidCallback? onAdShowed,
    VoidCallback? onClosed,
  }) async {
    final interstitialAd = ad as InterstitialAd;
    final completer = Completer<AdShowResult>();
    interstitialAd.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (ad) {
        onAdShowed?.call();
        reporter.report(
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
        reporter.report(
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
        reporter.report(
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
        reporter.report(
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
    String? eventName,
    void Function(Object ad, AdType type, String adUnitId)? onLateAdLoaded,
  }) async {
    log.d('📥 load:rewarded:${placement.name} id=${unit.id}');
    final completer = Completer<AdLoadResult<Object>>();

    Timer(timeout, () {
      if (!completer.isCompleted) {
        log.d('❌ timeout:rewarded:${placement.name}');
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
          log.d('✅ loaded:rewarded:${placement.name}');
          if (!completer.isCompleted) {
            completer.complete(
              AdLoadResult.success(ad: ad, type: type, adUnitId: unit.id),
            );
          } else {
            log.d('📥 late_load:rewarded:${placement.name} (cached)');
            if (onLateAdLoaded != null) {
              onLateAdLoaded(ad, type, unit.id);
            } else {
              ad.dispose();
            }
          }
        },
        onAdFailedToLoad: (error) {
          log.d('❌ failed:rewarded:${placement.name} code=${error.code}');
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
    String? eventName,
    required Object ad,
    required AdEventReporter reporter,
    VoidCallback? onAdShowed,
    VoidCallback? onClosed,
  }) async {
    final rewardedAd = ad as RewardedAd;
    final completer = Completer<AdShowResult>();
    bool rewardEarned = false;

    rewardedAd.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (ad) {
        onAdShowed?.call();
        reporter.report(
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
        reporter.report(
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
          completer.complete(AdShowResult.success(rewardEarned: rewardEarned));
        }
        reporter.report(
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
        reporter.report(
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

    await rewardedAd.show(
      onUserEarnedReward: (ad, item) {
        log.d(
          '💰 reward_earned:rewarded:${placement.name} amount=${item.amount}',
        );
        rewardEarned = true;
        reporter.report(
          AdEvent(
            eventType: AdEventType.rewardEarned,
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

  @override
  Future<AdLoadResult<Object>> load({
    required PlacementType placement,
    required AdUnitConfig unit,
    required Duration timeout,
    required AdEventReporter reporter,
    String? eventName,
    void Function(Object ad, AdType type, String adUnitId)? onLateAdLoaded,
  }) async {
    log.d('📥 load:native:${placement.name} id=${unit.id}');
    final completer = Completer<AdLoadResult<Object>>();

    Timer(timeout, () {
      if (!completer.isCompleted) {
        log.d('❌ timeout:native:${placement.name}');
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
          log.d('✅ loaded:native:${placement.name}');
          if (!completer.isCompleted) {
            completer.complete(
              AdLoadResult.success(
                ad: ad as NativeAd,
                type: type,
                adUnitId: unit.id,
              ),
            );
          } else {
            log.d('📥 late_load:native:${placement.name} (cached)');
            if (onLateAdLoaded != null) {
              onLateAdLoaded(ad as NativeAd, type, unit.id);
            } else {
              ad.dispose();
            }
          }
        },
        onAdFailedToLoad: (ad, error) {
          log.d('❌ failed:native:${placement.name} code=${error.code}');
          ad.dispose();
          if (!completer.isCompleted) {
            completer.complete(
              AdLoadResult.failure(type: type, adUnitId: unit.id, error: error),
            );
          }
        },
        onAdClicked: (ad) {
          reporter.report(
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
          log.d(
            '💰 income:native:${placement.name} value=$valueMicros $currencyCode',
          );
          reporter.report(
            AdEvent(
              eventType: AdEventType.income,
              placement: placement,
              adType: type,
              source: source,
              adUnitId: unit.id,
              revenue: valueMicros,
              currency: currencyCode,
              timestamp: DateTime.now(),
              eventName: eventName,
            ),
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
    String? eventName,
    required Object ad,
    required AdEventReporter reporter,
    VoidCallback? onAdShowed,
    VoidCallback? onClosed,
  }) async => AdShowResult.success();

  @override
  void dispose(Object ad) => (ad as NativeAd).dispose();
}
