import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/app/app_scope.dart';
import 'package:money_app/app/app_services.dart';
import 'package:money_app/app/app_shell.dart';
import 'package:money_app/features/settings/presentation/app_settings_controller.dart';

import '../support/fakes.dart';

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

/// Вкладка, читающая сервисы из `AppScope` в собственном `build`.
class _ServicesTab extends StatelessWidget {
  const _ServicesTab();

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return Text('Сервисы: ${identityHashCode(services)}');
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

/// Вкладки со счётчиком вызовов строителей: `calls[i]` растёт на 1 при
/// каждом вызове строителя вкладки `i`. Подписи: «Первая», «Вторая», «Третья»
/// (для 3 вкладок) либо «Вкладка i подпись»; содержимое — «`prefix` i».
List<AppTab> _countingTabs(
  List<int> calls, {
  String prefix = 'Вкладка',
  int count = 3,
}) {
  const names = ['Первая', 'Вторая', 'Третья'];
  return [
    for (var i = 0; i < count; i++)
      _tab(count == 3 ? names[i] : 'Вкладка $i подпись', (_) {
        calls[i]++;
        return Text('$prefix $i');
      }),
  ];
}

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
    // IndexedStack оставляет открытые вкладки в дереве, но скрытыми
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

  group('ленивая загрузка вкладок', () {
    testWidgets('до первого открытия строитель вкладки не вызывается', (
      tester,
    ) async {
      final calls = <int>[0, 0, 0];
      await _pumpShell(tester, _countingTabs(calls));

      expect(calls, [1, 0, 0]);
      expect(find.text('Вкладка 0'), findsOneWidget);
    });

    testWidgets('после первого перехода строитель вызван ровно один раз', (
      tester,
    ) async {
      final calls = <int>[0, 0, 0];
      await _pumpShell(tester, _countingTabs(calls));

      await tester.tap(find.text('Вторая'));
      await tester.pump();
      expect(calls, [1, 1, 0]);

      // Туда-обратно несколько раз: новых вызовов быть не должно.
      await tester.tap(find.text('Первая'));
      await tester.pump();
      await tester.tap(find.text('Вторая'));
      await tester.pump();
      await tester.tap(find.text('Первая'));
      await tester.pump();
      expect(calls, [1, 1, 0]);
    });

    testWidgets('перерисовки шлюза не вызывают строители повторно', (
      tester,
    ) async {
      final calls = <int>[0, 0, 0];
      final tabs = _countingTabs(calls);
      late StateSetter rebuildParent;
      var brightness = Brightness.light;

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            rebuildParent = setState;
            return MaterialApp(
              theme: ThemeData(brightness: brightness),
              home: AppShell(tabs: tabs),
            );
          },
        ),
      );
      await tester.tap(find.text('Вторая'));
      await tester.pump();
      expect(calls, [1, 1, 0]);

      // Родитель перерисовывается с прежним набором вкладок.
      rebuildParent(() {});
      await tester.pump();
      // Смена темы: шлюз перестраивается, вкладки тоже, но строители молчат.
      rebuildParent(() => brightness = Brightness.dark);
      await tester.pumpAndSettle();

      expect(calls, [1, 1, 0]);
      expect(find.text('Вкладка 1'), findsOneWidget);
    });

    testWidgets('позиция прокрутки открытой вкладки сохраняется', (
      tester,
    ) async {
      final tabs = [
        _tab('Первая', (_) => const Text('Первая вкладка')),
        _tab(
          'Список',
          (_) => ListView.builder(
            itemCount: 100,
            itemBuilder: (_, i) =>
                SizedBox(height: 60, child: Text('Строка $i')),
          ),
        ),
        _tab('Третья', (_) => const Text('Третья вкладка')),
      ];
      await _pumpShell(tester, tabs);

      await tester.tap(find.text('Список'));
      await tester.pump();
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pump();
      final before = tester
          .state<ScrollableState>(find.byType(Scrollable))
          .position
          .pixels;
      expect(before, greaterThan(0));

      await tester.tap(find.text('Первая'));
      await tester.pump();
      await tester.tap(find.text('Третья'));
      await tester.pump();
      await tester.tap(find.text('Список'));
      await tester.pump();

      final after = tester
          .state<ScrollableState>(find.byType(Scrollable))
          .position
          .pixels;
      expect(after, before);
    });

    testWidgets('не открытая вкладка не в дереве, открытая остаётся скрытой', (
      tester,
    ) async {
      await _pumpShell(tester, _testTabs());

      // Ни вторая, ни третья ещё не открывались: их виджетов нет совсем.
      expect(find.text('Содержимое второй', skipOffstage: false), findsNothing);
      expect(
        find.text('Содержимое третьей', skipOffstage: false),
        findsNothing,
      );

      await tester.tap(find.text('Вторая'));
      await tester.pump();

      // Первая открыта раньше: скрыта, но в дереве. Третья по-прежнему нет.
      expect(find.text('Счёт: 0'), findsNothing);
      expect(find.text('Счёт: 0', skipOffstage: false), findsOneWidget);
      expect(
        find.text('Содержимое третьей', skipOffstage: false),
        findsNothing,
      );
    });

    testWidgets('при смене набора вкладок кэш сбрасывается, сборка ленивая', (
      tester,
    ) async {
      final oldCalls = <int>[0, 0, 0];
      await _pumpShell(tester, _countingTabs(oldCalls, prefix: 'Старая'));
      await tester.tap(find.text('Вторая'));
      await tester.pump();
      expect(oldCalls, [1, 1, 0]);

      final newCalls = <int>[0, 0, 0];
      await _pumpShell(tester, _countingTabs(newCalls, prefix: 'Новая'));
      await tester.pump();

      // Выбранной остаётся вторая вкладка (индекс 1), строится только она.
      expect(newCalls, [0, 1, 0]);
      expect(oldCalls, [1, 1, 0]);
      expect(find.text('Новая 1'), findsOneWidget);
      // Содержимое старого набора не «протекло» в новое дерево.
      expect(find.textContaining('Старая', skipOffstage: false), findsNothing);
      expect(find.text('Новая 0', skipOffstage: false), findsNothing);
    });

    testWidgets('набор стал короче: выбранный индекс остаётся допустимым', (
      tester,
    ) async {
      await _pumpShell(tester, _countingTabs([0, 0, 0, 0, 0], count: 5));
      await tester.tap(find.text('Вкладка 4 подпись'));
      await tester.pump();
      expect(find.text('Вкладка 4'), findsOneWidget);

      final newCalls = <int>[0, 0, 0];
      await _pumpShell(tester, _countingTabs(newCalls, prefix: 'Новая'));
      await tester.pump();

      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        2,
      );
      expect(newCalls, [0, 0, 1]);
      expect(find.text('Новая 2'), findsOneWidget);
    });

    testWidgets('тот же набор в новом списке кэш не сбрасывает', (
      tester,
    ) async {
      final calls = <int>[0, 0, 0];
      final tabs = _countingTabs(calls);
      await _pumpShell(tester, tabs);
      await tester.tap(find.text('Вторая'));
      await tester.pump();

      await _pumpShell(tester, List.of(tabs));
      await tester.pump();

      expect(calls, [1, 1, 0]);
    });
  });

  group('системная кнопка «Назад»', () {
    // Сколько раз приложение попыталось закрыться (SystemNavigator.pop).
    late int exitCalls;

    setUp(() {
      exitCalls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'SystemNavigator.pop') exitCalls++;
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    int selectedIndex(WidgetTester tester) =>
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex;

    Future<void> pressBack(WidgetTester tester) async {
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
    }

    testWidgets('с другой вкладки возвращает на первую и не закрывает', (
      tester,
    ) async {
      await _pumpShell(tester, _testTabs());
      for (final label in ['Вторая', 'Третья']) {
        await tester.tap(find.text(label));
        await tester.pump();
        expect(selectedIndex(tester), isNot(0));

        await pressBack(tester);

        expect(selectedIndex(tester), 0);
        expect(find.text('Счёт: 0'), findsOneWidget);
        expect(exitCalls, 0);
      }
    });

    testWidgets('на первой вкладке «Назад» закрывает приложение', (
      tester,
    ) async {
      await _pumpShell(tester, _testTabs());

      await pressBack(tester);

      expect(exitCalls, 1);
      expect(selectedIndex(tester), 0);
    });

    testWidgets('с пятой вкладки: первое «Назад» на первую, второе — выход', (
      tester,
    ) async {
      await _pumpShell(tester, _countingTabs([0, 0, 0, 0, 0], count: 5));
      await tester.tap(find.text('Вкладка 4 подпись'));
      await tester.pump();
      expect(selectedIndex(tester), 4);

      await pressBack(tester);
      expect(selectedIndex(tester), 0);
      expect(find.text('Вкладка 0'), findsOneWidget);
      expect(exitCalls, 0);

      await pressBack(tester);
      expect(exitCalls, 1);
    });

    testWidgets('открытый поверх экран «Назад» закрывает первым', (
      tester,
    ) async {
      await _pumpShell(tester, _testTabs());
      await tester.tap(find.text('Третья'));
      await tester.pump();

      unawaited(
        tester
            .state<NavigatorState>(find.byType(Navigator))
            .push(
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('Поверх каркаса')),
              ),
            ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Поверх каркаса'), findsOneWidget);

      await pressBack(tester);

      // Экран закрыт, вкладка прежняя, приложение не закрыто.
      expect(find.text('Поверх каркаса'), findsNothing);
      expect(selectedIndex(tester), 2);
      expect(find.text('Содержимое третьей'), findsOneWidget);
      expect(exitCalls, 0);

      // Следующее «Назад» уже работает как обычно: на «Главную».
      await pressBack(tester);
      expect(selectedIndex(tester), 0);
      expect(exitCalls, 0);
    });

    testWidgets('экран поверх первой вкладки: «Назад» закрывает экран, '
        'а не приложение', (tester) async {
      await _pumpShell(tester, _testTabs());

      unawaited(
        tester
            .state<NavigatorState>(find.byType(Navigator))
            .push(
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('Поверх каркаса')),
              ),
            ),
      );
      await tester.pumpAndSettle();

      await pressBack(tester);

      expect(find.text('Поверх каркаса'), findsNothing);
      expect(find.text('Счёт: 0'), findsOneWidget);
      expect(exitCalls, 0);
    });

    testWidgets('состояние других вкладок после возврата на первую живо', (
      tester,
    ) async {
      final tabs = [
        _tab('Первая', (_) => const Text('Главная')),
        _tab('Счётчик', (_) => const _CounterTab()),
        _tab('Третья', (_) => const Text('Содержимое третьей')),
      ];
      await _pumpShell(tester, tabs);

      await tester.tap(find.text('Счётчик'));
      await tester.pump();
      await tester.tap(find.text('+1'));
      await tester.tap(find.text('+1'));
      await tester.pump();
      expect(find.text('Счёт: 2'), findsOneWidget);

      await pressBack(tester);
      expect(selectedIndex(tester), 0);
      expect(find.text('Главная'), findsOneWidget);

      await tester.tap(find.text('Счётчик'));
      await tester.pump();
      expect(find.text('Счёт: 2'), findsOneWidget);
    });
  });

  testWidgets('открытая вкладка, читающая AppScope в build, видит новые '
      'сервисы после их подмены над каркасом', (tester) async {
    final settings = AppSettingsController();
    addTearDown(settings.dispose);
    final first = fakeAppServices(settings: settings);
    final second = fakeAppServices(settings: settings);
    final tabs = [
      _tab('Первая', (_) => const _ServicesTab()),
      _tab('Вторая', (_) => const Text('Содержимое второй')),
      _tab('Третья', (_) => const Text('Содержимое третьей')),
    ];
    // Одни и те же вкладки и то же дерево: меняется только AppScope.
    Widget app(AppServices services) => MaterialApp(
      home: AppScope(
        services: services,
        child: AppShell(tabs: tabs),
      ),
    );

    await tester.pumpWidget(app(first));
    expect(find.text('Сервисы: ${identityHashCode(first)}'), findsOneWidget);

    await tester.pumpWidget(app(second));

    expect(identityHashCode(first), isNot(identityHashCode(second)));
    expect(find.text('Сервисы: ${identityHashCode(second)}'), findsOneWidget);
    expect(find.text('Сервисы: ${identityHashCode(first)}'), findsNothing);
  });

  test('меньше 3 или больше 5 вкладок недопустимо', () {
    List<AppTab> tabs(int count) => [
      for (var i = 0; i < count; i++) _tab('Вкладка $i', (_) => const Text('')),
    ];

    expect(() => AppShell(tabs: tabs(2)), throwsArgumentError);
    expect(() => AppShell(tabs: tabs(6)), throwsArgumentError);
    expect(() => AppShell(tabs: tabs(3)), returnsNormally);
    expect(() => AppShell(tabs: tabs(5)), returnsNormally);
  });
}
