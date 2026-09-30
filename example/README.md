# flutter_ad_plugin_example

Example app for verifying the AdMob, AppLovin MAX, and TopOn integrations in
the iOS Simulator.

## iOS Simulator

List and boot a simulator before running the demo:

```bash
xcrun simctl list devices available
open -a Simulator
flutter devices
```

## AdMob

AdMob includes official public test ad units, so this platform works in the
iOS Simulator without account credentials:

```bash
cd example
flutter run -d <ios-simulator-id> \
  --dart-define=AD_PLATFORM=admob
```

The example fills all placements with AdMob's official iOS test IDs.

## AppLovin MAX

MAX does not provide public test ad unit IDs. Supply the SDK key and ad unit
IDs from your MAX account. The iOS Simulator is automatically treated as a
test device by the MAX SDK; `MAX_TEST_DEVICE_ADVERTISING_IDS` is optional and
accepts comma-separated IDFA/IDFV values when needed.

```bash
cd example
flutter run -d <ios-simulator-id> \
  --dart-define=AD_PLATFORM=max \
  --dart-define=MAX_SDK_KEY=<max-sdk-key> \
  --dart-define=MAX_OPEN_AD_UNIT_ID=<open-ad-unit-id> \
  --dart-define=MAX_INTERSTITIAL_AD_UNIT_ID=<interstitial-ad-unit-id> \
  --dart-define=MAX_REWARDED_AD_UNIT_ID=<rewarded-ad-unit-id> \
  --dart-define=MAX_NATIVE_AD_UNIT_ID=<native-ad-unit-id> \
  --dart-define=MAX_NATIVE_VIDEO_AD_UNIT_ID=<native-video-ad-unit-id> \
  --dart-define=MAX_BANNER_AD_UNIT_ID=<banner-ad-unit-id>
```

Use the bug icon in the demo app bar to open the MAX Mediation Debugger.

## TopOn

TopOn does not provide public test ad unit IDs. Supply the app ID, app key,
and placement IDs from the TopOn dashboard. A debug key enables the debugger
button in the demo app bar.

`secmtp_sdk` 1.0.16 does not declare its TopOn Core dependency in the iOS
podspec. The example Podfile therefore adds `TPNiOS` 6.5.82 and forwards its
xcframework search path to `secmtp_sdk`.

```bash
cd example
flutter run -d <ios-simulator-id> \
  --dart-define=AD_PLATFORM=topon \
  --dart-define=TOPON_APP_ID=<topon-app-id> \
  --dart-define=TOPON_APP_KEY=<topon-app-key> \
  --dart-define=TOPON_DEBUG_KEY=<topon-debug-key> \
  --dart-define=TOPON_SPLASH_PLACEMENT_ID=<splash-placement-id> \
  --dart-define=TOPON_INTERSTITIAL_PLACEMENT_ID=<interstitial-placement-id> \
  --dart-define=TOPON_REWARDED_PLACEMENT_ID=<rewarded-placement-id> \
  --dart-define=TOPON_NATIVE_PLACEMENT_ID=<native-placement-id> \
  --dart-define=TOPON_NATIVE_VIDEO_PLACEMENT_ID=<native-video-placement-id> \
  --dart-define=TOPON_BANNER_PLACEMENT_ID=<banner-placement-id>
```

The JSON-style ad config is generated for the selected platform in
`lib/integration_templates.dart`.
