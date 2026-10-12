// Сторож канала напоминаний (шаг 6.24, ADR 0011, п. 11): имя канала, методов и
// ключей элемента в Dart и Swift совпадают. Kotlin добавится в шаге 6.25:
// достаточно прочитать MainActivity.kt и вызвать checkRemindersCommon.
// Нативный код на Windows не собирается, поэтому проверяем текстом.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/features/recurring/data/reminders_channel.dart';
import 'package:money_app/features/recurring/domain/reminder_plan.dart';

List<String> checkRemindersCommon(String source) {
  final errors = <String>[];
  final keys = const ReminderItem(
    id: 0,
    year: 2026,
    month: 1,
    day: 1,
    hour: 0,
    minute: 0,
    title: '',
    body: '',
  ).toMap().keys;
  for (final needle in [
    '"$remindersChannelName"',
    '"$remindersRequestPermissionMethod"',
    '"$remindersPermissionStatusMethod"',
    '"$remindersReplaceAllMethod"',
    for (final key in keys) '"$key"',
    for (final status in ReminderPermission.values) '"${status.name}"',
  ]) {
    if (!source.contains(needle)) errors.add('Не найдено $needle');
  }
  return errors;
}

List<String> checkRemindersSwift(String source) {
  final errors = checkRemindersCommon(source);
  final start = source.indexOf('func didInitializeImplicitFlutterEngine');
  final end = start < 0 ? -1 : source.indexOf('func ', start + 5);
  final body = start < 0 ? '' : source.substring(start, end);
  if (!body.contains('name: remindersChannelName')) {
    errors.add('Канал не создаётся в didInitializeImplicitFlutterEngine');
  }
  for (final needle in [
    'removeAllPendingNotificationRequests',
    'UNCalendarNotificationTrigger',
    'repeats: false',
    'willPresent',
    '[.banner, .list, .sound]',
    // Тап по уведомлению (ADR 0013, п. 11).
    '"$remindersTakeOpenRequestMethod"',
    'invokeMethod("$remindersOpenDueMethod"',
    'didReceive response: UNNotificationResponse',
    'UNNotificationDefaultActionIdentifier',
  ]) {
    if (!source.contains(needle)) errors.add('Не найдено $needle');
  }
  // Делегат уведомлений - до конца запуска, иначе тап, которым запустили
  // приложение, теряется.
  final launch = source.indexOf('didFinishLaunchingWithOptions');
  final launchEnd = launch < 0 ? -1 : source.indexOf('func ', launch);
  if (launch < 0 ||
      !source
          .substring(launch, launchEnd < 0 ? source.length : launchEnd)
          .contains('UNUserNotificationCenter.current().delegate = self')) {
    errors.add('Делегат уведомлений не назначен в didFinishLaunching');
  }
  return errors;
}

List<String> checkRemindersKotlin(String kotlin, String manifest) {
  final errors = checkRemindersCommon(kotlin);
  for (final needle in [
    'setAndAllowWhileIdle',
    'FLAG_IMMUTABLE',
    'ReminderReceiver',
    'areNotificationsEnabled',
    // Тап по уведомлению (ADR 0013, п. 11): метка в запуске, флаг в
    // onCreate и onNewIntent, ответ и обратный вызов.
    '"$remindersTakeOpenRequestMethod"',
    'invokeMethod("$remindersOpenDueMethod"',
    '"zuno.open"',
    '"due"',
    'override fun onNewIntent',
    'putExtra(openExtra, openDueValue)',
  ]) {
    if (!kotlin.contains(needle)) errors.add('Не найдено $needle');
  }
  if (!manifest.contains('android.permission.POST_NOTIFICATIONS')) {
    errors.add('В манифесте нет POST_NOTIFICATIONS');
  }
  if (manifest.contains('SCHEDULE_EXACT_ALARM')) {
    errors.add('Точные будильники не нужны (ADR 0011)');
  }
  final receiver = RegExp(r'<receiver[^>]*ReminderReceiver[^>]*>')
      .firstMatch(manifest)
      ?.group(0);
  if (receiver == null || !receiver.contains('android:exported="false"')) {
    errors.add('Приёмник ReminderReceiver должен быть exported="false"');
  }
  return errors;
}

void main() {
  final swift = File('ios/Runner/AppDelegate.swift').readAsStringSync();
  const androidMain = 'android/app/src/main';
  final kotlin =
      File('$androidMain/kotlin/com/tonyvinsenty/zuno/MainActivity.kt')
          .readAsStringSync() +
      File('$androidMain/kotlin/com/tonyvinsenty/zuno/ReminderReceiver.kt')
          .readAsStringSync();
  final manifest = File('$androidMain/AndroidManifest.xml').readAsStringSync();

  test('Kotlin и манифест: канал, методы, ключи, неточные будильники', () {
    expect(checkRemindersKotlin(kotlin, manifest), isEmpty);
  });

  test('сторож замечает экспортируемый приёмник и точные будильники', () {
    expect(
      checkRemindersKotlin(
        kotlin,
        manifest.replaceFirstMapped(
          RegExp(r'(<receiver[^>]*)android:exported="false"'),
          (m) => '${m[1]}android:exported="true"',
        ),
      ),
      isNotEmpty,
    );
    expect(
      checkRemindersKotlin(
        kotlin.replaceAll('setAndAllowWhileIdle', 'setExact'),
        manifest,
      ),
      isNotEmpty,
    );
  });

  test('сторож замечает потерю тапа по уведомлению в Kotlin', () {
    for (final broken in [
      kotlin.replaceAll('"takeOpenRequest"', '"takeOpen"'),
      kotlin.replaceAll('"openDue"', '"open"'),
      kotlin.replaceAll('override fun onNewIntent', 'fun onNewIntentOld'),
    ]) {
      expect(checkRemindersKotlin(broken, manifest), isNotEmpty);
    }
  });

  test('AppDelegate.swift: канал, методы, ключи и планирование', () {
    expect(checkRemindersSwift(swift), isEmpty);
  });

  test('сторож замечает другое имя канала, метода и ключа', () {
    expect(
      checkRemindersSwift(swift.replaceAll('zuno/reminders', 'zuno/other')),
      isNotEmpty,
    );
    expect(
      checkRemindersSwift(swift.replaceAll('"replaceAll"', '"replace"')),
      isNotEmpty,
    );
    expect(
      checkRemindersSwift(swift.replaceAll('"minute"', '"min"')),
      isNotEmpty,
    );
  });

  test('сторож замечает потерю тапа по уведомлению в Swift', () {
    for (final broken in [
      swift.replaceAll('"takeOpenRequest"', '"takeOpen"'),
      swift.replaceAll('"openDue"', '"open"'),
      swift.replaceAll('didReceive response', 'didGet response'),
      swift.replaceFirst(
        'UNUserNotificationCenter.current().delegate = self\n    return super',
        'return super',
      ),
    ]) {
      expect(checkRemindersSwift(broken), isNotEmpty);
    }
  });

  test('сторож замечает отсутствие показа при открытом приложении', () {
    expect(
      checkRemindersSwift(swift.replaceAll('willPresent', 'willShow')),
      isNotEmpty,
    );
  });
}
