import '../core/ad_enums.dart';
import '../core/ad_models.dart';

/// Generic ad cache service managing ad slots per placement.
///
/// Replaces the old three `_AdPoolStore` instances with a single service.
/// Handles slot CRUD, deduplication by cache key, loading state, and
/// attribution tracking (replacing adapter-level static maps).
///
/// ---
/// 泛型广告缓存服务，每个 placement 管理广告槽位。
/// 替代旧的三个 `_AdPoolStore`，统一处理槽位增删查、
/// cacheKey 去重、加载状态和 attribution 管理。
class AdCacheService {
  final Map<PlacementType, List<AdSlotState>> _cache = {};

  /// Attribution map keyed by ad object identity.
  /// Replaces the static maps in adapters.
  final Map<Object, AdAttribution> _attributions = {};

  /// Whether [placement] has at least one loaded ad slot.
  bool hasSlot(PlacementType placement) {
    final slots = _cache[placement];
    return slots != null && slots.any((s) => s is AdSlotLoaded);
  }

  /// Returns all ad slots for [placement], filtered to loaded only.
  List<AdSlotLoaded> getSlots(PlacementType placement) {
    final slots = _cache[placement];
    if (slots == null) {
      return const [];
    }
    return slots.whereType<AdSlotLoaded>().toList();
  }

  /// Returns the count of loaded slots for [placement].
  int countFor(PlacementType placement) => getSlots(placement).length;

  /// Checks if a slot with [cacheKey] already exists.
  bool hasSlotWithKey(PlacementType placement, String cacheKey) {
    return getSlots(placement).any((s) => s.cacheKey == cacheKey);
  }

  /// Returns the latest load error preserved for [placement], if any.
  Object? lastErrorFor(PlacementType placement) {
    final slots = _cache[placement];
    if (slots == null) {
      return null;
    }

    for (final state in slots.reversed) {
      if (state is AdSlotFailed) {
        return state.error;
      }
    }
    return null;
  }

  /// Marks a placement as loading, preserving existing loaded slots.
  void beginLoading(PlacementType placement) {
    final existing = getSlots(placement);
    if (existing.isEmpty) {
      _cache.remove(placement);
      return;
    }
    _cache[placement] = List<AdSlotState>.from(existing);
  }

  /// Commits the loaded slots for a placement (replaces existing).
  void commitSlots(
    PlacementType placement,
    List<AdSlotLoaded> slots, {
    Object? lastError,
  }) {
    if (slots.isEmpty && lastError == null) {
      _cache.remove(placement);
      return;
    }
    final states = <AdSlotState>[...slots];
    if (lastError != null) {
      states.add(AdSlotFailed(placement: placement, error: lastError));
    }
    _cache[placement] = states;
  }

  /// Adds a single loaded slot to the cache.
  void addSlot(PlacementType placement, AdSlotLoaded slot) {
    final existing = getSlots(placement);
    commitSlots(placement, [...existing, slot]);
  }

  /// Removes a specific loaded slot.
  void removeSlot(PlacementType placement, AdSlotLoaded slot) {
    final kept = getSlots(placement).where((s) => s.ad != slot.ad).toList();
    _attributions.remove(slot.ad);
    commitSlots(placement, kept);
  }

  /// Clears all slots for a placement.
  void clear(PlacementType placement) {
    final slots = getSlots(placement);
    for (final s in slots) {
      _attributions.remove(s.ad);
    }
    _cache.remove(placement);
  }

  /// Returns the first loaded slot, or null.
  AdSlotLoaded? firstSlot(PlacementType placement) {
    return getSlots(placement).firstOrNull;
  }

  /// Returns the first loaded slot excluding those in [exclude].
  AdSlotLoaded? firstSlotExcluding(
    PlacementType placement,
    Set<AdSlotLoaded> exclude,
  ) {
    for (final slot in getSlots(placement)) {
      if (!exclude.contains(slot)) {
        return slot;
      }
    }
    return null;
  }

  // --- Attribution management ---

  /// Sets the attribution for an ad object.
  void setAttribution(
    Object ad,
    PlacementType placement, {
    String? placementLabel,
    required String eventName,
  }) {
    final existing = _attributions[ad];
    if (existing == null) {
      _attributions[ad] = AdAttribution(
        placement: placement,
        placementLabel: placementLabel,
        eventName: eventName,
      );
      return;
    }
    existing
      ..placement = placement
      ..placementLabel = placementLabel
      ..eventName = eventName;
  }

  /// Gets the attribution for an ad object.
  AdAttribution? getAttribution(Object ad) {
    return _attributions[ad];
  }

  /// Removes attribution for a disposed ad.
  void removeAttribution(Object ad) {
    _attributions.remove(ad);
  }

  /// Clears all data (used during [AdPlugin.dispose]).
  void disposeAll() {
    _cache.clear();
    _attributions.clear();
  }
}
