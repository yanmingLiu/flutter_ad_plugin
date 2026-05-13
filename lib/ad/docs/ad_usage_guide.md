# Ad Usage Guide

## Purpose

这份文档回答三件事：

1. 业务代码应该怎么接广告
2. 不同场景该选哪个 `PlacementType`
3. 哪些事情应该交给广告模块，哪些不应该在业务层自己做

架构细节见：

- [ad_architecture.md](/Users/ai3/Documents/siren/lib/ad/docs/ad_architecture.md)

## Core Rules

- 全屏广告统一走 `AdService.instance.show(...)`
- 原生广告统一走 `showNative(...)` 或 `getNativeAd(...)`
- 不要在业务层直接接 `google_mobile_ads` 的 load/show 回调
- 不要在业务层自己实现广告冷却
- 不要在业务层自己维护缓存池
- `await show(...)` 返回时，广告已经关闭
- 业务层把 `show()` 的 `bool` 只当成“是否真正展示成功”

## Entry API

入口文件：

- [ad_service.dart](/Users/ai3/Documents/siren/lib/ad/service/ad_service.dart)

### Init

```dart
await AdService.instance.init();
```

适用：

- App 启动时初始化广告系统

### Preload One Placement

```dart
await AdService.instance.preload(PlacementType.chatSession);
```

适用：

- 你知道某个节点马上要用广告，想提高命中率

### Preload Startup Ads

```dart
await AdService.instance.preloadStartupAds();
```

适用：

- 启动阶段
- 优先准备开屏广告

### Show Fullscreen Ad

```dart
final shown = await AdService.instance.show(PlacementType.chatBack);
```

语义：

- `true`：广告成功展示并已关闭
- `false`：广告没展示出来

### Show Native Ad

```dart
final nativeAd = await AdService.instance.showNative(PlacementType.home);
if (nativeAd == null) return;
```

语义：

- 非空：拿到一个可展示的 `NativeAd`
- `null`：当前没有可用广告

### Get Native Ad Without Show Semantics

```dart
final nativeAd = AdService.instance.getNativeAd(PlacementType.home);
```

适用：

- 你只想读当前缓存
- 不想触发新的 native show 语义

## Placement Selection

定义见：

- [ad_enums.dart](/Users/ai3/Documents/siren/lib/ad/core/ad_enums.dart)
- [placement_capabilities.dart](/Users/ai3/Documents/siren/lib/ad/core/placement_capabilities.dart)
- [placement_policy.dart](/Users/ai3/Documents/siren/lib/ad/core/placement_policy.dart)

### `PlacementType.open`

适用：

- 开屏广告
- 回前台拦截广告
- 进入首页前的启动广告

说明：

- 是全屏 placement
- 有同 placement 冷却
- 有跨 placement 冷却
- 参与全局冷却
- 允许 `open / interstitial / rewarded`

调用：

```dart
await AdService.instance.show(PlacementType.open);
```

### `PlacementType.home`

适用：

- 首页 feed 中的 native 广告位

说明：

- 非全屏 placement
- 不走全屏 guard
- 只允许 `native`

调用：

```dart
final ad = await AdService.instance.showNative(PlacementType.home);
```

### `PlacementType.message`

适用：

- 消息场景的全屏广告
- 某个消息节点前插入的广告

说明：

- 是全屏 placement
- 当前默认不做同位冷却/跨位冷却
- 允许 `interstitial / rewarded`

调用：

```dart
final shown = await AdService.instance.show(PlacementType.message);
```

### `PlacementType.chatBack`

适用：

- 聊天页返回前
- 聊天过程中的普通拦截位

说明：

- 是全屏 placement
- 做同位冷却
- 做跨位冷却
- 参与全局冷却
- 允许 `interstitial / rewarded`

调用：

```dart
final shown = await AdService.instance.show(PlacementType.chatBack);
```

### `PlacementType.chatSession`

适用：

- 会话列表点进聊天页前
- 需要和 `chatBack` 分开统计、分开频控的聊天入口广告位

说明：

- 是全屏 placement
- 做同位冷却
- 做跨位冷却
- 参与全局冷却
- 允许 `interstitial / rewarded`

调用：

```dart
final shown = await AdService.instance.show(PlacementType.chatSession);
```

推荐模式：

```dart
await AdService.instance.show(PlacementType.chatSession);
await RouterTool.pushChat(session.characterId);
```

这样即使广告没展示出来，也不会阻塞正常进聊天页。

### `PlacementType.liveVideo`

适用：

- 图片/视频解锁前
- 明确的激励式节点

说明：

- 是全屏 placement
- 当前默认不做冷却
- 允许 `interstitial / rewarded`

调用：

```dart
final shown = await AdService.instance.show(PlacementType.liveVideo);
if (!shown) return;
await unlockAction();
```

## Common Patterns

### Splash Ad

```dart
await AdService.instance.show(PlacementType.open);
_enterApp();
```

语义：

- 广告结束后再进主页
- 没广告就直接进主页

### Gate Before Navigation

```dart
await AdService.instance.show(PlacementType.chatSession);
await RouterTool.pushChat(session.characterId);
```

适用：

- 广告只是前置插入，不是强制门槛

### Hard Gate Unlock

```dart
final shown = await AdService.instance.show(PlacementType.liveVideo);
if (!shown) return;
await unlockApi();
```

适用：

- 没看到广告就不给奖励

### Native Feed Slot

```dart
final nativeAd = await AdService.instance.showNative(
  PlacementType.home,
  placementLabel: 'home_feed',
);
if (nativeAd == null) return;
```

## What Business Layer Should Not Do

不要这样做：

- 直接 new `InterstitialAd` / `RewardedAd` / `NativeAd`
- 业务层自己记录上次广告展示时间
- 业务层自己判断 cooldown
- 业务层自己实现 load fail 重试
- 业务层把一个 ad object 跨页面长期持有

这些都应该交给广告模块统一处理。

## PlacementCapabilities Explained

`PlacementCapabilities` 解决的问题是：

- 某个 placement 到底允许哪几类广告类型进入候选池

它不是频控，不是展示时机，也不是业务语义。

例子：

- `home` 是一个原生广告位，所以只允许 `native`
- `chatSession` 是会话入口全屏广告位，所以允许 `interstitial / rewarded`
- `open` 是开屏位，所以兼容 `open / interstitial / rewarded`

如果配置里下发了一个 placement 不支持的广告类型，这条配置会被 controller 过滤掉，不会进加载流程。

## PlacementPolicy Explained

`PlacementPolicy` 解决的问题是：

- 这个 placement 在展示前要不要进全屏 guard
- 要不要做同位冷却
- 要不要做跨位冷却
- 展示成功后要不要参与全局冷却

它不决定广告类型，只决定展示策略。

一个常见误区是：

- `PlacementCapabilities` 管“能不能配这种广告类型”
- `PlacementPolicy` 管“即使有广告，当前这次能不能展示”

两者是不同层级，不要混用。

## Logging And Troubleshooting

关键日志看这些前缀：

- `[ad][service][show]`
- `[ad][fullscreen][preload]`
- `[ad][fullscreen][show]`
- `[ad][native][preload]`
- `[ad][native][show]`

最常见失败原因：

- `blocked_by_guard`
- `no_cache_before_show`
- `no_cache_after_preload`
- adapter `load failed`
- adapter `show failed`

`blocked_by_guard` 现在会额外打印：

- `reason`
- `retry_after`
- `related_placement`

看到这条日志时，优先判断是：

1. 当前已有全屏广告在展示
2. 同广告位冷却没过
3. 被别的广告位全局冷却影响

## Checklist For New Placement

新增一个广告位时，至少要完成：

1. 在 [ad_enums.dart](/Users/ai3/Documents/siren/lib/ad/core/ad_enums.dart) 增加 `PlacementType`
2. 在 [placement_capabilities.dart](/Users/ai3/Documents/siren/lib/ad/core/placement_capabilities.dart) 配允许的 `AdType`
3. 在 [placement_policy.dart](/Users/ai3/Documents/siren/lib/ad/core/placement_policy.dart) 配展示策略
4. 在默认配置或远程配置中补 placement 对应单元
5. 在业务层选择 `show()` 还是 `showNative()`
6. 补一条文档说明这个广告位的业务语义和推荐调用时机
