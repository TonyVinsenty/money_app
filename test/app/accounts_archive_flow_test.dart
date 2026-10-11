import 'package:flutter/cupertino.dart'
    show CupertinoAlertDialog, CupertinoDialogAction;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/app/app_routes.dart';
import 'package:money_app/app/app_scope.dart';
import 'package:money_app/app/balance_tab.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/accounts/domain/accounts_repository.dart';
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

Future<void> _pump(
  WidgetTester tester,
  InMemoryAccountsRepository repo, {
  TargetPlatform? platform,
}) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  _settings = AppSettingsController();
  addTearDown(_settings.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(platform: platform),
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

    // Раздел после возврата остаётся раскрытым.
    expect(find.text('Копилка'), findsOneWidget);
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

  testWidgets('кнопки читаются с названием счёта', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      InMemoryAccountsRepository([
        _acc('a', 'Карта'),
        _acc('b', 'Старая', archived: true),
      ]),
    );
    await _expandArchive(tester);
    expect(find.bySemanticsLabel('Вернуть «Старая» из архива'), findsOneWidget);
    expect(find.bySemanticsLabel('Удалить «Старая»'), findsOneWidget);
    handle.dispose();
  });

  group('удаление из архива (7.30h)', () {
    Future<InMemoryAccountsRepository> openArchive(
      WidgetTester tester, {
      AccountLinks? links,
    }) async {
      final repo = InMemoryAccountsRepository([
        _acc('a', 'Карта'),
        _acc('b', 'Тест', archived: true),
      ]);
      if (links != null) repo.links['b'] = links;
      await _pump(tester, repo);
      await _expandArchive(tester);
      return repo;
    }

    Future<void> tapDelete(WidgetTester tester) async {
      final key = AccountsSection.deleteKey('b');
      await tester.ensureVisible(find.byKey(key));
      await tester.tap(find.byKey(key));
      await tester.pumpAndSettle();
    }

    testWidgets('одна строка: название и обе кнопки на одной линии', (
      tester,
    ) async {
      await openArchive(tester);
      final name = tester.getCenter(find.text('Тест')).dy;
      for (final key in [
        AccountsSection.restoreKey('b'),
        AccountsSection.deleteKey('b'),
      ]) {
        expect(tester.getCenter(find.byKey(key)).dy, closeTo(name, 1));
        expect(tester.getSize(find.byKey(key)), const Size(48, 48));
      }
      // Подписи «Вернуть из архива» строкой под названием больше нет.
      expect(find.text(accountRestoreAction), findsNothing);
      final context = tester.element(find.byIcon(Icons.delete_outline));
      expect(IconTheme.of(context).color, Theme.of(context).colorScheme.error);
    });

    testWidgets('без привязок: короткий текст, «Удалить» удаляет', (
      tester,
    ) async {
      final repo = await openArchive(tester);
      await tapDelete(tester);

      expect(find.text('Удалить счёт «Тест»?'), findsOneWidget);
      expect(find.text('Счёт удалится насовсем.'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Удалить'));
      await tester.pumpAndSettle();

      expect(repo.deleted, ['b']);
      expect(find.text('Счёт «Тест» удалён'), findsOneWidget);
      expect(find.byKey(AccountsSection.archiveKey), findsNothing);
    });

    testWidgets('с операциями и переводами: оба предложения с числами', (
      tester,
    ) async {
      await openArchive(tester, links: (transactions: 12, transfers: 3));
      await tapDelete(tester);
      expect(
        find.text(
          'К счёту привязано 12 операций. '
          'После удаления они останутся без привязки к счёту. '
          'Переводы с этим счётом (3) будут удалены. '
          'Остатки других счетов изменятся на сумму этих переводов.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('«Отмена» ничего не делает', (tester) async {
      final repo = await openArchive(tester);
      await tapDelete(tester);
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();

      expect(repo.deleted, isEmpty);
      expect(find.text('Архив (1)'), findsOneWidget);
      expect(find.textContaining('удалён'), findsNothing);
    });

    testWidgets('сбой удаления: сообщение, счёт на месте', (tester) async {
      final repo = await openArchive(tester);
      await tapDelete(tester);
      repo.failWith = Exception('disk');
      await tester.tap(find.widgetWithText(TextButton, 'Удалить'));
      await tester.pumpAndSettle();

      expect(find.text(accountDeleteFailedMessage), findsOneWidget);
      expect(find.text('Архив (1)'), findsOneWidget);
    });

    testWidgets('360 dp, 200 %: название переносится, кнопки на экране', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final repo = InMemoryAccountsRepository([
        _acc('a', 'Карта'),
        _acc('b', 'Старая зарплатная карта банка', archived: true),
      ]);
      await _pump(tester, repo);
      await _expandArchive(tester);

      expect(tester.takeException(), isNull);
      final name = find.text('Старая зарплатная карта банка');
      expect(tester.getSize(name).height, greaterThan(40));
      for (final key in [
        AccountsSection.restoreKey('b'),
        AccountsSection.deleteKey('b'),
      ]) {
        expect(tester.getTopRight(find.byKey(key)).dx, lessThanOrEqualTo(360));
        expect(
          tester.getTopLeft(find.byKey(key)).dx,
          greaterThanOrEqualTo(tester.getTopRight(name).dx),
        );
      }
    });

    testWidgets('iPhone: CupertinoAlertDialog, «Удалить» красная и работает', (
      tester,
    ) async {
      final repo = InMemoryAccountsRepository([
        _acc('a', 'Карта'),
        _acc('b', 'Тест', archived: true),
      ]);
      await _pump(tester, repo, platform: TargetPlatform.iOS);
      await _expandArchive(tester);
      await tapDelete(tester);

      expect(find.byType(CupertinoAlertDialog), findsOneWidget);
      final delete = tester.widget<CupertinoDialogAction>(
        find.widgetWithText(CupertinoDialogAction, 'Удалить'),
      );
      expect(delete.isDestructiveAction, isTrue);
      await tester.tap(find.text('Удалить').last);
      await tester.pumpAndSettle();
      expect(repo.deleted, ['b']);
      expect(find.text('Счёт «Тест» удалён'), findsOneWidget);
    });
  });
}
