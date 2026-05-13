# Ad Architecture

## Overview

当前广告模块统一解决这几件事：

- 广告 SDK 初始化
- 广告配置读取与解析
- 全屏广告和原生广告的缓存管理
- 广告展示时机控制
- 广告频控与冷却
- 广告埋点上报
- 业务层统一调用接口

业务层唯一入口是 [ad_service.dart](/Users/ai3/Documents/siren/lib/ad/service/ad_service.dart)：

- `AdService.instance.init()`
- `AdService.instance.preload(...)`
- `AdService.instance.preloadStartupAds()`
- `AdService.instance.show(...)`
- `AdService.instance.loadNative(...)`
- `AdService.instance.showNative(...)`
- `AdService.instance.getNativeAd(...)`

## Main Modules

### Service Layer

文件：

- [ad_service.dart](/Users/ai3/Documents/siren/lib/ad/service/ad_service.dart)
- [ad_preload_service.dart](/Users/ai3/Documents/siren/lib/ad/service/ad_preload_service.dart)
- [ad_display_guard.dart](/Users/ai3/Documents/siren/lib/ad/service/ad_display_guard.dart)
- [ad_lifecycle_service.dart](/Users/ai3/Documents/siren/lib/ad/service/ad_lifecycle_service.dart)

职责：

- 对业务层暴露稳定 API
- 编排 config、controller、adapter、reporter
- 做展示前 guard 检查
- 做启动期预加载策略
- 承接展示成功/失败后的统一日志

### Config Layer

文件：

- [ad_config_repository.dart](/Users/ai3/Documents/siren/lib/ad/config/ad_config_repository.dart)
- [ad_config_parser.dart](/Users/ai3/Documents/siren/lib/ad/config/ad_config_parser.dart)
- [ad_config.dart](/Users/ai3/Documents/siren/lib/ad/core/ad_config.dart)

职责：

- 从 Firebase Remote Config 读取广告配置
- 回退到本地默认配置
- 解析 placement、type、source、weight、id
- 以 `AdConfig` 形式提供给 controller / guard / service

### Controller Layer

文件：

- [fullscreen_ad_controller.dart](/Users/ai3/Documents/siren/lib/ad/controller/fullscreen_ad_controller.dart)
- [native_ad_controller.dart](/Users/ai3/Documents/siren/lib/ad/controller/native_ad_controller.dart)

职责：

- 管理每个 placement 的缓存槽位 `PlacementAdSlot`
- 加载广告
- 使用缓存广告展示
- 展示完成或失败后清理缓存并补 preload

说明：

- `FullscreenAdController` 负责 `open / interstitial / rewarded`
- `NativeAdController` 负责 `native`

### Adapter Layer

文件：

- [admob_open_adapter.dart](/Users/ai3/Documents/siren/lib/ad/sdk/adapters/admob_open_adapter.dart)
- [admob_interstitial_adapter.dart](/Users/ai3/Documents/siren/lib/ad/sdk/adapters/admob_interstitial_adapter.dart)
- [admob_rewarded_adapter.dart](/Users/ai3/Documents/siren/lib/ad/sdk/adapters/admob_rewarded_adapter.dart)
- [admob_native_adapter.dart](/Users/ai3/Documents/siren/lib/ad/sdk/adapters/admob_native_adapter.dart)
- [ad_adapter_registry.dart](/Users/ai3/Documents/siren/lib/ad/sdk/ad_adapter_registry.dart)

职责：

- 屏蔽底层 SDK 差异
- 统一 load/show 返回模型
- 统一关闭、失败、收益等回调

### Analytics Layer

文件：

- [ad_event.dart](/Users/ai3/Documents/siren/lib/ad/analytics/ad_event.dart)
- [ad_event_reporter.dart](/Users/ai3/Documents/siren/lib/ad/analytics/ad_event_reporter.dart)

职责：

- 统一广告事件模型
- 统一本地 debug 日志
- 统一业务埋点 `adreq / adreq_succ / adreq_fail / ad_show / ad_show_fail`

## Startup Flow

当前推荐启动顺序：

1. `main()` 做基础初始化
2. `AdService.instance.init()` 初始化广告 SDK 与配置仓库
3. 进入闪屏页
4. 闪屏页中先打 `install / session` 事件
5. 闪屏页 `setup()` 内触发广告预加载
6. 需要展示开屏广告时调用 `show(PlacementType.open)`
7. 广告关闭后继续进入业务页

对应位置：

- [main.dart](/Users/ai3/Documents/siren/lib/main.dart)
- [splash_screen.dart](/Users/ai3/Documents/siren/lib/screens/mian/splash_screen.dart)

## Config Source

配置来源分两层：

1. Firebase Remote Config
2. 代码内默认配置

Remote Config key：

- `ad_config_json`

读取逻辑：

1. 读 Remote Config 字符串
2. 非空且 JSON 解析成功则使用远程配置
3. 否则回退到本地默认配置
4. 解析结果缓存到仓库内存

说明：

- 当前配置不是热更新模型
- App 运行中 Remote Config 即使变了，也不会自动清缓存重建广告池
- 如果要支持热更新，需要额外做：
  - 清理 config cache
  - 清理 placement 缓存广告
  - 重新 preload

## PlacementType

定义文件：

- [ad_enums.dart](/Users/ai3/Documents/siren/lib/ad/core/ad_enums.dart)

当前 placement：

- `open`
- `home`
- `message`
- `chatBack`
- `chatSession`
- `liveVideo`

它们只表示“业务广告位”，不直接等于广告类型。

例如：

- `PlacementType.open` 可以允许 `open`、`interstitial`、`rewarded`
- `PlacementType.home` 只允许 `native`

这个“广告位允许哪些广告类型”由 `PlacementCapabilities` 决定。

## PlacementCapabilities

定义文件：

- [placement_capabilities.dart](/Users/ai3/Documents/siren/lib/ad/core/placement_capabilities.dart)

作用：

- 定义每个 `PlacementType` 允许哪些 `AdType`
- controller 在遍历广告配置时会按它过滤非法组合

当前映射：

- `open` -> `open`, `interstitial`, `rewarded`
- `home` -> `native`
- `message` -> `interstitial`, `rewarded`
- `chatBack` -> `interstitial`, `rewarded`
- `chatSession` -> `interstitial`, `rewarded`
- `liveVideo` -> `interstitial`, `rewarded`

这层的意义：

- 防止配置层把不合理广告类型投给某个 placement
- 把“业务广告位”与“底层广告类型”解耦

例子：

- 如果 `home` placement 配置了 `interstitial`，即使远程配置下发了，这条配置也会被过滤掉
- 如果 `open` placement 没有 `open` 广告，但有 `interstitial`，则可以回退用 `interstitial`

## PlacementPolicy

定义文件：

- [placement_policy.dart](/Users/ai3/Documents/siren/lib/ad/core/placement_policy.dart)

作用：

- 定义每个 placement 的展示策略，而不是广告类型能力
- 主要给 `AdDisplayGuard` 使用

字段说明：

- `isFullscreen`
  - 是否属于全屏广告位
  - 只有全屏广告才会进入全屏 guard 逻辑
- `applySamePlacementCd`
  - 是否应用“同广告位冷却”
  - 例如 `chatSession` 展示后，短时间内再次点 `chatSession` 会被拦
- `applyDifferentPlacementCd`
  - 是否应用“跨广告位冷却”
  - 例如刚展示完 `open`，短时间内再展示 `chatSession` 可能被拦
- `contributesToGlobalCooldown`
  - 这个广告位展示成功后，是否参与全局冷却记录

当前策略表：

- `open`
  - 全屏
  - 同广告位冷却：是
  - 跨广告位冷却：是
  - 参与全局冷却：是
- `home`
  - 非全屏
  - 不参与 guard 冷却
- `message`
  - 全屏
  - 不做同广告位冷却
  - 不做跨广告位冷却
  - 不参与全局冷却
- `chatBack`
  - 全屏
  - 同广告位冷却：是
  - 跨广告位冷却：是
  - 参与全局冷却：是
- `chatSession`
  - 全屏
  - 同广告位冷却：是
  - 跨广告位冷却：是
  - 参与全局冷却：是
- `liveVideo`
  - 全屏
  - 不做同广告位冷却
  - 不做跨广告位冷却
  - 不参与全局冷却

设计意图：

- `chatBack / chatSession / open` 属于容易频繁触发的拦截广告，所以要控频
- `message / liveVideo` 当前策略更宽松，通常由具体业务场景自行控制触发频次
- `home` 是 native，不应该走全屏冷却

## AdDisplayGuard

定义文件：

- [ad_display_guard.dart](/Users/ai3/Documents/siren/lib/ad/service/ad_display_guard.dart)

作用：

- 在真正 show 前决定当前 placement 是否允许展示
- 返回结构化结果，而不是简单 `bool`

当前可返回的阻塞原因：

- `fullscreenShowing`
  - 已经有一个全屏广告在展示中
- `samePlacementCooldown`
  - 同 placement 冷却中
- `differentPlacementCooldown`
  - 被其他 placement 的全局冷却影响

`AdGuardResult` 字段：

- `allowed`
- `reason`
- `retryAfterSeconds`
- `relatedPlacement`

示例日志：

```text
[ad][service][show] blocked_by_guard placement=chatSession reason=samePlacementCooldown retry_after=23s related_placement=chatSession
```

```text
[ad][service][show] blocked_by_guard placement=chatSession reason=differentPlacementCooldown retry_after=11s related_placement=open
```

## Preload Strategy

文件：

- [ad_preload_service.dart](/Users/ai3/Documents/siren/lib/ad/service/ad_preload_service.dart)

当前策略：

- 优先保证 `open`
- 其他 placement 后台异步预加载

大致顺序：

1. `preload(PlacementType.open)`
2. 后台并发预加载：
   - `message`
   - `chatBack`
   - `chatSession`
   - `liveVideo`
   - `home native`

返回语义：

- `preloadStartupAds()` 返回值只表示 `open` 是否准备好

## Fullscreen Show Flow

业务层调用：

```dart
final shown = await AdService.instance.show(PlacementType.chatSession);
```

内部顺序：

1. `AdService.show()` 打 request 日志
2. `AdDisplayGuard.canShow()` 检查是否允许展示
3. 如果被拦截，输出 `blocked_by_guard + 原因`
4. 如果当前 placement 没缓存，尝试 `preload`
5. 如果 preload 后仍没缓存：
   - 打 `ad_show`
   - 打 `ad_show_fail(reason=no cache)`
   - 返回 `false`
6. 如果有缓存，进入 `FullscreenAdController.show()`
7. controller 根据缓存槽位里的 `loadedType + loadedSource` 选择 adapter
8. adapter 展示广告
9. 广告关闭后：
   - 清掉当前缓存
   - 自动补 preload
   - `show()` Future 完成
10. `AdService.show()` 返回 `true`

重要语义：

- `await show(...)` 返回时，广告生命周期已经结束
- 业务代码可以在下一行安全继续跳转/发请求

## Native Show Flow

业务层调用：

```dart
final ad = await AdService.instance.showNative(PlacementType.home);
if (ad == null) return;
```

当前语义：

- 有缓存：返回 `NativeAd`
- 无缓存：返回 `null`

说明：

- 原生广告不经过 `AdDisplayGuard` 的全屏冷却逻辑
- 原生广告也不应该由业务层直接自己 load SDK 对象

## Return Semantics

### `show()`

签名：

```dart
Future<bool> show(PlacementType placement, {String? placementLabel})
```

语义：

- `true`：广告成功展示，并且已经关闭
- `false`：广告没有成功展示

`false` 常见原因：

- guard 拦截
- 没缓存
- preload 失败
- SDK show 失败

### `showNative()`

签名：

```dart
Future<NativeAd?> showNative(PlacementType placement, {String? placementLabel})
```

语义：

- 非空：拿到可用原生广告
- `null`：当前无法展示

## Logging

关键日志前缀：

- `[ad][init]`
- `[ad][service][preload]`
- `[ad][service][show]`
- `[ad][fullscreen][preload]`
- `[ad][fullscreen][show]`
- `[ad][native][preload]`
- `[ad][native][show]`

推荐重点关注：

- `blocked_by_guard`
- `no_cache_before_show`
- `no_cache_after_preload`
- `success`
- `failed`

## Common Extension Rules

新增广告位时至少同步更新：

1. [ad_enums.dart](/Users/ai3/Documents/siren/lib/ad/core/ad_enums.dart) 增加 `PlacementType`
2. [placement_capabilities.dart](/Users/ai3/Documents/siren/lib/ad/core/placement_capabilities.dart) 配置允许的 `AdType`
3. [placement_policy.dart](/Users/ai3/Documents/siren/lib/ad/core/placement_policy.dart) 配置冷却/全屏策略
4. Remote Config 或默认配置里增加 placement 对应广告源
5. 业务代码接入对应 `show()` / `showNative()`
6. 如有特殊埋点或前后置行为，补 usage 文档
