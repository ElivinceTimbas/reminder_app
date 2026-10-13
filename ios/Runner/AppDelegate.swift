import AVFoundation
import Flutter
import UIKit
import flutter_local_notifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, AVAudioPlayerDelegate {
  private var previewPlayer: AVAudioPlayer?
  private var previewResult: FlutterResult?
  private var previewSessionActive = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func applicationDidEnterBackground(_ application: UIApplication) {
    stopPreview()
    super.applicationDidEnterBackground(application)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    FlutterLocalNotificationsPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let channel = FlutterMethodChannel(
      name: "com.deimos.reminder_app/sounds",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      switch call.method {
      case "preview":
        self.stopPreview()
        guard let path = call.arguments as? String else {
          result(FlutterError(code: "bad_args", message: "Expected a sound path", details: nil))
          return
        }
        do {
          let session = AVAudioSession.sharedInstance()
          // Release the recorder's active input route before preparing playback.
          try session.setActive(false, options: .notifyOthersOnDeactivation)
          try session.setCategory(.playback, mode: .default)
          try session.setActive(true)
          self.previewSessionActive = true
          let player = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
          player.delegate = self
          self.previewPlayer = player
          self.previewResult = result
          if !player.prepareToPlay() || !player.play() {
            self.stopPreview(error: FlutterError(code: "playback_failed", message: "This sound could not be played", details: nil))
          }
        } catch {
          self.stopPreview()
          result(FlutterError(code: "playback_failed", message: error.localizedDescription, details: nil))
        }
      case "stopPreview":
        self.stopPreview()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func stopPreview(error: FlutterError? = nil) {
    previewPlayer?.delegate = nil
    previewPlayer?.stop()
    previewPlayer = nil
    let pending = previewResult
    previewResult = nil
    pending?(error)
    if previewSessionActive {
      try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
      previewSessionActive = false
    }
  }

  func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    guard player === previewPlayer else { return }
    stopPreview(error: flag ? nil : FlutterError(code: "playback_failed", message: "Sound playback failed", details: nil))
  }

  func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
    guard player === previewPlayer else { return }
    stopPreview(error: FlutterError(code: "playback_failed", message: error?.localizedDescription ?? "Unsupported sound", details: nil))
  }
}
