# flutter_ad_plugin

Reusable Flutter ad plugin with configurable placements, policies, and analytics hooks.

## Install (Git dependency)

```yaml
dependencies:
  flutter_ad_plugin:
    git:
      url: git@github.com:yanmingLiu/flutter_ad_plugin.git
      ref: main
```

## Quick start

```dart
import 'package:flutter_ad_plugin/flutter_ad_plugin.dart';
import 'package:flutter_ad_plugin/ad/analytics/ad_event_reporter.dart';
import 'package:flutter_ad_plugin/ad/config/ad_config_repository.dart';

await FlutterAdPlugin.init(
  configRepository: DefaultAdConfigRepository(),
  eventReporter: DefaultAdEventReporter(),
);

await FlutterAdPlugin.preloadByKey('open');
final shown = await FlutterAdPlugin.showByKey('open');
```

## Documentation

- [接入指南](/docs/integration.md)
  - 含：初始化、埋点接入（`AdEventReporter`）、全屏/原生广告调用
- [广告配置（JSON 驱动）](/docs/ad_config.md)
- [架构说明](/docs/architecture.md)
- [时序图](/docs/sequence.md)
- [变更记录](/CHANGELOG.md)

## Native ad

```dart
await FlutterAdPlugin.loadNativeByKey('home');
final ad = FlutterAdPlugin.getNativeAdByKey('home');
if (ad != null) {
  return NativeAdView(ad: ad, height: 280);
}
```

可选：如果你不想手写字符串，也可以使用内置常量 `Placements.open/home/...`。

## Integration points

- `AdConfigRepository`: implement your own remote config source.
- `AdEventReporter`: implement your own analytics reporting.

## Example app

Run the example:

```bash
cd example
flutter pub get
flutter run
```

Reference templates:

- `example/lib/integration_templates.dart`
- `CHANGELOG.md` (`v0.1.0`)
