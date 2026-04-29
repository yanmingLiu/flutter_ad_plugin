import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../tools/log_tool.dart';
import '../analytics/ad_event.dart';
import '../analytics/ad_event_reporter.dart';
import '../config/ad_config_repository.dart';
import '../controller/fullscreen_ad_controller.dart';
import '../controller/native_ad_controller.dart';
import '../core/ad_enums.dart';
import '../sdk/ad_adapter_registry.dart';
import '../sdk/ad_sdk_initializer.dart';
import '../sdk/adapters/admob_interstitial_adapter.dart';
import '../sdk/adapters/admob_native_adapter.dart';
import '../sdk/adapters/admob_open_adapter.dart';
import '../sdk/adapters/admob_rewarded_adapter.dart';
import '../core/placement_policy.dart';
import 'ad_display_guard.dart';
import 'ad_lifecycle_service.dart';
import 'ad_preload_service.dart';

class AdService {
  AdService._internal();

  static final AdService instance = AdService._internal();

  AdConfigRepository _configRepository = DefaultAdConfigRepository();
  AdEventReporter _reporter = DefaultAdEventReporter();
  final AdSdkInitializer _sdkInitializer = createDefaultAdSdkInitializer();
  final AdAdapterRegistry _adapterRegistry = AdAdapterRegistry([
    AdmobOpenAdapter(),
    AdmobInterstitialAdapter(),
    AdmobRewardedAdapter(),
    AdmobNativeAdapter(),
  ]);
  final AdDisplayGuard _guard = AdDisplayGuard();

  late FullscreenAdController _fullscreenController;
  late NativeAdController _nativeController;
  late AdLifecycleService _lifecycleService;
  late AdPreloadService _preloadService;

  bool _initialized = false;

  Future<void> initWith({
    required AdConfigRepository configRepository,
    required AdEventReporter eventReporter,
  }) async {
    if (_initialized) return;
    _configRepository = configRepository;
    _reporter = eventReporter;
    _rebuildControllers();
    await init();
  }

  Future<void> init() async {
    if (_initialized) return;
    _rebuildControllers();
    log.d('[ad][init] start');
    await _sdkInitializer.initAll();
    await _configRepository.getConfig();
    _lifecycleService.start();
    _initialized = true;
    log.d('[ad][init] ready');
  }

  void _rebuildControllers() {
    _fullscreenController = FullscreenAdController(
      configRepository: _configRepository,
      adapterRegistry: _adapterRegistry,
      reporter: _reporter,
    );
    _nativeController = NativeAdController(
      configRepository: _configRepository,
      adapterRegistry: _adapterRegistry,
      reporter: _reporter,
    );
    _lifecycleService = AdLifecycleService(this);
    _preloadService = AdPreloadService(this);
  }

  Future<bool> preload(PlacementType placement) async {
    log.d('[ad][service][preload] placement=$placement');
    final ready = await _fullscreenController.preload(placement);
    log.d(
      '[ad][service][preload] finish placement=$placement ready=$ready has_cache=${_fullscreenController.hasAvailableAd(placement)}',
    );
    return ready;
  }

  Future<bool> preloadStartupAds() async {
    log.d('[ad][service][startup_preload] start');
    return _preloadService.preloadStartupAds();
  }

  Future<void> preloadSecondaryStartupAds() {
    log.d('[ad][service][startup_secondary_preload] start');
    return _preloadService.preloadSecondaryAds();
  }

  Future<bool> show(PlacementType placement, {String? placementLabel}) async {
    final placementValue = placementLabel ?? placement;
    log.d('[ad][service][show] request placement=$placementValue');
    final guardResult = await _guard.canShow(
      placement: placement,
      configRepository: _configRepository,
    );
    if (!guardResult.allowed) {
      final reason = guardResult.reason?.name ?? 'unknown';
      final retryAfter = guardResult.retryAfterSeconds;
      final relatedPlacement = guardResult.relatedPlacement;
      log.d(
        '[ad][service][show] 🚫 blocked_by_guard '
        'placement=$placementValue '
        'reason=$reason '
        'retry_after=${retryAfter ?? '-'}s '
        'related_placement=${relatedPlacement ?? '-'}',
      );
      _reporter.report(
        AdEvent(
          eventType: AdEventType.blockedByGuard,
          placement: placement,
          adType: AdType.interstitial,
          source: AdSource.admob,
          adUnitId: '',
          errorCode: -1,
          errorReason: reason,
          timestamp: DateTime.now(),
        ),
      );
      return false;
    }

    if (!_fullscreenController.hasAvailableAd(placement)) {
      log.d(
        '[ad][service][show] 🚫 no_cache_before_show placement=$placementValue, try_preload=true',
      );
      final preloadReady = await _fullscreenController.preload(placement);
      log.d(
        '[ad][service][show] preload_before_show placement=$placementValue ready=$preloadReady has_cache=${_fullscreenController.hasAvailableAd(placement)}',
      );
    }

    if (!_fullscreenController.hasAvailableAd(placement)) {
      log.d(
        '[ad][service][show] 🚫 no_cache_after_preload placement=$placementValue',
      );
      _reporter.report(
        AdEvent(
          eventType: AdEventType.show,
          placement: placement,
          placementLabel: placementLabel,
          adType: AdType.interstitial,
          source: AdSource.admob,
          adUnitId: '',
          timestamp: DateTime.now(),
        ),
      );
      _reporter.report(
        AdEvent(
          eventType: AdEventType.showFail,
          placement: placement,
          placementLabel: placementLabel,
          adType: AdType.interstitial,
          source: AdSource.admob,
          adUnitId: '',
          errorCode: -1,
          errorReason: 'no cache',
          timestamp: DateTime.now(),
        ),
      );
      final config = await _configRepository.getConfig();
      if (PlacementPolicies.of(
        config: config,
        placement: placement,
      ).showNotReadyToast) {
        log.d('[ad][service][show] not_ready_toast placement=$placementValue');
      }
      return false;
    }

    log.d('[ad][service][show] begin_display placement=$placementValue');
    _guard.markShowStarted(placement);
    final result = await _fullscreenController.show(
      placement,
      placementLabel: placementLabel,
    );
    if (result.shown) {
      _guard.markShowCompleted(placement);
      log.d('[ad][service][show] finish placement=$placementValue shown=true');
    } else {
      _guard.markShowFailed(placement);
      log.d(
        '[ad][service][show] finish placement=$placementValue shown=false error=${result.error}',
      );
    }
    return result.shown;
  }

  Future<bool> loadNative(PlacementType placement) async {
    log.d('[ad][service][native_preload] placement=$placement');
    return _nativeController.preload(placement);
  }

  NativeAd? getNativeAd(PlacementType placement) {
    return _nativeController.getAd(placement);
  }

  Future<NativeAd?> showNative(
    PlacementType placement, {
    String? placementLabel,
  }) async {
    log.d(
      '[ad][service][native_show] request placement=${placementLabel ?? placement}',
    );
    return _nativeController.show(placement, placementLabel: placementLabel);
  }

  bool hasReadyAd(PlacementType placement) {
    return _fullscreenController.hasAvailableAd(placement) ||
        _nativeController.hasAvailableAd(placement);
  }

  void dispose() {
    _fullscreenController.dispose();
    _nativeController.dispose();
  }
}
