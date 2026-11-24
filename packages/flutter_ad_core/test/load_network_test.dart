import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ad_core/models.dart';
import 'package:flutter_ad_core/platform.dart';

class _Loader with CommonLoaderMixin<String> {}

void main() {
  test(
    'successful SDK load preserves its network; absent metadata stays null',
    () async {
      for (final network in ['SDK network', null]) {
        final result = await _Loader().loadWithCompleter(
          unit: const AdUnitConfig(
            source: AdSource('test'),
            weight: 1,
            type: AdType.interstitial,
            id: 'unit',
          ),
          timeout: const Duration(seconds: 1),
          loadTimeoutLabel: 'test',
          sourceName: 'test',
          typeName: 'interstitial',
          networkOf: (_) => network,
          startLoad: (loaded, failed) async => loaded('ad'),
        );
        expect(result.isSuccess, isTrue);
        expect(result.network, network);
      }
    },
  );
}
