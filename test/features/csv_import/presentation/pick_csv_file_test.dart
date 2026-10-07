import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/features/csv_import/presentation/pick_csv_file.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void mock(Future<Object?> Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(filesChannel, handler);
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(filesChannel, null);
  });

  test('возвращает путь к копии и зовёт нужный метод', () async {
    String? method;
    mock((call) async {
      method = call.method;
      return '/cache/csv_import/a.csv';
    });
    expect(await pickCsvFile(), '/cache/csv_import/a.csv');
    expect(method, pickCsvFileMethod);
  });

  test('отмена — null', () async {
    mock((call) async => null);
    expect(await pickCsvFile(), isNull);
  });

  for (final code in [pickErrorBusy, pickErrorNoPicker, pickErrorCopyFailed]) {
    test('ошибка платформы $code — PickFileException', () async {
      mock((call) async => throw PlatformException(code: code, message: 'm'));
      await expectLater(
        pickCsvFile(),
        throwsA(
          isA<PickFileException>()
              .having((e) => e.code, 'code', code)
              .having((e) => e.details, 'details', 'm'),
        ),
      );
    });
  }
}
