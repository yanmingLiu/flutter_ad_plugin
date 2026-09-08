/// A lightweight cancellation token for aborting in-flight ad loads.
///
/// Used by [AdLoaderService] to cancel a pending load when a new request
/// supersedes it or when [AdPlugin.dispose] is called.
///
/// ---
/// 轻量级取消令牌，用于中止正在进行的广告加载。
class CancellationToken {
  bool _cancelled = false;
  final Set<void Function()> _listeners = {};

  bool get isCancelled => _cancelled;

  /// Registers a callback and returns a function that removes it.
  void Function() addListener(void Function() listener) {
    if (_cancelled) {
      listener();
      return () {};
    }
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    final listeners = List<void Function()>.of(_listeners);
    _listeners.clear();
    for (final listener in listeners) {
      listener();
    }
  }
}
