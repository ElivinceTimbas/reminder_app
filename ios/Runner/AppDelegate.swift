import Flutter
import UIKit
// Required by flutter_local_notifications for the background action isolate.
import flutter_local_notifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Required so notifications are presented while the app is in foreground.
    UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    FlutterLocalNotificationsPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Resolves a notification sound against the app bundle.
    //
    // UNNotificationSound(named:) only ever looks inside the read-only,
    // code-signed bundle, so a sound imported into Documents at runtime can
    // NEVER be an iOS notification sound. Dart cannot ask Bundle.main, so the
    // lookup lives here and returns nil for anything not bundled — the caller
    // then falls back to the system tone instead of passing a name that would
    // silently not play.
    let channel = FlutterMethodChannel(
      name: "com.deimos.reminder_app/sounds",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "bundleSoundNamed" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let name = call.arguments as? String, !name.isEmpty else {
        result(nil)
        return
      }
      let base = (name as NSString).deletingPathExtension
      let ext = (name as NSString).pathExtension
      let url = ext.isEmpty
        ? Bundle.main.url(forResource: base, withExtension: nil)
        : Bundle.main.url(forResource: base, withExtension: ext)
      result(url?.lastPathComponent)
    }
  }
}