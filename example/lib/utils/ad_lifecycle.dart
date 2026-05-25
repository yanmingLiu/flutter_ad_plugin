import 'dart:async';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdLifecycle {
  AdLifecycle({required this.onForeground});

  final void Function() onForeground;
  StreamSubscription<AppState>? _sub;

  void start() {
    // AppStateEventNotifier 能精准识别前后台切换，自动处理广告关闭导致的回弹
    AppStateEventNotifier.startListening();
    _sub = AppStateEventNotifier.appStateStream.listen((state) {
      if (state == AppState.foreground) {
        onForeground();
      }
    });
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }
}
