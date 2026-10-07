import 'package:money_app/features/csv_import/domain/parse_csv_import.dart';
import 'package:money_app/features/csv_import/domain/plan_csv_import.dart';

/// Подготовка и запись импорта CSV (ADR 0009, п. 6). Экран знает только этот
/// интерфейс; реализация поверх базы — `CsvImportWriter`, в тестах — фейк.
abstract interface class CsvImportStore {
  /// Строит план по разобранным строкам. В базу ничего не пишет.
  Future<CsvImportPlan> prepare(List<ParsedCsvRow> rows);

  /// Пишет план целиком или ничего (одна транзакция).
  Future<void> write(CsvImportPlan plan);
}
