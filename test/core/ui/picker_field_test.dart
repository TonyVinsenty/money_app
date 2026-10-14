import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/ui/picker_field.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';

Widget _host(Widget field, {double scale = 1}) => MaterialApp(
  theme: AppTheme.light(),
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
    child: Scaffold(
      body: Padding(padding: const EdgeInsets.all(16), child: field),
    ),
  ),
);

void main() {
  testWidgets('показывает подпись, значение и шеврон', (tester) async {
    await tester.pumpWidget(
      _host(PickerField(label: 'Категория', value: 'Кафе', onTap: () {})),
    );
    expect(find.text('Категория'), findsOneWidget);
    expect(find.text('Кафе'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    final style = tester.widget<Text>(find.text('Кафе')).style;
    expect(style?.fontSize, 16);
  });

  testWidgets('касание вызывает onTap, аватар показан', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(
        PickerField(
          label: 'Категория',
          value: 'Кафе',
          leading: const Icon(Icons.coffee),
          onTap: () => taps++,
        ),
      ),
    );
    expect(find.byIcon(Icons.coffee), findsOneWidget);
    await tester.tap(find.text('Кафе'));
    expect(taps, 1);
  });

  testWidgets('errorText виден под полем, значение красное', (tester) async {
    await tester.pumpWidget(
      _host(
        PickerField(
          label: 'Счёт',
          value: 'Карта',
          errorText: 'Выберите другой счёт',
          onTap: () {},
        ),
      ),
    );
    expect(find.text('Выберите другой счёт'), findsOneWidget);
    final context = tester.element(find.text('Карта'));
    expect(
      tester.widget<Text>(find.text('Карта')).style?.color,
      Theme.of(context).colorScheme.error,
    );
  });

  testWidgets('hasError: красное значение без текста под полем', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        PickerField(
          label: 'Категория',
          value: 'Выберите категорию',
          hasError: true,
          onTap: () {},
        ),
      ),
    );
    final context = tester.element(find.text('Выберите категорию'));
    expect(
      tester.widget<Text>(find.text('Выберите категорию')).style?.color,
      Theme.of(context).colorScheme.error,
    );
  });

  testWidgets('скринридер: «Категория, Кафе» одной кнопкой', (tester) async {
    final semantics = tester.ensureSemantics();
    var taps = 0;
    await tester.pumpWidget(
      _host(
        PickerField(label: 'Категория', value: 'Кафе', onTap: () => taps++),
      ),
    );
    final finder = find.bySemanticsLabel('Категория: Кафе');
    expect(finder, findsOneWidget);
    expect(tester.getSemantics(finder).flagsCollection.isButton, isTrue);
    expect(find.bySemanticsLabel('Кафе'), findsNothing);
    expect(taps, 0);
    semantics.dispose();
  });

  testWidgets('semanticsLabel заменяет фразу', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(
        PickerField(
          label: 'Подкатегория',
          value: 'Без подкатегории',
          semanticsLabel: 'Без подкатегории',
          onTap: () {},
        ),
      ),
    );
    expect(find.bySemanticsLabel('Без подкатегории'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Подкатегория: Без подкатегории'),
      findsNothing,
    );
    semantics.dispose();
  });

  testWidgets('крупный шрифт 200 %: длинное значение переносится', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        PickerField(
          label: 'Категория',
          value: 'Очень длинное название категории расходов на дом',
          onTap: () {},
        ),
        scale: 2,
      ),
    );
    expect(tester.takeException(), isNull);
    final h = tester.getSize(find.byType(PickerField)).height;
    expect(h, greaterThan(100));
  });
}
