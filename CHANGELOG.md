# Changelog

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
