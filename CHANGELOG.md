# Changelog

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
