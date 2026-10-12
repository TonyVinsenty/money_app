import 'package:money_app/core/database/app_database.dart';
import 'package:money_app/core/money/currency_catalog.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/features/accounts/data/accounts_repository_impl.dart';
import 'package:money_app/features/accounts/data/transfers_repository_impl.dart';
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/accounts/domain/transfer.dart';
import 'package:money_app/features/categories/data/categories_repository_impl.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/recurring/data/recurring_repository_impl.dart';
import 'package:money_app/features/recurring/domain/recurring_payment.dart';
import 'package:money_app/features/transactions/data/transactions_repository_impl.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

import 'fake_id_generator.dart';
import 'fixed_clock.dart';

/// Набор «крайних данных» (этап 7, К2): всё, что допускают правила, на
/// пределе. Сегодня — 12 октября 2026, полдень.
///
/// - 30 категорий расходов и 2 дохода с названиями ровно 40 символов (одно —
///   без единого пробела), подкатегория на 40 символов;
/// - суммы до 999 999 999,99 ₽ (предел ввода; итоги месяца — больше),
///   комментарии на 200 символов;
/// - 10 счетов разных валют, в том числе BTC с 8 знаками, названия по 40;
/// - платежи 31-го числа, 29 февраля и сегодняшний (плашка «К оплате»);
/// - перевод между счетами с комментарием на 200 символов.
final extremeClock = FixedClock(DateTime(2026, 10, 12, 12));

/// Самая большая сумма, которую можно ввести в рублях: 999 999 999,99 ₽.
const int extremeMaxRubMinor = 99999999999;

/// Ровно 40 символов: [text], обрезанный или дополненный буквой «я».
String extreme40(String text) => text.padRight(40, 'я').substring(0, 40);

/// Название без пробелов: переносить его можно только посреди слова.
final extremeUnbreakable = extreme40('Сверхдлиннаякатегориябезединогопробела');

/// 200 символов комментария со словами разной длины.
final extremeNote =
    ('Очень длинный комментарий к операции, который проверяет перенос '
                'строк, обрезку и отсутствие переполнений на узком экране при '
                'крупном шрифте; ' *
            3)
        .substring(0, 200);

String _categoryName(int i) =>
    i == 0 ? extremeUnbreakable : extreme40('$i Коммунальные платежи и дом');

/// Название счёта [i] из набора: ровно 40 символов, у счёта 1 — без пробелов.
String extremeAccountName(int i) => i == 1
    ? extreme40('Счётбезпробеловсамыйдлинныйизвозможных')
    : extreme40('$i Основная карта для ежедневных трат');

/// Название платежа [id] из набора: ровно 40 символов.
String extremePaymentTitle(String id) =>
    extreme40('$id Ежемесячный платёж за длинную услугу');

/// Валюты 10 счетов: рубль первым (основной), BTC с 8 знаками.
const extremeCurrencies = [
  'RUB',
  'RUB',
  'USD',
  'EUR',
  'CNY',
  'BTC',
  'ETH',
  'USDT',
  'TON',
  'XRP',
];

/// Остаток на открытие: предел ввода в единицах валюты (999 999,99999999
/// для 8 знаков, 999 999 999,99 для 2).
int _openingMinor(int digits) => digits >= 8 ? 99999999999999 : 99999999999;

/// Кладёт набор в базу [db] (обычно в памяти, уже с категориями по
/// умолчанию) через настоящие репозитории, как это делает приложение.
Future<void> seedExtremeData(AppDatabase db) async {
  final clock = extremeClock;
  final categories = DriftCategoriesRepository(db, clock: clock);
  final transactions = DriftTransactionsRepository(db, clock: clock);
  final accounts = DriftAccountsRepository(db, clock: clock);
  final transfers = DriftTransfersRepository(db, clock: clock);
  final recurring = DriftRecurringRepository(
    db,
    transactions,
    clock: clock,
    ids: FakeIdGenerator(prefix: 'rec'),
  );

  for (var i = 0; i < 30; i++) {
    await categories.create(
      Category.topLevel(
        id: 'x-cat-$i',
        kind: CategoryKind.expense,
        name: _categoryName(i),
        iconKey: 'shopping_cart',
        sortOrder: 100 + i,
      ),
    );
  }
  await categories.create(
    Category(
      id: 'x-sub',
      kind: CategoryKind.expense,
      name: extreme40('Подкатегория с очень длинным названием'),
      iconKey: 'shopping_cart',
      parentId: 'x-cat-1',
      sortOrder: 0,
    ),
  );
  for (var i = 0; i < 2; i++) {
    await categories.create(
      Category.topLevel(
        id: 'x-inc-$i',
        kind: CategoryKind.income,
        name: extreme40('$i Зарплата и премии за долгую работу'),
        iconKey: 'work',
        sortOrder: 100 + i,
      ),
    );
  }

  for (var i = 0; i < extremeCurrencies.length; i++) {
    final code = extremeCurrencies[i];
    final digits = currencyInfoFor(code).digits;
    await accounts.create(
      Account(
        id: 'x-acc-$i',
        name: extremeAccountName(i),
        iconKey: 'wallet',
        openingBalance: Money.fromMinor(_openingMinor(digits), code),
        sortOrder: i,
        currencyDigits: digits,
      ),
    );
  }

  // Операции текущего месяца: по одной в каждой категории, первая — на
  // предел. Плюс прошлый месяц для «Сравнения».
  var n = 0;
  Future<void> add(
    TransactionType type,
    String categoryId,
    int minor,
    DateOnly day, {
    String? subcategoryId,
    String? note,
    String? accountId,
  }) => transactions.add(
    Transaction(
      id: 'x-tx-${n++}',
      type: type,
      amount: Money.fromMinor(minor, 'RUB'),
      occurredOn: day,
      occurredAt: DateTime(day.year, day.month, day.day, 10).toUtc(),
      categoryId: categoryId,
      subcategoryId: subcategoryId,
      note: note,
      accountId: accountId,
    ),
  );

  for (var i = 0; i < 30; i++) {
    final minor = i == 0 ? extremeMaxRubMinor : extremeMaxRubMinor ~/ (i + 1);
    await add(
      TransactionType.expense,
      'x-cat-$i',
      minor,
      DateOnly(2026, 10, 1 + i % 12),
      subcategoryId: i == 1 ? 'x-sub' : null,
      note: i.isEven ? extremeNote : null,
      accountId: i < 3 ? 'x-acc-0' : null,
    );
    await add(
      TransactionType.expense,
      'x-cat-$i',
      minor ~/ 3,
      DateOnly(2026, 9, 1 + i % 30),
    );
  }
  for (var i = 0; i < 2; i++) {
    await add(
      TransactionType.income,
      'x-inc-$i',
      extremeMaxRubMinor,
      DateOnly(2026, 10, 5),
      note: extremeNote,
      accountId: 'x-acc-0',
    );
  }

  await transfers.add(
    Transfer(
      id: 'x-transfer',
      fromAccountId: 'x-acc-0',
      toAccountId: 'x-acc-1',
      amount: Money.fromMinor(extremeMaxRubMinor, 'RUB'),
      occurredOn: DateOnly(2026, 10, 3),
      occurredAt: DateTime(2026, 10, 3, 10).toUtc(),
      note: extremeNote,
    ),
  );

  Future<void> payment(
    String id,
    RepeatUnit unit,
    DateOnly startsOn, {
    String? accountId,
  }) => recurring.create(
    RecurringPayment(
      id: id,
      title: extremePaymentTitle(id),
      type: TransactionType.expense,
      amount: Money.fromMinor(extremeMaxRubMinor, 'RUB'),
      categoryId: 'x-cat-0',
      subcategoryId: null,
      accountId: accountId,
      unit: unit,
      every: 1,
      startsOn: startsOn,
    ),
  );
  // 31-го числа: в феврале — 28-го (ADR 0004).
  await payment('p31', RepeatUnit.month, DateOnly(2026, 1, 31));
  // 29 февраля: в невисокосный год — 28-го.
  await payment('p29', RepeatUnit.year, DateOnly(2024, 2, 29));
  // Сегодня: плашка «К оплате» на «Главной» и блок на «Балансе».
  await payment(
    'pToday',
    RepeatUnit.month,
    DateOnly(2026, 10, 12),
    accountId: 'x-acc-0',
  );
}
