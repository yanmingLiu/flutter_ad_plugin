import 'package:flutter_ad_plugin/src/core/ad_config.dart';
import 'package:flutter_ad_plugin/src/core/ad_enums.dart';
import 'package:flutter_ad_plugin/src/core/ad_policy.dart';
import 'package:flutter_ad_plugin/src/engine/ad_guard.dart';
import 'package:flutter_test/flutter_test.dart';

AdConfigRepository _configRepo({
  int samePlacementCd = 30,
  int differentPlacementCd = 30,
  PlacementType placement = const PlacementType('open'),
  bool isFullscreen = true,
  bool applySameCd = true,
  bool applyDiffCd = true,
  bool contributesGlobal = true,
  bool waitForLoadOnShow = true,
  bool preferHighValue = true,
}) {
  final config = AdConfig(
    loadTimeoutSeconds: 7,
    samePlacementCdSeconds: samePlacementCd,
    differentPlacementCdSeconds: differentPlacementCd,
    placements: {},
    policies: {
      placement: PlacementPolicy(
        isFullscreen: isFullscreen,
        applySamePlacementCd: applySameCd,
        applyDifferentPlacementCd: applyDiffCd,
        contributesToGlobalCooldown: contributesGlobal,
        showNotReadyToast: false,
        waitForLoadOnShow: waitForLoadOnShow,
        preferHighValueOnShow: preferHighValue,
      ),
    },
  );
  return _StubConfigRepo(config);
}

class _StubConfigRepo implements AdConfigRepository {
  final AdConfig config;
  const _StubConfigRepo(this.config);

  @override
  Future<AdConfig> getConfig() async => config;
}

void main() {
  late AdDisplayGuard guard;

  setUp(() {
    guard = AdDisplayGuard();
  });

  group('canShow', () {
    test('allows non-fullscreen placement immediately', () async {
      final repo = _configRepo(
        placement: const PlacementType('native'),
        isFullscreen: false,
        applySameCd: false,
        applyDiffCd: false,
      );
      final result = await guard.canShow(
        placement: const PlacementType('native'),
        configRepository: repo,
      );
      expect(result.allowed, isTrue);
    });

    test('blocks when fullscreen is already showing', () async {
      final placement = const PlacementType('open');
      final repo = _configRepo(placement: placement);

      guard.markShowStarted(placement, PlacementPolicy(
        isFullscreen: true,
        applySamePlacementCd: false,
        applyDifferentPlacementCd: false,
        contributesToGlobalCooldown: false,
        showNotReadyToast: false,
        waitForLoadOnShow: false,
        preferHighValueOnShow: false,
      ));

      final result = await guard.canShow(
        placement: placement,
        configRepository: repo,
      );
      expect(result.allowed, isFalse);
      expect(result.reason, AdGuardBlockReason.fullscreenShowing);
    });

    test('allows after markShowCompleted clears mutex', () async {
      final placement = const PlacementType('open');
      final repo = _configRepo(
        placement: placement,
        applySameCd: false,
        applyDiffCd: false,
      );
      final policy = PlacementPolicy(
        isFullscreen: true,
        applySamePlacementCd: false,
        applyDifferentPlacementCd: false,
        contributesToGlobalCooldown: false,
        showNotReadyToast: false,
        waitForLoadOnShow: false,
        preferHighValueOnShow: false,
      );

      guard.markShowStarted(placement, policy);

      final blocked = await guard.canShow(
        placement: placement,
        configRepository: repo,
      );
      expect(blocked.allowed, isFalse);

      guard.markShowCompleted(placement, policy);

      final allowed = await guard.canShow(
        placement: placement,
        configRepository: repo,
      );
      expect(allowed.allowed, isTrue);
    });

    test('blocks same placement within CD period', () async {
      const placement = PlacementType('open');
      final repo = _configRepo(
        placement: placement,
        samePlacementCd: 30,
        applySameCd: true,
      );
      final policy = PlacementPolicy(
        isFullscreen: true,
        applySamePlacementCd: true,
        applyDifferentPlacementCd: false,
        contributesToGlobalCooldown: false,
        showNotReadyToast: false,
        waitForLoadOnShow: false,
        preferHighValueOnShow: false,
      );

      guard.markShowCompleted(placement, policy);

      final result = await guard.canShow(
        placement: placement,
        configRepository: repo,
      );
      expect(result.allowed, isFalse);
      expect(result.reason, AdGuardBlockReason.samePlacementCooldown);
      expect(result.retryAfterSeconds, lessThanOrEqualTo(30));
    });

    test('blocks different placement within global CD period', () async {
      const placementA = PlacementType('open');
      const placementB = PlacementType('interstitial');
      final repoB = _configRepo(
        placement: placementB,
        applyDiffCd: true,
        differentPlacementCd: 30,
      );
      final policy = PlacementPolicy(
        isFullscreen: true,
        applySamePlacementCd: false,
        applyDifferentPlacementCd: false,
        contributesToGlobalCooldown: true,
        showNotReadyToast: false,
        waitForLoadOnShow: false,
        preferHighValueOnShow: false,
      );

      guard.markShowCompleted(placementA, policy);

      final result = await guard.canShow(
        placement: placementB,
        configRepository: repoB,
      );
      expect(result.allowed, isFalse);
      expect(result.reason, AdGuardBlockReason.differentPlacementCooldown);
      expect(result.relatedPlacement, placementA);
    });

    test('allows same placement when CD is disabled', () async {
      const placement = PlacementType('open');
      final repo = _configRepo(
        placement: placement,
        applySameCd: false,
        applyDiffCd: false,
      );
      final policy = PlacementPolicy(
        isFullscreen: true,
        applySamePlacementCd: false,
        applyDifferentPlacementCd: false,
        contributesToGlobalCooldown: false,
        showNotReadyToast: false,
        waitForLoadOnShow: false,
        preferHighValueOnShow: false,
      );

      guard.markShowCompleted(placement, policy);

      final result = await guard.canShow(
        placement: placement,
        configRepository: repo,
      );
      expect(result.allowed, isTrue);
    });

    test('allows different placement when global CD is disabled', () async {
      const placementA = PlacementType('open');
      const placementB = PlacementType('interstitial');
      final repo = _configRepo(
        placement: placementB,
        applyDiffCd: false,
      );
      final policy = PlacementPolicy(
        isFullscreen: true,
        applySamePlacementCd: false,
        applyDifferentPlacementCd: false,
        contributesToGlobalCooldown: true,
        showNotReadyToast: false,
        waitForLoadOnShow: false,
        preferHighValueOnShow: false,
      );

      guard.markShowCompleted(placementA, policy);

      final result = await guard.canShow(
        placement: placementB,
        configRepository: repo,
      );
      expect(result.allowed, isTrue);
    });

    test('does not block global CD for same placement', () async {
      const placement = PlacementType('open');
      final repo = _configRepo(
        placement: placement,
        applySameCd: false,
        applyDiffCd: true,
      );
      final policy = PlacementPolicy(
        isFullscreen: true,
        applySamePlacementCd: false,
        applyDifferentPlacementCd: false,
        contributesToGlobalCooldown: true,
        showNotReadyToast: false,
        waitForLoadOnShow: false,
        preferHighValueOnShow: false,
      );

      guard.markShowCompleted(placement, policy);

      final result = await guard.canShow(
        placement: placement,
        configRepository: repo,
      );
      // Same placement should not be blocked by different-placement CD
      expect(result.allowed, isTrue);
    });
  });

  group('markShowStarted', () {
    test('sets mutex for fullscreen placement', () async {
      const placement = PlacementType('open');
      final repo = _configRepo(placement: placement, isFullscreen: true);
      final policy = PlacementPolicy(
        isFullscreen: true,
        applySamePlacementCd: false,
        applyDifferentPlacementCd: false,
        contributesToGlobalCooldown: false,
        showNotReadyToast: false,
        waitForLoadOnShow: false,
        preferHighValueOnShow: false,
      );
      guard.markShowStarted(placement, policy);

      final result = await guard.canShow(
        placement: placement,
        configRepository: repo,
      );
      expect(result.allowed, isFalse);
      expect(result.reason, AdGuardBlockReason.fullscreenShowing);
    });

    test('does not set mutex for non-fullscreen placement', () async {
      const placement = PlacementType('native');
      final repo = _configRepo(
        placement: placement,
        isFullscreen: false,
        applySameCd: false,
        applyDiffCd: false,
      );
      final policy = PlacementPolicy(
        isFullscreen: false,
        applySamePlacementCd: false,
        applyDifferentPlacementCd: false,
        contributesToGlobalCooldown: false,
        showNotReadyToast: false,
        waitForLoadOnShow: false,
        preferHighValueOnShow: false,
      );
      guard.markShowStarted(placement, policy);

      final result = await guard.canShow(
        placement: const PlacementType('open'),
        configRepository: repo,
      );
      // Non-fullscreen ads should not block fullscreen ads
      expect(result.allowed, isTrue);
    });
  });

  group('markShowCompleted', () {
    test('records per-placement timestamp', () async {
      const placement = PlacementType('open');
      final repo = _configRepo(
        placement: placement,
        applySameCd: true,
        samePlacementCd: 30,
      );
      final policy = PlacementPolicy(
        isFullscreen: true,
        applySamePlacementCd: true,
        applyDifferentPlacementCd: false,
        contributesToGlobalCooldown: false,
        showNotReadyToast: false,
        waitForLoadOnShow: false,
        preferHighValueOnShow: false,
      );
      guard.markShowCompleted(placement, policy);

      final result = await guard.canShow(
        placement: placement,
        configRepository: repo,
      );
      expect(result.allowed, isFalse);
      expect(result.reason, AdGuardBlockReason.samePlacementCooldown);
    });

    test('records global CD when contributesToGlobalCooldown is true', () async {
      const placementA = PlacementType('open');
      const placementB = PlacementType('interstitial');
      final repo = _configRepo(
        placement: placementB,
        applyDiffCd: true,
      );
      final policy = PlacementPolicy(
        isFullscreen: true,
        applySamePlacementCd: false,
        applyDifferentPlacementCd: false,
        contributesToGlobalCooldown: true,
        showNotReadyToast: false,
        waitForLoadOnShow: false,
        preferHighValueOnShow: false,
      );
      guard.markShowCompleted(placementA, policy);

      final result = await guard.canShow(
        placement: placementB,
        configRepository: repo,
      );
      expect(result.allowed, isFalse);
      expect(result.reason, AdGuardBlockReason.differentPlacementCooldown);
    });

    test('clears mutex after completion', () async {
      const placement = PlacementType('open');
      final repo = _configRepo(
        placement: placement,
        applySameCd: false,
        applyDiffCd: false,
      );
      final policy = PlacementPolicy(
        isFullscreen: true,
        applySamePlacementCd: false,
        applyDifferentPlacementCd: false,
        contributesToGlobalCooldown: false,
        showNotReadyToast: false,
        waitForLoadOnShow: false,
        preferHighValueOnShow: false,
      );
      guard.markShowStarted(placement, policy);

      final blocked = await guard.canShow(
        placement: placement,
        configRepository: repo,
      );
      expect(blocked.allowed, isFalse);

      guard.markShowCompleted(placement, policy);

      final allowed = await guard.canShow(
        placement: placement,
        configRepository: repo,
      );
      expect(allowed.allowed, isTrue);
    });
  });

  group('markShowFailed', () {
    test('clears mutex but does NOT record CD timestamps', () async {
      const placement = PlacementType('open');
      final repo = _configRepo(
        placement: placement,
        applySameCd: true,
      );
      final policy = PlacementPolicy(
        isFullscreen: true,
        applySamePlacementCd: false,
        applyDifferentPlacementCd: false,
        contributesToGlobalCooldown: false,
        showNotReadyToast: false,
        waitForLoadOnShow: false,
        preferHighValueOnShow: false,
      );
      guard.markShowStarted(placement, policy);
      guard.markShowFailed(placement, policy);

      final result = await guard.canShow(
        placement: placement,
        configRepository: repo,
      );
      // Mutex cleared, and no CD recorded, so should be allowed
      expect(result.allowed, isTrue);
    });

    test('markShowCompleted then canShow: blocks via same CD', () async {
      const placement = PlacementType('open');
      final repo = _configRepo(
        placement: placement,
        samePlacementCd: 30,
        applySameCd: true,
      );
      final policy = PlacementPolicy(
        isFullscreen: true,
        applySamePlacementCd: true,
        applyDifferentPlacementCd: false,
        contributesToGlobalCooldown: false,
        showNotReadyToast: false,
        waitForLoadOnShow: false,
        preferHighValueOnShow: false,
      );

      guard.markShowStarted(placement, policy);
      guard.markShowCompleted(placement, policy);

      final result = await guard.canShow(
        placement: placement,
        configRepository: repo,
      );
      expect(result.allowed, isFalse);
      expect(result.reason, AdGuardBlockReason.samePlacementCooldown);
    });

    test('markShowFailed then canShow: is allowed (no CD recorded)', () async {
      const placement = PlacementType('open');
      final repo = _configRepo(
        placement: placement,
        samePlacementCd: 30,
        applySameCd: true,
      );
      final policy = PlacementPolicy(
        isFullscreen: true,
        applySamePlacementCd: true,
        applyDifferentPlacementCd: false,
        contributesToGlobalCooldown: false,
        showNotReadyToast: false,
        waitForLoadOnShow: false,
        preferHighValueOnShow: false,
      );

      guard.markShowStarted(placement, policy);
      guard.markShowFailed(placement, policy);

      final result = await guard.canShow(
        placement: placement,
        configRepository: repo,
      );
      expect(result.allowed, isTrue);
    });
  });
}
