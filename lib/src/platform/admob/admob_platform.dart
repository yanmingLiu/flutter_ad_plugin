import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../core/ad_config.dart';
import '../../core/ad_enums.dart';
import '../../core/ad_models.dart';
import '../../ui/fullscreen_native_ad_view.dart';
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
  String? network,
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
      network: network,
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

/// AdMob 全屏广告适配器基类。
///
/// 开屏、插屏、激励的加载和展示生命周期基本一致，差异只在 SDK load/show
/// 调用和具体广告对象类型。公共流程集中在这里，避免三套生命周期重复漂移。
abstract class _AdmobFullscreenAdapter<TAd extends AdWithoutView>
    implements AdTypeAdapter {
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
    required AdEventReporter reporter,
    required String eventName,
    bool renderAsFullscreen = false,
    void Function(Object ad, AdType type, String adUnitId)? onLateAdLoaded,
  }) async {
    final completer = Completer<AdLoadResult<Object>>();

    final timer = Timer(timeout, () {
      if (!completer.isCompleted) {
        log.v(
          '❌ [adapter_load] timeout: source=${source.name} type=${type.name} '
          'placement=${placement.name} id=${unit.id} timeout=${timeout.inSeconds}s',
        );
        completer.complete(
          AdLoadResult.failure(
            type: type,
            adUnitId: unit.id,
            error: TimeoutException('$_loadTimeoutName ad load timeout'),
          ),
        );
      }
    });

    try {
      await _loadSdkAd(
        adUnitId: unit.id,
        onLoaded: (ad) {
          if (!completer.isCompleted) {
            completer.complete(
              AdLoadResult.success(ad: ad, type: type, adUnitId: unit.id),
            );
            return;
          }

          if (onLateAdLoaded != null) {
            onLateAdLoaded(ad, type, unit.id);
          } else {
            ad.dispose();
          }
        },
        onFailed: (error) {
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
      );
    } catch (e) {
      log.v(
        '❌ [adapter_load] failed: source=${source.name} type=${type.name} '
        'placement=${placement.name} id=${unit.id} error=$e',
      );
      if (!completer.isCompleted) {
        completer.complete(
          AdLoadResult.failure(type: type, adUnitId: unit.id, error: e),
        );
      }
    }

    return completer.future.whenComplete(timer.cancel);
  }

  @override
  Future<AdShowResult> show({
    required PlacementType placement,
    BuildContext? context,
    String? placementLabel,
    required String eventName,
    required Object ad,
    required AdEventReporter reporter,
    VoidCallback? onAdShowed,
    VoidCallback? onClosed,
    int closePassThroughPercent = 0,
    AdFullScreenNativeStyle style = const AdFullScreenNativeStyle(),
  }) async {
    final fullscreenAd = ad as TAd;
    final completer = Completer<AdShowResult>();

    fullscreenAd.onPaidEvent = (ad, valueMicros, precision, currencyCode) {
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
        network: ad.responseInfo?.loadedAdapterResponseInfo?.adSourceName,
      );
    };

    _setFullScreenContentCallback(
      fullscreenAd,
      FullScreenContentCallback<TAd>(
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
              network: ad.responseInfo?.loadedAdapterResponseInfo?.adSourceName,
            ),
          );
        },
        onAdFailedToShowFullScreenContent: (ad, error) {
          ad.dispose();
          if (!completer.isCompleted) {
            completer.complete(AdShowResult.failure(error));
          }
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
              network: ad.responseInfo?.loadedAdapterResponseInfo?.adSourceName,
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
              network: ad.responseInfo?.loadedAdapterResponseInfo?.adSourceName,
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
              network: ad.responseInfo?.loadedAdapterResponseInfo?.adSourceName,
            ),
          );
        },
      ),
    );

    try {
      await _showSdkAd(fullscreenAd);
    } catch (e) {
      fullscreenAd.dispose();
      if (!completer.isCompleted) {
        completer.complete(AdShowResult.failure(e));
      }
      _reportLifecycleEvent(
        reporter,
        AdEvent(
          eventType: AdEventType.showFail,
          placement: placement,
          placementLabel: placementLabel,
          adType: type,
          source: source,
          adUnitId: fullscreenAd.adUnitId,
          errorReason: e.toString(),
          timestamp: DateTime.now(),
          eventName: eventName,
        ),
      );
    }

    return completer.future;
  }

  @override
  void dispose(Object ad) => (ad as TAd).dispose();
}

/// AdMob 开屏广告适配器。
class AdmobOpenAdapter extends _AdmobFullscreenAdapter<AppOpenAd> {
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
  ) {
    ad.fullScreenContentCallback = callback;
  }

  @override
  Future<void> _showSdkAd(AppOpenAd ad) => ad.show();
}

/// AdMob 插屏广告适配器。
class AdmobInterstitialAdapter extends _AdmobFullscreenAdapter<InterstitialAd> {
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
  ) {
    ad.fullScreenContentCallback = callback;
  }

  @override
  Future<void> _showSdkAd(InterstitialAd ad) => ad.show();
}

/// AdMob 激励广告适配器。
class AdmobRewardedAdapter extends _AdmobFullscreenAdapter<RewardedAd> {
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
  ) {
    ad.fullScreenContentCallback = callback;
  }

  @override
  Future<void> _showSdkAd(RewardedAd ad) {
    return ad.show(onUserEarnedReward: (ad, item) {});
  }
}

/// AdMob 原生广告适配器
class AdmobNativeAdapter implements AdTypeAdapter {
  /// The factory ID for inline native ads using the home list-tile layout.
  ///
  /// @Deprecated: Use `native_factory_id` in your JSON ad-unit config instead.
  /// Migrate by adding `"native_factory_id": "homeListTile"` to the relevant
  /// ad unit in your config JSON, then register a matching `NativeAdFactory`
  /// on the native side.
  ///
  /// 已弃用：请在 JSON 配置中使用 `native_factory_id` 字段替代。
  @Deprecated('Use native_factory_id in AdUnitConfig instead.')
  static const String homeFactoryId = 'homeListTile';

  /// The factory ID for fullscreen native ads.
  ///
  /// @Deprecated: Use `native_factory_id` in your JSON ad-unit config instead.
  /// Migrate by adding `"native_factory_id": "fullScreenNative"` to the relevant
  /// ad unit in your config JSON, then register a matching `NativeAdFactory`
  /// on the native side.
  ///
  /// 已弃用：请在 JSON 配置中使用 `native_factory_id` 字段替代。
  @Deprecated('Use native_factory_id in AdUnitConfig instead.')
  static const String fullScreenFactoryId = 'fullScreenNative';
  static const String _androidNativeVideoTestAdUnitId =
      'ca-app-pub-3940256099942544/1044960115';
  static const String _androidNativeAdvancedTestAdUnitId =
      'ca-app-pub-3940256099942544/2247696110';

  @override
  AdSource get source => AdSource.admob;
  @override
  AdType get type => AdType.native;

  static final Map<NativeAd, NativeAdAttribution> _attributions = {};
  static final Map<NativeAd, _NativeAdState> _states = {};

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

  static bool hasClicked(Object ad) {
    return ad is NativeAd && (_states[ad]?.clicked ?? false);
  }

  static void addClickListener(Object ad, VoidCallback listener) {
    if (ad is! NativeAd) {
      return;
    }
    _states.putIfAbsent(ad, _NativeAdState.new).clickListeners.add(listener);
  }

  static void removeClickListener(Object ad, VoidCallback listener) {
    if (ad is! NativeAd) {
      return;
    }
    final state = _states[ad];
    if (state == null) {
      return;
    }
    state.clickListeners.remove(listener);
  }

  @override
  Future<AdLoadResult<Object>> load({
    required PlacementType placement,
    required AdUnitConfig unit,
    required Duration timeout,
    required AdEventReporter reporter,
    required String eventName,
    bool renderAsFullscreen = false,
    void Function(Object ad, AdType type, String adUnitId)? onLateAdLoaded,
  }) async {
    final completer = Completer<AdLoadResult<Object>>();

    final timer = Timer(timeout, () {
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

    final isFullscreenNative = renderAsFullscreen;
    final templateType = unit.templateType?.toLowerCase() == 'small'
        ? TemplateType.small
        : TemplateType.medium;

    void startLoad({
      required String adUnitId,
      required bool allowAndroidTestFallback,
    }) {
      final ad = NativeAd(
        adUnitId: adUnitId,
        factoryId: isFullscreenNative
            // ignore: deprecated_member_use_from_same_package
            ? (unit.nativeFactoryId ?? fullScreenFactoryId)
            : unit.nativeFactoryId,
        nativeAdOptions: isFullscreenNative
            ? NativeAdOptions(
                adChoicesPlacement: AdChoicesPlacement.topLeftCorner,
              )
            : null,
        nativeTemplateStyle:
            isFullscreenNative || unit.nativeFactoryId != null
                ? null
                : NativeTemplateStyle(templateType: templateType),
        request: const AdRequest(),
        listener: NativeAdListener(
          onAdLoaded: (ad) {
            final nativeAd = ad as NativeAd;
            _attributions[nativeAd] = NativeAdAttribution(
              placement: placement,
              eventName: eventName,
            );
            _states.putIfAbsent(nativeAd, _NativeAdState.new);
            if (!completer.isCompleted) {
              completer.complete(
                AdLoadResult.success(
                  ad: nativeAd,
                  type: type,
                  adUnitId: adUnitId,
                ),
              );
            } else {
              if (onLateAdLoaded != null) {
                onLateAdLoaded(nativeAd, type, adUnitId);
              } else {
                nativeAd.dispose();
              }
            }
          },
          onAdFailedToLoad: (ad, error) {
            log.v(
              '❌ [adapter_load] failed: source=${source.name} type=${type.name} '
              'placement=${placement.name} id=$adUnitId code=${error.code} '
              'message=${error.message}',
            );
            if (ad is NativeAd) {
              _attributions.remove(ad);
              _states.remove(ad);
            }
            ad.dispose();
            if (_shouldRetryAndroidNativeTestFallback(
              adUnitId: adUnitId,
              error: error,
              isFullscreenNative: isFullscreenNative,
              allowFallback: allowAndroidTestFallback,
            )) {
              log.v(
                '[adapter_load] retry_android_test_fallback: '
                'placement=${placement.name} from=$adUnitId '
                'to=$_androidNativeAdvancedTestAdUnitId',
              );
              startLoad(
                adUnitId: _androidNativeAdvancedTestAdUnitId,
                allowAndroidTestFallback: false,
              );
              return;
            }
            if (!completer.isCompleted) {
              completer.complete(
                AdLoadResult.failure(
                  type: type,
                  adUnitId: adUnitId,
                  error: error,
                ),
              );
            }
          },
          onAdClicked: (ad) {
            final attribution = _attributions[ad];
            final reportPlacement = attribution?.placement ?? placement;
            final nativeAd = ad as NativeAd;
            final state = _states.putIfAbsent(nativeAd, _NativeAdState.new)
              ..clicked = true;
            _reportLifecycleEvent(
              reporter,
              AdEvent(
                eventType: AdEventType.clicked,
                placement: reportPlacement,
                placementLabel: attribution?.placementLabel,
                adType: type,
                source: source,
                adUnitId: adUnitId,
                timestamp: DateTime.now(),
                eventName: attribution?.eventName ?? eventName,
                network:
                    ad.responseInfo?.loadedAdapterResponseInfo?.adSourceName,
              ),
            );
            for (final listener in List<VoidCallback>.of(
              state.clickListeners,
            )) {
              listener();
            }
          },
          onAdImpression: (ad) {
            final nativeAd = ad as NativeAd;
            final state = _states.putIfAbsent(nativeAd, _NativeAdState.new);
            final attribution = _attributions[nativeAd];
            if (state.impressionReported) {
              return;
            }
            state.impressionReported = true;
            state.onAdShowed?.call();
            if (state.reportShowSuccessOnImpression) {
              _reportLifecycleEvent(
                reporter,
                AdEvent(
                  eventType: AdEventType.showSuccess,
                  placement: attribution?.placement ?? placement,
                  placementLabel: attribution?.placementLabel,
                  adType: type,
                  source: source,
                  adUnitId: adUnitId,
                  timestamp: DateTime.now(),
                  eventName: attribution?.eventName ?? eventName,
                  network:
                      ad.responseInfo?.loadedAdapterResponseInfo?.adSourceName,
                ),
              );
            }
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
              adUnitId: adUnitId,
              valueMicros: valueMicros,
              currencyCode: currencyCode,
              network: ad.responseInfo?.loadedAdapterResponseInfo?.adSourceName,
            );
          },
        ),
      );
      unawaited(ad.load());
    }

    startLoad(adUnitId: unit.id, allowAndroidTestFallback: true);
    return completer.future.whenComplete(timer.cancel);
  }

  @override
  Future<AdShowResult> show({
    required PlacementType placement,
    BuildContext? context,
    String? placementLabel,
    required String eventName,
    required Object ad,
    required AdEventReporter reporter,
    VoidCallback? onAdShowed,
    VoidCallback? onClosed,
    int closePassThroughPercent = 0,
    AdFullScreenNativeStyle style = const AdFullScreenNativeStyle(),
  }) async {
    if (ad is! NativeAd) {
      _reportLifecycleEvent(
        reporter,
        AdEvent(
          eventType: AdEventType.showFail,
          placement: placement,
          placementLabel: placementLabel,
          adType: type,
          source: source,
          errorReason: 'invalid_native_ad',
          timestamp: DateTime.now(),
          eventName: eventName,
        ),
      );
      return AdShowResult.failure('invalid_native_ad');
    }
    updateAttribution(
      ad: ad,
      placement: placement,
      placementLabel: placementLabel,
      eventName: eventName,
    );
    final state = _states.putIfAbsent(ad, _NativeAdState.new)
      ..onAdShowed = onAdShowed
      ..reportShowSuccessOnImpression = true;

    final result = await FullScreenNativeAdView.show(
      context: context,
      ad: ad,
      closePassThroughPercent: closePassThroughPercent,
      hasClicked: () => state.clicked,
      addClickListener: (listener) => addClickListener(ad, listener),
      removeClickListener: (listener) => removeClickListener(ad, listener),
      style: style,
      onClosed: () {
        onClosed?.call();
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
            network: ad.responseInfo?.loadedAdapterResponseInfo?.adSourceName,
          ),
        );
      },
    );
    if (!result.shown) {
      _reportLifecycleEvent(
        reporter,
        AdEvent(
          eventType: AdEventType.showFail,
          placement: placement,
          placementLabel: placementLabel,
          adType: type,
          source: source,
          adUnitId: ad.adUnitId,
          errorReason: result.error?.toString(),
          timestamp: DateTime.now(),
          eventName: eventName,
          network: ad.responseInfo?.loadedAdapterResponseInfo?.adSourceName,
        ),
      );
    }
    return result;
  }

  @override
  void dispose(Object ad) {
    if (ad is NativeAd) {
      _attributions.remove(ad);
      _states.remove(ad);
      ad.dispose();
    }
  }

  bool _shouldRetryAndroidNativeTestFallback({
    required String adUnitId,
    required LoadAdError error,
    required bool isFullscreenNative,
    required bool allowFallback,
  }) {
    return allowFallback &&
        kDebugMode &&
        defaultTargetPlatform == TargetPlatform.android &&
        isFullscreenNative &&
        adUnitId == _androidNativeVideoTestAdUnitId &&
        error.code == 3;
  }
}

class _NativeAdState {
  bool clicked = false;
  bool impressionReported = false;
  bool reportShowSuccessOnImpression = false;
  VoidCallback? onAdShowed;
  final Set<VoidCallback> clickListeners = <VoidCallback>{};
}
