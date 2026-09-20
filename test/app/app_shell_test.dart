import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/app/app_shell.dart';

/// Вкладка, у которой есть собственное состояние: счётчик нажатий.
class _CounterTab extends StatefulWidget {
  const _CounterTab();

  @override
  State<_CounterTab> createState() => _CounterTabState();
}

class _CounterTabState extends State<_CounterTab> {
  int _count = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('Счёт: $_count'),
        TextButton(
          onPressed: () => setState(() => _count++),
          child: const Text('+1'),
        ),
      ],
    );
  }
}

AppTab _tab(String label, WidgetBuilder builder) {
  return AppTab(
    label: label,
    icon: Icons.circle_outlined,
    selectedIcon: Icons.circle,
    builder: builder,
  );
}

List<AppTab> _testTabs() => [
  _tab('Первая', (_) => const _CounterTab()),
  _tab('Вторая', (_) => const Text('Содержимое второй')),
  _tab('Третья', (_) => const Text('Содержимое третьей')),
];

Future<void> _pumpShell(WidgetTester tester, List<AppTab> tabs) {
  return tester.pumpWidget(MaterialApp(home: AppShell(tabs: tabs)));
}

void main() {
  testWidgets('в панели видны все названия, выбрана первая вкладка', (
    tester,
  ) async {
    await _pumpShell(tester, _testTabs());

    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.selectedIndex, 0);
    expect(bar.destinations, hasLength(3));
    for (final label in ['Первая', 'Вторая', 'Третья']) {
      expect(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(label),
        ),
        findsOneWidget,
      );
    }
    expect(find.text('Счёт: 0'), findsOneWidget);
    expect(find.text('Содержимое второй'), findsNothing);
  });

  testWidgets('тап по вкладке показывает её содержимое и прячет прежнее', (
    tester,
  ) async {
    await _pumpShell(tester, _testTabs());

    await tester.tap(find.text('Вторая'));
    await tester.pump();

    expect(find.text('Содержимое второй'), findsOneWidget);
    // IndexedStack оставляет остальные вкладки в дереве, но скрытыми
    // (Offstage). find по умолчанию пропускает скрытое, поэтому первая
    // вкладка «не находится», хотя её состояние живо (см. следующий тест).
    expect(find.text('Счёт: 0'), findsNothing);
    expect(find.text('Счёт: 0', skipOffstage: false), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );
  });

  testWidgets('состояние вкладки сохраняется при переключении', (tester) async {
    await _pumpShell(tester, _testTabs());

    await tester.tap(find.text('+1'));
    await tester.tap(find.text('+1'));
    await tester.pump();
    expect(find.text('Счёт: 2'), findsOneWidget);

    await tester.tap(find.text('Вторая'));
    await tester.pump();
    await tester.tap(find.text('Первая'));
    await tester.pump();

    expect(find.text('Счёт: 2'), findsOneWidget);
  });

  test('меньше 3 или больше 5 вкладок недопустимо', () {
    List<AppTab> tabs(int count) => [
      for (var i = 0; i < count; i++) _tab('Вкладка $i', (_) => const Text('')),
    ];

    expect(() => AppShell(tabs: tabs(2)), throwsAssertionError);
    expect(() => AppShell(tabs: tabs(6)), throwsAssertionError);
    expect(() => AppShell(tabs: tabs(3)), returnsNormally);
    expect(() => AppShell(tabs: tabs(5)), returnsNormally);
  });
}
