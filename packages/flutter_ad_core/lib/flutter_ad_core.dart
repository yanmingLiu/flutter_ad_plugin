/// Core orchestration library for flutter_ad.
///
/// Contains the main `AdPlugin` facade, `AdPlatform` abstract interface,
/// engine services (waterfall, caching, guard, presenter) and data models.
library;

export 'ad_plugin.dart' show AdPlugin;
export 'models.dart'
    show
        AdEvent,
        AdEventType,
        AdNotReadyEvent,
        AdShowResult,
        AdSequenceShowResult,
        PlacementType;
export 'platform.dart'
    show
        AdPlatform,
        AdAdapterRegistry,
        AdRawCallback,
        AdImpressionCallback,
        AdPaidCallback,
        AdClickedCallback,
        AdClosedCallback,
        AdRewardedCallback,
        AdShowedCallback,
        AdShowFailedCallback,
        CommonLoaderMixin,
        CancellationToken,
        AppLogger;
