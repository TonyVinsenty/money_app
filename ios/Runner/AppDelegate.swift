import Flutter
import UIKit
import UniformTypeIdentifiers
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  // Канал, по которому Dart просит отправить файл через системное «Поделиться».
  // Имя канала и метод должны совпадать с lib/features/settings/presentation/share_csv_file.dart.
  private let shareChannelName = "com.tonyvinsenty.zuno/share"

  // Канал выбора файла для импорта CSV (ADR 0009, п. 5). Имя, метод и коды ошибок —
  // как в lib/features/csv_import/presentation/pick_csv_file.dart и в MainActivity.kt.
  private let filesChannelName = "com.tonyvinsenty.zuno/files"

  // Канал напоминаний (ADR 0011, п. 11). Имя, методы и ключи элементов — как в
  // lib/features/recurring/data/reminders_channel.dart и lib/features/recurring/domain/reminder_plan.dart.
  private let remindersChannelName = "com.tonyvinsenty.zuno/reminders"

  // Канал ссылок (шаг 8.0): открыть страницу во внешнем браузере. Имя, метод
  // и ключ — как в lib/features/settings/presentation/open_external_link.dart.
  private let linksChannelName = "com.tonyvinsenty.zuno/links"

  // Канал иконки (ADR 0014, п. 2 и 3). Имя, методы и ключ — как в
  // lib/features/settings/data/app_icon_channel.dart и в MainActivity.kt.
  private let appIconChannelName = "com.tonyvinsenty.zuno/app_icon"

  // Иконка по умолчанию — набор AppIcon (имя альтернативной иконки nil).
  private let appIconDefault = "ring"

  // id варианта -> альтернативный набор в Assets.xcassets; те же имена — в
  // ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES (project.pbxproj).
  // Имена не менять никогда (ADR 0014, п. 6).
  private let appIconSets = [
    "ring_blue": "AppIcon-RingBlue",
    "coins": "AppIcon-Coins",
    "wallet": "AppIcon-Wallet",
  ]

  // Ожидающий ответ Dart, пока открыто окно выбора (второй вызов получит "busy").
  // Делегат окна — сам AppDelegate: он живёт всё время работы приложения.
  private var pendingPick: FlutterResult?

  // Был ли тап по нашему уведомлению с прошлого вопроса Dart (takeOpenRequest,
  // ADR 0013, п. 11).
  private var openRequested = false

  // Канал напоминаний, когда движок готов: для вызова openDue.
  private var remindersChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Делегат — до конца запуска: иначе тап, которым приложение запустили,
    // не дойдёт до didReceive. Он же показывает уведомление при открытом
    // приложении (willPresent ниже).
    UNUserNotificationCenter.current().delegate = self
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

    let reminders = FlutterMethodChannel(
      name: remindersChannelName,
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    reminders.setMethodCallHandler { call, result in
      self.handleReminders(call, result: result)
    }
    remindersChannel = reminders

    let links = FlutterMethodChannel(
      name: linksChannelName,
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    links.setMethodCallHandler { call, result in
      self.handleLinks(call, result: result)
    }

    let appIcon = FlutterMethodChannel(
      name: appIconChannelName,
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    appIcon.setMethodCallHandler { call, result in
      self.handleAppIcon(call, result: result)
    }
  }

  // Какая иконка стоит — спрашиваем систему (ADR 0014, п. 1). Окно «Вы
  // изменили значок» показывает сама iOS, убрать его нельзя.
  private func handleAppIcon(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let app = UIApplication.shared
    switch call.method {
    case "supported":
      result(app.supportsAlternateIcons)
    case "current":
      guard let name = app.alternateIconName else {
        result(appIconDefault)
        return
      }
      result(appIconSets.first { $0.value == name }?.key)
    case "set":
      guard let args = call.arguments as? [String: Any],
        let id = args["id"] as? String
      else {
        result(false)
        return
      }
      let name: String?
      if id == appIconDefault {
        name = nil
      } else if let set = appIconSets[id] {
        name = set
      } else {
        result(false)
        return
      }
      if app.alternateIconName == name {
        result(true)
        return
      }
      app.setAlternateIconName(name) { error in
        DispatchQueue.main.async { result(error == nil) }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // Только https: другие схемы канал не открывает.
  private func handleLinks(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "openUrl" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard let args = call.arguments as? [String: Any],
      let text = args["url"] as? String,
      let url = URL(string: text),
      url.scheme == "https"
    else {
      result(false)
      return
    }
    UIApplication.shared.open(url, options: [:]) { opened in result(opened) }
  }

  // Показ уведомления, когда приложение открыто.
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .list, .sound])
  }

  // Тап по уведомлению: запоминаем; если движок уже работает, подсказываем
  // Dart спросить сейчас же. Иначе Dart спросит сам при запуске.
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
      openRequested = true
      remindersChannel?.invokeMethod("openDue", arguments: nil)
    }
    completionHandler()
  }

  private func handleReminders(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let center = UNUserNotificationCenter.current()
    switch call.method {
    case "requestPermission":
      center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
        DispatchQueue.main.async { result(granted) }
      }
    case "permissionStatus":
      center.getNotificationSettings { settings in
        let status: String
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
          status = "granted"
        case .denied:
          status = "denied"
        default:
          status = "notDetermined"
        }
        DispatchQueue.main.async { result(status) }
      }
    // Настройки уведомлений Zuno (ADR 0013, п. 11); до iOS 16 — общая
    // страница приложения в «Настройках».
    case "openSettings":
      let name: String
      if #available(iOS 16.0, *) {
        name = UIApplication.openNotificationSettingsURLString
      } else {
        name = UIApplication.openSettingsURLString
      }
      guard let url = URL(string: name) else {
        result(false)
        return
      }
      UIApplication.shared.open(url, options: [:]) { opened in result(opened) }
    // Ответ сбрасывает флаг: тап обрабатывается ровно один раз.
    case "takeOpenRequest":
      result(openRequested)
      openRequested = false
    case "replaceAll":
      guard let items = call.arguments as? [[String: Any]] else {
        result(FlutterError(code: "bad_args", message: "Не передан список напоминаний", details: nil))
        return
      }
      var requests: [UNNotificationRequest] = []
      for item in items {
        guard let id = item["id"] as? Int,
          let year = item["year"] as? Int,
          let month = item["month"] as? Int,
          let day = item["day"] as? Int,
          let hour = item["hour"] as? Int,
          let minute = item["minute"] as? Int,
          let title = item["title"] as? String,
          let body = item["body"] as? String
        else {
          result(FlutterError(code: "bad_args", message: "Неверный элемент напоминания", details: nil))
          return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        // Местное «настенное» время: календарь и пояс устройства.
        var date = DateComponents()
        date.year = year
        date.month = month
        date.day = day
        date.hour = hour
        date.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: false)
        requests.append(UNNotificationRequest(identifier: String(id), content: content, trigger: trigger))
      }
      center.removeAllPendingNotificationRequests()
      let group = DispatchGroup()
      for request in requests {
        group.enter()
        center.add(request) { _ in group.leave() }
      }
      group.notify(queue: .main) { result(nil) }
    default:
      result(FlutterMethodNotImplemented)
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
    // Ответ в Dart уходит ровно один раз: iOS иногда вызывает обработчик повторно.
    var pendingShare: FlutterResult? = result
    share.completionWithItemsHandler = { _, completed, _, error in
      guard let reply = pendingShare else { return }
      pendingShare = nil
      if let error = error {
        reply(FlutterError(code: "share_failed", message: error.localizedDescription, details: nil))
      } else {
        // true: файл отправлен или сохранён; false: пользователь закрыл окно.
        reply(completed)
      }
    }
    presenter.present(share, animated: true)
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
