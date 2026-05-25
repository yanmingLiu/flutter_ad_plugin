import 'package:flutter_ad_plugin/flutter_ad_plugin.dart';
import 'package:flutter_test/flutter_test.dart';

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
    const openPlacement = PlacementType('open');
    expect(config.getUnits(openPlacement), hasLength(1));
    expect(config.getUnits(openPlacement).single.type, AdType.interstitial);
  });

  test('parses per-unit timeout and multiple ad ids', () {
    final config = AdConfigParser().parse({
      'load_timeout': 7,
      'message': [
        {
          'source': 'admob',
          'weight': 2,
          'type': 'interstitial',
          'id': 'unit-1',
          'id2': 'unit-2',
          'load_timeout': 15,
        },
      ],
      'home': [
        {
          'source': 'admob',
          'weight': 1,
          'type': 'native',
          'id': 'native-1',
          'ids': ['native-2', 'native-3'],
        },
      ],
    });

    const messagePlacement = PlacementType('message');
    const homePlacement = PlacementType('home');
    final messageUnits = config.getUnits(messagePlacement);
    expect(messageUnits, hasLength(2));
    expect(messageUnits.map((unit) => unit.id), ['unit-1', 'unit-2']);
    expect(messageUnits.map((unit) => unit.loadTimeoutSeconds), [15, 15]);
    expect(
      config.loadTimeoutFor(messageUnits.first),
      const Duration(seconds: 15),
    );
    expect(config.cacheSizeFor(messagePlacement), 2);

    final homeUnits = config.getUnits(homePlacement);
    expect(homeUnits, hasLength(3));
    expect(homeUnits.map((unit) => unit.id), [
      'native-1',
      'native-2',
      'native-3',
    ]);
    expect(config.loadTimeoutFor(homeUnits.first), const Duration(seconds: 7));
    expect(config.cacheSizeFor(homePlacement), 3);
  });

  test('default repository falls back to host local config', () async {
    final repository = DefaultAdConfigRepository(
      localConfig: {
        'load_timeout': 9,
        'open': [
          {'source': 'admob', 'weight': 1, 'type': 'open', 'id': 'local-open'},
        ],
      },
    );

    const openPlacement = PlacementType('open');
    final config = await repository.getConfig();

    expect(config.loadTimeoutSeconds, 9);
    expect(config.getUnits(openPlacement).single.id, 'local-open');
  });
}
