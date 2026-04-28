import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../core/ad_enums.dart';

abstract class AdSourceSdkInitializer {
  AdSource get source;

  Future<void> init();
}

class AdSdkInitializer {
  AdSdkInitializer(List<AdSourceSdkInitializer> initializers)
    : _initializers = {
        for (final initializer in initializers) initializer.source: initializer,
      };

  final Map<AdSource, AdSourceSdkInitializer> _initializers;

  Future<void> initAll() async {
    for (final initializer in _initializers.values) {
      await initializer.init();
    }
  }

  Future<void> initSource(AdSource source) async {
    final initializer = _initializers[source];
    if (initializer == null) {
      throw StateError(
        'No SDK initializer registered for source=${source.name}',
      );
    }
    await initializer.init();
  }

  bool supports(AdSource source) => _initializers.containsKey(source);
}

AdSdkInitializer createDefaultAdSdkInitializer() {
  return AdSdkInitializer([AdmobSdkInitializer()]);
}

class AdmobSdkInitializer implements AdSourceSdkInitializer {
  @override
  AdSource get source => AdSource.admob;

  @override
  Future<void> init() async {
    await MobileAds.instance.initialize();
  }
}
