// Создаёт тестовый набор `test/fixtures/zuno-test-dataset.csv` (шаг i.16).
//
// Запуск из корня проекта: `dart run tool/make_test_dataset.dart`.
//
// Набор выдуманный, без личных данных: июль и сентябрь 2026 с операциями,
// август пустой. Формат — тот же, что у экспорта (ADR 0006), поэтому файл
// грузится через «Загрузить из CSV» как своя выгрузка. Случайность —
// собственный генератор с фиксированным зерном: при повторном запуске файл
// получается тот же байт в байт (это проверяет тест набора).
//
// Категория «Хобби» встречается только в июле: в тесте её заранее создают
// с id из файла и отправляют в архив, так операции попадают в архивную
// категорию. На эмуляторе её отправляют в архив руками после загрузки.

import 'dart:io';

import 'package:money_app/core/csv/csv_codec.dart';
import 'package:money_app/core/money/currency.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/export/domain/transactions_export.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

import '../test/support/csv_v1_compat.dart';

/// Куда пишется набор (путь от корня проекта).
const String testDatasetPath = 'test/fixtures/zuno-test-dataset.csv';

/// Зерно случайности. Поменяете — поменяются файл и итоги в тесте.
const int testDatasetSeed = 20261007;

/// id категории «Хобби», которая в тесте лежит в архиве.
const String testDatasetHobbyId = 'c0de0000-0000-7000-8000-000000000020';

/// id подкатегорий «Хобби» (создаются в тесте вместе с ней).
const String testDatasetHobbyPaintsId = 'c0de0000-0000-7000-8000-000000000021';
const String testDatasetHobbyBrushesId = 'c0de0000-0000-7000-8000-000000000022';

void main() {
  File(testDatasetPath).writeAsStringSync(buildTestDataset(), flush: true);
  stdout.writeln('Записано: $testDatasetPath');
}

/// Текст набора (с BOM и `\r\n`, как у экспорта).
String buildTestDataset() {
  final data = _Dataset(_Random(testDatasetSeed));
  data.month(2026, 7, withHobby: true);
  // Август намеренно пустой.
  data.month(2026, 9, withHobby: false);
  // Набор остаётся в формате v1 (11 колонок): это сторож совместимости
  // (ADR 0010, п. 10). Берём из строк v2 только колонки v1.
  final rows = buildTransactionsCsvRows(
    transactions: data.transactions,
    categories: data.categories,
    accounts: const [],
  );
  final keep = [
    for (final h in csvV1Headers) transactionsExportHeaders.indexOf(h),
  ];
  return encodeCsv([
    for (final row in rows) [for (final i in keep) row[i]],
  ]);
}

/// Генератор xorshift32: своя реализация, чтобы файл не зависел от того,
/// как `dart:math` устроит `Random` в другой версии Dart.
final class _Random {
  _Random(int seed) : _state = seed & 0xFFFFFFFF;

  int _state;

  /// Число от 0 до [max] - 1.
  int next(int max) {
    var x = _state;
    x ^= (x << 13) & 0xFFFFFFFF;
    x ^= x >> 17;
    x ^= (x << 5) & 0xFFFFFFFF;
    _state = x;
    return x % max;
  }

  /// Число от [min] до [max] включительно.
  int between(int min, int max) => min + next(max - min + 1);

  /// «Да» с вероятностью [percent] процентов.
  bool chance(int percent) => next(100) < percent;

  T pick<T>(List<T> items) => items[next(items.length)];

  String hex(int digits) {
    final buffer = StringBuffer();
    for (var i = 0; i < digits; i++) {
      buffer.write(next(16).toRadixString(16));
    }
    return buffer.toString();
  }
}

/// Комментарии без личных данных; среди них — с `;`, кавычками и переносом
/// строки. Ключ — имя подкатегории, а у операции без подкатегории — имя
/// категории.
const Map<String, List<String>> _notes = {
  'Продукты': ['на неделю', 'список:\nхлеб, молоко, яйца'],
  'Овощи': ['по акции', 'на рынке'],
  'Обед': ['с коллегами', 'бизнес-ланч'],
  'Такси': ['в аэропорт; ночью', 'опаздывал'],
  'Кино': ['фильм "Дюна"', 'с друзьями'],
  'Подарки': ['на день рождения', 'на новоселье'],
  'Прочее': ['наличными'],
  'Краски': ['для этюдов'],
  'Подработка': ['перевод за проект'],
};

final class _Dataset {
  _Dataset(this._random) {
    _food = _top(1, CategoryKind.expense, 'Продукты');
    _foodVeg = _sub(2, _food, 'Овощи');
    _foodMilk = _sub(3, _food, 'Молочное');
    _foodBread = _sub(4, _food, 'Хлеб');
    _cafe = _top(5, CategoryKind.expense, 'Кафе');
    _cafeCoffee = _sub(6, _cafe, 'Кофе');
    _cafeLunch = _sub(7, _cafe, 'Обед');
    _transport = _top(8, CategoryKind.expense, 'Транспорт');
    _metro = _sub(9, _transport, 'Метро');
    _taxi = _sub(10, _transport, 'Такси');
    _home = _top(11, CategoryKind.expense, 'Дом');
    _utilities = _sub(12, _home, 'Коммуналка');
    _health = _top(13, CategoryKind.expense, 'Здоровье');
    _clothes = _top(14, CategoryKind.expense, 'Одежда');
    _fun = _top(15, CategoryKind.expense, 'Развлечения');
    _cinema = _sub(16, _fun, 'Кино');
    _phone = _top(17, CategoryKind.expense, 'Связь');
    _gifts = _top(18, CategoryKind.expense, 'Подарки');
    _otherExpense = _top(19, CategoryKind.expense, 'Прочее');
    _hobby = Category.topLevel(
      id: testDatasetHobbyId,
      kind: CategoryKind.expense,
      name: 'Хобби',
      iconKey: 'palette',
      sortOrder: _sortOrder++,
    );
    categories.add(_hobby);
    _hobbyPaints = _subWithId(testDatasetHobbyPaintsId, _hobby, 'Краски');
    _hobbyBrushes = _subWithId(testDatasetHobbyBrushesId, _hobby, 'Кисти');
    _salary = _top(30, CategoryKind.income, 'Зарплата');
    _salaryAdvance = _sub(31, _salary, 'Аванс');
    _salaryRest = _sub(32, _salary, 'Расчёт');
    _sideJob = _top(33, CategoryKind.income, 'Подработка');
    _present = _top(34, CategoryKind.income, 'Подарок');
    _otherIncome = _top(35, CategoryKind.income, 'Прочее');
  }

  final _Random _random;
  final List<Category> categories = [];
  final List<Transaction> transactions = [];

  late final Category _food, _foodVeg, _foodMilk, _foodBread;
  late final Category _cafe, _cafeCoffee, _cafeLunch;
  late final Category _transport, _metro, _taxi;
  late final Category _home, _utilities, _health, _clothes;
  late final Category _fun, _cinema, _phone, _gifts, _otherExpense;
  late final Category _hobby, _hobbyPaints, _hobbyBrushes;
  late final Category _salary, _salaryAdvance, _salaryRest;
  late final Category _sideJob, _present, _otherIncome;

  int _sortOrder = 0;

  Category _top(int n, CategoryKind kind, String name) {
    final category = Category.topLevel(
      id: _categoryId(n),
      kind: kind,
      name: name,
      iconKey: 'more_horiz',
      sortOrder: _sortOrder++,
    );
    categories.add(category);
    return category;
  }

  Category _sub(int n, Category parent, String name) =>
      _subWithId(_categoryId(n), parent, name);

  Category _subWithId(String id, Category parent, String name) {
    final category = Category.subcategoryOf(
      id: id,
      parent: parent,
      name: name,
      iconKey: 'more_horiz',
      sortOrder: _sortOrder++,
    );
    categories.add(category);
    return category;
  }

  static String _categoryId(int n) =>
      'c0de0000-0000-7000-8000-${n.toString().padLeft(12, '0')}';

  /// Операции одного месяца: доходы по расписанию, расходы — каждый день.
  void month(int year, int month, {required bool withHobby}) {
    final days = DateTime.utc(year, month + 1, 0).day;
    for (var d = 1; d <= days; d++) {
      final day = DateOnly(year, month, d);
      final weekend = DateTime.utc(year, month, d).weekday >= DateTime.saturday;
      if (d == 5) _income(day, _salary, _salaryAdvance, 4000000, 0);
      if (d == 20) _income(day, _salary, _salaryRest, 5500000, 5000);
      if (_random.chance(8)) {
        _income(day, _sideJob, null, _random.between(3000, 15000) * 100, 0);
      }
      if (d == 28) {
        _income(day, _otherIncome, null, _random.between(30000, 90000), 0);
      }
      if (month == 7 && d == 12) _income(day, _present, null, 500000, 0);

      for (var i = _random.between(1, 2); i > 0; i--) {
        final sub = _random.pick([_foodVeg, _foodMilk, _foodBread, null]);
        _expense(day, _food, sub, _random.between(15000, 350000));
      }
      if (_random.chance(70)) {
        _expense(day, _cafe, _cafeCoffee, _random.between(18, 42) * 1000);
      }
      if (!weekend && _random.chance(50)) {
        _expense(day, _cafe, _cafeLunch, _random.between(35, 90) * 1000);
      }
      if (!weekend) {
        _expense(day, _transport, _metro, 6800);
        _expense(day, _transport, _metro, 6800);
      }
      if (_random.chance(12)) {
        _expense(day, _transport, _taxi, _random.between(300, 1500) * 100);
      }
      if (d == 10) _expense(day, _home, _utilities, 648350);
      if (_random.chance(6)) {
        _expense(day, _home, null, _random.between(50000, 900000));
      }
      if (_random.chance(6)) {
        _expense(day, _health, null, _random.between(30000, 450000));
      }
      if (_random.chance(5)) {
        _expense(day, _clothes, null, _random.between(1500, 12000) * 100);
      }
      if (weekend && _random.chance(40)) {
        _expense(day, _fun, _cinema, _random.between(35, 120) * 1000);
      }
      if (d == 15) _expense(day, _phone, null, 65000);
      if (_random.chance(4)) {
        _expense(day, _gifts, null, _random.between(1000, 8000) * 100);
      }
      if (_random.chance(5)) {
        _expense(day, _otherExpense, null, _random.between(5000, 300000));
      }
      if (withHobby && weekend) {
        final sub = _random.pick([_hobbyPaints, _hobbyBrushes, null]);
        _expense(day, _hobby, sub, _random.between(20000, 250000));
      }
    }
    if (month == 9) {
      // Нулевой расход: бесплатное мероприятие.
      _expense(
        DateOnly(year, month, 13),
        _fun,
        null,
        0,
        note: 'бесплатный вход',
      );
    }
  }

  void _income(
    DateOnly day,
    Category category,
    Category? sub,
    int baseMinor,
    int spreadRubles,
  ) {
    final extra = spreadRubles == 0
        ? 0
        : _random.between(0, spreadRubles) * 100;
    _add(TransactionType.income, day, category, sub, baseMinor + extra);
  }

  void _expense(
    DateOnly day,
    Category category,
    Category? sub,
    int minor, {
    String? note,
  }) {
    _add(TransactionType.expense, day, category, sub, minor, note: note);
  }

  void _add(
    TransactionType type,
    DateOnly day,
    Category category,
    Category? sub,
    int minor, {
    String? note,
  }) {
    // Время 06:00-18:59 UTC: в часовых поясах от UTC-6 до UTC+5 это тот же
    // местный день, поэтому момент из файла принимается как есть.
    final at = DateTime.utc(
      day.year,
      day.month,
      day.day,
      _random.between(6, 18),
      _random.between(0, 59),
    );
    final choices = _notes[sub?.name ?? category.name];
    final comment =
        note ??
        (choices != null && _random.chance(25) ? _random.pick(choices) : null);
    transactions.add(
      Transaction.create(
        id: _transactionId(at),
        type: type,
        amount: Money.fromMinor(minor, rubCurrencyCode),
        occurredOn: day,
        occurredAt: at,
        category: category,
        subcategory: sub,
        note: comment,
      ),
    );
  }

  /// id в виде UUID v7: первые 12 цифр — момент операции в миллисекундах.
  String _transactionId(DateTime at) {
    final time = at.millisecondsSinceEpoch.toRadixString(16).padLeft(12, '0');
    final variant = (8 + _random.next(4)).toRadixString(16);
    return '${time.substring(0, 8)}-${time.substring(8)}-7${_random.hex(3)}-'
        '$variant${_random.hex(3)}-${_random.hex(12)}';
  }
}
