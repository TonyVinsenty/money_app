package com.tonyvinsenty.zuno

import android.content.ClipData
import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {

    // Канал, по которому Dart просит отправить файл через системное «Поделиться».
    // Имя канала и метод должны совпадать с lib/features/settings/presentation/share_csv_file.dart.
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
    }
}
