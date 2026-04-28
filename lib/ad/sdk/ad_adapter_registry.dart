import 'ad_type_adapter.dart';
import '../core/ad_enums.dart';

class AdAdapterRegistry {
  AdAdapterRegistry(List<AdTypeAdapter> adapters)
    : _adapters = {
        for (final adapter in adapters)
          _AdapterKey(adapter.source, adapter.type): adapter,
      };

  final Map<_AdapterKey, AdTypeAdapter> _adapters;

  AdTypeAdapter get(AdSource source, AdType type) {
    final adapter = _adapters[_AdapterKey(source, type)];
    if (adapter == null) {
      throw StateError(
        'No adapter registered for source=${source.name}, type=${type.name}',
      );
    }
    return adapter;
  }
}

class _AdapterKey {
  const _AdapterKey(this.source, this.type);

  final AdSource source;
  final AdType type;

  @override
  bool operator ==(Object other) {
    return other is _AdapterKey && other.source == source && other.type == type;
  }

  @override
  int get hashCode => Object.hash(source, type);
}
