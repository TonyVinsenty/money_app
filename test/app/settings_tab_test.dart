import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/app/app_routes.dart';
import 'package:money_app/app/app_scope.dart';
import 'package:money_app/app/app_shell.dart';
import 'package:money_app/app/app_tabs.dart';
import 'package:money_app/app/browse_scope.dart';
import 'package:money_app/core/money/currency.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/accounts/presentation/account_texts.dart';
import 'package:money_app/features/categories/presentation/categories_screen.dart';
import 'package:money_app/features/settings/presentation/app_settings_controller.dart';
import 'package:money_app/features/settings/presentation/settings_screen.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

import '../support/fakes.dart';
import '../support/fixed_clock.dart';

/// Репозиторий операций для "Главной": ей нужны только итоги месяца.
class _TotalsOnlyRepository extends FakeTransactionsRepository {
  @override
  Stream<Money> watchTotal({
    required TransactionType type,
    required DateRange period,
    String currency = rubCurrencyCode,
  }) => Stream.value(Money.zero(currency));

  @override
  Stream<List<Transaction>> watchInPeriod(
    DateRange period, {
    String currency = rubCurrencyCode,
  }) => Stream.value(const []);
}

/// Каркас с настоящими вкладками и фейковыми репозиториями. Тема берётся из
/// настроек, как в `MoneyApp`: так видно, что выбор в «Настройках» доходит
/// до `MaterialApp`.
Future<AppSettingsController> _pump(
  WidgetTester tester, {
  FixedClock? clock,
}) async {
  final settings = AppSettingsController();
  addTearDown(settings.dispose);
  // Экран «Категории» читает список сразу при открытии.
  final categories = InMemoryCategoriesRepository(const []);
  addTearDown(categories.dispose);
  await tester.pumpWidget(
    ListenableBuilder(
      listenable: settings,
      builder: (context, _) => MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: settings.themeMode,
        onGenerateRoute: onGenerateAppRoute,
        home: AppScope(
          services: fakeAppServices(
            settings: settings,
            categories: categories,
            clock: clock,
            transactions: _TotalsOnlyRepository(),
          ),
          child: BrowseHost(child: AppShell(tabs: defaultAppTabs)),
        ),
      ),
    ),
  );
  await tester.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Настройки'),
    ),
  );
  await tester.pumpAndSettle();
  return settings;
}

ThemeMode _groupValue(WidgetTester tester) => tester
    .widget<RadioGroup<ThemeMode>>(find.byType(RadioGroup<ThemeMode>))
    .groupValue!;

ThemeMode _appThemeMode(WidgetTester tester) =>
    tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode!;

void main() {
  // «Главная» показывает название месяца в подписи итога, даже пока операций
  // нет, поэтому русская локаль нужна и здесь (в приложении её ставит main).
  setUpAll(() async {
    await initializeDateFormatting('ru');
  });

  testWidgets('«Настройки»: заглушки нет, тема «как в системе» выбрана', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.textContaining('Здесь будут'), findsNothing);
    expect(find.text('Категории'), findsOneWidget);
    expect(_groupValue(tester), ThemeMode.system);
  });

  testWidgets('выбор темы меняет тему приложения и отметку в списке', (
    tester,
  ) async {
    final settings = await _pump(tester);

    await tester.tap(find.text('Тёмная'));
    await tester.pumpAndSettle();
    expect(settings.themeMode, ThemeMode.dark);
    expect(_appThemeMode(tester), ThemeMode.dark);
    expect(_groupValue(tester), ThemeMode.dark);

    await tester.tap(find.text('Светлая'));
    await tester.pumpAndSettle();
    expect(_appThemeMode(tester), ThemeMode.light);
  });

  testWidgets('пункт «Категории» открывает экран, «Назад» возвращает', (
    tester,
  ) async {
    await _pump(tester);

    await tester.tap(find.text('Категории'));
    await tester.pumpAndSettle();
    expect(find.byType(CategoriesScreen), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text(categoriesScreenTitle),
      ),
      findsOneWidget,
    );

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(CategoriesScreen), findsNothing);
    expect(find.text('Тема'), findsOneWidget);
  });

  testWidgets('подпись экспорта следует за днём в настройках и часами', (
    tester,
  ) async {
    final settings = await _pump(
      tester,
      clock: FixedClock(DateTime(2027, 1, 2, 12)),
    );
    expect(find.text('Последний экспорт: ещё не было'), findsOneWidget);

    // Как после успешного «Поделиться»: экран сообщает вкладке, вкладка
    // записывает сегодняшний день из часов приложения.
    tester.widget<SettingsScreen>(find.byType(SettingsScreen)).onExportShared();
    await tester.pump();
    expect(settings.lastExportDay, DateOnly(2027, 1, 2));
    expect(find.text('Последний экспорт: 2 января'), findsOneWidget);

    settings.setLastExportDay(DateOnly(2026, 12, 31));
    await tester.pump();
    expect(
      find.textContaining('Последний экспорт: 31 декабря 2026'),
      findsOneWidget,
    );
  });

  testWidgets('вкладка «Баланс» показывает счета, а не заглушку', (
    tester,
  ) async {
    await _pump(tester);

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Баланс'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(tabInDevelopmentLabel), findsNothing);
    expect(find.text(accountsSectionTitle), findsOneWidget);
  });
}
