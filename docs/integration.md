# 接入指南

## 初始化

在 App 启动时初始化广告模块：

```dart
WidgetsFlutterBinding.ensureInitialized();
await AdService.instance.init();
```

推荐在启动页或首页前预加载首批广告：

```dart
await AdService.instance.preloadStartupAds();
await AdService.instance.loadNative(PlacementType.home);
```

## 展示全屏广告

```dart
final shown = await AdService.instance.show(PlacementType.open);
```

返回值语义：

- `true`：广告成功展示，并且关闭回调已经完成。
- `false`：广告未展示，可能是无缓存、加载失败、频控阻止或广告位无配置。

## 展示原生广告

```dart
await AdService.instance.loadNative(PlacementType.home);
final ad = AdService.instance.getNativeAd(PlacementType.home);

if (ad != null) {
  NativeAdView(ad: ad, height: 280);
}
```

原生广告对象由模块负责缓存和释放，业务层不要自行 `dispose`。

## 新增广告位

新增广告位至少需要同步修改：

1. `lib/ad/core/ad_enums.dart` 增加 `PlacementType`
2. `lib/ad/core/placement_capabilities.dart` 配置允许的 `AdType`
3. `lib/ad/core/placement_policy.dart` 配置频控和全屏策略
4. `lib/ad/config/ad_config_repository.dart` 或远程配置增加对应广告源
5. 在业务触发点调用 `preload`、`show` 或 `loadNative`
