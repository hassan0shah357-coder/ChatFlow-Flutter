import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    
    // Setup screen wake control channel for proximity sensor
    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
    let screenWakeChannel = FlutterMethodChannel(name: "screen_wake_control",
                                                  binaryMessenger: controller.binaryMessenger)
    
    screenWakeChannel.setMethodCallHandler({
      [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
      guard let self = self else { return }
      
      switch call.method {
      case "acquireProximityWakeLock":
        self.enableProximityMonitoring()
        result(nil)
      case "releaseProximityWakeLock":
        self.disableProximityMonitoring()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    })
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  private func enableProximityMonitoring() {
    let device = UIDevice.current
    device.isProximityMonitoringEnabled = true
    print("📱 iOS: Proximity monitoring enabled")
  }
  
  private func disableProximityMonitoring() {
    let device = UIDevice.current
    device.isProximityMonitoringEnabled = false
    print("📱 iOS: Proximity monitoring disabled")
  }
}
