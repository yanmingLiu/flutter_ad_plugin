/// A lightweight cancellation token for aborting in-flight ad loads.
///
/// Used by [AdLoaderService] to cancel a pending load when a new request
/// supersedes it or when [AdPlugin.dispose] is called.
///
/// ---
/// 轻量级取消令牌，用于中止正在进行的广告加载。
class CancellationToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;

  void cancel() {
    _cancelled = true;
  }
}
