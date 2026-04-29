# 接入指南

## 1) 依赖接入

```yaml
dependencies:
  flutter_ad_plugin:
    git:
      url: git@github.com:yanmingLiu/flutter_ad_plugin.git
      ref: v0.1.0
```

## 2) 初始化（注入配置和埋点）

```dart
await FlutterAdPlugin.init(
  configRepository: MyConfigRepository(),
  eventReporter: MyAdEventReporter(),
);
```

### 埋点接入（外部项目）

插件不会绑定具体埋点平台，宿主项目需要实现 `AdEventReporter` 并在初始化时注入。

```dart
import 'package:flutter_ad_plugin/ad/analytics/ad_event.dart';
import 'package:flutter_ad_plugin/ad/analytics/ad_event_reporter.dart';

class MyAdEventReporter implements AdEventReporter {
  @override
  Future<void> report(AdEvent event) async {
    final placement = event.placementLabel ?? event.placement;
    final params = {
      'event_type': event.eventType.name,
      'placement': placement,
      'ad_type': event.adType.name,
      'source': event.source.name,
      'ad_unit_id': event.adUnitId,
      'error_code': event.errorCode,
      'error_reason': event.errorReason,
      'revenue': event.revenue,
      'currency': event.currency,
      'ts': event.timestamp.toIso8601String(),
    };

    // TODO: 映射到你的埋点系统（Firebase / AppsFlyer / Adjust / 自研）
    // sendToAnalytics(params);
  }
}
```

当前会回调的核心事件类型（`AdEventType`）：

- `loadRequested`
- `loadSucceeded`
- `loadFailed`
- `show`
- `showSuccess`
- `showFail`
- `close`
- `rewardEarned`
- `income`
- `blockedByGuard`

埋点建议：

- 失败事件（`loadFailed/showFail`）务必上报 `error_code`、`error_reason`
- 收益事件（`income`）务必上报 `revenue`、`currency`、`ad_unit_id`
- 业务广告位建议优先使用 `placementLabel`，未传时回退 `placement`

## 3) 开屏/全屏广告

```dart
await FlutterAdPlugin.preloadByKey('open');
final shown = await FlutterAdPlugin.showByKey('open');
```

## 4) 原生广告

```dart
await FlutterAdPlugin.loadNativeByKey('home');
final ad = FlutterAdPlugin.getNativeAdByKey('home');
if (ad != null) {
  NativeAdView(ad: ad, height: 280);
}
```

## 5) 只传 JSON 的实现方式

`MyConfigRepository` 内部直接解析 JSON：

```dart
class MyConfigRepository implements AdConfigRepository {
  @override
  Future<AdConfig> getConfig() async {
    final json = ...; // remote/local json map
    return AdConfigParser().parse(json);
  }
}
```

你只需要维护 JSON 即可决定：

- 广告位（placement key）
- 候选广告类型与权重
- 冷却策略和提示策略（`placement_policy`）

## 6) 新增广告位

当前版本已支持纯字符串广告位：  
新增 placement key 只需要在 JSON 中新增对应节点，不需要再改插件源码映射表。

可选：内置常量 `Placements.*` 仅用于常见 key 便捷引用，不是必须。
