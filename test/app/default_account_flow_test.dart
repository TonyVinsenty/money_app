import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/app/app_routes.dart';
import 'package:money_app/app/app_scope.dart';
import 'package:money_app/app/balance_tab.dart';
import 'package:money_app/core/money/currency_catalog.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/accounts/presentation/account_form_screen.dart';
import 'package:money_app/features/accounts/presentation/account_screen.dart';
import 'package:money_app/features/accounts/presentation/account_texts.dart';
import 'package:money_app/features/accounts/presentation/accounts_section.dart';
import 'package:money_app/features/settings/presentation/app_settings_controller.dart';

import '../support/fakes.dart';

/// Основной счёт (шаг 5.11): вкладка «Баланс», экран счёта и форма.
Account _acc(String id, String name, {String currency = 'RUB'}) => Account(
  id: id,
  name: name,
  iconKey: 'card',
  openingBalance: Money.zero(currency),
  sortOrder: 0,
  currencyDigits: 2,
);

late AppSettingsController _settings;

Future<void> _pump(WidgetTester tester, InMemoryAccountsRepository repo) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  _settings = AppSettingsController();
  addTearDown(_settings.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      onGenerateRoute: onGenerateAppRoute,
      home: AppScope(
        services: fakeAppServices(settings: _settings, accounts: repo),
        child: const Scaffold(body: BalanceTab()),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

Future<void> _tapKey(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

Future<void> _createAccount(WidgetTester tester, String name) async {
  await _tapKey(tester, AccountsSection.addButtonKey);
  await tester.enterText(find.byKey(AccountFormScreen.nameFieldKey), name);
  await _tapKey(tester, AccountFormScreen.saveButtonKey);
  // Форма не ждёт «довеска» с основным счётом: даём ему закончиться.
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
  await tester.pumpAndSettle();
}

Finder get _label => find.text(accountDefaultLabel);

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru');
  });

  testWidgets('первый созданный счёт - основной, второй - нет', (tester) async {
    final repo = InMemoryAccountsRepository();
    await _pump(tester, repo);
    await _createAccount(tester, 'Карта');
    expect(_settings.defaultAccountId, repo.all.single.id);
    expect(_label, findsOneWidget);

    await _createAccount(tester, 'Наличные');
    expect(repo.all, hasLength(2));
    expect(_settings.defaultAccountId, repo.all.first.id);
    expect(_label, findsOneWidget);
  });

  testWidgets('смена основного на экране счёта', (tester) async {
    final repo = InMemoryAccountsRepository([
      _acc('a', 'Карта'),
      _acc('b', 'Наличные'),
    ]);
    await _pump(tester, repo);
    await _settings.setDefaultAccountId('a');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Наличные'));
    await tester.pumpAndSettle();
    expect(find.byKey(AccountScreen.defaultHintKey), findsNothing);
    await _tapKey(tester, AccountScreen.makeDefaultKey);
    expect(_settings.defaultAccountId, 'b');
    // На экране: пометка есть, кнопки больше нет.
    expect(find.text(accountDefaultHint), findsOneWidget);
    expect(find.byKey(AccountScreen.makeDefaultKey), findsNothing);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(_label, findsOneWidget);
    expect(
      find.descendant(
        of: find.ancestor(
          of: find.text('Наличные'),
          matching: find.byType(InkWell),
        ),
        matching: _label,
      ),
      findsOneWidget,
    );
  });

  testWidgets('у основного счёта кнопки нет; у счёта в другой валюте - тоже', (
    tester,
  ) async {
    final repo = InMemoryAccountsRepository([
      _acc('a', 'Карта'),
      _acc('u', 'Доллары', currency: 'USD'),
    ]);
    await _pump(tester, repo);
    await _settings.setDefaultAccountId('a');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Карта'));
    await tester.pumpAndSettle();
    expect(find.byKey(AccountScreen.makeDefaultKey), findsNothing);
    expect(find.text(accountDefaultHint), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Доллары'));
    await tester.pumpAndSettle();
    expect(find.byKey(AccountScreen.makeDefaultKey), findsNothing);
    expect(find.text(accountDefaultHint), findsNothing);
  });

  testWidgets('архив основного: основным становится следующий счёт той же '
      'валюты, сообщение; бывший основной после возврата не основной', (
    tester,
  ) async {
    final repo = InMemoryAccountsRepository([
      _acc('u', 'Доллары', currency: 'USD'),
      _acc('a', 'Карта'),
      _acc('b', 'Наличные'),
    ]);
    await _pump(tester, repo);
    await _settings.setDefaultAccountId('a');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Карта'));
    await tester.pumpAndSettle();
    await _tapKey(tester, AccountScreen.archiveKey);
    expect(_settings.defaultAccountId, 'b');
    expect(find.text(accountDefaultChangedMessage('Наличные')), findsOneWidget);
    expect(_label, findsOneWidget);

    // Вернули «Карту»: основным остаётся «Наличные».
    await tester.tap(find.text(accountUndoAction));
    await tester.pumpAndSettle();
    expect(_settings.defaultAccountId, 'b');
    expect(_label, findsOneWidget);
  });

  testWidgets('архив основного без замены: ключ остаётся, сообщение '
      'обычное', (tester) async {
    final repo = InMemoryAccountsRepository([
      _acc('a', 'Карта'),
      _acc('u', 'Доллары', currency: 'USD'),
    ]);
    await _pump(tester, repo);
    await _settings.setDefaultAccountId('a');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Карта'));
    await tester.pumpAndSettle();
    await _tapKey(tester, AccountScreen.archiveKey);
    expect(_settings.defaultAccountId, 'a');
    expect(find.text(accountArchivedMessage('Карта')), findsOneWidget);
    expect(_label, findsNothing);
  });

  testWidgets('новый USD-счёт не отнимает основной у живого RUB-счёта', (
    tester,
  ) async {
    final repo = InMemoryAccountsRepository([_acc('a', 'Карта')]);
    await _pump(tester, repo);
    await _settings.setDefaultAccountId('a');
    await _settings.setMainCurrency(catalogCurrency('USD')!);
    final usd = _acc('u', 'Доллары', currency: 'USD');
    await tester.runAsync(() async {
      await repo.create(usd);
      await adoptFirstAccountAsDefault(usd, repo, _settings);
    });
    expect(_settings.defaultAccountId, 'a');

    await _settings.setMainCurrency(catalogCurrency('RUB')!);
    await tester.pumpAndSettle();
    expect(_label, findsOneWidget);
  });

  testWidgets('основная валюта сменилась: пометки нет, вернули - есть', (
    tester,
  ) async {
    final repo = InMemoryAccountsRepository([_acc('a', 'Карта')]);
    await _pump(tester, repo);
    await _settings.setDefaultAccountId('a');
    await tester.pumpAndSettle();
    expect(_label, findsOneWidget);

    await _settings.setMainCurrency(catalogCurrency('USD')!);
    await tester.pumpAndSettle();
    expect(_label, findsNothing);
    // Запись в настройках не стёрта.
    expect(_settings.defaultAccountId, 'a');

    await _settings.setMainCurrency(catalogCurrency('RUB')!);
    await tester.pumpAndSettle();
    expect(_label, findsOneWidget);
  });

  testWidgets('ключ на несуществующий счёт - основного нет', (tester) async {
    final repo = InMemoryAccountsRepository([_acc('a', 'Карта')]);
    await _pump(tester, repo);
    await _settings.setDefaultAccountId('gone');
    await tester.pumpAndSettle();
    expect(_label, findsNothing);
  });

  test(
    'первый счёт в USD при основном рубле - не основной; рублёвый - да',
    () async {
      final repo = InMemoryAccountsRepository();
      final settings = AppSettingsController();
      addTearDown(settings.dispose);

      final usd = _acc('u', 'Доллары', currency: 'USD');
      await repo.create(usd);
      await adoptFirstAccountAsDefault(usd, repo, settings);
      expect(settings.defaultAccountId, isNull);

      final rub = _acc('r', 'Карта');
      await repo.create(rub);
      await adoptFirstAccountAsDefault(rub, repo, settings);
      expect(settings.defaultAccountId, 'r');

      // Уже есть основной: следующий рублёвый им не становится.
      final other = _acc('o', 'Наличные');
      await repo.create(other);
      await adoptFirstAccountAsDefault(other, repo, settings);
      expect(settings.defaultAccountId, 'r');
    },
  );

  testWidgets('строка основного счёта читается скринридером', (tester) async {
    final repo = InMemoryAccountsRepository([_acc('a', 'Карта')]);
    await _pump(tester, repo);
    await _settings.setDefaultAccountId('a');
    await tester.pumpAndSettle();
    final handle = tester.ensureSemantics();
    expect(
      find.bySemanticsLabel(RegExp('^Карта, основной, остаток')),
      findsOneWidget,
    );
    handle.dispose();
  });
}
