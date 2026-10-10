import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/id/id_generator.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/features/csv_import/domain/csv_import_failures.dart';
import 'package:money_app/features/csv_import/domain/parse_csv_import.dart';
import 'package:money_app/features/csv_import/domain/plan_csv_import.dart';
import 'package:money_app/features/csv_import/presentation/csv_import_texts.dart';
import 'package:money_app/features/recurring/domain/recurring_payment.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

import '../../../support/fixed_clock.dart';

// Разбор и план строк регулярных платежей (шаг 6.16, ADR 0011, п. 10).

final _clock = FixedClock(DateTime(2026, 10, 7, 9, 30));
const _pid = '0199aaaa-bbbb-7ccc-8ddd-eeeeeeeeeec1';

/// Заранее посчитанные UUID v5 (пространство `csvImportFingerprintNamespace`)
/// для строки платежа `_line()` и строки операции без id.
const _pinnedRecurringId = 'c880a605-ecd1-57f4-8b28-e9d1a3208ad4';
const _pinnedOperationId = '393eda0c-61c4-5122-8d41-418b8b43fae8';

const _header =
    'Дата;Тип;Сумма;Валюта;Категория;Подкатегория;Комментарий;'
    'ID операции;Повтор;Каждые;До;Напоминать';

final class _SeqIds implements IdGenerator {
  var _n = 0;

  @override
  String newId() => 'new-${++_n}';
}

CsvImportParsed _parsed(String rows) {
  final result = parseCsvImport(
    utf8.encode('$_header\r\n$rows\r\n'),
    clock: _clock,
  );
  expect(result, isA<CsvImportParsed>());
  return result as CsvImportParsed;
}

List<CsvRowError> _errors(String rows) => _parsed(rows).errors;

/// Строка платежа с заменой отдельных ячеек.
String _line({
  String date = '05.11.2026',
  String type = 'Регулярный расход',
  String amount = '-650,00',
  String category = 'Связь',
  String title = 'Интернет',
  String id = '',
  String repeat = 'месяц',
  String every = '1',
  String until = '',
  String remind = 'да',
}) =>
    '$date;$type;$amount;;$category;;$title;$id;$repeat;$every;$until;$remind';

CsvImportPlan _plan(
  CsvImportParsed parsed, {
  Set<String> live = const {},
  Set<String> deleted = const {},
}) => planCsvImport(
  rows: parsed.rows,
  recurring: parsed.recurring,
  categories: const [],
  liveTransactionIds: const {},
  deletedTransactionIds: const {},
  liveRecurringIds: live,
  deletedRecurringIds: deleted,
  today: DateOnly(2026, 10, 7),
  ids: _SeqIds(),
  isKnownIconKey: (_) => true,
);

void main() {
  group('разбор', () {
    test('платёж в будущем читается; поля попали в строку', () {
      final result = _parsed(
        _line(id: _pid, every: '2', until: '31.12.2026', remind: 'НЕТ'),
      );
      expect(result.errors, isEmpty);
      expect(result.rows, isEmpty);
      final p = result.recurring.single;
      expect(p.row.day, DateOnly(2026, 11, 5));
      expect(p.row.type, TransactionType.expense);
      expect(p.row.amount.minorUnits, 65000);
      expect(p.row.note, 'Интернет');
      expect(p.row.transactionId, _pid);
      expect(p.unit, RepeatUnit.month);
      expect(p.every, 2);
      expect(p.endsOn, DateOnly(2026, 12, 31));
      expect(p.remind, isFalse);
    });

    test(
      'пустые Каждые, До, Напоминать: 1, бессрочно, да; доход и регистр',
      () {
        final p = _parsed(
          _line(
            type: 'регулярный ДОХОД',
            amount: '90000',
            repeat: 'Год',
            every: '',
            remind: '',
          ),
        ).recurring.single;
        expect(p.row.type, TransactionType.income);
        expect(p.unit, RepeatUnit.year);
        expect(p.every, 1);
        expect(p.endsOn, isNull);
        expect(p.remind, isTrue);
      },
    );

    test('будущая дата у обычной операции по-прежнему ошибка', () {
      final errors = _errors(
        _line(type: 'Расход', repeat: '', every: '', remind: ''),
      );
      expect(errors.single, isA<CsvFutureDate>());
    });

    test('Повтор неизвестен или пуст', () {
      expect(_errors(_line(repeat: 'день')).single, isA<CsvInvalidRepeat>());
      expect(_errors(_line(repeat: '')).single, isA<CsvInvalidRepeat>());
    });

    test('Каждые вне 1-99 или не число', () {
      for (final every in ['0', '100', '-1', '2,5', 'x']) {
        expect(
          _errors(_line(every: every)).single,
          isA<CsvEveryOutOfRange>(),
          reason: every,
        );
      }
      expect(_parsed(_line(every: '99')).errors, isEmpty);
    });

    test('До раньше Даты, не дата; до того же дня - можно', () {
      expect(
        _errors(_line(until: '04.11.2026')).single,
        isA<CsvUntilBeforeStart>(),
      );
      expect(
        _errors(_line(until: '32.01.2027')).single,
        isA<CsvInvalidUntil>(),
      );
      expect(_parsed(_line(until: '05.11.2026')).errors, isEmpty);
    });

    test('Напоминать не да/нет', () {
      expect(_errors(_line(remind: 'ага')).single, isA<CsvInvalidRemind>());
    });

    test('нет категории и сумма 0', () {
      expect(_errors(_line(category: '')).single, isA<CsvEmptyCategory>());
      expect(_errors(_line(amount: '0')).single, isA<CsvRecurringZeroAmount>());
      expect(
        _errors(_line(amount: '0,00', type: 'Регулярный доход')).single,
        isA<CsvRecurringZeroAmount>(),
      );
    });

    test('название: пустое и длиннее 40; доход с минусом', () {
      expect(_errors(_line(title: '')).single, isA<CsvRecurringTitle>());
      expect(_errors(_line(title: 'я' * 41)).single, isA<CsvRecurringTitle>());
      expect(_parsed(_line(title: 'я' * 40)).errors, isEmpty);
      expect(
        _errors(_line(type: 'Регулярный доход', amount: '-5')).single,
        isA<CsvNegativeIncome>(),
      );
    });

    test('повторяющийся ID платежа - ошибка', () {
      final errors = _errors('${_line(id: _pid)}\r\n${_line(id: _pid)}');
      expect(errors.single, isA<CsvDuplicateTransactionId>());
    });

    test('Повтор, Каждые, До, Напоминать у обычной операции - ошибка', () {
      const ok = '04.10.2026;Расход;5;;Кафе;;;;';
      final cases = {
        'Повтор': '$okмесяц;;;',
        'Каждые': '$ok;2;;',
        'До': '$ok;;31.12.2026;',
        'Напоминать': '$ok;;;да',
      };
      for (final entry in cases.entries) {
        final error = _errors(entry.value).single;
        expect(error, isA<CsvRecurringColumnOnOperation>(), reason: entry.key);
        expect((error as CsvRecurringColumnOnOperation).column, entry.key);
      }
      // Переводы и остатки тоже.
      expect(
        _errors('04.10.2026;Начальный остаток;5;;;;;;месяц;;;')
            .whereType<CsvRecurringColumnOnOperation>(),
        hasLength(1),
      );
    });

    test('пустые четыре колонки у операции ошибки не дают', () {
      expect(_errors('04.10.2026;Расход;5;;Кафе;;;;;;;'), isEmpty);
    });

    test('все ошибки строки собираются', () {
      final errors = _errors(
        _line(repeat: 'x', every: '0', until: 'y', remind: 'z', category: ''),
      );
      expect(errors, hasLength(5));
    });
  });

  group('план', () {
    test(
      'платёж готов к записи: категория создаётся, trackedThrough = день',
      () {
        final plan = _plan(
          _parsed(_line(id: _pid, until: '31.12.2026', remind: 'нет')),
        );
        expect(plan.errors, isEmpty);
        expect(plan.categoriesToCreate.single.name, 'Связь');
        final p = plan.recurring.single;
        expect(p.id, _pid);
        expect(p.title, 'Интернет');
        expect(p.amount.minorUnits, 65000);
        expect(p.categoryId, plan.categoriesToCreate.single.id);
        expect(p.startsOn, DateOnly(2026, 11, 5));
        expect(p.endsOn, DateOnly(2026, 12, 31));
        expect(p.remind, isFalse);
        expect(p.trackedThrough, DateOnly(2026, 10, 7));
        expect(plan.skippedExisting, 0);
      },
    );

    test('платёж, который уже есть, - «уже есть»; удалённый - «удалён»', () {
      final parsed = _parsed(_line(id: _pid.toUpperCase()));
      final existing = _plan(parsed, live: {_pid});
      expect(existing.recurring, isEmpty);
      expect(existing.skippedExisting, 1);
      final removed = _plan(parsed, deleted: {_pid});
      expect(removed.recurring, isEmpty);
      expect(removed.skippedDeleted, 1);
    });

    test('без id: отпечаток стабилен, повторная загрузка - «уже есть»', () {
      final parsed = _parsed(_line());
      final first = _plan(parsed).recurring.single;
      final again = _plan(parsed, live: {first.id});
      expect(again.recurring, isEmpty);
      expect(again.skippedExisting, 1);
      // Тот же результат при другом порядке и числе других строк.
      final other = _parsed('${_line(title: 'Свет')}\r\n${_line()}');
      expect(_plan(other).recurring.last.id, first.id);
    });

    test('отпечатки строк без id закреплены конкретными значениями: смена '
        'формата отпечатка задвоила бы данные при повторной загрузке', () {
      final payment = _plan(_parsed(_line())).recurring.single;
      expect(payment.id, _pinnedRecurringId);
      final operation = _plan(
        _parsed('05.10.2026;Расход;-650,00;;Связь;;Интернет;;;;;'),
      ).transactions.single;
      expect(operation.id, _pinnedOperationId);
    });

    test('отпечаток зависит от повтора, даты и названия; одинаковые строки '
        'получают разные id', () {
      final ids = {
        for (final row in [
          _line(),
          _line(every: '2'),
          _line(repeat: 'год'),
          _line(date: '06.11.2026'),
          _line(title: 'Свет'),
          _line(),
        ])
          _plan(_parsed(row)).recurring.single.id,
      };
      expect(ids, hasLength(5));
      final twins = _plan(_parsed('${_line()}\r\n${_line()}')).recurring;
      expect(twins[0].id, isNot(twins[1].id));
    });

    test('счёт другой валюты - ошибка плана, как у операций', () {
      final parsed = parseCsvImport(
        utf8.encode(
          'Дата;Тип;Сумма;Валюта;Категория;Счёт;Комментарий;Повтор\r\n'
          '05.11.2026;Регулярный расход;-5;USD;Связь;Карта;Х;месяц\r\n',
        ),
        clock: _clock,
      ) as CsvImportParsed;
      expect(parsed.errors, isEmpty);
      final plan = _plan(parsed);
      expect(plan.errors.single, isA<CsvAccountCurrencyMismatch>());
      expect(plan.recurring, isEmpty);
    });
  });

  group('тексты', () {
    test('каждая новая ошибка даёт понятный текст', () {
      expect(
        csvRowErrorMessage(const CsvInvalidRepeat(2, 'день')),
        'Строка 2: повтор «день» — нужно «неделя», «месяц» или «год»',
      );
      expect(
        csvRowErrorMessage(const CsvInvalidRepeat(2, '')),
        'Строка 2: не указан повтор — нужно «неделя», «месяц» или «год»',
      );
      expect(
        csvRowErrorMessage(const CsvEveryOutOfRange(2, '100')),
        'Строка 2: в колонке «Каждые» «100» — нужно целое число от 1 до 99 '
        'или пусто',
      );
      expect(
        csvRowErrorMessage(const CsvInvalidUntil(2, '32.01.2027')),
        'Строка 2: в колонке «До» «32.01.2027» — нужна настоящая дата в виде '
        'ДД.ММ.ГГГГ или пусто',
      );
      expect(
        csvRowErrorMessage(const CsvUntilBeforeStart(2, '04.11.2026')),
        'Строка 2: в колонке «До» «04.11.2026» — это раньше даты первого '
        'платежа',
      );
      expect(
        csvRowErrorMessage(const CsvInvalidRemind(2, 'ага')),
        'Строка 2: в колонке «Напоминать» «ага» — нужно «да», «нет» или пусто',
      );
      expect(
        csvRowErrorMessage(const CsvRecurringZeroAmount(2, '0')),
        'Строка 2: сумма «0» — у регулярного платежа нужна сумма больше нуля',
      );
      expect(
        csvRowErrorMessage(const CsvRecurringTitle(2, '')),
        'Строка 2: у регулярного платежа не указано название '
        '(колонка «Комментарий»)',
      );
      expect(
        csvRowErrorMessage(const CsvRecurringTitle(2, 'я')),
        'Строка 2: название регулярного платежа длиннее 40 символов',
      );
      expect(
        csvRowErrorMessage(
          const CsvRecurringColumnOnOperation(2, 'месяц', 'Повтор'),
        ),
        'Строка 2: в колонке «Повтор» стоит «месяц» — у обычной операции она '
        'должна быть пустой. Похоже, колонки съехали',
      );
    });
  });
}
