/// Core orchestration library for flutter_ad.
///
/// Contains the main `AdPlugin` facade, `AdPlatform` abstract interface,
/// engine services (waterfall, caching, guard, presenter) and data models.
library;

export 'ad_plugin.dart' show AdPlugin;
export 'engine.dart'
    show
        AdCacheService,
        AdEventMapper,
        AdDisplayGuard,
        AdGuardResult,
        AdGuardBlockReason,
        AdLoaderService,
        AdPresenter;
export 'models.dart'
    show
        AdSource,
        AdType,
        AdInitializationState,
        AdInitializationStatus,
        AdEvent,
        AdEventType,
        AdEventReporter,
        AdNotReadyEvent,
        AdShowResult,
        AdSequenceShowResult,
        PlacementType,
        AdConfig,
        AdConfigParser,
        AdConfigRepository,
        AdUnitConfig,
        PlacementPolicy,
        AdSlotState,
        AdSlotLoaded,
        AdSlotFailed,
        AdAttribution;
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
