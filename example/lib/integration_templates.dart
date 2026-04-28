import 'package:flutter_ad_plugin/ad/analytics/ad_event.dart';
import 'package:flutter_ad_plugin/ad/analytics/ad_event_reporter.dart';
import 'package:flutter_ad_plugin/ad/config/ad_config_repository.dart';
import 'package:flutter_ad_plugin/ad/core/ad_config.dart';
import 'package:flutter_ad_plugin/ad/core/ad_enums.dart';

class MyConfigRepository implements AdConfigRepository {
  @override
  Future<AdConfig> getConfig() async {
    return const AdConfig(
      loadTimeoutSeconds: 7,
      samePlacementCdSeconds: 30,
      differentPlacementCdSeconds: 30,
      placements: {
        PlacementType.open: [
          AdUnitConfig(
            source: AdSource.admob,
            weight: 3,
            type: AdType.open,
            id: 'ca-app-pub-3940256099942544/5575463023',
          ),
        ],
        PlacementType.home: [
          AdUnitConfig(
            source: AdSource.admob,
            weight: 1,
            type: AdType.native,
            id: 'ca-app-pub-3940256099942544/1044960115',
          ),
        ],
      },
    );
  }
}

class MyAdEventReporter implements AdEventReporter {
  @override
  Future<void> report(AdEvent event) async {
    // Replace with your analytics system:
    // Firebase / AppsFlyer / Adjust / internal BI endpoint.
    // ignore: avoid_print
    print(
      '[my-ad-event] type=${event.eventType.name} placement=${event.placement.name} unit=${event.adUnitId}',
    );
  }
}
