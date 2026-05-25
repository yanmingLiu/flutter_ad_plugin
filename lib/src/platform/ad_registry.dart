import '../core/ad_enums.dart';
import 'ad_adapter.dart';

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

class AdAdapterRegistry {
  final Map<String, AdTypeAdapter> _adapters = {};

  AdAdapterRegistry(List<AdTypeAdapter> adapters) {
    for (final adapter in adapters) {
      _adapters[_key(adapter.source, adapter.type)] = adapter;
    }
  }

  String _key(AdSource source, AdType type) => '${source.name}_${type.name}';

  AdTypeAdapter get(AdSource source, AdType type) {
    final adapter = _adapters[_key(source, type)];
    if (adapter == null) {
      throw StateError(
        'No adapter registered for source=${source.name}, type=${type.name}',
      );
    }
    return adapter;
  }
}
