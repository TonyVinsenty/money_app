import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/features/settings/data/app_icon_channel.dart';
import 'package:money_app/features/settings/domain/app_icon_choice.dart';

void main() {
  group('AppIconChoice', () {
    test('стабильные id и вариант по умолчанию', () {
      expect(AppIconChoice.values.map((c) => c.id), [
        'ring',
        'ring_blue',
        'coins',
        'wallet',
      ]);
      expect(AppIconChoice.defaultChoice, AppIconChoice.ring);
    });

    test('fromId: известный id — вариант, иначе null', () {
      expect(AppIconChoice.fromId('coins'), AppIconChoice.coins);
      expect(AppIconChoice.fromId('nope'), isNull);
      expect(AppIconChoice.fromId(null), isNull);
    });
  });

  group('AppIconChannel', () {
    late List<(String, Object?)> calls;

    AppIconChannel channel(Object? Function(String method) answer) =>
        AppIconChannel(
          invoke: (method, [arguments]) async {
            calls.add((method, arguments));
            return answer(method);
          },
        );

    setUp(() => calls = []);

    test('current: ответ натива — вариант', () async {
      expect(await channel((_) => 'wallet').current(), AppIconChoice.wallet);
      expect(calls.single.$1, appIconCurrentMethod);
    });

    test('current: неизвестный id или не строка — null', () async {
      expect(await channel((_) => 'other').current(), isNull);
      expect(await channel((_) => 42).current(), isNull);
      expect(await channel((_) => null).current(), isNull);
    });

    test('set: передаёт id, true — успех', () async {
      expect(await channel((_) => true).set(AppIconChoice.ringBlue), isTrue);
      expect(calls.single.$1, appIconSetMethod);
      expect(calls.single.$2, {appIconIdArg: 'ring_blue'});
    });

    test('set: false или null — отказ', () async {
      expect(await channel((_) => false).set(AppIconChoice.coins), isFalse);
      expect(await channel((_) => null).set(AppIconChoice.coins), isFalse);
    });

    test('supported: только true — поддерживается', () async {
      expect(await channel((_) => true).supported(), isTrue);
      expect(await channel((_) => false).supported(), isFalse);
      expect(await channel((_) => null).supported(), isFalse);
      expect(calls.first.$1, appIconSupportedMethod);
    });

    test('ошибка натива — отказ без исключения', () async {
      final failing = AppIconChannel(
        invoke: (method, [arguments]) async =>
            throw PlatformException(code: 'failed'),
      );
      expect(await failing.supported(), isFalse);
      expect(await failing.current(), isNull);
      expect(await failing.set(AppIconChoice.wallet), isFalse);
    });

    test('нет канала (платформа без реализации) — не поддерживается', () async {
      final missing = AppIconChannel(
        invoke: (method, [arguments]) async => throw MissingPluginException(),
      );
      expect(await missing.supported(), isFalse);
      expect(await missing.current(), isNull);
      expect(await missing.set(AppIconChoice.wallet), isFalse);
    });

    testWidgets('настоящий канал без натива в тестах — не поддерживается', (
      tester,
    ) async {
      // Ответ платформы приходит вне поддельного времени виджет-теста.
      final supported = await tester.runAsync(
        () => const AppIconChannel().supported(),
      );
      expect(supported, isFalse);
    });
  });
}
