import Flutter
import google_mobile_ads
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var homeNativeAdFactory: HomeNativeAdFactory?
  private var fullScreenNativeAdFactory: FullScreenNativeAdFactory?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    let homeFactory = HomeNativeAdFactory()
    homeNativeAdFactory = homeFactory
    FLTGoogleMobileAdsPlugin.registerNativeAdFactory(
      self,
      factoryId: "homeListTile",
      nativeAdFactory: homeFactory
    )
    let factory = FullScreenNativeAdFactory()
    fullScreenNativeAdFactory = factory
    let registered = FLTGoogleMobileAdsPlugin.registerNativeAdFactory(
      self,
      factoryId: "fullScreenNative",
      nativeAdFactory: factory
    )
    NSLog(
      "[flutter_ad_plugin] fullScreenNative factory %@",
      registered ? "registered" : "already registered"
    )
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func applicationWillTerminate(_ application: UIApplication) {
    FLTGoogleMobileAdsPlugin.unregisterNativeAdFactory(
      self,
      factoryId: "homeListTile"
    )
    FLTGoogleMobileAdsPlugin.unregisterNativeAdFactory(
      self,
      factoryId: "fullScreenNative"
    )
    homeNativeAdFactory = nil
    fullScreenNativeAdFactory = nil
  }
}
