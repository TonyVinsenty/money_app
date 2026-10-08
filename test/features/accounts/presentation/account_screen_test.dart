import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/app/app_routes.dart';
import 'package:money_app/app/app_scope.dart';
import 'package:money_app/app/balance_tab.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/money/currency_catalog.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/ui/category_rule_text.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/accounts/domain/accounts_repository.dart';
import 'package:money_app/features/accounts/presentation/account_adjust_dialog.dart';
import 'package:money_app/features/accounts/presentation/account_form_screen.dart';
import 'package:money_app/features/accounts/presentation/account_screen.dart';
import 'package:money_app/features/accounts/presentation/account_texts.dart';
import 'package:money_app/features/accounts/presentation/accounts_section.dart';
import 'package:money_app/features/settings/presentation/app_settings_controller.dart';

import '../../../support/fakes.dart';

Money rub(int minor) => Money.fromMinor(minor, 'RUB');

Account acc(String id, String name, {int opening = 0}) => Account(
  id: id,
  name: name,
  iconKey: 'card',
  openingBalance: rub(opening),
  sortOrder: 0,
);

Future<void> pumpTab(
  WidgetTester tester,
  InMemoryAccountsRepository repo, {
  double textScale = 1,
}) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final settings = AppSettingsController();
  addTearDown(settings.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      onGenerateRoute: onGenerateAppRoute,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: AppScope(
        services: fakeAppServices(settings: settings, accounts: repo),
        child: const Scaffold(body: BalanceTab()),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

Future<void> openAccount(WidgetTester tester, String name) async {
  await tester.tap(find.text(name));
  await tester.pumpAndSettle();
}

Future<void> tapKey(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

String? totalText(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(AccountsSection.totalKey)).data;

/// Репозиторий, потоки которого ничего не отдают: счёт «ещё грузится».
class _NeverLoadedRepository extends Fake implements AccountsRepository {
  @override
  Stream<List<Account>> watchAll() => StreamController<List<Account>>().stream;

  @override
  Stream<Map<String, Money>> watchBalances() =>
      StreamController<Map<String, Money>>().stream;
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('счёт в своей валюте с 4 знаками: экран в её знаках', (
    tester,
  ) async {
    final abcInfo = currencyInfoFor('ABC', digits: 4);
    final repo = InMemoryAccountsRepository([
      Account(
        id: 'c',
        name: 'Своя',
        iconKey: 'card',
        currencyDigits: 4,
        openingBalance: Money.fromMinor(15000, 'ABC'),
        sortOrder: 0,
      ),
    ]);
    await pumpTab(tester, repo);
    await openAccount(tester, 'Своя');
    expect(
      tester.widget<Text>(find.byKey(AccountScreen.balanceKey)).data,
      formatMoney(Money.fromMinor(15000, 'ABC'), currency: abcInfo),
    );
    await tapKey(tester, AccountScreen.archiveKey);
    expect(
      find.text(
        accountArchiveDialogText(Money.fromMinor(15000, 'ABC'), abcInfo),
      ),
      findsOneWidget,
    );
  });

  testWidgets('показывает название и остаток живыми данными', (tester) async {
    final repo = InMemoryAccountsRepository([
      acc('a', 'Карта', opening: 100000),
    ])..net['a'] = rub(-30000);
    await pumpTab(tester, repo);
    await openAccount(tester, 'Карта');
    expect(find.text(accountBalanceCaption), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(AccountScreen.balanceKey)).data,
      formatMoney(rub(70000)),
    );
    repo.net['a'] = rub(-40000);
    await repo.update('a', name: 'Карта', iconKey: 'card'); // обновление потока
    await tester.pump();
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(AccountScreen.balanceKey)).data,
      formatMoney(rub(60000)),
    );
  });

  testWidgets('«Изменить»: переименование видно на экране и во вкладке', (
    tester,
  ) async {
    final repo = InMemoryAccountsRepository([acc('a', 'Карта')]);
    await pumpTab(tester, repo);
    await openAccount(tester, 'Карта');
    await tapKey(tester, AccountScreen.editKey);
    expect(find.text(accountFormEditTitle), findsOneWidget);
    await tester.enterText(
      find.byKey(AccountFormScreen.nameFieldKey),
      'Зарплатная',
    );
    await tapKey(tester, AccountFormScreen.saveButtonKey);
    expect(find.text('Зарплатная'), findsOneWidget); // заголовок экрана счёта
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Зарплатная'), findsOneWidget);
    expect(find.text('Карта'), findsNothing);
  });

  group('«Поправить остаток»', () {
    testWidgets('при операциях остаток становится ровно введённым', (
      tester,
    ) async {
      final repo = InMemoryAccountsRepository([
        acc('a', 'Карта', opening: 100000),
      ])..net['a'] = rub(-30000);
      await pumpTab(tester, repo);
      await openAccount(tester, 'Карта');
      await tapKey(tester, AccountScreen.adjustKey);
      expect(find.text(accountAdjustTitle), findsWidgets);
      expect(find.text(accountAdjustHelper), findsOneWidget);
      // Поле заполнено текущим остатком.
      expect(
        tester
            .widget<TextField>(find.byKey(AccountAdjustDialog.fieldKey))
            .controller!
            .text,
        '700,00',
      );
      await tester.enterText(
        find.byKey(AccountAdjustDialog.fieldKey),
        '1500,50',
      );
      await tapKey(tester, AccountAdjustDialog.saveKey);
      expect(
        tester.widget<Text>(find.byKey(AccountScreen.balanceKey)).data,
        formatMoney(rub(150050)),
      );
      // Стартовый остаток подобран, «операции» (net) не тронуты.
      expect(repo.all.single.openingBalance, rub(180050));
      expect(repo.net['a'], rub(-30000));
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(totalText(tester), '+${formatMoney(rub(150050))}');
    });

    testWidgets('сбой записи: сообщение, экран остаётся', (tester) async {
      final repo = InMemoryAccountsRepository([acc('a', 'Карта')]);
      await pumpTab(tester, repo);
      await openAccount(tester, 'Карта');
      await tapKey(tester, AccountScreen.adjustKey);
      await tester.enterText(find.byKey(AccountAdjustDialog.fieldKey), '50');
      repo.failWith = Exception('db');
      await tapKey(tester, AccountAdjustDialog.saveKey);
      expect(find.text(categorySaveFailedText), findsOneWidget);
      expect(find.byType(AccountScreen), findsOneWidget);
    });

    testWidgets('«Минус (долг)», ошибка суммы и отмена', (tester) async {
      final repo = InMemoryAccountsRepository([acc('a', 'Карта')]);
      await pumpTab(tester, repo);
      await openAccount(tester, 'Карта');
      await tapKey(tester, AccountScreen.adjustKey);
      await tester.enterText(find.byKey(AccountAdjustDialog.fieldKey), '');
      await tapKey(tester, AccountAdjustDialog.saveKey);
      expect(find.byType(AccountAdjustDialog), findsOneWidget); // ошибка суммы
      await tester.enterText(find.byKey(AccountAdjustDialog.fieldKey), '50');
      await tapKey(tester, AccountAdjustDialog.minusKey);
      await tapKey(tester, AccountAdjustDialog.saveKey);
      expect(
        tester.widget<Text>(find.byKey(AccountScreen.balanceKey)).data,
        formatMoney(rub(-5000)),
      );
      // Отмена ничего не меняет.
      await tapKey(tester, AccountScreen.adjustKey);
      await tester.tap(find.text(accountCancelLabel));
      await tester.pumpAndSettle();
      expect(repo.all.single.openingBalance, rub(-5000));
    });
  });

  group('«В архив»', () {
    testWidgets('нулевой остаток: сразу в архив, «Вернуть» возвращает', (
      tester,
    ) async {
      final repo = InMemoryAccountsRepository([acc('a', 'Карта')]);
      await pumpTab(tester, repo);
      await openAccount(tester, 'Карта');
      await tapKey(tester, AccountScreen.archiveKey);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(AccountScreen), findsNothing);
      expect(find.text(accountArchivedMessage('Карта')), findsOneWidget);
      expect(find.text('Карта'), findsNothing); // пропал со вкладки
      await tester.tap(find.text(accountUndoAction));
      await tester.pumpAndSettle();
      expect(find.text('Карта'), findsOneWidget);
    });

    testWidgets('ненулевой: диалог с текстом; отмена, затем подтверждение', (
      tester,
    ) async {
      final repo = InMemoryAccountsRepository([
        acc('a', 'Карта', opening: 1200000),
        acc('b', 'Наличные', opening: 5000),
      ]);
      await pumpTab(tester, repo);
      expect(totalText(tester), '+${formatMoney(rub(1205000))}');
      await openAccount(tester, 'Карта');
      await tapKey(tester, AccountScreen.archiveKey);
      expect(find.text(accountArchiveDialogTitle('Карта')), findsOneWidget);
      expect(
        find.text(
          accountArchiveDialogText(rub(1200000), currencyInfoFor('RUB')),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text(accountCancelLabel));
      await tester.pumpAndSettle();
      expect(repo.all.first.isArchived, isFalse);
      expect(find.byType(AccountScreen), findsOneWidget);

      await tapKey(tester, AccountScreen.archiveKey);
      await tester.tap(find.widgetWithText(FilledButton, accountArchiveButton));
      await tester.pumpAndSettle();
      expect(find.byType(AccountScreen), findsNothing);
      expect(find.text('Карта'), findsNothing);
      expect(totalText(tester), '+${formatMoney(rub(5000))}'); // без «Карты»
      expect(find.text(accountArchivedMessage('Карта')), findsOneWidget);
    });

    testWidgets('«Назад» во время записи: экран под ним не закрывается', (
      tester,
    ) async {
      final repo = InMemoryAccountsRepository([acc('a', 'Карта')])
        ..archiveGate = Completer<void>();
      await pumpTab(tester, repo);
      await openAccount(tester, 'Карта');
      await tester.ensureVisible(find.byKey(AccountScreen.archiveKey));
      await tester.tap(find.byKey(AccountScreen.archiveKey));
      await tester.pump();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(AccountScreen), findsNothing);
      expect(find.byType(BalanceTab), findsOneWidget);
      repo.archiveGate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(BalanceTab), findsOneWidget);
      expect(find.text(accountArchivedMessage('Карта')), findsOneWidget);
    });

    testWidgets('сбой записи: сообщение, экран остаётся', (tester) async {
      final repo = InMemoryAccountsRepository([acc('a', 'Карта')]);
      await pumpTab(tester, repo);
      await openAccount(tester, 'Карта');
      repo.failWith = Exception('db');
      await tapKey(tester, AccountScreen.archiveKey);
      expect(find.text(categorySaveFailedText), findsOneWidget);
      expect(find.byType(AccountScreen), findsOneWidget);
    });

    testWidgets('«Вернуть» при занятом имени объясняет причину', (
      tester,
    ) async {
      final repo = InMemoryAccountsRepository([acc('a', 'Карта')]);
      await pumpTab(tester, repo);
      await openAccount(tester, 'Карта');
      await tapKey(tester, AccountScreen.archiveKey);
      await repo.create(acc('b', 'карта'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(accountUndoAction));
      await tester.pumpAndSettle();
      expect(find.text(accountRestoreDuplicateText), findsOneWidget);
      expect(repo.all.first.isArchived, isTrue);
    });
  });

  testWidgets('кнопки экрана не ниже 48 dp', (tester) async {
    final repo = InMemoryAccountsRepository([acc('a', 'Карта')]);
    await pumpTab(tester, repo);
    await openAccount(tester, 'Карта');
    for (final key in [
      AccountScreen.editKey,
      AccountScreen.adjustKey,
      AccountScreen.archiveKey,
    ]) {
      expect(
        tester.getSize(find.byKey(key)).height,
        greaterThanOrEqualTo(48),
        reason: '$key',
      );
    }
  });

  testWidgets('диалог остатка: символ валюты виден, подзаголовок долга', (
    tester,
  ) async {
    final repo = InMemoryAccountsRepository([acc('a', 'Карта')]);
    await pumpTab(tester, repo);
    await openAccount(tester, 'Карта');
    await tapKey(tester, AccountScreen.adjustKey);
    await tester.enterText(find.byKey(AccountAdjustDialog.fieldKey), '');
    await tester.pump();
    expect(find.text('₽'), findsOneWidget);
    expect(find.text(accountFormMinusHelper), findsOneWidget);
  });

  testWidgets('«0» и «Минус (долг)» в диалоге: остаток 0 без минуса', (
    tester,
  ) async {
    final repo = InMemoryAccountsRepository([acc('a', 'Карта', opening: 5000)]);
    await pumpTab(tester, repo);
    await openAccount(tester, 'Карта');
    await tapKey(tester, AccountScreen.adjustKey);
    await tester.enterText(find.byKey(AccountAdjustDialog.fieldKey), '0');
    await tapKey(tester, AccountAdjustDialog.minusKey);
    await tapKey(tester, AccountAdjustDialog.saveKey);
    expect(repo.all.single.openingBalance.minorUnits, 0);
    final shown = tester
        .widget<Text>(find.byKey(AccountScreen.balanceKey))
        .data!;
    expect(shown, formatMoney(rub(0)));
    expect(shown.contains('\u2212'), isFalse);
  });

  testWidgets('счёт ещё не загружен: индикатор загрузки', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: AccountScreen(
          accounts: _NeverLoadedRepository(),
          accountId: 'a',
          onEdit: (_) async {},
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('360 dp и шрифт 200 %: экран и диалоги без переполнения', (
    tester,
  ) async {
    final repo = InMemoryAccountsRepository([
      acc('a', 'Очень длинное название кредитной карты', opening: -123456789),
    ]);
    await pumpTab(tester, repo, textScale: 2);
    await openAccount(tester, 'Очень длинное название кредитной карты');
    expect(tester.takeException(), isNull);
    await tapKey(tester, AccountScreen.adjustKey);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text(accountCancelLabel));
    await tester.pumpAndSettle();
    await tapKey(tester, AccountScreen.archiveKey);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
