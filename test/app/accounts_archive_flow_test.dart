import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/app/app_routes.dart';
import 'package:money_app/app/app_scope.dart';
import 'package:money_app/app/balance_tab.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/accounts/presentation/account_texts.dart';
import 'package:money_app/features/accounts/presentation/accounts_section.dart';
import 'package:money_app/features/settings/presentation/app_settings_controller.dart';

import '../support/fakes.dart';

/// Раздел «Архив (N)» вкладки «Баланс» (шаг 5.12a).
Account _acc(String id, String name, {bool archived = false}) => Account(
  id: id,
  name: name,
  iconKey: 'card',
  openingBalance: Money.zero('RUB'),
  sortOrder: 0,
  currencyDigits: 2,
  archivedAt: archived ? DateTime.utc(2026, 9, 1) : null,
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

Future<void> _expandArchive(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(AccountsSection.archiveKey));
  await tester.tap(find.byKey(AccountsSection.archiveKey));
  await tester.pumpAndSettle();
}

Future<void> _restore(WidgetTester tester, String id) async {
  final key = AccountsSection.restoreKey(id);
  await tester.ensureVisible(find.byKey(key));
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru');
  });

  testWidgets('архива нет - раздела нет', (tester) async {
    await _pump(tester, InMemoryAccountsRepository([_acc('a', 'Карта')]));
    expect(find.byKey(AccountsSection.archiveKey), findsNothing);
  });

  testWidgets('«Архив (N)» свёрнут; возврат возвращает счёт в список', (
    tester,
  ) async {
    final repo = InMemoryAccountsRepository([
      _acc('a', 'Карта'),
      _acc('b', 'Старая', archived: true),
      _acc('c', 'Копилка', archived: true),
    ]);
    await _pump(tester, repo);
    expect(find.text('Архив (2)'), findsOneWidget);
    expect(find.text('Старая'), findsNothing);

    await _expandArchive(tester);
    expect(find.text('Старая'), findsOneWidget);
    await _restore(tester, 'b');
    expect(repo.all.firstWhere((a) => a.id == 'b').isArchived, isFalse);
    expect(find.text(accountRestoredMessage('Старая')), findsOneWidget);
    expect(find.text('Архив (1)'), findsOneWidget);

    await _expandArchive(tester);
    await _restore(tester, 'c');
    expect(find.byKey(AccountsSection.archiveKey), findsNothing);
  });

  testWidgets('занятое имя: сообщение, счёт остаётся в архиве', (tester) async {
    final repo = InMemoryAccountsRepository([
      _acc('a', 'Карта'),
      _acc('b', 'карта', archived: true),
    ]);
    await _pump(tester, repo);
    await _expandArchive(tester);
    await _restore(tester, 'b');
    expect(find.text(accountRestoreDuplicateText), findsOneWidget);
    expect(repo.all.firstWhere((a) => a.id == 'b').isArchived, isTrue);
    expect(find.text('Архив (1)'), findsOneWidget);
  });

  testWidgets('все счета в архиве: подсказка и раздел «Архив»', (tester) async {
    await _pump(
      tester,
      InMemoryAccountsRepository([_acc('a', 'Карта', archived: true)]),
    );
    expect(find.text(accountsEmptyText), findsOneWidget);
    expect(find.text('Архив (1)'), findsOneWidget);
  });

  testWidgets('вернули бывший основной без замены - он снова основной', (
    tester,
  ) async {
    final repo = InMemoryAccountsRepository([
      _acc('a', 'Карта', archived: true),
    ]);
    await _pump(tester, repo);
    await _settings.setDefaultAccountId('a');
    await tester.pumpAndSettle();
    expect(find.text(accountDefaultLabel), findsNothing);

    await _expandArchive(tester);
    await _restore(tester, 'a');
    expect(find.text(accountDefaultLabel), findsOneWidget);
  });

  testWidgets('кнопка возврата читается «Вернуть из архива: Старая»', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      InMemoryAccountsRepository([
        _acc('a', 'Карта'),
        _acc('b', 'Старая', archived: true),
      ]),
    );
    await _expandArchive(tester);
    expect(find.bySemanticsLabel('Вернуть из архива: Старая'), findsOneWidget);
    handle.dispose();
  });
}
