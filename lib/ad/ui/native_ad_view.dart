import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class NativeAdView extends StatelessWidget {
  const NativeAdView({
    super.key,
    required this.ad,
    this.height = 280,
  });

  final NativeAd ad;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: AdWidget(ad: ad),
    );
  }
}
