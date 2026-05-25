import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class NativeAdView extends StatelessWidget {
  const NativeAdView({super.key, required this.ad, this.height = 280});

  /// 原始广告对象（AdMob NativeAd 或其他平台的广告对象）
  final Object ad;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (ad is NativeAd) {
      return SizedBox(
        height: height,
        child: AdWidget(ad: ad as NativeAd),
      );
    }

    // 如果将来有其他平台，在这里继续扩展 else if (ad is MaxNativeAd) ...

    return const SizedBox.shrink();
  }
}

class DualNativeAdView extends StatelessWidget {
  const DualNativeAdView({
    super.key,
    required this.ads,
    this.height = 600,
    this.direction = Axis.vertical,
    this.spacing = 0,
  });

  final List<Object> ads;
  final double height;
  final Axis direction;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    if (ads.length < 2) {
      return const SizedBox.shrink();
    }

    final children = [
      Expanded(child: NativeAdView(ad: ads[0])),
      if (spacing > 0) SizedBox(width: spacing, height: spacing),
      Expanded(child: NativeAdView(ad: ads[1])),
    ];

    return SizedBox(
      height: height,
      child: direction == Axis.horizontal
          ? Row(children: children)
          : Column(children: children),
    );
  }
}
