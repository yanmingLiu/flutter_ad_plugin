import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../../core/ad_enums.dart';
import '../ad_sdk_initializer.dart';

class AdmobSdkInitializer implements AdSourceSdkInitializer {
  @override
  AdSource get source => AdSource.admob;

  @override
  Future<void> init() async {
    await MobileAds.instance.initialize();
  }
}
