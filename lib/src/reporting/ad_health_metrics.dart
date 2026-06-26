import '../core/ad_enums.dart';

/// Aggregated health metrics for a single placement.
///
/// Tracks load/show counts, latency, and error rates to help
/// monitor ad performance.
///
/// ---
/// 单个广告位的聚合健康度指标。追踪加载/展示次数、延迟和错误率。
class AdHealthSnapshot {
  final PlacementType placement;

  final int loadAttempts;
  final int loadSuccesses;
  final int loadFailures;
  final Duration totalLoadLatency;

  final int showAttempts;
  final int showSuccesses;
  final int showFailures;

  double get fillRate =>
      loadAttempts > 0 ? loadSuccesses / loadAttempts : 0.0;

  Duration get avgLoadLatency =>
      loadSuccesses > 0
          ? Duration(microseconds: totalLoadLatency.inMicroseconds ~/ loadSuccesses)
          : Duration.zero;

  double get showRate =>
      showAttempts > 0 ? showSuccesses / showAttempts : 0.0;

  const AdHealthSnapshot({
    required this.placement,
    this.loadAttempts = 0,
    this.loadSuccesses = 0,
    this.loadFailures = 0,
    this.totalLoadLatency = Duration.zero,
    this.showAttempts = 0,
    this.showSuccesses = 0,
    this.showFailures = 0,
  });
}

/// Collects ad health metrics during the plugin's lifetime.
///
/// Does not persist across sessions. Reset via [reset] or plugin dispose.
///
/// ---
/// 收集插件运行期间的广告健康度指标。不跨会话持久化。
class AdHealthMetrics {
  final Map<PlacementType, _Metrics> _data = {};

  void recordLoadAttempt(PlacementType p) {
    _data.putIfAbsent(p, _Metrics.new).loadAttempts++;
  }

  void recordLoadSuccess(PlacementType p, Duration latency) {
    final m = _data.putIfAbsent(p, _Metrics.new);
    m.loadSuccesses++;
    m.totalLoadLatency += latency;
  }

  void recordLoadFailure(PlacementType p) {
    _data.putIfAbsent(p, _Metrics.new).loadFailures++;
  }

  void recordShowAttempt(PlacementType p) {
    _data.putIfAbsent(p, _Metrics.new).showAttempts++;
  }

  void recordShowSuccess(PlacementType p) {
    _data.putIfAbsent(p, _Metrics.new).showSuccesses++;
  }

  void recordShowFailure(PlacementType p) {
    _data.putIfAbsent(p, _Metrics.new).showFailures++;
  }

  /// Returns a snapshot for [placement], or null if no data.
  AdHealthSnapshot? snapshot(PlacementType placement) {
    final m = _data[placement];
    if (m == null) return null;
    return AdHealthSnapshot(
      placement: placement,
      loadAttempts: m.loadAttempts,
      loadSuccesses: m.loadSuccesses,
      loadFailures: m.loadFailures,
      totalLoadLatency: m.totalLoadLatency,
      showAttempts: m.showAttempts,
      showSuccesses: m.showSuccesses,
      showFailures: m.showFailures,
    );
  }

  /// Returns snapshots for all tracked placements.
  List<AdHealthSnapshot> allSnapshots() {
    return _data.entries.map((e) {
      final m = e.value;
      return AdHealthSnapshot(
        placement: e.key,
        loadAttempts: m.loadAttempts,
        loadSuccesses: m.loadSuccesses,
        loadFailures: m.loadFailures,
        totalLoadLatency: m.totalLoadLatency,
        showAttempts: m.showAttempts,
        showSuccesses: m.showSuccesses,
        showFailures: m.showFailures,
      );
    }).toList();
  }

  /// Clears all metrics.
  void reset() {
    _data.clear();
  }
}

class _Metrics {
  int loadAttempts = 0;
  int loadSuccesses = 0;
  int loadFailures = 0;
  Duration totalLoadLatency = Duration.zero;
  int showAttempts = 0;
  int showSuccesses = 0;
  int showFailures = 0;
}
