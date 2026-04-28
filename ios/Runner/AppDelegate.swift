import Flutter
import google_mobile_ads
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var homeNativeAdFactory: HomeNativeAdFactory?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    let factory = HomeNativeAdFactory()
    homeNativeAdFactory = factory
    FLTGoogleMobileAdsPlugin.registerNativeAdFactory(
      self,
      factoryId: "homeListTile",
      nativeAdFactory: factory
    )
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func applicationWillTerminate(_ application: UIApplication) {
    FLTGoogleMobileAdsPlugin.unregisterNativeAdFactory(
      self,
      factoryId: "homeListTile"
    )
  }
}
