package com.tonyvinsenty.zuno

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

// Показывает уведомление о регулярном платеже, когда срабатывает будильник
// (ставится в MainActivity.kt, канал reminders, ADR 0011, п. 11). Приёмник не
// экспортируется (см. AndroidManifest.xml).
class ReminderReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        ensureReminderChannel(context)

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, reminderChannelId)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }
        builder
            .setSmallIcon(context.applicationInfo.icon)
            .setContentTitle(intent.getStringExtra("title") ?: "")
            .setContentText(intent.getStringExtra("body") ?: "")
            .setAutoCancel(true)

        // Тап открывает приложение.
        context.packageManager.getLaunchIntentForPackage(context.packageName)?.let { launch ->
            builder.setContentIntent(
                PendingIntent.getActivity(
                    context,
                    0,
                    launch,
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
                ),
            )
        }
        manager.notify(intent.getIntExtra("id", 0), builder.build())
    }
}

// Идентификатор канала уведомлений «Регулярные платежи».
const val reminderChannelId = "recurring_payments"

// Канал нужен с Android 8 (API 26); ниже его нет, и ничего делать не надо.
fun ensureReminderChannel(context: Context) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
    val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    manager.createNotificationChannel(
        NotificationChannel(
            reminderChannelId,
            "Регулярные платежи",
            NotificationManager.IMPORTANCE_DEFAULT,
        ),
    )
}
