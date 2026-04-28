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

await FlutterAdPlugin.preload(PlacementType.open);
final shown = await FlutterAdPlugin.show(PlacementType.open);
```

## Native ad

```dart
await FlutterAdPlugin.loadNative(PlacementType.home);
final ad = FlutterAdPlugin.getNativeAd(PlacementType.home);
if (ad != null) {
  return NativeAdView(ad: ad, height: 280);
}
```

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
