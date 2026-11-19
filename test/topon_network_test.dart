import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ad_plugin/flutter_ad_topon.dart';

void main() {
  test('network name takes precedence over firm ID', () {
    expect(
      topOnNetwork({'network_name': ' Custom ', 'network_firm_id': 2}),
      'Custom',
    );
  });

  test('empty names fall back to numeric or string firm IDs', () {
    const names = {
      1: 'Meta',
      2: 'AdMob',
      5: 'AppLovin',
      6: 'Mintegral',
      8: 'GDT',
      15: 'CSJ',
      50: 'Pangle',
      59: 'Bigo',
      66: 'TopOn ADX',
    };
    for (final entry in names.entries) {
      for (final id in [entry.key, entry.key.toString()]) {
        expect(
          topOnNetwork({'network_name': ' ', 'network_firm_id': id}),
          entry.value,
        );
      }
    }
  });

  test('unknown IDs remain identifiable and missing metadata stays null', () {
    expect(topOnNetwork({'network_firm_id': 999}), 'Unknown(999)');
    expect(topOnNetwork({}), isNull);
    expect(topOnNetwork({'network_name': '', 'network_firm_id': ' '}), isNull);
    expect(topOnNetwork({'network': 'legacy'}), isNull);
  });
}
