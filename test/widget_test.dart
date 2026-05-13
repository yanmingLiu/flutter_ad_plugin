import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ad_plugin/ad/config/ad_config_parser.dart';
import 'package:flutter_ad_plugin/ad/core/ad_enums.dart';

void main() {
  test('parses placement ad units', () {
    final config = AdConfigParser().parse({
      'load_timeout': 3,
      'open': [
        {
          'source': 'admob',
          'weight': 2,
          'type': 'interstitial',
          'id': 'unit-1',
        },
      ],
    });

    expect(config.loadTimeoutSeconds, 3);
    expect(config.getUnits(PlacementType.open), hasLength(1));
    expect(
      config.getUnits(PlacementType.open).single.type,
      AdType.interstitial,
    );
  });
}
