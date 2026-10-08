import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/app/app_routes.dart';
import 'package:money_app/app/app_scope.dart';
import 'package:money_app/app/balance_tab.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/ui/category_rule_text.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/accounts/presentation/account_form_screen.dart';
import 'package:money_app/features/accounts/presentation/account_texts.dart';
import 'package:money_app/features/accounts/presentation/accounts_section.dart';
import 'package:money_app/features/settings/presentation/app_settings_controller.dart';

import '../../../support/fake_id_generator.dart';
import '../../../support/fakes.dart';

Money rub(int minor) => Money.fromMinor(minor, 'RUB');

Account acc(String id, String name, {String icon = 'card'}) => Account(
  id: id,
  name: name,
  iconKey: icon,
  openingBalance: Money.zero('RUB'),
  sortOrder: 0,
);

void useSmallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Вкладка «Баланс» с настоящим маршрутом формы.
Future<void> pumpTab(
  WidgetTester tester,
  InMemoryAccountsRepository repo,
) async {
  useSmallScreen(tester);
  final settings = AppSettingsController();
  addTearDown(settings.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      onGenerateRoute: onGenerateAppRoute,
      home: AppScope(
        services: fakeAppServices(settings: settings, accounts: repo),
        child: const Scaffold(body: BalanceTab()),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

Future<void> openForm(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(AccountsSection.addButtonKey));
  await tester.tap(find.byKey(AccountsSection.addButtonKey));
  await tester.pumpAndSettle();
}

Future<void> save(WidgetTester tester) async {
  await tester.tap(find.byKey(AccountFormScreen.saveButtonKey));
  await tester.pumpAndSettle();
}

Future<void> typeName(WidgetTester tester, String text) =>
    tester.enterText(find.byKey(AccountFormScreen.nameFieldKey), text);

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  group('новый счёт', () {
    testWidgets('кнопка открывает форму; с остатком: счёт в списке и «Всего»', (
      tester,
    ) async {
      final repo = InMemoryAccountsRepository();
      await pumpTab(tester, repo);
      await openForm(tester);
      expect(find.text(accountFormCreateTitle), findsOneWidget);
      expect(find.text(accountFormBalanceHelper), findsOneWidget);
      expect(find.text(accountFormMinusHelper), findsOneWidget);

      await typeName(tester, '  Карта ');
      await tester.enterText(
        find.byKey(AccountFormScreen.balanceFieldKey),
        '150,50',
      );
      await save(tester);

      final saved = repo.all.single;
      expect(saved.id, 'id-1');
      expect(saved.name, 'Карта');
      expect(saved.iconKey, 'card');
      expect(saved.sortOrder, 0);
      expect(saved.openingBalance, rub(15050));
      // Форма закрыта, счёт в списке, «Всего» пересчитано.
      expect(find.byType(AccountFormScreen), findsNothing);
      expect(find.text('Карта'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(AccountsSection.totalKey)).data,
        '+${formatMoney(rub(15050))}',
      );
    });

    testWidgets('кнопка видна и когда счета уже есть; порядок растёт', (
      tester,
    ) async {
      final repo = InMemoryAccountsRepository([acc('a', 'Карта')]);
      await pumpTab(tester, repo);
      expect(find.byKey(AccountsSection.addButtonKey), findsOneWidget);
      await openForm(tester);
      await typeName(tester, 'Наличные');
      await tester.tap(find.byKey(const ValueKey('icon-cash')));
      await tester.pump();
      await save(tester);

      final added = repo.all.last;
      expect(added.sortOrder, 1);
      expect(added.iconKey, 'cash');
      expect(added.openingBalance, Money.zero('RUB'));
    });

    testWidgets('пустая сумма — 0', (tester) async {
      final repo = InMemoryAccountsRepository();
      await pumpTab(tester, repo);
      await openForm(tester);
      await typeName(tester, 'Копилка');
      await save(tester);
      expect(repo.all.single.openingBalance, Money.zero('RUB'));
    });

    testWidgets('«Минус (долг)» делает остаток отрицательным', (tester) async {
      final repo = InMemoryAccountsRepository();
      await pumpTab(tester, repo);
      await openForm(tester);
      await typeName(tester, 'Кредитка');
      await tester.enterText(
        find.byKey(AccountFormScreen.balanceFieldKey),
        '1000',
      );
      await tester.tap(find.byKey(AccountFormScreen.minusSwitchKey));
      await tester.pump();
      await save(tester);

      expect(repo.all.single.openingBalance, rub(-100000));
      expect(
        tester.widget<Text>(find.byKey(AccountsSection.totalKey)).data,
        formatMoney(rub(-100000)),
      );
    });

    testWidgets('пустое имя: текст под полем, счёт не создан', (tester) async {
      final repo = InMemoryAccountsRepository();
      await pumpTab(tester, repo);
      await openForm(tester);
      await typeName(tester, '   ');
      await save(tester);
      expect(find.text('Введите название счёта'), findsOneWidget);
      expect(find.byType(AccountFormScreen), findsOneWidget);
      expect(repo.all, isEmpty);
    });

    testWidgets('дубль имени: текст под полем', (tester) async {
      final repo = InMemoryAccountsRepository([acc('a', 'Карта')]);
      await pumpTab(tester, repo);
      await openForm(tester);
      await typeName(tester, 'карта');
      await save(tester);
      expect(
        find.text('Такой счёт уже есть. Выберите другое название'),
        findsOneWidget,
      );
      expect(repo.all, hasLength(1));
    });

    testWidgets('ошибка суммы — текст под полем, запись не идёт', (
      tester,
    ) async {
      final repo = InMemoryAccountsRepository();
      await pumpTab(tester, repo);
      await openForm(tester);
      await typeName(tester, 'Карта');
      await tester.enterText(
        find.byKey(AccountFormScreen.balanceFieldKey),
        '99999999999999',
      );
      await save(tester);
      expect(find.textContaining('Слишком большая сумма'), findsOneWidget);
      expect(repo.all, isEmpty);
    });

    testWidgets('сбой записи: общий текст, форма открыта', (tester) async {
      final repo = InMemoryAccountsRepository()..failWith = Exception('db');
      await pumpTab(tester, repo);
      await openForm(tester);
      await typeName(tester, 'Карта');
      await save(tester);
      expect(find.text(categorySaveFailedText), findsOneWidget);
      expect(find.byType(AccountFormScreen), findsOneWidget);
    });
  });

  group('правка счёта', () {
    Future<void> pumpEdit(
      WidgetTester tester,
      InMemoryAccountsRepository repo, {
      double scale = 1,
    }) async {
      useSmallScreen(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(360, 800),
              textScaler: TextScaler.linear(scale),
            ),
            child: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => AccountFormScreen(
                        accounts: repo,
                        idGenerator: FakeIdGenerator(),
                        currency: 'RUB',
                        editing: repo.all.first,
                      ),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('меняет имя и значок; остатка и переключателя нет', (
      tester,
    ) async {
      final repo = InMemoryAccountsRepository([acc('a', 'Карта')]);
      await pumpEdit(tester, repo);
      expect(find.text(accountFormEditTitle), findsOneWidget);
      expect(find.byKey(AccountFormScreen.balanceFieldKey), findsNothing);
      expect(find.byKey(AccountFormScreen.minusSwitchKey), findsNothing);

      await typeName(tester, 'Вклад');
      await tester.tap(find.byKey(const ValueKey('icon-deposit')));
      await tester.pump();
      await save(tester);

      expect(repo.all.single.name, 'Вклад');
      expect(repo.all.single.iconKey, 'deposit');
      expect(find.byType(AccountFormScreen), findsNothing);
    });

    for (final scale in [1.0, 2.0]) {
      testWidgets('360 dp, шрифт ${scale * 100} %: без переполнения', (
        tester,
      ) async {
        final repo = InMemoryAccountsRepository([acc('a', 'Карта')]);
        await pumpEdit(tester, repo, scale: scale);
        expect(tester.takeException(), isNull);
      });
    }
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('новая форма на 360 dp, шрифт ${scale * 100} %: без ошибок', (
      tester,
    ) async {
      useSmallScreen(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(360, 800),
              textScaler: TextScaler.linear(scale),
            ),
            child: AccountFormScreen(
              accounts: InMemoryAccountsRepository(),
              idGenerator: FakeIdGenerator(),
              currency: 'RUB',
            ),
          ),
        ),
      );
      await typeName(tester, 'Очень длинное название счёта для проверки');
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
}
