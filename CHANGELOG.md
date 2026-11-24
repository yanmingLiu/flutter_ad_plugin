# Changelog

## 0.2.1 - 2026-11-24

- Core: 扩充公开入口导出清单（补充导出 `AdConfigParser`、`AdConfig`、`AdLoaderService`、`AdPresenter`、`AdCacheService`、`AdDisplayGuard` 等全部引擎与数据模型类型）。
- MAX / AdMob / TopOn: 级联导出全套 Core API，宿主项目无需显式声明 Core 即可直接构建追加瀑布流与高级调度服务，彻底消除 Git 传递依赖的解析冲突。
- 测试: 清理各子包测试用例中冗余的 `models.dart` 导入。

## 0.2.0 - 2026-11-24

- Breaking: 仅支持 `packages/` 下的分包接入。迁移方式见 README。
- 示例和回归测试改用分包，移除仓库根目录的聚合包与重复实现。
- Core 公开导出 `AdType`，双 Native 达到整组数量后才进入缓存。
- 修复 AdMob 激励回调提前清空和 MAX 同广告位并发请求覆盖。
- TopOn 从缓存广告读取加载估值与广告网络，开屏关闭与全屏事件归因按实际回包处理。

## 0.1.1

- feat: 在广告事件 `AdEvent` 中增加 `estimatedRevenue` 预估收益字段，并在 `income` 时输出。
  - MAX: 在广告加载完成时获取预估收益（`revenue * 1000000`），在 `income` 收益事件触发时回调透出。
  - TopOn: 在广告加载完成时从响应参数提取预估收益（`* 1000000`），在 `income` 收益事件触发时回调透出。
  - AdMob: 维持在 `income` 阶段回调，SDK 未返回预估收益时默认返回 `0`。
  - 同步更新主包及单组件拆分子包（`flutter_ad_core`、`flutter_ad_max`、`flutter_ad_admob`、`flutter_ad_topon`）。

## 0.1.0

- Restructured repository to reusable Flutter package form.
- Added public package entrypoint `lib/flutter_ad_plugin.dart`.
- Added injectable initialization API:
  - `AdConfigRepository`
  - `AdEventReporter`
- Kept existing ad orchestration features:
  - placement model
  - preload/show flow
  - fullscreen guard & cooldown policies
  - native ad loading/rendering
- Added iOS native ad factory implementation and registration for `homeListTile`.
- Added `example/` app demonstrating package integration.
- Added package-level README for Git dependency usage.
