import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/features/settings/presentation/share_csv_file.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  // Записываем все вызовы, которые Dart отправил в нативный канал.
  late List<MethodCall> calls;

  setUp(() {
    calls = [];
    messenger.setMockMethodCallHandler(shareChannel, (call) async {
      calls.add(call);
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(shareChannel, null);
  });

  test('шлёт в канал метод shareCsvFile с путём к файлу', () async {
    await shareCsvFile('/cache/zuno-export.csv');

    expect(calls, hasLength(1));
    expect(calls.single.method, 'shareCsvFile');
    expect(calls.single.arguments, {'path': '/cache/zuno-export.csv'});
  });

  void replyWith(Object? value) {
    messenger.setMockMethodCallHandler(shareChannel, (call) async => value);
  }

  test('канал вернул true: файл отправлен', () async {
    replyWith(true);
    expect(await shareCsvFile('/cache/zuno-export.csv'), isTrue);
  });

  test('канал вернул false: отмена', () async {
    replyWith(false);
    expect(await shareCsvFile('/cache/zuno-export.csv'), isFalse);
  });

  test('канал вернул null (старая сборка): считаем отправкой', () async {
    replyWith(null);
    expect(await shareCsvFile('/cache/zuno-export.csv'), isTrue);
  });

  test('ошибка на стороне Android приходит как PlatformException', () async {
    messenger.setMockMethodCallHandler(shareChannel, (call) async {
      throw PlatformException(code: 'share_failed', message: 'нет приложения');
    });

    await expectLater(
      shareCsvFile('/cache/zuno-export.csv'),
      throwsA(
        isA<PlatformException>().having((e) => e.code, 'code', 'share_failed'),
      ),
    );
  });
}
