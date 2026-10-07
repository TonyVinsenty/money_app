package com.tonyvinsenty.zuno

import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException

class MainActivity : FlutterActivity() {

    // Канал, по которому Dart просит отправить файл через системное «Поделиться».
    // Имя канала и метод должны совпадать с lib/features/settings/presentation/share_csv_file.dart
    // и с ios/Runner/AppDelegate.swift.
    private val shareChannelName = "com.tonyvinsenty.zuno/share"

    // Authority нашего FileProvider (см. AndroidManifest.xml). Отдельный от share_plus.
    private val fileProviderAuthority = "com.tonyvinsenty.zuno.fileprovider"

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
                    val chooser = Intent.createChooser(send, null).apply {
                        // Запуск из applicationContext без ожидания результата: выбранное
                        // приложение откроется в своей задаче, а не внутри окна Zuno.
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    applicationContext.startActivity(chooser)
                    result.success(null)
                } catch (e: Exception) {
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
