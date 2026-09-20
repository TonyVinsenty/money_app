import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/features/settings/presentation/settings_screen.dart';

Widget _app({
  ThemeMode mode = ThemeMode.system,
  ValueChanged<ThemeMode>? onChanged,
  VoidCallback? onCategories,
  double textScale = 1,
}) {
  return MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Scaffold(
      body: SettingsScreen(
        themeMode: mode,
        onThemeModeChanged: onChanged ?? (_) {},
        onOpenCategories: onCategories ?? () {},
      ),
    ),
  );
}

/// Какая тема сейчас выбрана в группе переключателей.
ThemeMode _groupValue(WidgetTester tester) => tester
    .widget<RadioGroup<ThemeMode>>(find.byType(RadioGroup<ThemeMode>))
    .groupValue!;

void main() {
  testWidgets('три варианта темы, выбран текущий', (tester) async {
    await tester.pumpWidget(_app(mode: ThemeMode.dark));

    expect(find.text('Тема'), findsOneWidget);
    expect(_groupValue(tester), ThemeMode.dark);
  });

  for (final (label, mode) in [
    ('Как в системе', ThemeMode.system),
    ('Светлая', ThemeMode.light),
    ('Тёмная', ThemeMode.dark),
  ]) {
    testWidgets('тап «$label» сообщает $mode', (tester) async {
      // Стартуем с другого значения, чтобы тап по выбранному не был «пустым».
      final start = mode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
      final calls = <ThemeMode>[];
      await tester.pumpWidget(_app(mode: start, onChanged: calls.add));

      await tester.tap(find.text(label));
      await tester.pump();

      expect(calls, [mode]);
    });
  }

  testWidgets('пункт «Категории» вызывает переход', (tester) async {
    var opened = 0;
    await tester.pumpWidget(_app(onCategories: () => opened++));

    await tester.tap(find.text('Категории'));

    expect(opened, 1);
  });

  testWidgets('заглушки «Здесь будут…» на экране нет', (tester) async {
    await tester.pumpWidget(_app());

    expect(find.textContaining('Здесь будут'), findsNothing);
  });

  testWidgets('скринридер: заголовок раздела, выбранный вариант, кнопка', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_app(mode: ThemeMode.light));

    expect(
      tester.getSemantics(find.text('Тема')).flagsCollection.isHeader,
      isTrue,
    );
    final light = tester.getSemantics(
      find.widgetWithText(RadioListTile<ThemeMode>, 'Светлая'),
    );
    expect(light.getSemanticsData().flagsCollection.isChecked.name, 'isTrue');
    final dark = tester.getSemantics(
      find.widgetWithText(RadioListTile<ThemeMode>, 'Тёмная'),
    );
    expect(dark.getSemanticsData().flagsCollection.isChecked.name, 'isFalse');
    expect(
      tester.getSemantics(find.text('Категории')).flagsCollection.isButton,
      isTrue,
    );
    semantics.dispose();
  });

  testWidgets('зоны нажатия не ниже 48 dp, шрифт 200% без переполнения', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(240, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(textScale: 2));

    expect(tester.takeException(), isNull);
    final tiles = {
      for (final label in ['Как в системе', 'Светлая', 'Тёмная'])
        label: find.widgetWithText(RadioListTile<ThemeMode>, label),
      'Категории': find.widgetWithText(ListTile, 'Категории'),
    };
    for (final MapEntry(key: label, value: tile) in tiles.entries) {
      expect(
        tester.getSize(tile).height,
        greaterThanOrEqualTo(48),
        reason: label,
      );
    }
  });
}
