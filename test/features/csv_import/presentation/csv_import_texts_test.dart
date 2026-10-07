import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/money/parse_amount.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/csv_import/domain/csv_import_failures.dart';
import 'package:money_app/features/csv_import/presentation/csv_import_texts.dart';

Category _top(String id, String name, CategoryKind kind) => Category.topLevel(
  id: id,
  kind: kind,
  name: name,
  iconKey: 'more_horiz',
  sortOrder: 0,
);

Category _sub(String id, Category parent, String name) =>
    Category.subcategoryOf(
      id: id,
      parent: parent,
      name: name,
      iconKey: 'more_horiz',
      sortOrder: 0,
    );

void main() {
  group('csvRowErrorMessage', () {
    test('номер строки и значение в ёлочках', () {
      expect(
        csvRowErrorMessage(
          const CsvInvalidAmount(15, '12.3.4', AmountParseFailure.notANumber),
        ),
        'Строка 15: сумма «12.3.4» — не число',
      );
    });

    test('пустое значение — «не указана»', () {
      expect(
        csvRowErrorMessage(const CsvInvalidDate(3, '  ')),
        'Строка 3: не указана дата',
      );
      expect(
        csvRowErrorMessage(const CsvInvalidType(4, '')),
        'Строка 4: не указан тип',
      );
      expect(
        csvRowErrorMessage(
          const CsvInvalidAmount(5, '', AmountParseFailure.empty),
        ),
        'Строка 5: не указана сумма',
      );
    });

    test('длинное значение обрезается до 30 символов с «…»', () {
      final long = 'я' * 31;
      expect(
        csvRowErrorMessage(CsvInvalidType(2, long)),
        'Строка 2: тип «${'я' * 30}…» — нужен «Расход» или «Доход»',
      );
      expect(
        csvRowErrorMessage(CsvInvalidType(2, 'я' * 30)),
        'Строка 2: тип «${'я' * 30}» — нужен «Расход» или «Доход»',
      );
    });

    test('лимиты длины берутся из правил', () {
      expect(
        csvRowErrorMessage(const CsvCategoryTooLong(7, 'x')),
        'Строка 7: категория длиннее 40 символов',
      );
      expect(
        csvRowErrorMessage(const CsvNoteTooLong(8, 'x')),
        'Строка 8: комментарий длиннее 200 символов',
      );
    });

    test('колонка ID называется как в файле', () {
      expect(
        csvRowErrorMessage(
          const CsvInvalidId(9, 'abc', CsvIdColumn.subcategory),
        ),
        'Строка 9: в колонке «ID подкатегории» не ID. Очистите эту ячейку',
      );
    });

    test('лишние ячейки: подсказка зависит от разделителя', () {
      expect(
        csvRowErrorMessage(const CsvExtraCells(5, ',')),
        'Строка 5: ячеек больше, чем колонок. Похоже, сумма или текст с '
        'запятой без кавычек: нужно "350,50"',
      );
      expect(
        csvRowErrorMessage(const CsvExtraCells(5, ';')),
        'Строка 5: ячеек больше, чем колонок. Похоже, в тексте есть «;» '
        'без кавычек вокруг ячейки',
      );
    });

    test('каждая ошибка строки и каждая причина суммы дают текст', () {
      final errors = <CsvRowError>[
        const CsvInvalidDate(2, '31.02.2026'),
        const CsvFutureDate(2, '01.01.2099'),
        const CsvInvalidType(2, 'Покупка'),
        for (final f in AmountParseFailure.values)
          CsvInvalidAmount(2, '1,234', f),
        const CsvNegativeIncome(2, '-5'),
        const CsvUnsupportedCurrency(2, 'USD'),
        const CsvEmptyCategory(2, ''),
        const CsvCategoryTooLong(2, 'x'),
        const CsvSubcategoryTooLong(2, 'x'),
        const CsvNoteTooLong(2, 'x'),
        for (final c in CsvIdColumn.values) CsvInvalidId(2, 'x', c),
        const CsvDuplicateTransactionId(2, 'x'),
        const CsvCategoryKindMismatch(2, 'x'),
        const CsvCategoryIdIsSubcategory(2, 'x'),
        const CsvSubcategoryWrongParent(2, 'x'),
        const CsvExtraCells(2, ','),
        const CsvExtraCells(2, ';'),
      ];
      final texts = errors.map(csvRowErrorMessage).toList();
      for (final text in texts) {
        expect(text, startsWith('Строка 2: '));
        expect(text, isNot(contains('null')));
      }
      // Разные ошибки не сливаются в один и тот же текст.
      expect(texts.toSet(), hasLength(texts.length));
    });
  });

  group('csvFileFailureMessage', () {
    test('одна и несколько недостающих колонок', () {
      expect(
        csvFileFailureMessage(const CsvMissingColumns(['Дата'])),
        startsWith('Нет обязательной колонки «Дата». '),
      );
      expect(
        csvFileFailureMessage(const CsvMissingColumns(['Дата', 'Сумма'])),
        startsWith('Нет обязательных колонок: «Дата», «Сумма». '),
      );
    });

    test('не UTF-8 — подсказка про пункт Excel', () {
      expect(
        csvFileFailureMessage(const CsvNotUtf8()),
        contains('«CSV UTF-8 (разделитель - запятая)»'),
      );
    });

    test('у каждой ошибки файла свой текст', () {
      final texts = [
        const CsvNotUtf8(),
        const CsvMalformed('x'),
        const CsvEmptyFile(),
        const CsvMissingColumns(['Тип']),
        const CsvDuplicateColumn('Сумма'),
      ].map(csvFileFailureMessage).toSet();
      expect(texts, hasLength(5));
    });
  });

  group('счётчики', () {
    test('«Будет добавлена/добавлены/добавлено» по числу', () {
      expect(csvImportWillAdd(1), 'Будет добавлена 1 операция');
      expect(csvImportWillAdd(3), 'Будут добавлены 3 операции');
      expect(csvImportWillAdd(11), 'Будет добавлено 11 операций');
      expect(csvImportWillAdd(21), 'Будет добавлена 21 операция');
    });

    test('разряды разделяет неразрывный пробел', () {
      final nbsp = String.fromCharCode(0x00A0);
      expect(csvImportWillAdd(1234), 'Будут добавлены 1${nbsp}234 операции');
      expect(csvImportMoreErrors(1500), '… и ещё 1${nbsp}500');
    });
  });

  group('csvImportNewCategoryLines', () {
    final food = _top('food', 'Еда', CategoryKind.expense);

    test('сначала расходы, потом доходы; родитель из базы или из новых', () {
      final pharmacy = _top('ph', 'Аптека', CategoryKind.expense);
      final cashback = _top('cb', 'Кэшбэк', CategoryKind.income);
      final cafe = _sub('cafe', food, 'Кафе');
      final drugs = _sub('dr', pharmacy, 'Лекарства');
      expect(
        csvImportNewCategoryLines([cashback, pharmacy, cafe, drugs], [food]),
        ['Расходы: Аптека, Еда → Кафе, Аптека → Лекарства', 'Доходы: Кэшбэк'],
      );
    });

    test('нет новых категорий — пустой список', () {
      expect(csvImportNewCategoryLines(const [], [food]), isEmpty);
    });
  });
}
