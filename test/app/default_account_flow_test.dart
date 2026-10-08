import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  // «Довесок» с основным счётом идёт в фоне на настоящем времени (fakeAsync
  // его не двигает), поэтому ждём 20 мс настоящего времени.
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

    // «Вернуть» отменяет всё: «Карта» снова в списке и снова основная.
    await tester.tap(find.text(accountUndoAction));
    await tester.pumpAndSettle();
    expect(repo.all.firstWhere((a) => a.id == 'a').isArchived, isFalse);
    expect(_settings.defaultAccountId, 'a');
    expect(_label, findsOneWidget);
  });

  testWidgets('«Вернуть» не трогает основной, если его уже выбрали руками', (
    tester,
  ) async {
    final repo = InMemoryAccountsRepository([
      _acc('a', 'Карта'),
      _acc('b', 'Наличные'),
      _acc('c', 'Копилка'),
    ]);
    await _pump(tester, repo);
    await _settings.setDefaultAccountId('a');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Карта'));
    await tester.pumpAndSettle();
    await _tapKey(tester, AccountScreen.archiveKey);
    expect(_settings.defaultAccountId, 'b');

    await _settings.setDefaultAccountId('c');
    await tester.tap(find.text(accountUndoAction));
    await tester.pumpAndSettle();
    expect(_settings.defaultAccountId, 'c');
  });

  testWidgets('«Сделать основным» озвучивается', (tester) async {
    final announcements = <String>[];
    tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(
      SystemChannels.accessibility,
      (message) async {
        final map = message as Map<Object?, Object?>;
        if (map['type'] == 'announce') {
          final data = map['data']! as Map<Object?, Object?>;
          announcements.add(data['message']! as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockDecodedMessageHandler<dynamic>(
            SystemChannels.accessibility,
            null,
          ),
    );
    final repo = InMemoryAccountsRepository([_acc('a', 'Карта')]);
    await _pump(tester, repo);
    await tester.tap(find.text('Карта'));
    await tester.pumpAndSettle();
    await _tapKey(tester, AccountScreen.makeDefaultKey);
    expect(announcements, [accountMadeDefaultAnnouncement('Карта')]);
  });

  testWidgets('двойной тап по «Операции» вызывает переход один раз', (
    tester,
  ) async {
    var calls = 0;
    final repo = InMemoryAccountsRepository([_acc('a', 'Карта')]);
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: AccountScreen(
          accounts: repo,
          accountId: 'a',
          onEdit: (_) async {},
          onShowTransactions: (_) => calls++,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    final button = find.byKey(AccountScreen.operationsKey);
    await tester.tap(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(calls, 1);
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
