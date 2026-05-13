import 'package:flutter/foundation.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:flutter_ad_plugin/ad/core/ad_config.dart';

import '../../tools/log_tool.dart';
import '../analytics/ad_event.dart';
import '../analytics/ad_event_reporter.dart';
import '../config/ad_config_repository.dart';
import '../controller/fullscreen_ad_controller.dart';
import '../controller/native_ad_controller.dart';
import '../core/ad_enums.dart';
import '../core/placement_policy.dart';
import '../sdk/ad_adapter_registry.dart';
import '../sdk/ad_sdk_initializer.dart';
import '../sdk/adapters/admob_interstitial_adapter.dart';
import '../sdk/adapters/admob_native_adapter.dart';
import '../sdk/adapters/admob_open_adapter.dart';
import '../sdk/adapters/admob_rewarded_adapter.dart';
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

  AdConfigRepository get configRepository => _configRepository;
  Future<AdConfig> get config => _configRepository.getConfig();

  bool _initialized = false;

  Future<void> initWith({
    required AdConfigRepository configRepository,
    required AdEventReporter eventReporter,
  }) async {
    if (_initialized) return;
    _configRepository = configRepository;
    _reporter = eventReporter;
    await init();
  }

  Future<void> init() async {
    if (_initialized) return;
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

    log.d('🏁 [init] start');
    await _sdkInitializer.initAll();
    await _configRepository.getConfig();
    _lifecycleService.start();
    _initialized = true;
    log.d('🏁 [init] ready');
  }

  Future<bool> preload(PlacementType placement) async {
    log.d('📥 [service] preload: ${placement.name}');
    final ready = await _fullscreenController.preload(placement);
    log.d('📥 [service] preload_finish: ${placement.name} ready=$ready');
    return ready;
  }

  Future<bool> preloadStartupAds() async {
    log.d('📥 [service] startup_preload');
    return _preloadService.preloadStartupAds();
  }

  Future<void> preloadSecondaryStartupAds() {
    log.d('📥 [service] secondary_preload');
    return _preloadService.preloadSecondaryAds();
  }

  Future<bool> show(
    PlacementType placement, {
    String? placementLabel,
    VoidCallback? onAdShowed,
  }) async {
    final placementValue = placementLabel ?? placement.name;
    log.d('🚀 [service] show: $placementValue');
    final guardResult = await _guard.canShow(
      placement: placement,
      configRepository: _configRepository,
    );
    if (!guardResult.allowed) {
      final reason = guardResult.reason?.name ?? 'unknown';
      log.d('🚫 [service] blocked: $placementValue reason=$reason');
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
      log.d('📥 [service] no_cache: $placementValue, try_preload');
      await _fullscreenController.preload(placement);
    }

    if (!_fullscreenController.hasAvailableAd(placement)) {
      log.d('❌ [service] show_failed: $placementValue reason=no_cache');
      final slot = _fullscreenController.getSlot(placement);
      final fallbackType = placement == PlacementType.open
          ? AdType.open
          : AdType.interstitial;
      final adType = slot?.loadedType ?? fallbackType;
      final source = slot?.loadedSource ?? AdSource.admob;
      final adUnitId = slot?.adUnitId ?? '';

      _reporter.report(
        AdEvent(
          eventType: AdEventType.show,
          placement: placement,
          placementLabel: placementLabel,
          adType: adType,
          source: source,
          adUnitId: adUnitId,
          timestamp: DateTime.now(),
        ),
      );
      _reporter.report(
        AdEvent(
          eventType: AdEventType.showFail,
          placement: placement,
          placementLabel: placementLabel,
          adType: adType,
          source: source,
          adUnitId: adUnitId,
          errorCode: -1,
          errorReason: 'no cache',
          timestamp: DateTime.now(),
        ),
      );
      if (PlacementPolicies.of(placement).showNotReadyToast) {
        SmartDialog.showToast('The ad is not ready, please try again later.');
      }
      return false;
    }

    log.d('🚀 [service] displaying: $placementValue');
    _guard.markShowStarted(placement);
    final result = await _fullscreenController.show(
      placement: placement,
      placementLabel: placementLabel,
      onAdShowed: onAdShowed,
    );
    if (result.shown) {
      _guard.markShowCompleted(placement);
      log.d('✅ [service] shown: $placementValue');
    } else {
      _guard.markShowFailed(placement);
      log.d('❌ [service] show_failed: $placementValue error=${result.error}');
    }
    return result.shown;
  }

  Future<bool> loadNative(PlacementType placement) async {
    log.d('📥 [service] native_preload: ${placement.name}');
    return _nativeController.preload(placement);
  }

  NativeAd? getNativeAd(PlacementType placement) {
    return _nativeController.getAd(placement);
  }

  Future<NativeAd?> showNative(
    PlacementType placement, {
    String? placementLabel,
  }) async {
    log.d('🚀 [service] native_show: ${placementLabel ?? placement.name}');
    return _nativeController.show(placement, placementLabel: placementLabel);
  }

  bool hasReadyAd(PlacementType placement) {
    return _fullscreenController.hasAvailableAd(placement) ||
        _nativeController.hasAvailableAd(placement);
  }

  void dispose() {
    // 待后续在控制器中实现具体的资源释放逻辑
  }
}
