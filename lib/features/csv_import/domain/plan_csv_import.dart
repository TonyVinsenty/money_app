import 'package:money_app/core/id/id_generator.dart';
import 'package:money_app/core/money/currency.dart';
import 'package:money_app/core/money/currency_catalog.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/money/parse_amount.dart';
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/accounts/domain/account_rules.dart';
import 'package:money_app/features/accounts/domain/transfer.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/categories/domain/category_rules.dart';
import 'package:money_app/features/csv_import/domain/csv_import_failures.dart';
import 'package:money_app/features/csv_import/domain/parse_csv_import.dart';
import 'package:money_app/features/export/domain/transactions_export.dart';
import 'package:money_app/features/transactions/domain/category_kind_mapping.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:uuid/uuid.dart';

/// Пространство имён для «отпечатков» строк без `ID операции`. Менять нельзя:
/// иначе повторная загрузка старого файла задвоит операции.
const String csvImportFingerprintNamespace =
    '6f1c2a5e-3b7d-4c8a-9e21-5d0b7a4c9f13';

/// Иконка категорий, созданных импортом.
const String csvImportCategoryIconKey = 'more_horiz';

/// Значок счетов, созданных импортом («Другое»); тот же ключ, что
/// `otherAccountIconKey` в `core/ui` (сверяет тест).
const String csvImportAccountIconKey = 'other';

/// Разделитель частей отпечатка (управляющий символ, в именах не встречается).
const String _sep = '\u001F';

/// Итог планирования: что записать и что пропустить. Ничего не пишет сам.
final class CsvImportPlan {
  const CsvImportPlan({
    required this.transactions,
    required this.skippedExisting,
    required this.skippedDeleted,
    required this.categoriesToCreate,
    required this.errors,
    this.accountsToCreate = const [],
    this.transfers = const [],
  });

  /// Операции к добавлению, в порядке строк файла.
  final List<Transaction> transactions;

  /// Пропущено: такая операция уже есть.
  final int skippedExisting;

  /// Пропущено: такая операция удалена в приложении.
  final int skippedDeleted;

  /// Новые категории и подкатегории в порядке первого появления в файле
  /// (родитель всегда раньше своих подкатегорий).
  final List<Category> categoriesToCreate;

  /// Ошибки строк; если список не пуст, писать нельзя ничего.
  final List<CsvRowError> errors;

  /// Новые счета в порядке файла (сначала со строками `Начальный остаток`).
  /// Основным ни один не становится. Пишутся раньше категорий.
  final List<Account> accountsToCreate;

  /// Переводы к добавлению, в порядке строк файла; пишутся после операций.
  final List<Transfer> transfers;
}

/// Строит план импорта (ADR 0009, п. 6).
///
/// [categories] — все не удалённые категории и подкатегории, включая
/// архивные. [deletedCategoryIds] — id мягко удалённых категорий: они тоже
/// заняты, новая категория не получит такой id. [liveTransactionIds] и
/// [deletedTransactionIds] — id операций в базе. [ids] даёт id для новых
/// категорий и счетов. [accounts] — все не удалённые счета (и архивные),
/// [deletedAccountIds] — id мягко удалённых. [openingBalances] — строки
/// `Начальный остаток`. [isKnownIconKey] говорит, знает ли приложение значок:
/// пустой и незнакомый ключ из файла заменяется на «Другое» (ADR 0010, п. 17).
/// [parsedTransfers] - строки `Перевод`, [liveTransferIds] и
/// [deletedTransferIds] - id переводов в базе.
CsvImportPlan planCsvImport({
  required List<ParsedCsvRow> rows,
  required List<Category> categories,
  required Set<String> liveTransactionIds,
  required Set<String> deletedTransactionIds,
  required IdGenerator ids,
  required bool Function(String iconKey) isKnownIconKey,
  Set<String> deletedCategoryIds = const {},
  List<ParsedOpeningBalance> openingBalances = const [],
  List<Account> accounts = const [],
  Set<String> deletedAccountIds = const {},
  List<ParsedTransfer> parsedTransfers = const [],
  Set<String> liveTransferIds = const {},
  Set<String> deletedTransferIds = const {},
}) {
  final live = {for (final id in liveTransactionIds) id.toLowerCase()};
  final deleted = {for (final id in deletedTransactionIds) id.toLowerCase()};
  final byId = {for (final c in categories) c.id.toLowerCase(): c};
  final taken = {
    ...byId.keys,
    for (final id in deletedCategoryIds) id.toLowerCase(),
  };
  final planned = <Category>[];
  final nextSort = <String, int>{};

  for (final c in categories) {
    final key = _sortKey(c.kind, c.parentId);
    final next = c.sortOrder + 1;
    if (next > (nextSort[key] ?? 0)) nextSort[key] = next;
  }

  final transactions = <Transaction>[];
  final errors = <CsvRowError>[];
  final accountBook = _AccountBook(accounts, deletedAccountIds, ids);
  var skippedExisting = _planOpeningBalances(
    openingBalances,
    accountBook,
    errors,
  );
  final fingerprintCounts = <String, int>{};
  var skippedDeleted = 0;

  for (final row in rows) {
    final String id;
    final given = row.transactionId;
    if (given != null) {
      id = given.toLowerCase();
    } else {
      final base = _fingerprintBase(row);
      final n = (fingerprintCounts[base] ?? 0) + 1;
      fingerprintCounts[base] = n;
      id = const Uuid().v5(csvImportFingerprintNamespace, '$base$_sep$n');
    }
    if (live.contains(id)) {
      skippedExisting++;
      continue;
    }
    if (deleted.contains(id)) {
      skippedDeleted++;
      continue;
    }

    final kind = row.type.categoryKind;

    // Сначала только проверки: пока строка может оказаться с ошибкой,
    // в план ничего не попадает.
    var rowFailed = false;
    Category? category;
    final categoryId = row.categoryId?.toLowerCase();
    final byGivenId = categoryId == null ? null : byId[categoryId];
    if (byGivenId != null) {
      if (!byGivenId.isTopLevel) {
        errors.add(CsvCategoryIdIsSubcategory(row.line, row.categoryId!));
        rowFailed = true;
      } else if (byGivenId.kind != kind) {
        errors.add(CsvCategoryKindMismatch(row.line, row.categoryId!));
        rowFailed = true;
      } else {
        category = byGivenId;
      }
    } else {
      category = _findByName(
        [...categories, ...planned],
        kind: kind,
        parentId: null,
        key: categoryNameKey(row.categoryName),
      );
    }

    final subName = row.subcategoryName;
    Category? subcategory;
    final subId = row.subcategoryId?.toLowerCase();
    final bySubId = subId == null ? null : byId[subId];
    if (subName != null && bySubId != null) {
      // Подкатегория по id должна быть дочерней найденной категории; если
      // категории ещё нет (будет создана), чужая подкатегория ей не подойдёт.
      if (bySubId.isTopLevel ||
          category == null ||
          bySubId.parentId != category.id) {
        errors.add(CsvSubcategoryWrongParent(row.line, row.subcategoryId!));
        rowFailed = true;
      } else {
        subcategory = bySubId;
      }
    }

    // Счёт: найденный или будущий (его создадут рублёвым, п. 16.11).
    final accountName = row.accountName;
    var account = accountBook.find(row.accountId, accountName);
    if (account == null && accountName == null && row.accountId != null) {
      errors.add(CsvAccountIdNotFound(row.line, row.accountId!));
      rowFailed = true;
    }
    final accountCurrency = account?.currency ?? rubCurrencyCode;
    if ((account != null || accountName != null) &&
        accountCurrency != row.amount.currency) {
      errors.add(
        CsvAccountCurrencyMismatch(
          row.line,
          row.amount.currency,
          account?.name ?? accountName!,
          accountCurrency,
        ),
      );
      rowFailed = true;
    }
    if (rowFailed) continue;

    // Строка годна: создаём недостающее.
    if (account == null && accountName != null) {
      account = accountBook.create(
        fromFile: row.accountId,
        name: accountName,
        balance: Money.fromMinor(0, rubCurrencyCode),
        digits: currencyInfoFor(rubCurrencyCode).digits,
      );
    }
    category ??= _planned(
      planned,
      Category.topLevel(
        id: _freeId(row.categoryId, taken, ids),
        kind: kind,
        name: row.categoryName,
        iconKey: _iconOr(row.categoryIconKey, isKnownIconKey),
        sortOrder: _takeSort(nextSort, kind, null),
      ),
    );
    if (subName != null && subcategory == null) {
      subcategory =
          _findByName(
            [...categories, ...planned],
            kind: kind,
            parentId: category.id,
            key: categoryNameKey(subName),
          ) ??
          _planned(
            planned,
            Category.subcategoryOf(
              id: _freeId(row.subcategoryId, taken, ids),
              parent: category,
              name: subName,
              iconKey: _iconOr(row.subcategoryIconKey, isKnownIconKey),
              sortOrder: _takeSort(nextSort, kind, category.id),
            ),
          );
    }

    transactions.add(
      Transaction(
        id: id,
        type: row.type,
        amount: row.amount,
        occurredOn: row.day,
        occurredAt: row.occurredAt,
        categoryId: category.id,
        subcategoryId: subcategory?.id,
        note: row.note,
        accountId: account?.id,
      ),
    );
  }

  final transfers = <Transfer>[];
  final liveTransfers = {for (final id in liveTransferIds) id.toLowerCase()};
  final deletedTransfers = {
    for (final id in deletedTransferIds) id.toLowerCase(),
  };
  final transferPrints = <String, int>{};
  for (final row in parsedTransfers) {
    final String id;
    final given = row.transferId;
    if (given != null) {
      id = given.toLowerCase();
    } else {
      final base = _transferFingerprintBase(row);
      final n = (transferPrints[base] ?? 0) + 1;
      transferPrints[base] = n;
      id = const Uuid().v5(csvImportFingerprintNamespace, '$base$_sep$n');
    }
    if (liveTransfers.contains(id)) {
      skippedExisting++;
      continue;
    }
    if (deletedTransfers.contains(id)) {
      skippedDeleted++;
      continue;
    }
    final transfer = _planTransfer(row, id, accountBook, errors);
    if (transfer != null) transfers.add(transfer);
  }

  return CsvImportPlan(
    accountsToCreate: accountBook.planned,
    transactions: transactions,
    transfers: transfers,
    skippedExisting: skippedExisting,
    skippedDeleted: skippedDeleted,
    categoriesToCreate: planned,
    errors: errors,
  );
}

/// Один перевод: находит или создаёт оба счёта (создаются в валюте перевода,
/// нулевой остаток). Ошибки дописывает в [errors] и тогда ничего не создаёт.
Transfer? _planTransfer(
  ParsedTransfer row,
  String id,
  _AccountBook book,
  List<CsvRowError> errors,
) {
  final currency = row.amount.currency;
  final before = errors.length;
  final from = book.find(row.fromAccountId, row.fromAccountName);
  final to = book.find(row.toAccountId, row.toAccountName);
  if (from == null && row.fromAccountName == null) {
    errors.add(CsvAccountIdNotFound(row.line, row.fromAccountId!));
  }
  if (to == null && row.toAccountName == null) {
    errors.add(CsvTransferToAccountIdNotFound(row.line, row.toAccountId!));
  }
  for (final account in [from, to]) {
    if (account != null && account.currency != currency) {
      errors.add(
        CsvAccountCurrencyMismatch(
          row.line,
          currency,
          account.name,
          account.currency,
        ),
      );
    }
  }
  final fromName = row.fromAccountName;
  final toName = row.toAccountName;
  final same = from != null && from.id == to?.id;
  final sameNew =
      from == null &&
      to == null &&
      fromName != null &&
      toName != null &&
      accountNameKey(fromName) == accountNameKey(toName);
  if (same || sameNew) {
    errors.add(CsvTransferSameAccount(row.line, from?.name ?? fromName!));
  }

  // Знаки суммы: каталог, иначе знаки счетов этой валюты.
  var amount = row.amount;
  final fileDigits = row.customDigits;
  int digits = catalogCurrency(currency)?.digits ?? 2;
  if (fileDigits != null) {
    final known =
        [from, to]
            .where((a) => a != null && a.currency == currency)
            .map((a) => a!.currencyDigits)
            .firstOrNull ??
        book.digitsOf(currency);
    if (known == null) {
      errors.add(CsvTransferCurrencyNoOpeningBalance(row.line, currency));
    } else {
      digits = known;
      if (known != fileDigits) {
        final rescaled = _rescale(amount.minorUnits, fileDigits, known);
        if (rescaled == null) {
          final text = formatCsvAmount(
            amount,
            currency: currencyInfoFor(currency, digits: fileDigits),
          );
          errors.add(
            CsvInvalidAmount(
              row.line,
              text,
              known < fileDigits
                  ? AmountParseFailure.tooManyDecimals
                  : AmountParseFailure.tooLarge,
              currencyCode: currency,
              currencyDigits: known,
            ),
          );
        } else {
          amount = Money.fromMinor(rescaled, currency);
        }
      }
    }
  }
  if (errors.length > before) return null;

  final fromAccount =
      from ??
      book.create(
        fromFile: row.fromAccountId,
        name: fromName!,
        balance: Money.zero(currency),
        digits: digits,
      );
  final toAccount =
      to ??
      book.create(
        fromFile: row.toAccountId,
        name: toName!,
        balance: Money.zero(currency),
        digits: digits,
      );
  return Transfer(
    id: id,
    fromAccountId: fromAccount.id,
    toAccountId: toAccount.id,
    amount: amount,
    occurredOn: row.day,
    occurredAt: row.occurredAt,
    note: row.note,
  );
}

/// Переводит сумму из [fromDigits] знаков в [toDigits]; `null` — не выходит
/// (лишние ненулевые цифры или слишком большая сумма).
int? _rescale(int minor, int fromDigits, int toDigits) {
  if (toDigits < fromDigits) {
    final cut = _pow10(fromDigits - toDigits);
    return minor % cut == 0 ? minor ~/ cut : null;
  }
  final scale = _pow10(toDigits - fromDigits);
  return minor > maxInputMinorUnits ~/ scale ? null : minor * scale;
}

String _transferFingerprintBase(ParsedTransfer row) {
  String account(String? name, String? id) =>
      name != null ? accountNameKey(name) : (id ?? '').toLowerCase();
  return [
    row.day.toString(),
    'transfer',
    row.amount.minorUnits.toString(),
    row.amount.currency,
    account(row.fromAccountName, row.fromAccountId),
    account(row.toAccountName, row.toAccountId),
    row.note ?? '',
  ].join(_sep);
}

/// Ключ из файла, если приложение его знает, иначе «Другое».
String _iconOr(String? key, bool Function(String) isKnown) =>
    key != null && isKnown(key) ? key : csvImportCategoryIconKey;

/// Счета базы и счета, которые импорт собирается создать (ADR 0010, п. 10).
final class _AccountBook {
  _AccountBook(List<Account> existing, Set<String> deletedIds, this._ids)
    : _all = [...existing],
      _byId = {for (final a in existing) a.id.toLowerCase(): a},
      _taken = {
        for (final a in existing) a.id.toLowerCase(),
        for (final id in deletedIds) id.toLowerCase(),
      },
      _nextSort = existing.fold(
        0,
        (next, a) => a.sortOrder >= next ? a.sortOrder + 1 : next,
      );

  final List<Account> _all;
  final Map<String, Account> _byId;
  final Set<String> _taken;
  final IdGenerator _ids;
  int _nextSort;

  /// Новые счета в порядке создания.
  final List<Account> planned = [];

  /// По id (в том числе архивный), затем по имени среди не архивных.
  Account? find(String? id, String? name) {
    final byId = id == null ? null : _byId[id.toLowerCase()];
    if (byId != null || name == null) return byId;
    final key = accountNameKey(name);
    for (final a in _all) {
      if (!a.isArchived && accountNameKey(a.name) == key) return a;
    }
    return null;
  }

  /// Знаков после запятой у уже известного счёта этой валюты.
  int? digitsOf(String currency) {
    for (final a in _all) {
      if (a.currency == currency) return a.currencyDigits;
    }
    return null;
  }

  /// Счёт для строки `Начальный остаток`: если есть `ID счёта`, ищем только по
  /// нему (одноимённые счета с разными id — разные счета), иначе по имени.
  Account? findForOpeningBalance(String? id, String name) =>
      id == null ? find(null, name) : _byId[id.toLowerCase()];

  /// Имя, свободное среди не архивных счетов: «Карта», «Карта (2)», «Карта (3)»…
  /// Основа обрезается, чтобы имя с суффиксом влезло в лимит.
  String _freeName(String name) {
    bool isFree(String candidate) {
      final key = accountNameKey(candidate);
      return !_all.any((a) => !a.isArchived && accountNameKey(a.name) == key);
    }

    if (isFree(name)) return name;
    for (var n = 2; ; n++) {
      final suffix = ' ($n)';
      final room = accountNameMaxLength - suffix.length;
      final runes = name.runes.toList();
      final base = runes.length > room
          ? String.fromCharCodes(runes.take(room)).trimRight()
          : name;
      final candidate = '$base$suffix';
      if (isFree(candidate)) return candidate;
    }
  }

  Account create({
    required String? fromFile,
    required String name,
    required Money balance,
    required int digits,
    DateTime? createdAt,
  }) {
    final id = _freeId(fromFile, _taken, _ids);
    final account = Account(
      id: id,
      name: _freeName(name),
      iconKey: csvImportAccountIconKey,
      openingBalance: balance,
      sortOrder: _nextSort++,
      currencyDigits: digits,
      createdAt: createdAt,
    );
    planned.add(account);
    _all.add(account);
    _byId[id.toLowerCase()] = account;
    return account;
  }
}

/// Строки `Начальный остаток`: новые счета с остатком; существующие счета не
/// меняются (остаток в базе не перезаписывается). Возвращает, сколько строк
/// пропущено, потому что счёт уже есть.
int _planOpeningBalances(
  List<ParsedOpeningBalance> balances,
  _AccountBook book,
  List<CsvRowError> errors,
) {
  var skipped = 0;
  final seenLines = <String, int>{};
  for (final ob in balances) {
    // Дубль — по ID счёта; по имени — только у строк без id.
    final key = ob.accountId != null
        ? 'id:${ob.accountId!.toLowerCase()}'
        : 'name:${accountNameKey(ob.accountName)}';
    final first = seenLines[key];
    if (first != null) {
      errors.add(CsvDuplicateOpeningBalance(ob.line, ob.accountName, first));
      continue;
    }
    seenLines[key] = ob.line;

    final currency = ob.amount.currency;
    final found = book.findForOpeningBalance(ob.accountId, ob.accountName);
    if (found != null) {
      if (found.currency != currency) {
        errors.add(
          CsvAccountCurrencyMismatch(
            ob.line,
            currency,
            found.name,
            found.currency,
          ),
        );
      } else {
        skipped++;
      }
      continue;
    }

    // Знаки: каталог, иначе уже известный счёт этой валюты, иначе из файла.
    final knownDigits =
        catalogCurrency(currency)?.digits ?? book.digitsOf(currency);
    final fileDigits = ob.customDigits;
    var minor = ob.amount.minorUnits;
    if (knownDigits != null &&
        fileDigits != null &&
        knownDigits != fileDigits) {
      // Сумма разобрана по знакам из файла, а у валюты знаки уже заданы.
      final AmountParseFailure? failure;
      if (knownDigits < fileDigits) {
        // Лишние нули справа («1,5000» при 2 знаках) — не ошибка.
        final cut = _pow10(fileDigits - knownDigits);
        if (minor % cut == 0) {
          minor ~/= cut;
          failure = null;
        } else {
          failure = AmountParseFailure.tooManyDecimals;
        }
      } else {
        final scale = _pow10(knownDigits - fileDigits);
        if (minor.abs() > maxInputMinorUnits ~/ scale) {
          failure = AmountParseFailure.tooLarge;
        } else {
          minor *= scale;
          failure = null;
        }
      }
      if (failure != null) {
        final text = formatCsvAmount(
          Money.fromMinor(ob.amount.minorUnits.abs(), currency),
          currency: currencyInfoFor(currency, digits: fileDigits),
        );
        errors.add(
          CsvInvalidAmount(
            ob.line,
            ob.amount.minorUnits < 0 ? '-$text' : text,
            failure,
            currencyCode: currency,
            currencyDigits: knownDigits,
          ),
        );
        continue;
      }
    }
    book.create(
      fromFile: ob.accountId,
      name: ob.accountName,
      balance: Money.fromMinor(minor, currency),
      digits: knownDigits ?? fileDigits ?? 2,
      createdAt: ob.occurredAt,
    );
  }
  return skipped;
}

int _pow10(int n) {
  var result = 1;
  for (var i = 0; i < n; i++) {
    result *= 10;
  }
  return result;
}

String _fingerprintBase(ParsedCsvRow row) {
  return [
    row.day.toString(),
    row.type.name,
    row.amount.minorUnits.toString(),
    row.amount.currency,
    categoryNameKey(row.categoryName),
    categoryNameKey(row.subcategoryName ?? ''),
    row.note ?? '',
  ].join(_sep);
}

String _sortKey(CategoryKind kind, String? parentId) =>
    '${kind.name}|${parentId ?? ''}';

int _takeSort(Map<String, int> next, CategoryKind kind, String? parentId) {
  final key = _sortKey(kind, parentId);
  final value = next[key] ?? 0;
  next[key] = value + 1;
  return value;
}

Category _planned(List<Category> planned, Category category) {
  planned.add(category);
  return category;
}

/// Id из файла, если он есть и свободен, иначе новый. Занимает выбранный id.
String _freeId(String? fromFile, Set<String> taken, IdGenerator ids) {
  final candidate = fromFile?.toLowerCase();
  final id = candidate != null && !taken.contains(candidate)
      ? candidate
      : ids.newId();
  taken.add(id.toLowerCase());
  return id;
}

Category? _findByName(
  Iterable<Category> pool, {
  required CategoryKind kind,
  required String? parentId,
  required String key,
}) {
  for (final c in pool) {
    if (!c.isArchived &&
        c.kind == kind &&
        c.parentId == parentId &&
        categoryNameKey(c.name) == key) {
      return c;
    }
  }
  return null;
}
