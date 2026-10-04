import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/app/app_scope.dart';
import 'package:money_app/app/app_shell.dart';
import 'package:money_app/app/app_tabs.dart';
import 'package:money_app/app/browse_controller.dart';
import 'package:money_app/app/browse_scope.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/features/settings/presentation/app_settings_controller.dart';

import '../support/fakes.dart';

AppTab _tab(String label) => AppTab(
  label: label,
  icon: Icons.circle_outlined,
  selectedIcon: Icons.circle,
  builder: (_) => Text('Содержимое $label'),
);

/// Каркас под `BrowseHost`; уведомитель вкладки берётся из scope.
Future<void> _pump(
  WidgetTester tester,
  FakeTransactionsRepository repo, {
  Widget? replacement,
  void Function(BrowseController, ValueNotifier<int>)? onReady,
}) async {
  final settings = AppSettingsController();
  addTearDown(settings.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: AppScope(
        services: fakeAppServices(settings: settings, transactions: repo),
        child:
            replacement ??
            BrowseHost(
              child: Builder(
                builder: (context) {
                  onReady?.call(
                    BrowseScope.of(context),
                    BrowseScope.selectedTabOf(context),
                  );
                  return AppShell(
                    tabs: [_tab('Первая'), _tab('Вторая'), _tab('Третья')],
                    selectedTab: BrowseScope.selectedTabOf(context),
                  );
                },
              ),
            ),
      ),
    ),
  );
}

Finder _navLabel(String text) =>
    find.descendant(of: find.byType(NavigationBar), matching: find.text(text));

void main() {
  test('defaultAppTabs[historyTabIndex] — «История»', () {
    expect(defaultAppTabs[historyTabIndex].label, 'История');
  });

  group('AppShell с внешним уведомителем', () {
    testWidgets('смена значения переключает вкладку', (tester) async {
      late ValueNotifier<int> tab;
      await _pump(
        tester,
        FakeTransactionsRepository(),
        onReady: (_, t) => tab = t,
      );
      expect(find.text('Содержимое Первая'), findsOneWidget);

      tab.value = 1;
      await tester.pump();

      expect(find.text('Содержимое Вторая'), findsOneWidget);
    });

    testWidgets('нажатие в нижней навигации пишет в уведомитель', (
      tester,
    ) async {
      late ValueNotifier<int> tab;
      await _pump(
        tester,
        FakeTransactionsRepository(),
        onReady: (_, t) => tab = t,
      );

      await tester.tap(_navLabel('Третья'));
      await tester.pump();

      expect(tab.value, 2);
    });

    testWidgets('«Назад» со второй вкладки возвращает на «Главную»', (
      tester,
    ) async {
      late ValueNotifier<int> tab;
      await _pump(
        tester,
        FakeTransactionsRepository(),
        onReady: (_, t) => tab = t,
      );
      tab.value = 1;
      await tester.pump();

      await tester.binding.handlePopRoute();
      await tester.pump();

      expect(tab.value, 0);
      expect(find.text('Содержимое Первая'), findsOneWidget);
    });
  });

  group('BrowseHost', () {
    testWidgets(
      'firstDay из репозитория доходит до контроллера и обновляется',
      (tester) async {
        final repo = FakeTransactionsRepository()
          ..firstDay = DateOnly(2026, 7, 1);
        late BrowseController controller;
        await _pump(tester, repo, onReady: (c, _) => controller = c);
        await tester.pump();

        expect(controller.firstDay, DateOnly(2026, 7, 1));
        expect(controller.today, DateOnly(2026, 9, 20));

        repo.setFirstDay(DateOnly(2026, 5, 3));
        await tester.pump();
        expect(controller.firstDay, DateOnly(2026, 5, 3));

        repo.setFirstDay(null);
        await tester.pump();
        expect(controller.firstDay, isNull);
      },
    );

    testWidgets('ошибка потока не роняет приложение, день остаётся', (
      tester,
    ) async {
      final repo = FakeTransactionsRepository()
        ..firstDay = DateOnly(2026, 7, 1);
      late BrowseController controller;
      await _pump(tester, repo, onReady: (c, _) => controller = c);
      await tester.pump();

      repo.failFirstDay(StateError('boom'));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(controller.firstDay, DateOnly(2026, 7, 1));
    });

    testWidgets('после удаления хоста подписка отменена', (tester) async {
      final repo = FakeTransactionsRepository();
      await _pump(tester, repo);
      await tester.pump();
      expect(repo.firstDayListeners, 1);

      await _pump(tester, repo, replacement: const SizedBox());
      await tester.pump();

      expect(repo.firstDayListeners, 0);
    });

    testWidgets('перерисовка не создаёт вторую подписку', (tester) async {
      final repo = FakeTransactionsRepository();
      await _pump(tester, repo);
      await tester.pump();

      await tester.tap(_navLabel('Вторая'));
      await tester.pump();

      expect(repo.firstDayListeners, 1);
    });
  });
}
