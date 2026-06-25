import 'package:flutter/widgets.dart';

import 'src/core/ad_config.dart';
import 'src/core/ad_enums.dart';
import 'src/engine/ad_engine.dart';
import 'src/ui/native_ad_view.dart';
import 'src/utils/ad_logger.dart';
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

  /// 是否输出详细广告日志。
  ///
  /// 默认关闭。完整广告生命周期事件仍会通过 [AdEventReporter] 回调给宿主，
  /// 控制台只打印失败事件；打开后才额外输出完整事件 JSON 和内部诊断。
  static set verboseLogging(bool enabled) {
    log.verboseEnabled = enabled;
  }

  /// 初始化广告引擎，必须在使用其他方法前调用。
  ///
  /// [fullScreenNativeStyle] configures the overlay appearance for fullscreen
  /// native ads (background color, close button widget and position, top label).
  /// Defaults to the built-in style with a yellow close button on black background.
  ///
  /// [fullScreenNativeStyle] 配置全屏原生广告遮罩层样式（背景色、关闭按钮外观
  /// 和位置、顶部标签）。默认使用内置样式（黑色背景 + 黄色关闭按钮）。
  static Future<void> init({
    required AdConfigRepository configRepository,
    required AdEventReporter eventReporter,
    Map<PlacementType, PlacementPolicy> placementPolicies = const {},
    AdNotReadyCallback? onAdNotReady,
    int nativeAdCloseClickPercent = 0,
    AdFullScreenNativeStyle fullScreenNativeStyle =
        const AdFullScreenNativeStyle(),
  }) {
    return AdEngine.instance.initWith(
      configRepository: configRepository,
      eventReporter: eventReporter,
      placementPolicies: placementPolicies,
      onAdNotReady: onAdNotReady,
      nativeAdCloseClickPercent: nativeAdCloseClickPercent,
      fullScreenNativeStyle: fullScreenNativeStyle,
    );
  }

  /// 预加载指定广告位的全屏广告（开屏/插屏/激励）。
  ///
  /// [eventName] 是宿主自定义事件名，必须由调用方明确传入并原样透传。
  static Future<bool> preload(
    PlacementType placement, {
    required String eventName,
  }) {
    return AdEngine.instance.preload(placement, eventName: eventName);
  }

  /// 批量预加载广告位。
  ///
  /// 插件会根据 JSON 中每个 placement 的类型自动加载全屏广告和/或原生广告；
  /// 具体在冷启动、热启动或业务流程中预加载哪些广告位，由宿主决定。
  ///
  /// 这是 fire-and-forget API：返回时只表示预加载任务已发起，不表示广告已加载完成。
  static Future<void> preloadPlacements(
    Iterable<PlacementType> placements, {
    required String eventName,
  }) {
    return AdEngine.instance.preloadPlacements(
      placements,
      eventName: eventName,
    );
  }

  /// 展示指定广告位的全屏广告。
  ///
  /// 会阻塞直到用户关闭广告或展示失败。同一广告位如果配置了多个
  /// 全屏类型（通过 id/id2 展开），连续调用两次 show() 可逐个弹出。
  static Future<bool> show(
    PlacementType placement, {
    BuildContext? context,
    String? placementLabel,
    required String eventName,
    int? closePassThroughPercent,
  }) {
    return AdEngine.instance.show(
      placement,
      context: context,
      placementLabel: placementLabel,
      eventName: eventName,
      closePassThroughPercent: closePassThroughPercent,
    );
  }

  /// 按缓存情况连续展示同一广告位下的两个全屏广告。
  static Future<bool> showSequence(
    PlacementType placement, {
    BuildContext? context,
    String? placementLabel,
    required String eventName,
    int? closePassThroughPercent,
  }) {
    return AdEngine.instance.showSequence(
      placement,
      context: context,
      placementLabel: placementLabel,
      eventName: eventName,
      closePassThroughPercent: closePassThroughPercent,
    );
  }

  /// 预加载指定广告位的原生广告。
  static Future<bool> loadNative(
    PlacementType placement, {
    required String eventName,
  }) {
    return AdEngine.instance.preloadNative(placement, eventName: eventName);
  }

  /// 获取已缓存的原生广告对象（单个）。
  static Object? getNativeAd(
    PlacementType placement, {
    String? placementLabel,
    required String eventName,
  }) {
    return AdEngine.instance.getNativeAd(
      placement,
      placementLabel: placementLabel,
      eventName: eventName,
    );
  }

  /// 获取已缓存的原生广告对象（多个），用于双原生组合展示。
  static List<Object> getNativeAds(
    PlacementType placement, {
    int count = 2,
    String? placementLabel,
    required String eventName,
  }) {
    return AdEngine.instance.getNativeAds(
      placement,
      count: count,
      placementLabel: placementLabel,
      eventName: eventName,
    );
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
