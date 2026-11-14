import Flutter
import UIKit
import UserNotifications
import Photos

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // 将通知响应交给 Flutter 的代理链，支持前台显示和点击后打开当天记录。
    // 此处仅设置代理；系统授权由 Dart 在用户阅读说明并同意后请求。
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // 使用隐式engine的registrar，兼容当前UIScene生命周期。只在用户按下
    // “保存相册”后申请addOnly权限；预览与系统分享不访问照片库。
    let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "DreamExport")!
    FlutterMethodChannel(name: "morpheus/dream_export", binaryMessenger: registrar.messenger())
      .setMethodCallHandler { call, result in
        guard call.method == "saveToAlbum" else {
          result(FlutterMethodNotImplemented)
          return
        }
        guard let args = call.arguments as? [String: Any],
              let path = args["path"] as? String,
              FileManager.default.fileExists(atPath: path) else {
          result(FlutterError(code: "saveFailed", message: "Missing export file", details: nil))
          return
        }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
          guard status == .authorized || status == .limited else {
            DispatchQueue.main.async {
              result(FlutterError(code: "permissionDenied", message: nil, details: nil))
            }
            return
          }
          // Photos异步完成后才回Dart成功；不把提交请求当作照片已经落盘。
          PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: URL(fileURLWithPath: path))
          }) { success, _ in
            DispatchQueue.main.async {
              if success { result(nil) }
              else { result(FlutterError(code: "saveFailed", message: nil, details: nil)) }
            }
          }
        }
      }
  }
}
