import 'package:flutter/foundation.dart';

import '../core/ad_config.dart';
import '../core/ad_enums.dart';
import '../core/ad_models.dart';
import '../utils/ad_reporter.dart';

/// 广告类型适配器的抽象接口。
///
/// 每个 AdMob/MAX/TopOn 等广告平台为每种广告类型（开屏/插屏/激励/原生）
/// 提供一个实现类。引擎通过 [AdAdapterRegistry] 按 source + type 查找适配器。
///
/// ## show() 的 await 行为
/// [show] 应阻塞直到用户关闭广告（或展示失败）才返回 [AdShowResult]。
/// 这样可以实现连续调用两次 show() 逐个弹出的效果。
abstract class AdTypeAdapter {
  AdSource get source;
  AdType get type;

  /// 加载广告并返回 [AdLoadResult]。
  ///
  /// [eventName] 由引擎透传，用于该加载链路中产生的埋点事件
  /// （如原生广告的 income/click 事件）。
  Future<AdLoadResult<Object>> load({
    required PlacementType placement,
    required AdUnitConfig unit,
    required Duration timeout,
    required AdEventReporter reporter,
    String? eventName,
    void Function(Object ad, AdType type, String adUnitId)? onLateAdLoaded,
  });

  /// 展示已加载的广告。
  ///
  /// 实现方必须等待用户关闭广告（onDismissed）后才 complete，
  /// 不得在 ad.show() 返回后立即 complete。
  Future<AdShowResult> show({
    required PlacementType placement,
    String? placementLabel,
    String? eventName,
    required Object ad,
    required AdEventReporter reporter,
    VoidCallback? onAdShowed,
    VoidCallback? onClosed,
  });

  void dispose(Object ad);
}
