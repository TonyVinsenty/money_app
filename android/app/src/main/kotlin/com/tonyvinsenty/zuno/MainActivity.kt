package com.tonyvinsenty.zuno

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ActivityNotFoundException
import android.content.BroadcastReceiver
import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.util.Calendar

class MainActivity : FlutterActivity() {

    // Канал, по которому Dart просит отправить файл через системное «Поделиться».
    // Имя канала и метод должны совпадать с lib/features/settings/presentation/share_csv_file.dart
    // и с ios/Runner/AppDelegate.swift.
    private val shareChannelName = "com.tonyvinsenty.zuno/share"

    // Authority нашего FileProvider (см. AndroidManifest.xml). Отдельный от share_plus.
    private val fileProviderAuthority = "com.tonyvinsenty.zuno.fileprovider"

    // Окно «Поделиться» сообщает о выбранном приложении этим широковещательным
    // сообщением (только внутри Zuno). Отправил ли пользователь файл в самом
    // приложении, Android не сообщает: выбор приложения считаем отправкой.
    private val shareChosenAction = "com.tonyvinsenty.zuno.SHARE_CHOSEN"

    // Ожидающий ответ Dart, пока открыто окно «Поделиться».
    private var pendingShare: MethodChannel.Result? = null

    // Окно «Поделиться» закрыло собой Zuno (onPause после открытия окна).
    private var sharePaused = false

    private val mainHandler = Handler(Looper.getMainLooper())

    private val shareChosenReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            finishShare(true)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        ContextCompat.registerReceiver(
            this,
            shareChosenReceiver,
            IntentFilter(shareChosenAction),
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
        // Запуск тапом по уведомлению; после пересоздания окна метка в
        // intent та же, второй раз её не считаем.
        if (savedInstanceState == null && isOpenDue(intent)) openRequested = true
    }

    // Тап по уведомлению, когда Zuno уже открыт или свёрнут (singleTop):
    // запоминаем и подсказываем Dart спросить сейчас же.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (!isOpenDue(intent)) return
        openRequested = true
        remindersChannel?.invokeMethod("openDue", null)
    }

    private fun isOpenDue(intent: Intent?) = intent?.getStringExtra(openExtra) == openDueValue

    // Был ли тап по уведомлению с прошлого вопроса Dart (takeOpenRequest).
    private var openRequested = false

    // Канал напоминаний, пока движок работает: для вызова openDue.
    private var remindersChannel: MethodChannel? = null

    override fun onDestroy() {
        unregisterReceiver(shareChosenReceiver)
        pendingShare = null
        remindersChannel = null
        super.onDestroy()
    }

    override fun onPause() {
        super.onPause()
        if (pendingShare != null) sharePaused = true
    }

    // Вернулись в Zuno, а сообщения о выбранном приложении нет — окно закрыли
    // без выбора. Небольшая пауза — на случай, если сообщение ещё в очереди.
    override fun onResume() {
        super.onResume()
        if (pendingShare != null && sharePaused) {
            mainHandler.postDelayed({ finishShare(false) }, 500)
        }
    }

    // Ответ в Dart уходит ровно один раз.
    private fun finishShare(chosen: Boolean) {
        val result = pendingShare ?: return
        pendingShare = null
        sharePaused = false
        result.success(chosen)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, shareChannelName)
            .setMethodCallHandler { call, result ->
                if (call.method != "shareCsvFile") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }

                val path = call.argument<String>("path")
                if (path == null) {
                    result.error("bad_args", "Не передан путь к файлу", null)
                    return@setMethodCallHandler
                }

                val file = File(path)
                if (!file.exists()) {
                    result.error("file_not_found", "Файл не найден: $path", null)
                    return@setMethodCallHandler
                }

                try {
                    // Даём другому приложению временный доступ на чтение именно этого файла.
                    val uri = FileProvider.getUriForFile(applicationContext, fileProviderAuthority, file)

                    val send = Intent(Intent.ACTION_SEND).apply {
                        type = "text/csv"
                        putExtra(Intent.EXTRA_STREAM, uri)
                        // ClipData нужен, чтобы флаг доступа дошёл до приложения, которое выберут.
                        clipData = ClipData.newRawUri(null, uri)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }
                    // Прежнее окно могло закрыться без ответа: считаем его отменой.
                    finishShare(false)
                    var flags = PendingIntent.FLAG_UPDATE_CURRENT
                    // Система дописывает в сообщение выбранное приложение,
                    // поэтому с Android 12 сообщение должно быть изменяемым.
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        flags = flags or PendingIntent.FLAG_MUTABLE
                    }
                    val chosen = PendingIntent.getBroadcast(
                        applicationContext,
                        0,
                        Intent(shareChosenAction).setPackage(packageName),
                        flags,
                    )
                    val chooser = Intent.createChooser(send, null, chosen.intentSender).apply {
                        // Запуск из applicationContext без ожидания результата: выбранное
                        // приложение откроется в своей задаче, а не внутри окна Zuno.
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    pendingShare = result
                    applicationContext.startActivity(chooser)
                } catch (e: Exception) {
                    pendingShare = null
                    result.error("share_failed", e.message, null)
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, filesChannelName)
            .setMethodCallHandler { call, result ->
                if (call.method != "pickCsvFile") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                if (pendingPick != null) {
                    result.error("busy", "Окно выбора файла уже открыто", null)
                    return@setMethodCallHandler
                }

                val open = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "*/*"
                    putExtra(
                        Intent.EXTRA_MIME_TYPES,
                        arrayOf("text/csv", "text/comma-separated-values", "text/plain"),
                    )
                }
                pendingPick = result
                try {
                    startActivityForResult(open, pickFileRequestCode)
                } catch (e: ActivityNotFoundException) {
                    pendingPick = null
                    result.error("no_picker", e.message, null)
                } catch (e: Exception) {
                    pendingPick = null
                    result.error("copy_failed", e.message, null)
                }
            }

        remindersChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, remindersChannelName)
            .apply { setMethodCallHandler { call, result -> handleReminders(call, result) } }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, linksChannelName)
            .setMethodCallHandler { call, result ->
                if (call.method != "openUrl") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                result.success(openUrl(call.argument<String>("url")))
            }
    }

    // Канал ссылок (шаг 8.0): открыть страницу во внешнем браузере. Имя, метод
    // и ключ — как в lib/features/settings/presentation/open_external_link.dart
    // и в ios/Runner/AppDelegate.swift.
    private val linksChannelName = "com.tonyvinsenty.zuno/links"

    // Только https: другие схемы канал не открывает. Нет браузера — false.
    private fun openUrl(text: String?): Boolean {
        val uri = text?.let(Uri::parse) ?: return false
        if (uri.scheme != "https") return false
        return try {
            startActivity(Intent(Intent.ACTION_VIEW, uri).addCategory(Intent.CATEGORY_BROWSABLE))
            true
        } catch (e: ActivityNotFoundException) {
            false
        }
    }

    // Канал напоминаний (ADR 0011, п. 11): имя, методы и ключи — как в
    // lib/features/recurring/data/reminders_channel.dart, reminder_plan.dart
    // и в ios/Runner/AppDelegate.swift.
    private val remindersChannelName = "com.tonyvinsenty.zuno/reminders"
    private val notificationsRequestCode = 4102
    private val maxReminders = 40
    private val prefs by lazy { getSharedPreferences("reminders", MODE_PRIVATE) }

    // Ожидающий ответ Dart, пока открыт системный запрос разрешения.
    private var pendingPermission: MethodChannel.Result? = null

    // Разрешение на Android 13+ нужно просить отдельно; ниже достаточно, чтобы
    // уведомления не были выключены в настройках системы.
    private fun notificationsGranted(): Boolean {
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (!manager.areNotificationsEnabled()) return false
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
    }

    private fun handleReminders(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "requestPermission" -> {
                ensureReminderChannel(this)
                if (notificationsGranted()) {
                    result.success(true)
                } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && pendingPermission == null) {
                    pendingPermission = result
                    requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), notificationsRequestCode)
                } else {
                    result.success(false)
                }
            }
            // Правило: выдано -> "granted"; не выдано и уже спрашивали (флаг
            // "asked") или уведомления выключены в системе -> "denied"; иначе
            // "notDetermined". Ниже Android 13 спрашивать нечего: "granted"/"denied".
            "permissionStatus" -> {
                val status = when {
                    notificationsGranted() -> "granted"
                    Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU -> "denied"
                    prefs.getBoolean("asked", false) -> "denied"
                    else -> "notDetermined"
                }
                result.success(status)
            }
            "replaceAll" -> {
                val items = call.arguments as? List<*>
                if (items == null) {
                    result.error("bad_args", "Не передан список напоминаний", null)
                    return
                }
                try {
                    scheduleReminders(items)
                    result.success(null)
                } catch (e: Exception) {
                    result.error("schedule_failed", e.message, null)
                }
            }
            "openSettings" -> result.success(openNotificationSettings())
            // Ответ сбрасывает флаг: тап обрабатывается ровно один раз.
            "takeOpenRequest" -> {
                result.success(openRequested)
                openRequested = false
            }
            else -> result.notImplemented()
        }
    }

    // Настройки уведомлений Zuno (ADR 0013, п. 11); если их экрана нет
    // (Android ниже 8 или чужая прошивка) — карточка приложения.
    private fun openNotificationSettings(): Boolean {
        val notifications = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
        } else {
            null
        }
        val details = Intent(
            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.fromParts("package", packageName, null),
        )
        for (intent in listOfNotNull(notifications, details)) {
            try {
                startActivity(intent)
                return true
            } catch (e: ActivityNotFoundException) {
                // Пробуем следующий экран.
            }
        }
        return false
    }

    @Deprecated("FlutterActivity наследует Activity, поэтому ответ окна приходит сюда")
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != notificationsRequestCode) return
        prefs.edit().putBoolean("asked", true).apply()
        val result = pendingPermission ?: return
        pendingPermission = null
        result.success(notificationsGranted())
    }

    // Снимает свои будильники с кодами 0..39 и ставит новые. Время — местное
    // «настенное» по часам и поясу устройства; будильник неточный
    // (setAndAllowWhileIdle), без разрешения на точные.
    private fun scheduleReminders(items: List<*>) {
        val alarms = getSystemService(ALARM_SERVICE) as AlarmManager
        for (code in 0 until maxReminders) {
            val old = PendingIntent.getBroadcast(
                this,
                code,
                Intent(this, ReminderReceiver::class.java),
                PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
            )
            if (old != null) {
                alarms.cancel(old)
                old.cancel()
            }
        }
        val now = System.currentTimeMillis()
        for (raw in items.take(maxReminders)) {
            val item = raw as? Map<*, *> ?: throw IllegalArgumentException("Неверный элемент напоминания")
            fun number(key: String) =
                (item[key] as? Number)?.toInt() ?: throw IllegalArgumentException("Нет поля $key")
            val id = number("id")
            val at = Calendar.getInstance().apply {
                clear()
                set(number("year"), number("month") - 1, number("day"), number("hour"), number("minute"), 0)
            }.timeInMillis
            if (id !in 0 until maxReminders || at <= now) continue
            val intent = Intent(this, ReminderReceiver::class.java).apply {
                putExtra("id", id)
                putExtra("title", item["title"] as? String ?: "")
                putExtra("body", item["body"] as? String ?: "")
            }
            val pending = PendingIntent.getBroadcast(
                this,
                id,
                intent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pending)
        }
    }

    // Канал выбора файла: имя и метод — как в lib/features/csv_import/presentation/pick_csv_file.dart
    // и в ios/Runner/AppDelegate.swift.
    private val filesChannelName = "com.tonyvinsenty.zuno/files"
    private val pickFileRequestCode = 4101

    // Ожидающий ответ Dart, пока открыто окно выбора (второй вызов получит "busy").
    private var pendingPick: MethodChannel.Result? = null

    @Deprecated("FlutterActivity наследует Activity, поэтому ответ окна приходит сюда")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != pickFileRequestCode) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val result = pendingPick ?: return
        pendingPick = null

        val uri = if (resultCode == RESULT_OK) data?.data else null
        if (uri == null) {
            // Отмена не ошибка: Dart получает null.
            result.success(null)
            return
        }

        // Копируем не на главном потоке, а ответ отдаём на главном.
        Thread {
            try {
                val path = copyToCache(uri)
                runOnUiThread { result.success(path) }
            } catch (e: Exception) {
                runOnUiThread { result.error("copy_failed", e.message, null) }
            }
        }.start()
    }

    // Копия выбранного файла в cacheDir/csv_import; прежние копии удаляем.
    private fun copyToCache(uri: Uri): String {
        val dir = File(cacheDir, "csv_import")
        dir.deleteRecursively()
        if (!dir.mkdirs()) throw IOException("Не удалось создать каталог копии")
        val target = File(dir, "import.csv")
        val input = contentResolver.openInputStream(uri)
            ?: throw IOException("Не удалось открыть файл")
        input.use { source ->
            target.outputStream().use { sink -> source.copyTo(sink) }
        }
        return target.absolutePath
    }
}
