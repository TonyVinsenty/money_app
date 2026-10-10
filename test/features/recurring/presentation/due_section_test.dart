import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/app/app_scope.dart';
import 'package:money_app/app/due_actions.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/core/ui/transaction_rule_text.dart';
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/recurring/domain/recurring_payment.dart';
import 'package:money_app/features/recurring/presentation/due_section.dart';
import 'package:money_app/features/recurring/presentation/recurring_texts.dart';
import 'package:money_app/features/settings/presentation/app_settings_controller.dart';
import 'package:money_app/features/transactions/domain/transaction_rules.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

import '../../../support/fakes.dart';
import '../../../support/fixed_clock.dart';
import '../../../support/in_memory_recurring_repository.dart';

final _food = Category.topLevel(
  id: 'food',
  kind: CategoryKind.expense,
  name: 'Связь',
  iconKey: 'tag',
  sortOrder: 0,
);

Account _card({bool archived = false}) => Account(
  id: 'card',
  name: 'Карта',
  iconKey: 'card',
  openingBalance: Money.fromMinor(0, 'RUB'),
  sortOrder: 0,
  currencyDigits: 2,
  archivedAt: archived ? DateTime.utc(2026, 10, 1) : null,
);

RecurringPayment _payment(String id, String title, DateOnly startsOn) =>
    RecurringPayment(
      id: id,
      title: title,
      type: TransactionType.expense,
      amount: Money.fromMinor(65000, 'RUB'),
      categoryId: 'food',
      accountId: 'card',
      unit: RepeatUnit.month,
      every: 1,
      startsOn: startsOn,
    );

/// Категории для «Сохранено: ... · Связь».
class _Cats extends InMemoryCategoriesRepository {
  _Cats(super.initial);

  @override
  Future<Category?> findById(String id) async =>
      all.where((c) => c.id == id).firstOrNull;
}

// Репозиторий создаётся лениво, уже внутри testWidgets: потоки, созданные в
// setUp, живут в «настоящей» зоне, и tester.pump не успевает доставить им
// события.
InMemoryRecurringRepository? _created;
InMemoryRecurringRepository get repo {
  final existing = _created;
  if (existing != null) return existing;
  final clock = FixedClock(DateTime.utc(2026, 10, 10, 12));
  late final InMemoryRecurringRepository r;
  r = InMemoryRecurringRepository(
    clock,
    InMemoryLinkedTransactions(
      (id) => [...r.categories].where((c) => c.id == id).firstOrNull,
    ),
  );
  return _created = r
    ..categories.add(_food)
    ..accounts.add(_card());
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  final today = DateOnly(2026, 10, 10);
  late AppSettingsController settings;
  late List<RecurringPayment> edited;

  setUp(() {
    _created = null;
    settings = AppSettingsController();
    addTearDown(settings.dispose);
    edited = [];
  });

  Future<void> seed(List<RecurringPayment> payments) async {
    for (final p in payments) {
      await repo.create(p);
    }
    await repo.materializeDue(today);
  }

  Future<void> pump(
    WidgetTester tester, {
    double scale = 1,
    double width = 400,
    bool streamArchivedCategory = false,
    bool archivedAccount = false,
  }) async {
    tester.view.physicalSize = Size(width, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final services = fakeAppServices(
      settings: settings,
      recurring: repo,
      transactions: repo.transactions,
      categories: _Cats([_food]),
      clock: FixedClock(DateTime.utc(2026, 10, 10, 12)),
    );
    final shownCategories = [
      streamArchivedCategory
          ? _food.archived(DateTime.utc(2026, 10, 1))
          : _food,
    ];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: AppScope(
          services: services,
          child: Builder(
            builder: (context) => Scaffold(
              body: SingleChildScrollView(
                child: DueSection(
                  dues: repo.watchDue(),
                  categories: Stream.value(shownCategories),
                  accounts: Stream.value([_card(archived: archivedAccount)]),
                  today: today,
                  onPay:
                      (
                        due, {
                        required amount,
                        required day,
                        required accountId,
                      }) => DueActions(services).pay(
                        context,
                        due,
                        amount: amount,
                        day: day,
                        accountId: accountId,
                      ),
                  onSkip: (due) => DueActions(services).skip(context, due),
                  onEdit: edited.add,
                  onPickAccount: (context, accounts, selectedId) async =>
                      (id: null),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  String money(int minor) => formatMoney(Money.fromMinor(minor, 'RUB'));

  testWidgets('нет записей: блока нет', (tester) async {
    await pump(tester);
    expect(find.byKey(DueSection.titleKey), findsNothing);
  });

  testWidgets('заголовок с числом, строки и дни', (tester) async {
    await seed([
      _payment('a', 'Интернет', today),
      _payment('b', 'Аренда', today.addDays(-1)),
      _payment('c', 'Вода', DateOnly(2026, 10, 5)),
    ]);
    await pump(tester);
    expect(find.text('К оплате (3)'), findsOneWidget);
    expect(find.text('Интернет · ${money(65000)}'), findsOneWidget);
    expect(find.text('Сегодня'), findsOneWidget);
    expect(find.text('Вчера'), findsOneWidget);
    expect(find.text('5 октября'), findsOneWidget);
    expect(find.text('Оплачено'), findsNWidgets(3));
    expect(find.text('Пропустить'), findsNWidgets(3));
  });

  testWidgets('озвучка: кнопки с названием, в строке - доход или расход', (
    tester,
  ) async {
    await seed([_payment('a', 'Интернет', today)]);
    final handle = tester.ensureSemantics();
    await pump(tester);
    expect(find.bySemanticsLabel('Оплачено: Интернет'), findsOneWidget);
    expect(find.bySemanticsLabel('Пропустить: Интернет'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('^Интернет, расход .*сегодня')),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('«Оплачено»: строка исчезла, операция с суммой, «Отменить»', (
    tester,
  ) async {
    await seed([_payment('a', 'Интернет', today)]);
    await pump(tester);
    await tester.tap(find.text('Оплачено'));
    await tester.pumpAndSettle();
    expect(find.byKey(DueSection.titleKey), findsNothing);
    final tx = repo.transactions.items.values.single;
    expect(tx.amount.minorUnits, 65000);
    expect(tx.note, 'Интернет');
    expect(
      find.text('Сохранено: расход ${money(65000)} · Связь'),
      findsOneWidget,
    );

    await tester.tap(find.text('Отменить'));
    await tester.pumpAndSettle();
    expect(repo.transactions.deleted, contains(tx.id));
    expect(find.text('К оплате (1)'), findsOneWidget);
  });

  testWidgets('«Пропустить» и «Отменить»', (tester) async {
    await seed([_payment('a', 'Интернет', today)]);
    await pump(tester);
    await tester.tap(find.text('Пропустить'));
    await tester.pumpAndSettle();
    expect(find.byKey(DueSection.titleKey), findsNothing);
    expect(
      find.text('Платёж «Интернет» за 10 октября пропущен'),
      findsOneWidget,
    );

    await tester.tap(find.text('Отменить'));
    await tester.pumpAndSettle();
    expect(find.text('К оплате (1)'), findsOneWidget);
  });

  testWidgets('лист «Оплата»: другая сумма', (tester) async {
    await seed([_payment('a', 'Интернет', today)]);
    await pump(tester);
    await tester.tap(find.text('Интернет · ${money(65000)}'));
    await tester.pumpAndSettle();
    expect(find.text('Оплата: Интернет'), findsOneWidget);
    expect(find.text('Сумма'), findsOneWidget);
    expect(find.text('Дата'), findsOneWidget);
    expect(find.text('Счёт'), findsOneWidget);
    expect(find.text('Карта'), findsOneWidget);

    await tester.enterText(
      find.descendant(
        of: find.byKey(DueSection.sheetAmountKey),
        matching: find.byType(TextField),
      ),
      '700',
    );
    await tester.tap(find.byKey(DueSection.sheetPayKey));
    await tester.pumpAndSettle();
    expect(find.text('Оплата: Интернет'), findsNothing);
    final tx = repo.transactions.items.values.single;
    expect(tx.amount.minorUnits, 70000);
    expect(tx.occurredOn, today);
    expect(tx.accountId, 'card');
    // Платёж не изменился.
    expect((await repo.findById('a'))!.amount.minorUnits, 65000);
  });

  testWidgets('архивная категория: пояснение и «Изменить»', (tester) async {
    await seed([_payment('a', 'Интернет', today)]);
    await pump(tester, streamArchivedCategory: true);
    expect(find.text(dueCategoryArchivedText('Связь')), findsOneWidget);
    expect(find.text('Оплачено'), findsNothing);
    await tester.tap(find.text('Изменить'));
    expect(edited.single.id, 'a');
    // «Пропустить» остаётся.
    expect(find.text('Пропустить'), findsOneWidget);
  });

  testWidgets('архивный счёт: пояснение и «Изменить»', (tester) async {
    await seed([_payment('a', 'Интернет', today)]);
    await pump(tester, archivedAccount: true);
    expect(find.text(dueAccountArchivedText('Карта')), findsOneWidget);
    expect(find.text('Оплачено'), findsNothing);
    expect(find.text('Изменить'), findsOneWidget);
  });

  testWidgets('ошибка оплаты показана текстом, запись остаётся', (
    tester,
  ) async {
    await seed([_payment('a', 'Интернет', today)]);
    // Список категорий у блока «свежий», а в базе категория уже в архиве.
    repo.categories[0] = _food.archived(DateTime.utc(2026, 10, 1));
    await pump(tester);
    await tester.tap(find.text('Оплачено'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        transactionRuleMessage(
          TransactionRule.categoryArchived,
          type: TransactionType.expense,
        ),
      ),
      findsOneWidget,
    );
    expect(find.text('К оплате (1)'), findsOneWidget);
  });

  testWidgets('360 dp и 200 %: без переполнения', (tester) async {
    await seed([
      _payment('a', 'Квартплата и коммунальные услуги', today),
      _payment('b', 'Аренда', today.addDays(-1)),
    ]);
    await pump(tester, scale: 2, width: 360);
    expect(tester.takeException(), isNull);
    await tester.tap(
      find.text('Квартплата и коммунальные услуги · ${money(65000)}'),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(DueSection.sheetPayKey), findsOneWidget);
  });
}
