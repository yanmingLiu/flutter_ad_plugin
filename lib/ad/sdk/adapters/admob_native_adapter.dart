import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../analytics/ad_event_reporter.dart';
import '../../core/ad_config.dart';
import '../../core/ad_enums.dart';
import '../../core/ad_models.dart';
import '../../../tools/log_tool.dart';
import '../ad_type_adapter.dart';

class AdmobNativeAdapter implements AdTypeAdapter<NativeAd> {
  static const _factoryId = 'homeListTile';

  @override
  AdSource get source => AdSource.admob;

  @override
  AdType get type => AdType.native;

  @override
  Future<AdLoadResult<NativeAd>> load({
    required PlacementType placement,
    required AdUnitConfig unit,
    required Duration timeout,
  }) async {
    log.d(
      '[ad][admob_native][load] start placement=${placement.name} adid=${unit.id}',
    );
    final completer = Completer<AdLoadResult<NativeAd>>();
    final ad = NativeAd(
      adUnitId: unit.id,
      factoryId: _factoryId,
      request: const AdRequest(),
      listener: NativeAdListener(
        onAdLoaded: (ad) {
          log.d(
            '[ad][admob_native][load] loaded placement=${placement.name} adid=${unit.id}',
          );
          if (!completer.isCompleted) {
            completer.complete(
              AdLoadResult.success(
                ad: ad as NativeAd,
                type: type,
                adUnitId: unit.id,
              ),
            );
          }
        },
        onAdFailedToLoad: (ad, error) {
          log.d(
            '[ad][admob_native][load] failed placement=${placement.name} adid=${unit.id} code=${error.code} reason=${error.message}',
          );
          ad.dispose();
          if (!completer.isCompleted) {
            completer.complete(
              AdLoadResult.failure(type: type, adUnitId: unit.id, error: error),
            );
          }
        },
      ),
    );
    await ad.load();
    return completer.future.timeout(
      timeout,
      onTimeout: () {
        log.d(
          '[ad][admob_native][load] timeout placement=${placement.name} adid=${unit.id}',
        );
        ad.dispose();
        return AdLoadResult.failure(
          type: type,
          adUnitId: unit.id,
          error: TimeoutException('native ad load timeout'),
        );
      },
    );
  }

  @override
  Future<AdShowResult> show({
    required PlacementType placement,
    String? placementLabel,
    required NativeAd ad,
    required AdEventReporter reporter,
    VoidCallback? onClosed,
  }) async {
    return AdShowResult.success();
  }

  @override
  void dispose(NativeAd ad) {
    ad.dispose();
  }
}
