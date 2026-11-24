import 'package:flutter_ad_admob/flutter_ad_admob.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class _RewardedAd extends Fake implements RewardedAd {
  @override
  OnPaidEventCallback? onPaidEvent;

  @override
  FullScreenContentCallback<RewardedAd>? fullScreenContentCallback;

  @override
  ResponseInfo? get responseInfo => null;

  late OnUserEarnedRewardCallback reward;
  bool disposed = false;

  @override
  Future<void> show({
    required OnUserEarnedRewardCallback onUserEarnedReward,
  }) async {
    reward = onUserEarnedReward;
  }

  @override
  Future<void> dispose() async => disposed = true;
}

void main() {
  test(
    'reward still reaches the caller after the SDK show Future returns',
    () async {
      final ad = _RewardedAd();
      final callbacks = <AdRawCallback>[];
      final result = AdmobRewardedAdapter().show(
        placement: const PlacementType('reward'),
        eventName: 'reward',
        ad: ad,
        onCallback: callbacks.add,
      );

      await Future<void>.delayed(Duration.zero);
      ad.reward(ad, RewardItem(3, 'credits'));
      ad.fullScreenContentCallback!.onAdDismissedFullScreenContent!(ad);

      expect((await result).shown, isTrue);
      expect(ad.disposed, isTrue);
      final reward = callbacks.whereType<AdRewardedCallback>().single;
      expect(reward.ad, same(ad));
      expect(reward.amount, 3);
    },
  );
}
