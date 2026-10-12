import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/features/recurring/data/reminders_channel.dart';
import 'package:money_app/features/recurring/domain/reminder_plan.dart';

void main() {
  late List<(String, Object?)> calls;
  late Object? answer;
  late RemindersChannel channel;

  setUp(() {
    calls = [];
    answer = null;
    channel = RemindersChannel(
      invoke: (method, [arguments]) async {
        calls.add((method, arguments));
        return answer;
      },
    );
  });

  test('requestPermission: true только на true', () async {
    answer = true;
    expect(await channel.requestPermission(), isTrue);
    answer = false;
    expect(await channel.requestPermission(), isFalse);
    answer = null;
    expect(await channel.requestPermission(), isFalse);
    expect(calls.first, ('requestPermission', null));
  });

  test('permissionStatus: три значения, остальное - notDetermined', () async {
    answer = 'granted';
    expect(await channel.permissionStatus(), ReminderPermission.granted);
    answer = 'denied';
    expect(await channel.permissionStatus(), ReminderPermission.denied);
    answer = 'notDetermined';
    expect(await channel.permissionStatus(), ReminderPermission.notDetermined);
    answer = null;
    expect(await channel.permissionStatus(), ReminderPermission.notDetermined);
    expect(calls.first.$1, 'permissionStatus');
  });

  test('replaceAll передаёт список словарей', () async {
    const item = ReminderItem(
      id: 0,
      year: 2026,
      month: 10,
      day: 20,
      hour: 10,
      minute: 0,
      title: 'Платёж сегодня: Интернет',
      body: 'Расход',
    );
    await channel.replaceAll([item]);
    await channel.replaceAll(const []);

    expect(calls[0].$1, 'replaceAll');
    expect(calls[0].$2, [
      {
        'id': 0,
        'year': 2026,
        'month': 10,
        'day': 20,
        'hour': 10,
        'minute': 0,
        'title': 'Платёж сегодня: Интернет',
        'body': 'Расход',
      },
    ]);
    expect(calls[1].$2, isEmpty);
  });

  test(
    'takeOpenRequest: true только на true; без реализации - false',
    () async {
      answer = true;
      expect(await channel.takeOpenRequest(), isTrue);
      answer = false;
      expect(await channel.takeOpenRequest(), isFalse);
      answer = null;
      expect(await channel.takeOpenRequest(), isFalse);
      expect(calls.first, ('takeOpenRequest', null));

      final missing = RemindersChannel(
        invoke: (method, [arguments]) async =>
            throw MissingPluginException(method),
      );
      expect(await missing.takeOpenRequest(), isFalse);
    },
  );

  test('openSettings: вызывает метод без аргументов', () async {
    await channel.openSettings();
    expect(calls.single, ('openSettings', null));
  });

  test('listenOpenDue: зовёт только на openDue; null снимает', () async {
    Future<void> Function(String method)? handler;
    final listening = RemindersChannel(
      invoke: (method, [arguments]) async => null,
      setHandler: (h) => handler = h,
    );
    var opened = 0;
    listening.listenOpenDue(() => opened++);
    await handler!('other');
    expect(opened, 0);
    await handler!('openDue');
    expect(opened, 1);
    listening.listenOpenDue(null);
    expect(handler, isNull);
  });
}
