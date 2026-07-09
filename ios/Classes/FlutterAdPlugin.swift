import Flutter
import google_mobile_ads
import UIKit

public final class FlutterAdPlugin: NSObject, FlutterPlugin {
  private static let fullScreenNativeAdFactory = FullScreenNativeAdFactory()
  private static var didRegisterFullScreenNativeFactory = false
  private static var registerAttempts = 0
  private static let maxRegisterAttempts = 5

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = FlutterAdPlugin()
    registrar.addApplicationDelegate(instance)
    DispatchQueue.main.async {
      registerFullScreenNativeFactoryIfPossible()
    }
  }

  public func applicationWillTerminate(_ application: UIApplication) {
    Self.unregisterFullScreenNativeFactoryIfPossible()
  }

  private static func registerFullScreenNativeFactoryIfPossible() {
    guard !didRegisterFullScreenNativeFactory,
      let registry = UIApplication.shared.delegate as? FlutterPluginRegistry
    else {
      return
    }

    guard registry.valuePublished(byPlugin: "FLTGoogleMobileAdsPlugin") != nil else {
      retryRegisterFullScreenNativeFactory()
      return
    }

    didRegisterFullScreenNativeFactory = FLTGoogleMobileAdsPlugin.registerNativeAdFactory(
      registry,
      factoryId: "fullScreenNative",
      nativeAdFactory: fullScreenNativeAdFactory
    )
    if didRegisterFullScreenNativeFactory {
      registerAttempts = 0
    }
  }

  private static func retryRegisterFullScreenNativeFactory() {
    guard registerAttempts < maxRegisterAttempts else {
      return
    }

    registerAttempts += 1
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
      registerFullScreenNativeFactoryIfPossible()
    }
  }

  private static func unregisterFullScreenNativeFactoryIfPossible() {
    guard didRegisterFullScreenNativeFactory,
      let registry = UIApplication.shared.delegate as? FlutterPluginRegistry
    else {
      return
    }

    FLTGoogleMobileAdsPlugin.unregisterNativeAdFactory(
      registry,
      factoryId: "fullScreenNative"
    )
    didRegisterFullScreenNativeFactory = false
  }
}
