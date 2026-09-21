import 'package:flutter_test/flutter_test.dart';

/// Даёт настоящей базе в памяти дочитать запрос и дожидается кадров.
///
/// Тап по плитке категории теперь сначала читает подкатегории (`.first` от
/// потока drift), а такое ожидание в фейковом времени виджет-теста само не
/// завершается: нужен глоток настоящего времени (`runAsync`).
Future<void> settleDatabase(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await tester.pumpAndSettle();
}
