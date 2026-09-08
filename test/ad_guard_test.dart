import 'package:flutter_ad_plugin/src/core/ad_config.dart';
import 'package:flutter_ad_plugin/src/core/ad_enums.dart';
import 'package:flutter_ad_plugin/src/core/ad_policy.dart';
import 'package:flutter_ad_plugin/src/engine/ad_guard.dart';
import 'package:flutter_test/flutter_test.dart';

const _fullscreenPolicy = PlacementPolicy(isFullscreen: true);
const _inlinePolicy = PlacementPolicy(isFullscreen: false);

AdConfigRepository _configRepo({
  int adCd = 30,
  PlacementType placement = const PlacementType('open'),
  bool isFullscreen = true,
}) {
  return _StubConfigRepo(
    AdConfig(
      loadTimeoutSeconds: 7,
      adCdSeconds: adCd,
      placements: const {},
      policies: {placement: PlacementPolicy(isFullscreen: isFullscreen)},
    ),
  );
}

class _StubConfigRepo implements AdConfigRepository {
  const _StubConfigRepo(this.config);

  final AdConfig config;

  @override
  Future<AdConfig> getConfig() async => config;
}

void main() {
  late AdDisplayGuard guard;

  setUp(() {
    guard = AdDisplayGuard();
  });

  test('non-fullscreen placement bypasses fullscreen guard', () async {
    const placement = PlacementType('home');
    final result = await guard.canShow(
      placement: placement,
      configRepository: _configRepo(placement: placement, isFullscreen: false),
    );
    expect(result.allowed, isTrue);
  });

  test('fullscreen placements are mutually exclusive', () async {
    const placement = PlacementType('open');
    final repo = _configRepo(placement: placement);
    guard.markShowStarted(placement, _fullscreenPolicy);

    final result = await guard.canShow(
      placement: placement,
      configRepository: repo,
    );
    expect(result.allowed, isFalse);
    expect(result.reason, AdGuardBlockReason.fullscreenShowing);
  });

  test('non-fullscreen show does not acquire fullscreen mutex', () async {
    const placement = PlacementType('open');
    guard.markShowStarted(const PlacementType('home'), _inlinePolicy);

    final result = await guard.canShow(
      placement: placement,
      configRepository: _configRepo(placement: placement),
    );
    expect(result.allowed, isTrue);
  });

  test('completed show blocks the same placement during ad_cd', () async {
    const placement = PlacementType('open');
    guard.markShowCompleted(placement);

    final result = await guard.canShow(
      placement: placement,
      configRepository: _configRepo(placement: placement),
    );
    expect(result.allowed, isFalse);
    expect(result.reason, AdGuardBlockReason.samePlacementCooldown);
    expect(result.relatedPlacement, placement);
    expect(result.retryAfterSeconds, lessThanOrEqualTo(30));
  });

  test('completed show blocks a different placement during ad_cd', () async {
    const first = PlacementType('open');
    const second = PlacementType('behavior');
    guard.markShowCompleted(first);

    final result = await guard.canShow(
      placement: second,
      configRepository: _configRepo(placement: second),
    );
    expect(result.allowed, isFalse);
    expect(result.reason, AdGuardBlockReason.differentPlacementCooldown);
    expect(result.relatedPlacement, first);
  });

  test('ad_cd zero allows the next fullscreen show', () async {
    const first = PlacementType('open');
    const second = PlacementType('behavior');
    guard.markShowCompleted(first);

    final result = await guard.canShow(
      placement: second,
      configRepository: _configRepo(placement: second, adCd: 0),
    );
    expect(result.allowed, isTrue);
  });

  test('completed show clears fullscreen mutex', () async {
    const placement = PlacementType('open');
    final repo = _configRepo(placement: placement, adCd: 0);
    guard.markShowStarted(placement, _fullscreenPolicy);
    guard.markShowCompleted(placement);

    final result = await guard.canShow(
      placement: placement,
      configRepository: repo,
    );
    expect(result.allowed, isTrue);
  });

  test('failed show clears mutex without recording cooldown', () async {
    const placement = PlacementType('open');
    final repo = _configRepo(placement: placement);
    guard.markShowStarted(placement, _fullscreenPolicy);
    guard.markShowFailed(placement, _fullscreenPolicy);

    final result = await guard.canShow(
      placement: placement,
      configRepository: repo,
    );
    expect(result.allowed, isTrue);
  });

  test('resetForTesting clears mutex and cooldown state', () async {
    const placement = PlacementType('open');
    final repo = _configRepo(placement: placement);
    guard.markShowStarted(placement, _fullscreenPolicy);
    guard.markShowCompleted(placement);
    guard.resetForTesting();

    final result = await guard.canShow(
      placement: placement,
      configRepository: repo,
    );
    expect(result.allowed, isTrue);
  });
}
