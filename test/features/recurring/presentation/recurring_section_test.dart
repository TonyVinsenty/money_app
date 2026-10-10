import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/app/app_scope.dart';
import 'package:money_app/app/balance_tab.dart';
import 'package:money_app/app/browse_scope.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/recurring/domain/recurring_payment.dart';
import 'package:money_app/features/recurring/domain/recurring_repository.dart';
import 'package:money_app/features/recurring/domain/recurring_schedule.dart';
import 'package:money_app/features/recurring/presentation/recurring_section.dart';
import 'package:money_app/features/recurring/presentation/recurring_texts.dart';
import 'package:money_app/features/settings/presentation/app_settings_controller.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

import '../../../support/fakes.dart';
import '../../../support/fixed_clock.dart';

final _minus = String.fromCharCode(0x2212);
final _nbsp = String.fromCharCode(0x00A0);

RecurringPayment _payment(
  String id,
  String title, {
  TransactionType type = TransactionType.expense,
  int minor = 65000,
  RepeatUnit unit = RepeatUnit.month,
  int every = 1,
  DateOnly? startsOn,
  DateOnly? endsOn,
}) => RecurringPayment(
  id: id,
  title: title,
  type: type,
  amount: Money.fromMinor(minor, 'RUB'),
  categoryId: 'cat',
  unit: unit,
  every: every,
  startsOn: startsOn ?? DateOnly(2026, 9, 5),
  endsOn: endsOn,
);

List<RecurringListItem> _items(
  List<RecurringPayment> payments,
  DateOnly today,
) => [
  for (final p in payments)
    RecurringListItem(payment: p, nextDue: nextDueAfter(p, today.addDays(-1))),
];

Future<void> _pumpSection(
  WidgetTester tester,
  List<RecurringPayment> payments, {
  double scale = 1,
  double width = 360,
  DateOnly? today,
}) async {
  tester.view.physicalSize = Size(width, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final day = today ?? DateOnly(2026, 10, 10);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: RecurringSection(
            items: Stream.value(_items(payments, day)),
            today: day,
            onAdd: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('пусто: текст Р1 и кнопка', (tester) async {
    await _pumpSection(tester, const []);
    expect(find.text('Регулярные платежи'), findsOneWidget);
    expect(find.byKey(RecurringSection.emptyKey), findsOneWidget);
    expect(find.text(recurringEmptyText), findsOneWidget);
    expect(find.text('Добавить платёж'), findsOneWidget);
  });

  testWidgets('несколько платежей: порядок по ближайшей дате, тексты Р2', (
    tester,
  ) async {
    await _pumpSection(tester, [
      _payment('a', 'Интернет'), // 5-го -> 5 ноября
      _payment(
        'b',
        'Спортзал',
        unit: RepeatUnit.week,
        startsOn: DateOnly(2026, 10, 2), // пятница
      ), // -> 16 октября
      _payment(
        'c',
        'Страховка',
        unit: RepeatUnit.year,
        startsOn: DateOnly(2025, 3, 12),
      ), // -> 12 марта
    ]);
    expect(
      find.text('Каждый месяц, 5-го · следующий 5 ноября'),
      findsOneWidget,
    );
    expect(
      find.text('Каждую неделю, по пятницам · следующий 16 октября'),
      findsOneWidget,
    );
    expect(
      find.text('Каждый год, 12 марта · следующий 12 марта'),
      findsOneWidget,
    );
    double y(String id) =>
        tester.getTopLeft(find.byKey(RecurringSection.rowKey(id))).dy;
    expect(y('b'), lessThan(y('a')));
    expect(y('a'), lessThan(y('c')));
  });

  testWidgets('доход и расход: знак в тексте и в озвучке', (tester) async {
    final handle = tester.ensureSemantics();
    await _pumpSection(tester, [
      _payment('a', 'Интернет'),
      _payment(
        'b',
        'Зарплата',
        type: TransactionType.income,
        minor: 8500000,
        startsOn: DateOnly(2026, 10, 25),
      ),
    ]);
    expect(find.text('${_minus}650,00$_nbsp₽'), findsOneWidget);
    expect(find.text('+85${_nbsp}000,00$_nbsp₽'), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        'Интернет, расход 650 рублей, каждый месяц 5-го, следующий 5 ноября',
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        'Зарплата, доход 85000 рублей, каждый месяц 25-го, '
        'следующий 25 октября',
      ),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('завершённый внизу и подписан «Завершён»', (tester) async {
    await _pumpSection(tester, [
      _payment('a', 'Аренда', endsOn: DateOnly(2026, 9, 30)),
      _payment('b', 'Яблоко'),
    ]);
    expect(find.text('Завершён'), findsOneWidget);
    double y(String id) =>
        tester.getTopLeft(find.byKey(RecurringSection.rowKey(id))).dy;
    expect(y('b'), lessThan(y('a')));
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('360 dp, шрифт ${scale * 100}%: без переполнения', (
      tester,
    ) async {
      await _pumpSection(tester, [
        _payment(
          'a',
          'Очень длинное название платежа за связь',
          minor: 123456789012,
          every: 3,
        ),
        _payment('b', 'Зарплата', type: TransactionType.income),
      ], scale: scale);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('смена дня без записи в базу обновляет «следующий»', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final settings = AppSettingsController();
    addTearDown(settings.dispose);
    final clock = FixedClock(DateTime(2026, 11, 4, 12));
    final repo = FakeRecurringRepository();
    // «Следующий» из потока посчитан на 4 ноября и больше не обновляется.
    repo.items = _items([_payment('a', 'Интернет')], DateOnly(2026, 11, 4));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: AppScope(
          services: fakeAppServices(
            settings: settings,
            recurring: repo,
            clock: clock,
          ),
          child: const BrowseHost(child: Scaffold(body: BalanceTab())),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byKey(RecurringSection.nextKey('a')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.text('Каждый месяц, 5-го · следующий 5 ноября'),
      findsOneWidget,
    );

    final element = tester.element(find.byType(BalanceTab));
    BrowseScope.controllerOf(element).updateToday(DateOnly(2026, 11, 5));
    await tester.pump();
    expect(
      find.text('Каждый месяц, 5-го · следующий 5 ноября'),
      findsOneWidget,
    );

    BrowseScope.controllerOf(element).updateToday(DateOnly(2026, 11, 6));
    await tester.pump();
    expect(
      find.text('Каждый месяц, 5-го · следующий 5 декабря'),
      findsOneWidget,
    );
  });
}
