import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../analytics/ad_event.dart';
import '../../analytics/ad_event_reporter.dart';
import '../../core/ad_config.dart';
import '../../core/ad_enums.dart';
import '../../core/ad_models.dart';
import '../../../tools/log_tool.dart';
import '../ad_type_adapter.dart';

class AdmobNativeAdapter implements AdTypeAdapter<NativeAd> {

  @override
  AdSource get source => AdSource.admob;

  @override
  AdType get type => AdType.native;

  @override
  Future<AdLoadResult<NativeAd>> load({
    required PlacementType placement,
    required AdUnitConfig unit,
    required Duration timeout,
    required AdEventReporter reporter,
    void Function(NativeAd ad, AdType type, String adUnitId)? onLateAdLoaded,
  }) async {
    log.d('📥 load:native:${placement.name} id=${unit.id}');
    final completer = Completer<AdLoadResult<NativeAd>>();

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

    final ad = NativeAd(
      adUnitId: unit.id,
      nativeTemplateStyle: NativeTemplateStyle(
        templateType: TemplateType.medium,
      ),
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
          log.d('👆 clicked:native:${placement.name}');
          reporter.report(
            AdEvent(
              eventType: AdEventType.clicked,
              placement: placement,
              adType: type,
              source: source,
              adUnitId: unit.id,
              timestamp: DateTime.now(),
            ),
          );
        },
        onPaidEvent: (ad, valueMicros, precision, currencyCode) {
          log.d('💰 income:native:${placement.name} value=$valueMicros $currencyCode');
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
    required NativeAd ad,
    required AdEventReporter reporter,
    VoidCallback? onAdShowed,
    VoidCallback? onClosed,
  }) async {
    return AdShowResult.success();
  }

  @override
  void dispose(NativeAd ad) {
    ad.dispose();
  }
}
