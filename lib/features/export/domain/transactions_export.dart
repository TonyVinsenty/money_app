import 'package:money_app/core/csv/csv_codec.dart';
import 'package:money_app/core/errors/data_corrupted_exception.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/money/currency_catalog.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/clock.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/accounts/domain/transfer.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/recurring/domain/recurring_payment.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

/// Чистая сборка CSV-экспорта по ADR 0006: без Flutter, без базы и без файлов.
///
/// Здесь только правила формата: заголовки, порядок колонок и строк, вид
/// суммы и даты. Чтение из базы и запись файла — в `features/export/data`.

/// Заголовки колонок в принятом порядке. Импорт ищет колонки по заголовку,
/// поэтому эти строки менять нельзя (ADR 0006, п. 2).
const List<String> transactionsExportHeaders = [
  csvColumnDate,
  csvColumnType,
  csvColumnAmount,
  csvColumnCurrency,
  csvColumnCategory,
  csvColumnSubcategory,
  csvColumnNote,
  csvColumnAccount,
  csvColumnTransferAccount,
  csvColumnTransactionId,
  csvColumnCategoryId,
  csvColumnSubcategoryId,
  csvColumnOccurredAtUtc,
  csvColumnAccountId,
  csvColumnTransferAccountId,
  csvColumnCategoryIcon,
  csvColumnSubcategoryIcon,
  csvColumnRepeat,
  csvColumnEvery,
  csvColumnUntil,
  csvColumnRemind,
];

// Имена колонок: общие для экспорта и импорта (ADR 0006, п. 2).
const String csvColumnDate = 'Дата';
const String csvColumnType = 'Тип';
const String csvColumnAmount = 'Сумма';
const String csvColumnCurrency = 'Валюта';
const String csvColumnCategory = 'Категория';
const String csvColumnSubcategory = 'Подкатегория';
const String csvColumnNote = 'Комментарий';
const String csvColumnTransactionId = 'ID операции';
const String csvColumnCategoryId = 'ID категории';
const String csvColumnSubcategoryId = 'ID подкатегории';
const String csvColumnOccurredAtUtc = 'Время операции (UTC)';

// Колонки v2 (ADR 0010, пп. 10 и 17).
const String csvColumnAccount = 'Счёт';
const String csvColumnTransferAccount = 'Счёт зачисления';
const String csvColumnAccountId = 'ID счёта';
const String csvColumnTransferAccountId = 'ID счёта зачисления';
const String csvColumnCategoryIcon = 'Значок категории';
const String csvColumnSubcategoryIcon = 'Значок подкатегории';

// Колонки v3 для регулярных платежей (ADR 0011, п. 10); у прочих строк пусты.
const String csvColumnRepeat = 'Повтор';
const String csvColumnEvery = 'Каждые';
const String csvColumnUntil = 'До';
const String csvColumnRemind = 'Напоминать';

// Тексты колонки «Повтор» и «Напоминать».
const String csvRepeatWeek = 'неделя';
const String csvRepeatMonth = 'месяц';
const String csvRepeatYear = 'год';
const String csvRemindYes = 'да';
const String csvRemindNo = 'нет';

// Тексты колонки «Тип».
const String csvTypeIncome = 'Доход';
const String csvTypeExpense = 'Расход';
const String csvTypeOpeningBalance = 'Начальный остаток';
const String csvTypeTransfer = 'Перевод';
const String csvTypeRecurringExpense = 'Регулярный расход';
const String csvTypeRecurringIncome = 'Регулярный доход';

/// Текст CSV-файла экспорта: заголовки, затем операции от старых к новым.
///
/// [categories] — все не удалённые категории, включая архивные: по ним берутся
/// имена. Если у операции нет категории или подкатегории в этом списке, бросает
/// [DataCorruptedException]: файл не формируется, строки не пропускаются.
/// [accounts] — все не удалённые счета, включая архивные: по строке
/// `Начальный остаток` на каждый; счёт операции не найден — тоже отказ.
/// [transfers] — не удалённые переводы: строка `Перевод` на каждый; счёт
/// перевода не найден — тоже отказ.
/// [recurring] — живые регулярные платежи: строка `Регулярный расход` или
/// `Регулярный доход` на каждый, после всех остальных строк (по дате первого
/// платежа, затем по id); категория или счёт не найдены — тоже отказ.
String buildTransactionsCsv({
  required List<Transaction> transactions,
  required List<Category> categories,
  required List<Account> accounts,
  List<Transfer> transfers = const [],
  List<RecurringPayment> recurring = const [],
}) {
  return encodeCsv(
    buildTransactionsCsvRows(
      transactions: transactions,
      categories: categories,
      accounts: accounts,
      transfers: transfers,
      recurring: recurring,
    ),
  );
}

/// Строки таблицы экспорта (первая строка — заголовки), без кодирования.
List<List<String>> buildTransactionsCsvRows({
  required List<Transaction> transactions,
  required List<Category> categories,
  required List<Account> accounts,
  List<Transfer> transfers = const [],
  List<RecurringPayment> recurring = const [],
}) {
  final byId = {for (final category in categories) category.id: category};
  final accountsById = {for (final account in accounts) account.id: account};
  final lines = <_Line>[
    for (final account in accounts) _openingBalanceLine(account),
    for (final transaction in transactions)
      _transactionLine(transaction, byId, accountsById),
    for (final transfer in transfers) _transferLine(transfer, accountsById),
  ]..sort(_byOccurrence);
  final recurringLines = <_Line>[
    for (final payment in recurring)
      if (!payment.isDeleted) _recurringLine(payment, byId, accountsById),
  ]..sort(_byOccurrence);
  return [
    transactionsExportHeaders,
    for (final line in lines) _withRecurringTail(line.row),
    for (final line in recurringLines) line.row,
  ];
}

/// Операции, переводы и остатки: колонки 18-21 пусты.
List<String> _withRecurringTail(List<String> row) => [...row, '', '', '', ''];

/// Строка `Регулярный расход`/`Регулярный доход`. `Дата` — первый платёж
/// (может быть в будущем), `ID операции` — id платежа, `Комментарий` —
/// название; `Время операции (UTC)` пусто. `Каждые` пишется всегда, `До` —
/// только если задано, `Напоминать` — `да`/`нет`.
_Line _recurringLine(
  RecurringPayment payment,
  Map<String, Category> byId,
  Map<String, Account> accountsById,
) {
  final category = byId[payment.categoryId];
  if (category == null) {
    throw DataCorruptedException(
      'Recurring payment "${payment.id}" refers to a missing category '
      '"${payment.categoryId}"',
    );
  }
  final subcategoryId = payment.subcategoryId;
  Category? subcategory;
  if (subcategoryId != null) {
    subcategory = byId[subcategoryId];
    if (subcategory == null) {
      throw DataCorruptedException(
        'Recurring payment "${payment.id}" refers to a missing subcategory '
        '"$subcategoryId"',
      );
    }
  }
  final accountId = payment.accountId;
  Account? account;
  if (accountId != null) {
    account = accountsById[accountId];
    if (account == null) {
      throw DataCorruptedException(
        'Recurring payment "${payment.id}" refers to a missing account '
        '"$accountId"',
      );
    }
  }
  final isExpense = payment.type == TransactionType.expense;
  final amountText = formatCsvAmount(
    payment.amount,
    currency: account != null && account.currency == payment.amount.currency
        ? account.currencyInfo
        : null,
  );
  final until = payment.endsOn;
  return _Line(
    payment.startsOn,
    DateTime.utc(
      payment.startsOn.year,
      payment.startsOn.month,
      payment.startsOn.day,
    ),
    payment.id,
    '',
    [
      formatCsvDate(payment.startsOn),
      isExpense ? csvTypeRecurringExpense : csvTypeRecurringIncome,
      isExpense ? '-$amountText' : amountText,
      payment.amount.currency,
      category.name,
      subcategory?.name ?? '',
      payment.title,
      account?.name ?? '',
      '',
      payment.id,
      payment.categoryId,
      subcategoryId ?? '',
      '',
      accountId ?? '',
      '',
      category.iconKey,
      subcategory?.iconKey ?? '',
      _repeatText(payment.unit),
      '${payment.every}',
      until == null ? '' : formatCsvDate(until),
      payment.remind ? csvRemindYes : csvRemindNo,
    ],
  );
}

String _repeatText(RepeatUnit unit) {
  switch (unit) {
    case RepeatUnit.week:
      return csvRepeatWeek;
    case RepeatUnit.month:
      return csvRepeatMonth;
    case RepeatUnit.year:
      return csvRepeatYear;
  }
}

/// Имя файла: `zuno-export-ГГГГ-ММ-ДД.csv`, дата — локальный день из [clock].
String exportFileName(Clock clock) {
  // DateOnly.toString() уже даёт вид ГГГГ-ММ-ДД.
  return 'zuno-export-${clock.today()}.csv';
}

/// Сумма для Excel: `350,00` из 35000 копеек. Ровно столько знаков, сколько у
/// валюты ([currency], по умолчанию запись каталога по коду суммы): `0,00150000`
/// у BTC, `1500` у иены (без запятой). Только целая арифметика.
String formatCsvAmount(Money amount, {CurrencyInfo? currency}) {
  final minor = amount.minorUnits;
  if (minor < 0) {
    throw ArgumentError.value(minor, 'amount', 'must not be negative');
  }
  final digits = (currency ?? currencyInfoFor(amount.currency)).digits;
  if (digits == 0) return '$minor';
  final divisor = pow10(digits);
  final fraction = (minor % divisor).toString().padLeft(digits, '0');
  return '${minor ~/ divisor},$fraction';
}

/// Дата `ДД.ММ.ГГГГ`, например `04.10.2026`.
String formatCsvDate(DateOnly day) {
  final dd = day.day.toString().padLeft(2, '0');
  final mm = day.month.toString().padLeft(2, '0');
  final yyyy = day.year.toString().padLeft(4, '0');
  return '$dd.$mm.$yyyy';
}

/// Строка таблицы с ключами порядка (ADR 0006, п. 4).
class _Line {
  const _Line(this.day, this.moment, this.id, this.accountId, this.row);

  final DateOnly day;
  final DateTime moment;

  /// `ID операции`; у «Начального остатка» пусто, поэтому он идёт первым.
  final String id;
  final String accountId;
  final List<String> row;
}

_Line _transactionLine(
  Transaction transaction,
  Map<String, Category> byId,
  Map<String, Account> accountsById,
) {
  final category = byId[transaction.categoryId];
  if (category == null) {
    throw DataCorruptedException(
      'Transaction "${transaction.id}" refers to a missing category '
      '"${transaction.categoryId}"',
    );
  }
  final subcategoryId = transaction.subcategoryId;
  Category? subcategory;
  if (subcategoryId != null) {
    subcategory = byId[subcategoryId];
    if (subcategory == null) {
      throw DataCorruptedException(
        'Transaction "${transaction.id}" refers to a missing subcategory '
        '"$subcategoryId"',
      );
    }
  }
  final accountId = transaction.accountId;
  Account? account;
  if (accountId != null) {
    account = accountsById[accountId];
    if (account == null) {
      throw DataCorruptedException(
        'Transaction "${transaction.id}" refers to a missing account '
        '"$accountId"',
      );
    }
  }
  // Знаки после запятой: у валюты счёта — из счёта (своя валюта может быть
  // не из каталога), иначе из каталога.
  final sameCurrency =
      account != null && account.currency == transaction.amount.currency;
  final amountText = _amountText(
    transaction,
    currency: sameCurrency ? account.currencyInfo : null,
  );
  return _Line(
    transaction.occurredOn,
    transaction.occurredAt,
    transaction.id,
    '',
    [
      formatCsvDate(transaction.occurredOn),
      _typeText(transaction.type),
      amountText,
      transaction.amount.currency,
      category.name,
      subcategory?.name ?? '',
      transaction.note ?? '',
      account?.name ?? '',
      '',
      transaction.id,
      transaction.categoryId,
      subcategoryId ?? '',
      transaction.occurredAt.toUtc().toIso8601String(),
      accountId ?? '',
      '',
      category.iconKey,
      subcategory?.iconKey ?? '',
    ],
  );
}

/// Строка `Перевод`: сумма без знака со знаками валюты, счёт «откуда» и
/// «куда», `ID операции` — id перевода; категория и значки пусты.
_Line _transferLine(Transfer transfer, Map<String, Account> accountsById) {
  Account account(String id) {
    final found = accountsById[id];
    if (found == null) {
      throw DataCorruptedException(
        'Transfer "${transfer.id}" refers to a missing account "$id"',
      );
    }
    return found;
  }

  final from = account(transfer.fromAccountId);
  final to = account(transfer.toAccountId);
  final currency = transfer.amount.currency;
  return _Line(transfer.occurredOn, transfer.occurredAt, transfer.id, '', [
    formatCsvDate(transfer.occurredOn),
    csvTypeTransfer,
    formatCsvAmount(
      transfer.amount,
      currency: from.currency == currency ? from.currencyInfo : null,
    ),
    currency,
    '',
    '',
    transfer.note ?? '',
    from.name,
    to.name,
    transfer.id,
    '',
    '',
    transfer.occurredAt.toUtc().toIso8601String(),
    from.id,
    to.id,
    '',
    '',
  ]);
}

/// Строка `Начальный остаток`: дата и время — момент создания счёта, сумма
/// со знаком (долг — `-1500,00`) и со знаками валюты счёта (ADR 0010, п. 10).
_Line _openingBalanceLine(Account account) {
  final createdAt = account.createdAt;
  if (createdAt == null) {
    throw DataCorruptedException(
      'Account "${account.id}" has no creation time',
    );
  }
  final day = DateOnly.fromDateTime(createdAt);
  final minor = account.openingBalance.minorUnits;
  final text = formatCsvAmount(
    Money.fromMinor(minor.abs(), account.currency),
    currency: account.currencyInfo,
  );
  return _Line(day, createdAt, '', account.id, [
    formatCsvDate(day),
    csvTypeOpeningBalance,
    minor < 0 ? '-$text' : text,
    account.currency,
    '',
    '',
    '',
    account.name,
    '',
    '',
    '',
    '',
    createdAt.toUtc().toIso8601String(),
    account.id,
    '',
    '',
    '',
  ]);
}

/// Сумма в колонке «Сумма»: у расхода перед числом обычный дефис `-`
/// (Excel читает `-350,00` как число). Доход и нулевой расход — без знака:
/// `-0,00` выглядит как ошибка. ADR 0006, п. 1.
String _amountText(Transaction transaction, {CurrencyInfo? currency}) {
  final text = formatCsvAmount(transaction.amount, currency: currency);
  final isExpense = transaction.type == TransactionType.expense;
  if (isExpense && !transaction.amount.isZero) {
    return '-$text';
  }
  return text;
}

String _typeText(TransactionType type) {
  switch (type) {
    case TransactionType.income:
      return csvTypeIncome;
    case TransactionType.expense:
      return csvTypeExpense;
  }
}

/// Порядок ADR 0006, п. 4: день, затем момент, затем id (у начального остатка
/// id пуст, он идёт первым; два таких — по id счёта).
int _byOccurrence(_Line a, _Line b) {
  final byDay = a.day.compareTo(b.day);
  if (byDay != 0) return byDay;
  final byMoment = a.moment.compareTo(b.moment);
  if (byMoment != 0) return byMoment;
  final byId = a.id.compareTo(b.id);
  if (byId != 0) return byId;
  return a.accountId.compareTo(b.accountId);
}
