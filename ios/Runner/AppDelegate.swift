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
    let factory = HomeNativeAdFactory()
    homeNativeAdFactory = factory
    let fullScreenFactory = FullScreenNativeAdFactory()
    fullScreenNativeAdFactory = fullScreenFactory
    FLTGoogleMobileAdsPlugin.registerNativeAdFactory(
      self,
      factoryId: "homeListTile",
      nativeAdFactory: factory
    )
    FLTGoogleMobileAdsPlugin.registerNativeAdFactory(
      self,
      factoryId: "fullScreenNative",
      nativeAdFactory: fullScreenFactory
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
  }
}
