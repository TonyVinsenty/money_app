import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  // Канал, по которому Dart просит отправить файл через системное «Поделиться».
  // Имя канала и метод должны совпадать с lib/features/settings/presentation/share_csv_file.dart.
  private let shareChannelName = "com.tonyvinsenty.zuno/share"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let channel = FlutterMethodChannel(
      name: shareChannelName,
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    // AppDelegate живёт всё время работы приложения, поэтому слабая ссылка не нужна,
    // а с ней при self == nil Dart не получил бы ответа.
    channel.setMethodCallHandler { call, result in
      self.handleShare(call, result: result)
    }
  }

  private func handleShare(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "shareCsvFile" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard let args = call.arguments as? [String: Any], let path = args["path"] as? String else {
      result(FlutterError(code: "bad_args", message: "Не передан путь к файлу", details: nil))
      return
    }
    guard FileManager.default.fileExists(atPath: path) else {
      result(FlutterError(code: "file_not_found", message: "Файл не найден: \(path)", details: nil))
      return
    }

    // Активная сцена -> её главное окно -> самый верхний показанный экран.
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
    let window = scene?.windows.first(where: { $0.isKeyWindow }) ?? scene?.windows.first
    var top = window?.rootViewController
    while let presented = top?.presentedViewController {
      top = presented
    }
    guard let presenter = top else {
      result(FlutterError(code: "share_failed", message: "Нет экрана для показа окна", details: nil))
      return
    }

    let share = UIActivityViewController(
      activityItems: [URL(fileURLWithPath: path)],
      applicationActivities: nil
    )
    // На iPad окно «Поделиться» без точки привязки роняет приложение:
    // привязываем к центру экрана, без стрелки.
    if let popover = share.popoverPresentationController {
      let view: UIView = presenter.view
      popover.sourceView = view
      popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
      popover.permittedArrowDirections = []
    }
    presenter.present(share, animated: true)
    // Результат (выбранное приложение или отмену) не ждём, как и на Android.
    result(nil)
  }
}
