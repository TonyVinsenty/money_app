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
  ]) {
    if (!source.contains(needle)) errors.add('Не найдено $needle');
  }
  return errors;
}

void main() {
  final swift = File('ios/Runner/AppDelegate.swift').readAsStringSync();

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

  test('сторож замечает отсутствие показа при открытом приложении', () {
    expect(
      checkRemindersSwift(swift.replaceAll('willPresent', 'willShow')),
      isNotEmpty,
    );
  });
}
