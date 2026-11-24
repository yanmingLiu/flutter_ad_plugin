import 'package:flutter_ad_max/flutter_ad_max.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('same MAX unit cannot overwrite the current callback owner', () async {
    final hub = MaxEventHub();
    final registry = hub.registry;
    MaxFullscreenHandle request() => MaxFullscreenHandle(
      type: AdType.interstitial,
      adUnitId: 'shared',
      placement: null,
      customData: null,
    );

    final first = request();
    final second = request();

    expect(registry.registerFullscreen(first), isTrue);
    expect(registry.registerFullscreen(second), isFalse);
    final adapter = MaxFullscreenAdapter(
      type: AdType.interstitial,
      eventHub: hub,
    );
    final conflictingLoad = await adapter.load(
      placement: const PlacementType('another_placement'),
      unit: const AdUnitConfig(
        source: AdSource.max,
        weight: 1,
        type: AdType.interstitial,
        id: 'shared',
      ),
      timeout: const Duration(seconds: 1),
      eventName: 'test',
    );
    expect(conflictingLoad.isSuccess, isFalse);
    expect(conflictingLoad.error.toString(), contains('already owned'));
    final conflictingShow = await adapter.show(
      placement: const PlacementType('another_placement'),
      eventName: 'test',
      ad: second,
    );
    expect(conflictingShow.errorReason, 'max_fullscreen_unit_busy');
    registry.unregisterFullscreen(second);
    expect(registry.fullscreenFor(AdType.interstitial, 'shared'), same(first));

    registry.unregisterFullscreen(first);
    expect(registry.registerFullscreen(second), isTrue);
    expect(registry.fullscreenFor(AdType.interstitial, 'shared'), same(second));
  });
}
