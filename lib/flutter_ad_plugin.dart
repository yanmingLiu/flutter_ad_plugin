import 'package:flutter/widgets.dart';

import 'src/core/ad_config.dart';
import 'src/core/ad_enums.dart';
import 'src/engine/ad_engine.dart';
import 'src/ui/native_ad_view.dart';
import 'src/utils/ad_reporter.dart';

export 'src/core/ad_config.dart';
export 'src/core/ad_enums.dart';
export 'src/ui/native_ad_view.dart';
export 'src/utils/ad_reporter.dart';

/// 广告插件对外的统一入口（Facade）。
///
/// 所有 API 均为静态方法，内部委托给 [AdEngine] 单例。
///
/// ## 初始化
/// 必须先调用 [init] 注入 [AdConfigRepository] 和 [AdEventReporter] 后才能使用广告功能。
///
/// ## show() 的 await 行为
/// [show] 会阻塞直到用户关闭广告（或展示失败）才返回。
/// 这意味着可以连续 await 两次 [show] 实现"关闭一个再弹下一个"的效果。
class FlutterAdPlugin {
  FlutterAdPlugin._();

  /// 初始化广告引擎，必须在使用其他方法前调用。
  static Future<void> init({
    required AdConfigRepository configRepository,
    required AdEventReporter eventReporter,
  }) {
    return AdEngine.instance.initWith(
      configRepository: configRepository,
      eventReporter: eventReporter,
    );
  }

  /// 预加载指定广告位的全屏广告（开屏/插屏/激励）。
  static Future<bool> preload(PlacementType placement, {String? eventName}) {
    return AdEngine.instance.preload(placement, eventName: eventName);
  }

  /// 展示指定广告位的全屏广告。
  ///
  /// 会阻塞直到用户关闭广告或展示失败。同一广告位如果配置了多个
  /// 全屏类型（通过 id/id2 展开），连续调用两次 show() 可逐个弹出。
  static Future<bool> show(PlacementType placement, {String? placementLabel, String? eventName}) {
    return AdEngine.instance.show(placement, placementLabel: placementLabel, eventName: eventName);
  }

  /// 预加载指定广告位的原生广告。
  static Future<bool> loadNative(PlacementType placement, {String? eventName}) {
    return AdEngine.instance.preloadNative(placement, eventName: eventName);
  }

  /// 获取已缓存的原生广告对象（单个）。
  static Object? getNativeAd(PlacementType placement) {
    return AdEngine.instance.getNativeAd(placement);
  }

  /// 获取已缓存的原生广告对象（多个），用于双原生组合展示。
  static List<Object> getNativeAds(PlacementType placement, {int count = 2}) {
    return AdEngine.instance.getNativeAds(placement, count: count);
  }

  /// 渲染单个原生广告的 Widget。
  static Widget nativeAdWidget({required Object ad, double height = 280}) {
    return NativeAdView(ad: ad, height: height);
  }

  /// 渲染双原生广告的 Widget（垂直或水平排列）。
  static Widget dualNativeAdWidget({
    required List<Object> ads,
    double height = 600,
    Axis direction = Axis.vertical,
  }) {
    return DualNativeAdView(ads: ads, height: height, direction: direction);
  }
}
