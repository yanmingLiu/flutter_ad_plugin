# Flutter Ad Plugin

独立 Flutter 广告模块示例项目，抽取自现有广告实现。项目保留统一广告入口、配置解析、AdMob 适配器、广告缓存、展示频控、生命周期触发、原生广告视图和埋点接口。

## 快速开始

```bash
flutter pub get
flutter run
```

当前项目默认使用 Google Mobile Ads 官方测试广告位，可以直接调试加载和展示流程。上线前需要替换：

- `lib/ad/config/ad_config_repository.dart` 中的默认广告位配置
- `android/app/src/main/AndroidManifest.xml` 中的 `APPLICATION_ID`
- `ios/Runner/Info.plist` 中的 `GADApplicationIdentifier`

## 使用入口

```dart
await AdService.instance.init();
await AdService.instance.preloadStartupAds();
await AdService.instance.show(PlacementType.open);

await AdService.instance.loadNative(PlacementType.home);
final nativeAd = AdService.instance.getNativeAd(PlacementType.home);
```

## 文档

- [架构说明](docs/architecture.md)
- [接入指南](docs/integration.md)
- [广告配置](docs/ad_config.md)
- [时序图](docs/sequence.md)

## 目录

```text
lib/ad/
  analytics/    广告事件和上报接口
  config/       配置仓库和 JSON 解析
  controller/   全屏广告与原生广告控制器
  core/         枚举、模型、广告位能力和策略
  sdk/          SDK 初始化、适配器注册、AdMob 适配器
  service/      对业务层暴露的服务、频控、生命周期、预加载
  ui/           Flutter 原生广告承载组件
```
# flutter_ad_plugin
