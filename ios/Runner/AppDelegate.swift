import Flutter
import UIKit
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  // Канал, по которому Dart просит отправить файл через системное «Поделиться».
  // Имя канала и метод должны совпадать с lib/features/settings/presentation/share_csv_file.dart.
  private let shareChannelName = "com.tonyvinsenty.zuno/share"

  // Канал выбора файла для импорта CSV (ADR 0009, п. 5). Имя, метод и коды ошибок —
  // как в lib/features/csv_import/presentation/pick_csv_file.dart и в MainActivity.kt.
  private let filesChannelName = "com.tonyvinsenty.zuno/files"

  // Ожидающий ответ Dart, пока открыто окно выбора (второй вызов получит "busy").
  // Делегат окна — сам AppDelegate: он живёт всё время работы приложения.
  private var pendingPick: FlutterResult?

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

    let files = FlutterMethodChannel(
      name: filesChannelName,
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    files.setMethodCallHandler { call, result in
      self.handlePick(call, result: result)
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

    guard let presenter = topViewController() else {
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

  // Активная сцена -> её главное окно -> самый верхний показанный экран.
  private func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
    let window = scene?.windows.first(where: { $0.isKeyWindow }) ?? scene?.windows.first
    var top = window?.rootViewController
    while let presented = top?.presentedViewController {
      top = presented
    }
    return top
  }

  private func handlePick(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "pickCsvFile" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard pendingPick == nil else {
      result(FlutterError(code: "busy", message: "Окно выбора файла уже открыто", details: nil))
      return
    }
    guard let presenter = topViewController() else {
      result(FlutterError(code: "no_picker", message: "Нет экрана для показа окна", details: nil))
      return
    }

    // asCopy: iOS сама копирует файл в каталог приложения, особые права доступа не нужны.
    let picker = UIDocumentPickerViewController(
      forOpeningContentTypes: [.commaSeparatedText, .plainText],
      asCopy: true
    )
    picker.delegate = self
    picker.allowsMultipleSelection = false
    // Закрыть окно можно только кнопкой «Отменить»: о смахивании вниз делегат
    // может не узнать, и тогда ответ в Dart не пришёл бы никогда.
    picker.isModalInPresentation = true
    pendingPick = result
    presenter.present(picker, animated: true)
  }

  // Копию от iOS переносим в tmp/csv_import/import.csv, прежние копии удаляем (как на Android).
  fileprivate func moveToImportDir(_ url: URL) throws -> String {
    let manager = FileManager.default
    let dir = manager.temporaryDirectory.appendingPathComponent("csv_import", isDirectory: true)
    if manager.fileExists(atPath: dir.path) {
      try manager.removeItem(at: dir)
    }
    try manager.createDirectory(at: dir, withIntermediateDirectories: true)
    let target = dir.appendingPathComponent("import.csv")
    try manager.moveItem(at: url, to: target)
    return target.path
  }

  fileprivate func takePendingPick() -> FlutterResult? {
    let result = pendingPick
    pendingPick = nil
    return result
  }
}

extension AppDelegate: UIDocumentPickerDelegate {
  func documentPicker(
    _ controller: UIDocumentPickerViewController,
    didPickDocumentsAt urls: [URL]
  ) {
    guard let result = takePendingPick() else { return }
    guard let url = urls.first else {
      result(nil)
      return
    }
    do {
      result(try moveToImportDir(url))
    } catch {
      result(FlutterError(code: "copy_failed", message: error.localizedDescription, details: nil))
    }
  }

  // Отмена не ошибка: Dart получает null.
  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    takePendingPick()?(nil)
  }
}
