import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/core/money/currency_catalog.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/ui/recurring_rule_text.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/recurring/domain/recurring_payment.dart';
import 'package:money_app/features/recurring/domain/recurring_rules.dart';
import 'package:money_app/features/recurring/presentation/recurring_form_screen.dart';
import 'package:money_app/features/recurring/presentation/recurring_section.dart';
import 'package:money_app/features/recurring/presentation/recurring_texts.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

import '../../../support/fake_id_generator.dart';
import '../../../support/fixed_clock.dart';
import '../../../support/in_memory_recurring_repository.dart';

final _food = Category.topLevel(
  id: 'food',
  kind: CategoryKind.expense,
  name: 'Еда',
  iconKey: 'tag',
  sortOrder: 0,
);
final _bread = Category.subcategoryOf(
  id: 'bread',
  parent: _food,
  name: 'Хлеб',
  iconKey: 'tag',
  sortOrder: 0,
);
final _salary = Category.topLevel(
  id: 'salary',
  kind: CategoryKind.income,
  name: 'Зарплата',
  iconKey: 'tag',
  sortOrder: 0,
);

Account _account(String id, String name, {String currency = 'RUB'}) => Account(
  id: id,
  name: name,
  iconKey: 'card',
  openingBalance: Money.fromMinor(0, currency),
  sortOrder: 0,
  currencyDigits: 2,
);

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  final today = DateOnly(2026, 10, 10);
  late InMemoryRecurringRepository repo;
  late List<Account> accountList;
  late List<String?> offeredAccountIds;
  RecurringCategoryChoice? nextChoice;

  setUp(() {
    final clock = FixedClock(DateTime.utc(2026, 10, 10, 12));
    late final InMemoryRecurringRepository r;
    r = InMemoryRecurringRepository(
      clock,
      InMemoryLinkedTransactions(
        (id) => [...r.categories].where((c) => c.id == id).firstOrNull,
      ),
    );
    repo = r..categories.addAll([_food, _bread, _salary]);
    accountList = [
      _account('card', 'Карта'),
      _account('usd', 'Доллары', currency: 'USD'),
    ];
    repo.accounts.addAll(accountList);
    offeredAccountIds = [];
    nextChoice = null;
  });

  Future<void> openForm(
    BuildContext context,
    String? defaultAccountId, {
    RecurringPayment? editing,
  }) => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => RecurringFormScreen(
        currency: currencyInfoFor('RUB'),
        today: today,
        repository: repo,
        idGenerator: FakeIdGenerator(),
        categories: Stream.value([...repo.categories]),
        accounts: Stream.value(accountList),
        defaultAccountId: defaultAccountId,
        editing: editing,
        onPickCategory: (context, type) async => nextChoice,
        onPickAccount: (context, accounts, selectedId) async {
          offeredAccountIds = [for (final a in accounts) a.id];
          return (id: 'card');
        },
      ),
    ),
  );

  /// Открывает раздел и нажимает «Добавить платёж» (или строку [openRow]).
  Future<void> pumpApp(
    WidgetTester tester, {
    String? defaultAccountId,
    String? openRow,
  }) async {
    tester.view.physicalSize = const Size(400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: RecurringSection(
              items: repo.watchAll(),
              today: today,
              onAdd: () => openForm(context, defaultAccountId),
              onOpen: (p) => openForm(context, defaultAccountId, editing: p),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(
        openRow == null
            ? RecurringSection.addButtonKey
            : RecurringSection.rowKey(openRow),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> fill(WidgetTester tester) async {
    await tester.enterText(
      find.byKey(RecurringFormScreen.nameFieldKey),
      'Интернет',
    );
    await tester.enterText(find.byType(EditableText).last, '650');
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.byKey(RecurringFormScreen.saveKey));
    await tester.pumpAndSettle();
  }

  testWidgets('create: payment appears in the list with "next"', (
    tester,
  ) async {
    await pumpApp(tester, defaultAccountId: 'card');
    await fill(tester);
    nextChoice = (category: _food, subcategory: _bread);
    await tester.tap(find.byKey(RecurringFormScreen.categoryKey));
    await tester.pumpAndSettle();
    expect(find.text('Еда · Хлеб'), findsOneWidget);
    // Основной счёт выбран сам.
    expect(find.text('Карта'), findsOneWidget);
    await save(tester);
    expect(find.byType(RecurringFormScreen), findsNothing);
    expect(find.text('Интернет'), findsOneWidget);
    expect(find.textContaining('следующий 10 октября'), findsOneWidget);
    final items = await tester.runAsync(() => repo.watchAll().first);
    final saved = items!.single.payment;
    expect(saved.categoryId, 'food');
    expect(saved.subcategoryId, 'bread');
    expect(saved.accountId, 'card');
    expect(saved.amount, Money.fromMinor(65000, 'RUB'));
    expect(saved.type, TransactionType.expense);
  });

  testWidgets('no category: error and nothing is saved', (tester) async {
    await pumpApp(tester);
    await fill(tester);
    await save(tester);
    expect(find.text(recurringErrorCategory), findsOneWidget);
    expect(find.byType(RecurringFormScreen), findsOneWidget);
    expect(await tester.runAsync(() => repo.watchAll().first), isEmpty);
  });

  testWidgets('switching Expense/Income resets the category', (tester) async {
    await pumpApp(tester);
    nextChoice = (category: _food, subcategory: null);
    await tester.tap(find.byKey(RecurringFormScreen.categoryKey));
    await tester.pumpAndSettle();
    expect(find.text('Еда'), findsOneWidget);
    await tester.tap(find.text(recurringFormIncome));
    await tester.pumpAndSettle();
    expect(find.text('Еда'), findsNothing);
    expect(find.text(recurringFormCategoryHint), findsOneWidget);
  });

  testWidgets('account sheet offers only live accounts of main currency', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(find.text(recurringFormAccountHint), findsOneWidget);
    await tester.tap(find.byKey(RecurringFormScreen.accountKey));
    await tester.pumpAndSettle();
    expect(offeredAccountIds, ['card']);
    expect(find.text('Карта'), findsOneWidget);
  });

  testWidgets('rule error from repository is shown, not thrown', (
    tester,
  ) async {
    await pumpApp(tester);
    await fill(tester);
    // Вид «Доход», а категория расходов: репозиторий отвергнет.
    await tester.tap(find.text(recurringFormIncome));
    await tester.pumpAndSettle();
    nextChoice = (category: _food, subcategory: null);
    await tester.tap(find.byKey(RecurringFormScreen.categoryKey));
    await tester.pumpAndSettle();
    await save(tester);
    expect(
      find.text(
        recurringRuleMessage(
          RecurringRule.typeKindMismatch,
          type: TransactionType.income,
        ),
      ),
      findsOneWidget,
    );
    expect(find.byType(RecurringFormScreen), findsOneWidget);
  });

  Future<void> seed({String id = 'p1'}) => repo.create(
    RecurringPayment(
      id: id,
      title: 'Интернет',
      type: TransactionType.expense,
      amount: Money.fromMinor(65000, 'RUB'),
      categoryId: 'food',
      unit: RepeatUnit.month,
      every: 1,
      startsOn: today,
    ),
  );

  testWidgets('edit: form is prefilled, new amount is saved', (tester) async {
    await seed();
    await pumpApp(tester, openRow: 'p1');
    expect(find.text(recurringFormTitleEdit), findsOneWidget);
    expect(find.text('Интернет'), findsOneWidget);
    expect(find.text('Еда'), findsOneWidget);
    await tester.enterText(find.byType(EditableText).last, '700');
    await save(tester);
    expect(find.byType(RecurringFormScreen), findsNothing);
    final items = await tester.runAsync(() => repo.watchAll().first);
    expect(items!.single.payment.amount, Money.fromMinor(70000, 'RUB'));
    expect(items.single.payment.id, 'p1');
    expect(find.textContaining('700'), findsOneWidget);
  });

  testWidgets('delete: note, snackbar and "Undo" bring it back', (
    tester,
  ) async {
    await seed();
    await pumpApp(tester, openRow: 'p1');
    expect(find.text(recurringDeleteNote), findsOneWidget);
    await tester.tap(find.byKey(RecurringFormScreen.deleteKey));
    await tester.pumpAndSettle();
    expect(find.byType(RecurringFormScreen), findsNothing);
    expect(find.byKey(RecurringSection.emptyKey), findsOneWidget);
    expect(find.text('Платёж «Интернет» удалён'), findsOneWidget);
    await tester.tap(find.text(recurringUndo));
    await tester.pumpAndSettle();
    expect(find.byKey(RecurringSection.rowKey('p1')), findsOneWidget);
  });

  testWidgets('archived category: note is shown until a new one is picked', (
    tester,
  ) async {
    await seed();
    repo.categories[0] = _food.archived(DateTime.utc(2026, 10, 1));
    await pumpApp(tester, openRow: 'p1');
    expect(find.byKey(RecurringFormScreen.archivedNoteKey), findsOneWidget);
    expect(
      find.text(
        recurringRuleMessage(
          RecurringRule.categoryArchived,
          type: TransactionType.expense,
        ),
      ),
      findsOneWidget,
    );
    nextChoice = (
      category: Category.topLevel(
        id: 'home',
        kind: CategoryKind.expense,
        name: 'Дом',
        iconKey: 'tag',
        sortOrder: 1,
      ),
      subcategory: null,
    );
    await tester.tap(find.byKey(RecurringFormScreen.categoryKey));
    await tester.pumpAndSettle();
    expect(find.byKey(RecurringFormScreen.archivedNoteKey), findsNothing);
    expect(find.text('Дом'), findsOneWidget);
  });
}
