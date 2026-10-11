import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var appleIntelligenceBridge: AppleIntelligenceBridge?
  private var receiptOcrBridge: ReceiptOcrBridge?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    appleIntelligenceBridge = AppleIntelligenceBridge(
      messenger: engineBridge.applicationRegistrar.messenger()
    )
    receiptOcrBridge = ReceiptOcrBridge(
      messenger: engineBridge.applicationRegistrar.messenger()
    )
  }
}
