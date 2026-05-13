import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../core/ad_enums.dart';
import 'ad_engine.dart';

class AdLifecycle {
  AdLifecycle(this._engine);

  final AdEngine _engine;
  bool _started = false;

  void start() {
    if (_started) {
      return;
    }
    _started = true;

    // 使用 Google Mobile Ads SDK 提供的 AppStateEventNotifier
    // 它能更精准地识别前后台切换，并自动处理广告关闭导致的回弹问题
    AppStateEventNotifier.startListening();
    AppStateEventNotifier.appStateStream.forEach((state) {
      if (state == AppState.foreground) {
        _onForeground();
      }
    });
  }

  Future<void> _onForeground() async {
    // 这里触发 show(open) 即可，AdEngine 内部仍保留 CD 检查以防止过快触发
    await _engine.show(PlacementType.open);
  }

  void dispose() {
    // AppStateEventNotifier 是全局单例，通常不需要手动 dispose
  }
}
