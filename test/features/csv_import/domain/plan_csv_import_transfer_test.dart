import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/id/id_generator.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/money/parse_amount.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/csv_import/domain/csv_import_failures.dart';
import 'package:money_app/features/csv_import/domain/parse_csv_import.dart';
import 'package:money_app/features/csv_import/domain/plan_csv_import.dart';
import 'package:money_app/features/csv_import/presentation/csv_import_texts.dart';

// План импорта для строк `Перевод` (шаг 5.25).

final class _SeqIds implements IdGenerator {
  var _n = 0;

  @override
  String newId() => 'new-${++_n}';
}

const _idA = '0199aaaa-bbbb-7ccc-8ddd-eeeeeeeeeea1';
const _idB = '0199aaaa-bbbb-7ccc-8ddd-eeeeeeeeeea2';
const _idC = '0199aaaa-bbbb-7ccc-8ddd-eeeeeeeeeea3';
const _tid = '0199aaaa-bbbb-7ccc-8ddd-eeeeeeeeeeb1';

Account _account(
  String id,
  String name, {
  String currency = 'RUB',
  int digits = 2,
  bool archived = false,
}) {
  final a = Account(
    id: id,
    name: name,
    iconKey: 'other',
    openingBalance: Money.fromMinor(0, currency),
    sortOrder: 0,
    currencyDigits: digits,
  );
  return archived ? a.archived(DateTime.utc(2026, 1, 1)) : a;
}

ParsedTransfer _row({
  String? from,
  String? fromId,
  String? to,
  String? toId,
  int minor = 15000,
  String currency = 'RUB',
  int? customDigits,
  String? id,
  String? note,
}) => ParsedTransfer(
  line: 4,
  day: DateOnly(2026, 10, 3),
  occurredAt: DateTime.utc(2026, 10, 3, 9),
  fromAccountName: from,
  fromAccountId: fromId,
  toAccountName: to,
  toAccountId: toId,
  amount: Money.fromMinor(minor, currency),
  customDigits: customDigits,
  note: note,
  transferId: id,
);

CsvImportPlan _plan(
  List<ParsedTransfer> transfers, {
  List<Account> accounts = const [],
  List<ParsedOpeningBalance> balances = const [],
  Set<String> live = const {},
  Set<String> deleted = const {},
}) => planCsvImport(
  rows: const [],
  categories: const [],
  liveTransactionIds: const {},
  deletedTransactionIds: const {},
  ids: _SeqIds(),
  isKnownIconKey: (_) => true,
  today: DateOnly(2026, 10, 7),
  accounts: accounts,
  openingBalances: balances,
  parsedTransfers: transfers,
  liveTransferIds: live,
  deletedTransferIds: deleted,
);

String _message(CsvImportPlan plan) => csvRowErrorMessage(plan.errors.single);

void main() {
  _rescaleGroup();
  test('счета найдены по имени и по ID: перевод в плане', () {
    final plan = _plan(
      [_row(from: 'карта', toId: _idB, id: _tid, note: 'x')],
      accounts: [_account(_idA, 'Карта'), _account(_idB, 'Наличные')],
    );
    expect(plan.errors, isEmpty);
    final t = plan.transfers.single;
    expect(t.id, _tid);
    expect(t.fromAccountId, _idA);
    expect(t.toAccountId, _idB);
    expect(t.note, 'x');
    expect(plan.accountsToCreate, isEmpty);
  });

  test('неизвестные имена: счета создаются в валюте перевода', () {
    final plan = _plan([
      _row(from: 'Кошелёк', to: 'Биржа', currency: 'BTC', minor: 150000),
    ]);
    expect(plan.errors, isEmpty);
    expect(plan.accountsToCreate.map((a) => a.currency), ['BTC', 'BTC']);
    expect(plan.accountsToCreate.first.currencyDigits, 8);
    expect(plan.transfers.single.toAccountId, plan.accountsToCreate.last.id);
  });

  test('архивный счёт по ID допустим', () {
    final plan = _plan(
      [_row(fromId: _idA, toId: _idB)],
      accounts: [
        _account(_idA, 'Карта', archived: true),
        _account(_idB, 'Наличные'),
      ],
    );
    expect(plan.errors, isEmpty);
    expect(plan.transfers, hasLength(1));
  });

  group('дубли', () {
    test('ID уже есть / удалён: в счётчики пропусков', () {
      final accounts = [_account(_idA, 'Карта'), _account(_idB, 'Наличные')];
      final plan = _plan(
        [
          _row(from: 'Карта', to: 'Наличные', id: _tid),
          _row(from: 'Карта', to: 'Наличные', id: _idC),
        ],
        accounts: accounts,
        live: {_tid.toUpperCase()},
        deleted: {_idC},
      );
      expect(plan.transfers, isEmpty);
      expect(plan.skippedExisting, 1);
      expect(plan.skippedDeleted, 1);
    });

    test('без ID: отпечаток стабилен, две одинаковые строки различаются', () {
      final accounts = [_account(_idA, 'Карта'), _account(_idB, 'Наличные')];
      final rows = [
        _row(from: 'Карта', to: 'Наличные'),
        _row(from: 'Карта', to: 'Наличные'),
      ];
      final first = _plan(rows, accounts: accounts);
      final second = _plan(rows, accounts: accounts);
      expect(first.transfers.map((t) => t.id), hasLength(2));
      expect(first.transfers[0].id, isNot(first.transfers[1].id));
      expect(
        first.transfers.map((t) => t.id),
        second.transfers.map((t) => t.id),
      );
      final again = _plan(
        rows,
        accounts: accounts,
        live: {for (final t in first.transfers) t.id},
      );
      expect(again.transfers, isEmpty);
      expect(again.skippedExisting, 2);
    });
  });

  group('ошибки', () {
    test('ID счёта зачисления не найден и имени нет', () {
      final plan = _plan(
        [_row(from: 'Карта', toId: _idC)],
        accounts: [_account(_idA, 'Карта')],
      );
      expect(
        _message(plan),
        'Строка 4: счёт с ID «$_idC» не найден. '
        'Укажите имя счёта в колонке «Счёт зачисления»',
      );
      expect(plan.transfers, isEmpty);
    });

    test('ID счёта не найден и имени нет — прежняя ошибка', () {
      final plan = _plan(
        [_row(fromId: _idC, to: 'Карта')],
        accounts: [_account(_idA, 'Карта')],
      );
      expect(plan.errors.single, isA<CsvAccountIdNotFound>());
    });

    test('своя валюта без начального остатка', () {
      final plan = _plan([
        _row(from: 'А', to: 'Б', currency: 'ABC', customDigits: 4),
      ]);
      expect(
        _message(plan),
        'Строка 4: перевод в валюте ABC: в файле нет начального остатка '
        'счёта в этой валюте',
      );
      expect(plan.accountsToCreate, isEmpty);
    });

    test('своя валюта со строкой остатка: счета есть, перевод проходит', () {
      ParsedOpeningBalance balance(String name) => ParsedOpeningBalance(
        line: 2,
        day: DateOnly(2026, 10, 1),
        occurredAt: DateTime.utc(2026, 10, 1, 9),
        accountName: name,
        accountId: null,
        amount: Money.fromMinor(0, 'ABC'),
        customDigits: 4,
      );
      final plan = _plan(
        [_row(from: 'А', to: 'Б', currency: 'ABC', customDigits: 4)],
        balances: [balance('А'), balance('Б')],
      );
      expect(plan.errors, isEmpty);
      expect(plan.transfers, hasLength(1));
    });

    test('найденный счёт другой валюты', () {
      final plan = _plan(
        [_row(from: 'Карта', to: 'Наличные', currency: 'USD')],
        accounts: [_account(_idA, 'Карта'), _account(_idB, 'Наличные')],
      );
      expect(plan.errors, hasLength(2));
      expect(plan.errors.first, isA<CsvAccountCurrencyMismatch>());
    });

    test('имя и ID указывают на один счёт', () {
      final plan = _plan(
        [_row(from: 'Карта', toId: _idA)],
        accounts: [_account(_idA, 'Карта')],
      );
      expect(plan.errors.single, isA<CsvTransferSameAccount>());
    });

    test('с ошибкой в плане нет ни переводов, ни новых счетов', () {
      final plan = _plan([_row(from: 'Новый', toId: _idC)]);
      expect(plan.errors, hasLength(1));
      expect(plan.accountsToCreate, isEmpty);
    });
  });

  test('тексты предпросмотра: перевод / перевода / переводов', () {
    expect(csvImportWillAddTransfers(1), 'Будет добавлен 1 перевод');
    expect(csvImportWillAddTransfers(3), 'Будут добавлены 3 перевода');
    expect(csvImportWillAddTransfers(5), 'Будет добавлено 5 переводов');
    expect(csvImportWillAddTransfers(21), 'Будет добавлен 21 перевод');
  });
}

void _rescaleGroup() {
  group('пересчёт суммы при других знаках своей валюты (5.25b)', () {
    final accounts4 = [
      _account(_idA, 'Свой А', currency: 'XYZ', digits: 4),
      _account(_idB, 'Свой Б', currency: 'XYZ', digits: 4),
    ];

    test('1,5 при 4 знаках счёта: 15000', () {
      final plan = _plan([
        _row(
          from: 'Свой А',
          to: 'Свой Б',
          currency: 'XYZ',
          minor: 15,
          customDigits: 1,
        ),
      ], accounts: accounts4);
      expect(plan.errors, isEmpty);
      expect(plan.transfers.single.amount, Money.fromMinor(15000, 'XYZ'));
    });

    test('лишние нули справа допустимы, ненулевые цифры - ошибка', () {
      final accounts2 = [
        _account(_idA, 'Свой А', currency: 'XYZ'),
        _account(_idB, 'Свой Б', currency: 'XYZ'),
      ];
      final ok = _plan([
        _row(
          from: 'Свой А',
          to: 'Свой Б',
          currency: 'XYZ',
          minor: 15000,
          customDigits: 4,
        ),
      ], accounts: accounts2);
      expect(ok.transfers.single.amount, Money.fromMinor(150, 'XYZ'));

      final bad = _plan([
        _row(
          from: 'Свой А',
          to: 'Свой Б',
          currency: 'XYZ',
          minor: 12345,
          customDigits: 4,
        ),
      ], accounts: accounts2);
      final error = bad.errors.single as CsvInvalidAmount;
      expect(error.failure, AmountParseFailure.tooManyDecimals);
      expect(error.currencyDigits, 2);
      expect(bad.transfers, isEmpty);
    });

    test('переполнение при пересчёте: tooLarge', () {
      final plan = _plan([
        _row(
          from: 'Свой А',
          to: 'Свой Б',
          currency: 'XYZ',
          minor: maxInputMinorUnits ~/ 10000 + 1,
          customDigits: 0,
        ),
      ], accounts: accounts4);
      final error = plan.errors.single as CsvInvalidAmount;
      expect(error.failure, AmountParseFailure.tooLarge);
    });
  });
}
