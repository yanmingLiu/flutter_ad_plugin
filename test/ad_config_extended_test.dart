import 'package:flutter_ad_plugin/flutter_ad_plugin.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AdConfigParser edge cases', () {
    test('handles empty JSON config', () {
      final config = AdConfigParser().parse({});

      expect(config.loadTimeoutSeconds, 7);
      expect(config.samePlacementCdSeconds, 30);
      expect(config.differentPlacementCdSeconds, 30);
      expect(config.commonPlacements, hasLength(2));
      expect(config.configuredPlacements, isEmpty);
    });

    test('ignores non-list top-level keys', () {
      final config = AdConfigParser().parse({
        'load_timeout': 3,
        'version': '1.0',
        'enabled': true,
        'metadata': {'key': 'value'},
      });

      expect(config.loadTimeoutSeconds, 3);
      expect(config.configuredPlacements, isEmpty);
    });

    test('ignores list that does not look like ad units', () {
      final config = AdConfigParser().parse({
        'tags': ['game', 'casual'],
        'scores': [
          {'player': 'A', 'points': 100},
        ],
      });

      expect(config.configuredPlacements, isEmpty);
    });

    test('parses ad_id2 alongside ad_id', () {
      final config = AdConfigParser().parse({
        'home': [
          {
            'ad_source': 'admob',
            'ad_type': 'native',
            'ad_weight': 1,
            'ad_id': 'native-1',
            'ad_id2': 'native-2',
          },
        ],
      });

      final units = config.getUnits(const PlacementType('home'));
      expect(units, hasLength(2));
      expect(units[0].id, 'native-1');
      expect(units[1].id, 'native-2');
    });

    test('parses numbered keys id3, id4, id5', () {
      final config = AdConfigParser().parse({
        'home': [
          {
            'ad_source': 'admob',
            'ad_type': 'native',
            'ad_weight': 1,
            'ad_id': 'n-1',
            'id3': 'n-3',
            'id5': 'n-5',
          },
        ],
      });

      final units = config.getUnits(const PlacementType('home'));
      expect(units, hasLength(3));
      expect(units.map((u) => u.id).toSet(), {'n-1', 'n-3', 'n-5'});
    });

    test('units are sorted by weight descending', () {
      final config = AdConfigParser().parse({
        'home': [
          {
            'ad_source': 'admob',
            'ad_type': 'open',
            'ad_weight': 1,
            'ad_id': 'low',
          },
          {
            'ad_source': 'admob',
            'ad_type': 'interstitial',
            'ad_weight': 5,
            'ad_id': 'high',
          },
          {
            'ad_source': 'admob',
            'ad_type': 'rewarded',
            'ad_weight': 3,
            'ad_id': 'mid',
          },
        ],
      });

      final units = config.getUnits(const PlacementType('home'));
      expect(units.map((u) => u.weight), [5, 3, 1]);
    });

    test('highValuePlacement from JSON takes priority', () {
      final config = AdConfigParser().parse({
        'high_value_placement': 'custom_hv',
        'level_h': [
          {
            'ad_source': 'admob',
            'ad_weight': 1,
            'ad_type': 'interstitial',
            'ad_id': 'hv-1',
          },
        ],
      });

      expect(config.highValuePlacement, const PlacementType('custom_hv'));
    });

    test('highValuePlacement falls back to level_h if not specified', () {
      final config = AdConfigParser().parse({
        'level_h': [
          {
            'ad_source': 'admob',
            'ad_weight': 1,
            'ad_type': 'interstitial',
            'ad_id': 'hv-1',
          },
        ],
      });

      expect(config.highValuePlacement, const PlacementType('level_h'));
    });

    test('highValuePlacement is null if no level_h and not configured', () {
      final config = AdConfigParser().parse({'high_value_placement': ''});
      expect(config.highValuePlacement, isNull);
    });

    test('commonPlacements supports single string', () {
      final config = AdConfigParser().parse({
        'common_placements': 'single_common',
      });

      expect(config.commonPlacements, [const PlacementType('single_common')]);
    });

    test('commonPlacements supports alias common_placement', () {
      final config = AdConfigParser().parse({
        'common_placement': ['alt1', 'alt2'],
      });

      expect(config.commonPlacements, [
        const PlacementType('alt1'),
        const PlacementType('alt2'),
      ]);
    });

    test('poolSize is derived from number of IDs', () {
      final config = AdConfigParser().parse({
        'multi': [
          {
            'source': 'admob',
            'weight': 1,
            'type': 'native',
            'id': 'n1',
            'id2': 'n2',
            'ids': ['n3', 'n4'],
            'id5': 'n5',
          },
        ],
      });

      final units = config.getUnits(const PlacementType('multi'));
      expect(units, hasLength(5));
      for (final unit in units) {
        expect(unit.poolSize, 5);
      }
    });

    test('cacheKey is unique per unit', () {
      final config = AdConfigParser().parse({
        'test': [
          {
            'source': 'admob',
            'weight': 1,
            'type': 'native',
            'id': 'n1',
            'id2': 'n2',
          },
        ],
      });

      final units = config.getUnits(const PlacementType('test'));
      expect(units, hasLength(2));
      expect(units[0].cacheKey, 'admob_native_0_n1');
      expect(units[1].cacheKey, 'admob_native_1_n2');
    });

    test('fullscreenCacheSizeFor filters by fullscreen type', () {
      final config = AdConfigParser().parse({
        'mixed': [
          {
            'source': 'admob',
            'weight': 1,
            'type': 'native',
            'id': 'n1',
            'id2': 'n2',
            'id3': 'n3',
          },
          {
            'source': 'admob',
            'weight': 2,
            'type': 'interstitial',
            'id': 'i1',
            'id2': 'i2',
          },
        ],
      });

      expect(config.nativeCacheSizeFor(const PlacementType('mixed')), 3);
      expect(config.fullscreenCacheSizeFor(const PlacementType('mixed')), 2);
      expect(config.cacheSizeFor(const PlacementType('mixed')), 3);
    });

    test(
      'fullscreenCacheSizeFor includes native for fullscreen policy',
      () async {
        final repo = DefaultAdConfigRepository(
          placementPolicies: {
            const PlacementType('fullscreen_native'): PlacementPolicy(
              isFullscreen: true,
              applySamePlacementCd: false,
              applyDifferentPlacementCd: false,
              contributesToGlobalCooldown: false,
              showNotReadyToast: true,
              waitForLoadOnShow: true,
              preferHighValueOnShow: false,
              allowedTypes: {AdType.native},
            ),
          },
          localConfig: {
            'fullscreen_native': [
              {
                'source': 'admob',
                'weight': 1,
                'type': 'native',
                'id': 'n1',
                'id2': 'n2',
              },
            ],
          },
        );

        final config = await repo.getConfig();
        expect(
          config.fullscreenCacheSizeFor(
            const PlacementType('fullscreen_native'),
          ),
          2,
        );
      },
    );

    test('hasPlacement returns true only for configured placements', () {
      final config = AdConfigParser().parse({
        'open': [
          {'source': 'admob', 'weight': 1, 'type': 'open', 'id': 'open-1'},
        ],
      });

      expect(config.hasPlacement(const PlacementType('open')), isTrue);
      expect(config.hasPlacement(const PlacementType('missing')), isFalse);
    });

    test('loadTimeoutFor uses unit timeout over global', () {
      final config = AdConfigParser().parse({
        'load_timeout': 7,
        'open': [
          {
            'source': 'admob',
            'weight': 1,
            'type': 'open',
            'id': 'o1',
            'load_timeout': 20,
          },
        ],
      });

      final unit = config.getUnits(const PlacementType('open')).single;
      expect(config.loadTimeoutFor(unit), const Duration(seconds: 20));
    });

    test('loadTimeoutFor falls back to global timeout', () {
      final config = AdConfigParser().parse({
        'load_timeout': 15,
        'open': [
          {'source': 'admob', 'weight': 1, 'type': 'open', 'id': 'o1'},
        ],
      });

      final unit = config.getUnits(const PlacementType('open')).single;
      expect(config.loadTimeoutFor(unit), const Duration(seconds: 15));
    });

    test('getPolicy returns default for non-configured policy', () {
      final config = AdConfigParser().parse({
        'open': [
          {'source': 'admob', 'weight': 1, 'type': 'open', 'id': 'open-1'},
        ],
      });

      final policy = config.getPolicy(const PlacementType('open'));
      expect(policy.isFullscreen, isTrue);
      // open placement defaults: waitForLoadOnShow=false
      expect(policy.waitForLoadOnShow, isFalse);
    });

    test(
      'default policy for non-open placement has waitForLoadOnShow=true',
      () {
        final config = AdConfigParser().parse({
          'interstitial': [
            {
              'source': 'admob',
              'weight': 1,
              'type': 'interstitial',
              'id': 'i-1',
            },
          ],
        });

        final policy = config.getPolicy(const PlacementType('interstitial'));
        expect(policy.waitForLoadOnShow, isTrue);
      },
    );

    test('ignores placement_policy from JSON', () {
      final config = AdConfigParser().parse({
        'open': [
          {'source': 'admob', 'weight': 1, 'type': 'open', 'id': 'o1'},
        ],
        'placement_policy': {
          'open': {
            'apply_same_placement_cd': true,
            'apply_different_placement_cd': true,
            'contributes_to_global_cooldown': true,
            'show_not_ready_toast': true,
            'wait_for_load_on_show': true,
            'prefer_high_value_on_show': true,
            'not_ready_msg': 'ignored',
          },
        },
      });

      final policy = config.getPolicy(const PlacementType('open'));
      expect(policy.isFullscreen, isTrue);
      expect(policy.applySamePlacementCd, isFalse);
      expect(policy.applyDifferentPlacementCd, isFalse);
      expect(policy.contributesToGlobalCooldown, isFalse);
      expect(policy.showNotReadyToast, isFalse);
      expect(policy.waitForLoadOnShow, isFalse);
      expect(policy.preferHighValueOnShow, isFalse);
      expect(policy.notReadyMsg, isNull);
    });

    test('repository placementPolicies override defaults', () async {
      final repo = DefaultAdConfigRepository(
        placementPolicies: {
          const PlacementType('open'): const PlacementPolicy(
            isFullscreen: true,
            applySamePlacementCd: true,
            applyDifferentPlacementCd: true,
            contributesToGlobalCooldown: true,
            showNotReadyToast: true,
            waitForLoadOnShow: true,
            preferHighValueOnShow: true,
            notReadyMsg: 'configured by caller',
          ),
        },
        localConfig: {
          'open': [
            {'source': 'admob', 'weight': 1, 'type': 'open', 'id': 'o1'},
          ],
        },
      );

      final config = await repo.getConfig();
      final policy = config.getPolicy(const PlacementType('open'));
      expect(policy.applySamePlacementCd, isTrue);
      expect(policy.applyDifferentPlacementCd, isTrue);
      expect(policy.contributesToGlobalCooldown, isTrue);
      expect(policy.showNotReadyToast, isTrue);
      expect(policy.waitForLoadOnShow, isTrue);
      expect(policy.preferHighValueOnShow, isTrue);
      expect(policy.notReadyMsg, 'configured by caller');
    });

    test('repository placementPolicies support allowedTypes', () async {
      final repo = DefaultAdConfigRepository(
        placementPolicies: {
          const PlacementType('filtered'): PlacementPolicy(
            isFullscreen: true,
            applySamePlacementCd: false,
            applyDifferentPlacementCd: false,
            contributesToGlobalCooldown: false,
            showNotReadyToast: false,
            waitForLoadOnShow: true,
            preferHighValueOnShow: false,
            allowedTypes: {AdType.interstitial, AdType.rewarded},
          ),
        },
        localConfig: {
          'filtered': [
            {'source': 'admob', 'weight': 1, 'type': 'native', 'id': 'n1'},
          ],
        },
      );

      final config = await repo.getConfig();
      final policy = config.getPolicy(const PlacementType('filtered'));
      expect(policy.supports(AdType.interstitial), isTrue);
      expect(policy.supports(AdType.rewarded), isTrue);
      expect(policy.supports(AdType.native), isFalse);
    });

    test('JSON placement_policy does not override default policies', () {
      final config = AdConfigParser().parse({
        'open': [
          {'source': 'admob', 'weight': 1, 'type': 'open', 'id': 'o1'},
        ],
        'level': [
          {'source': 'admob', 'weight': 1, 'type': 'interstitial', 'id': 'i1'},
        ],
        'placement_policy': {
          'open': {
            'is_fullscreen': 'maybe',
            'apply_same_placement_cd': 2,
            'apply_different_placement_cd': 'no',
            'contributes_to_global_cooldown': 'off',
            'show_not_ready_toast': 'false',
            'wait_load_on_show': 'yes',
            'prefer_high_value_on_show': null,
          },
          'level': {
            'is_fullscreen': 2,
            'wait_for_load_on_show': 'later',
            'prefer_high_value_on_show': 3,
          },
        },
      });

      final openPolicy = config.getPolicy(const PlacementType('open'));
      expect(openPolicy.isFullscreen, isTrue);
      expect(openPolicy.applySamePlacementCd, isFalse);
      expect(openPolicy.applyDifferentPlacementCd, isFalse);
      expect(openPolicy.contributesToGlobalCooldown, isFalse);
      expect(openPolicy.showNotReadyToast, isFalse);
      expect(openPolicy.waitForLoadOnShow, isFalse);
      expect(openPolicy.preferHighValueOnShow, isFalse);

      final levelPolicy = config.getPolicy(const PlacementType('level'));
      expect(levelPolicy.isFullscreen, isTrue);
      expect(levelPolicy.waitForLoadOnShow, isTrue);
      expect(levelPolicy.preferHighValueOnShow, isTrue);
    });

    group('PlacementPolicy.isFullscreen auto-inference', () {
      test('isFullscreen=true when placement has fullscreen units', () {
        final config = AdConfigParser().parse({
          'full': [
            {
              'source': 'admob',
              'weight': 1,
              'type': 'interstitial',
              'id': 'i1',
            },
          ],
        });

        expect(
          config.getPolicy(const PlacementType('full')).isFullscreen,
          isTrue,
        );
      });

      test('isFullscreen=false when placement has only native units', () {
        final config = AdConfigParser().parse({
          'only_native': [
            {'source': 'admob', 'weight': 1, 'type': 'native', 'id': 'n1'},
          ],
        });

        expect(
          config.getPolicy(const PlacementType('only_native')).isFullscreen,
          isFalse,
        );
      });
    });

    group('PlacementPolicy.supports', () {
      test('supports any type when no allowedTypes set and fullscreen', () {
        final config = AdConfigParser().parse({
          'home': [
            {
              'source': 'admob',
              'weight': 1,
              'type': 'interstitial',
              'id': 'i1',
            },
          ],
        });

        final policy = config.getPolicy(const PlacementType('home'));
        expect(policy.supports(AdType.interstitial), isTrue);
        expect(policy.supports(AdType.open), isTrue);
        expect(policy.supports(AdType.native), isTrue);
      });

      test('supports native only when not fullscreen', () {
        final config = AdConfigParser().parse({
          'only_native': [
            {'source': 'admob', 'weight': 1, 'type': 'native', 'id': 'n1'},
          ],
        });

        final policy = config.getPolicy(const PlacementType('only_native'));
        expect(policy.supports(AdType.native), isTrue);
        expect(policy.supports(AdType.interstitial), isFalse);
      });
    });
  });

  group('DefaultAdConfigRepository', () {
    test('parses local JSON string', () async {
      final repo = DefaultAdConfigRepository(
        localConfigJson:
            '{"load_timeout": 5, "test_p": [{"source":"admob","weight":1,"type":"native","id":"n1"}]}',
      );
      final config = await repo.getConfig();
      expect(config.loadTimeoutSeconds, 5);
      expect(config.getUnits(const PlacementType('test_p')), hasLength(1));
    });

    test('JSON string overrides localConfig map when both provided', () async {
      final repo = DefaultAdConfigRepository(
        localConfig: {'load_timeout': 3},
        localConfigJson: '{"load_timeout": 9}',
      );
      final config = await repo.getConfig();
      expect(config.loadTimeoutSeconds, 9);
    });

    test('cached config returns same instance', () async {
      final repo = DefaultAdConfigRepository(
        localConfig: {
          'load_timeout': 3,
          'open': [
            {'source': 'admob', 'weight': 1, 'type': 'open', 'id': 'o1'},
          ],
        },
      );
      final config1 = await repo.getConfig();
      final config2 = await repo.getConfig();
      expect(identical(config1, config2), isTrue);
    });
  });

  group('AdUnitConfig', () {
    test('isValid returns true for non-empty id', () {
      const unit = AdUnitConfig(
        source: AdSource.admob,
        weight: 1,
        type: AdType.open,
        id: 'unit-1',
      );
      expect(unit.isValid, isTrue);
    });

    test('isValid returns false for empty id', () {
      const unit = AdUnitConfig(
        source: AdSource.admob,
        weight: 1,
        type: AdType.open,
        id: '',
      );
      expect(unit.isValid, isFalse);
    });
  });
}
