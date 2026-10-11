import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/app/app_shell.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';

import '../support/contrast.dart';

List<AppTab> _tabs() => [
  for (final label in [
    'Главная',
    'История',
    'Аналитика',
    'Баланс',
    'Настройки',
  ])
    AppTab(
      label: label,
      icon: Icons.circle_outlined,
      selectedIcon: Icons.circle,
      // Список длиннее экрана: проверяем, что он уходит под капсулу.
      builder: (_) => ListView(
        children: [
          for (var i = 0; i < 40; i++) ListTile(title: Text('$label $i')),
        ],
      ),
    ),
];

Future<void> _pump(
  WidgetTester tester, {
  ThemeData? theme,
  EdgeInsets viewPadding = EdgeInsets.zero,
}) async {
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1;
  tester.view.viewPadding = FakeViewPadding(bottom: viewPadding.bottom);
  tester.view.padding = FakeViewPadding(bottom: viewPadding.bottom);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.light(),
      home: AppShell(tabs: _tabs()),
    ),
  );
}

Finder get _capsule => find.byType(NavCapsule);

void main() {
  testWidgets('панель внутри ClipRRect + BackdropFilter, пять вкладок', (
    tester,
  ) async {
    await _pump(tester);

    final clip = find.descendant(
      of: _capsule,
      matching: find.byType(ClipRRect),
    );
    expect(clip, findsOneWidget);
    final filter = find.descendant(
      of: clip,
      matching: find.byType(BackdropFilter),
    );
    expect(filter, findsOneWidget);
    expect(tester.widget<BackdropFilter>(filter).filter, isA<ImageFilter>());
    expect(
      find.descendant(of: filter, matching: find.byType(NavigationBar)),
      findsOneWidget,
    );
    expect(find.byType(NavigationDestination), findsNWidgets(5));
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).backgroundColor,
      Colors.transparent,
    );
  });

  testWidgets('капсула скруглена на всю высоту и не касается краёв', (
    tester,
  ) async {
    await _pump(tester, viewPadding: const EdgeInsets.only(bottom: 24));

    final rect = tester.getRect(
      find.descendant(of: _capsule, matching: find.byType(ClipRRect)),
    );
    expect(rect.left, 16);
    expect(rect.right, 393 - 16);
    expect(rect.height, navCapsuleHeight);
    // Над системной полоской (24) с зазором.
    expect(rect.bottom, 852 - 24 - navCapsuleGap);
    final radius = tester
        .widget<ClipRRect>(
          find.descendant(of: _capsule, matching: find.byType(ClipRRect)),
        )
        .borderRadius
        .resolve(TextDirection.ltr);
    expect(radius.topLeft.x, navCapsuleHeight / 2);
  });

  testWidgets('содержимое прокручивается под капсулой (extendBody)', (
    tester,
  ) async {
    await _pump(tester);
    expect(tester.widget<Scaffold>(find.byType(Scaffold)).extendBody, isTrue);
    // Тело занимает экран целиком, до нижнего края.
    final list = tester.getRect(find.byType(ListView));
    expect(list.bottom, 852);
  });

  testWidgets('озвучка вкладок прежняя: «История», вкладка 2 из 5', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester);
    // Строку «Вкладка N из M» даёт Flutter; в тесте локаль английская.
    final data = tester.getSemantics(find.text('История')).getSemanticsData();
    expect(data.label, startsWith('История'));
    expect(data.label, endsWith('Tab 2 of 5'));
    expect(data.flagsCollection.isButton, isTrue);
    semantics.dispose();
  });

  group('контраст подписей на полупрозрачной заливке', () {
    for (final (name, theme) in [
      ('светлая', AppTheme.light()),
      ('тёмная', AppTheme.dark()),
    ]) {
      testWidgets('$name тема: ≥ 4.5 над surface, белым и чёрным', (
        tester,
      ) async {
        await _pump(tester, theme: theme);
        final box = tester.widget<DecoratedBox>(
          find
              .descendant(
                of: find.byType(BackdropFilter),
                matching: find.byType(DecoratedBox),
              )
              .first,
        );
        final fill = (box.decoration as BoxDecoration).color!;
        expect(fill.a, lessThan(1), reason: 'заливка полупрозрачная');
        final scheme = theme.colorScheme;
        for (final under in [scheme.surface, Colors.white, Colors.black]) {
          final shown = Color.alphaBlend(fill, under);
          for (final label in [scheme.onSurface, scheme.onSurfaceVariant]) {
            expect(
              contrastRatio(label, shown),
              greaterThanOrEqualTo(4.5),
              reason: 'подпись $label над $under',
            );
          }
        }
      });
    }
  });
}
