import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/features/settings/presentation/settings_screen.dart';
import 'package:money_app/features/settings/presentation/share_csv_file.dart';

Widget _app({
  ThemeMode mode = ThemeMode.system,
  ValueChanged<ThemeMode>? onChanged,
  VoidCallback? onCategories,
  Future<String> Function()? onExport,
  ShareFile? shareFile,
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
        onExportCsv: onExport ?? () async => '/tmp/zuno-export.csv',
        shareFile: shareFile ?? (_) async {},
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

  group('экспорт в CSV', () {
    Finder exportItem() => find.widgetWithText(ListTile, exportCsvItemLabel);

    testWidgets('пункт «Экспорт в CSV» виден на экране', (tester) async {
      await tester.pumpWidget(_app());

      expect(find.text(exportCsvItemLabel), findsOneWidget);
      expect(tester.widget<ListTile>(exportItem()).enabled, isTrue);
    });

    testWidgets('тап готовит файл и отправляет его, ошибки нет', (
      tester,
    ) async {
      var exported = 0;
      final shared = <String>[];
      await tester.pumpWidget(
        _app(
          onExport: () async {
            exported++;
            return '/tmp/zuno-export-2026-10-04.csv';
          },
          shareFile: (path) async => shared.add(path),
        ),
      );

      await tester.tap(find.text(exportCsvItemLabel));
      await tester.pumpAndSettle();

      expect(exported, 1);
      expect(shared, ['/tmp/zuno-export-2026-10-04.csv']);
      expect(find.text(exportCsvFailedMessage), findsNothing);
      expect(tester.widget<ListTile>(exportItem()).enabled, isTrue);
    });

    testWidgets('во время выгрузки пункт недоступен и не запускается дважды', (
      tester,
    ) async {
      final gate = Completer<String>();
      var exported = 0;
      await tester.pumpWidget(
        _app(
          onExport: () {
            exported++;
            return gate.future;
          },
        ),
      );

      await tester.tap(find.text(exportCsvItemLabel));
      // Индикатор крутится вечно, поэтому pumpAndSettle здесь не годится.
      await tester.pump();

      expect(tester.widget<ListTile>(exportItem()).enabled, isFalse);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.tap(find.text(exportCsvItemLabel));
      await tester.pump();
      expect(exported, 1);

      gate.complete('/tmp/zuno-export.csv');
      await tester.pumpAndSettle();
      expect(tester.widget<ListTile>(exportItem()).enabled, isTrue);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('ошибка выгрузки: SnackBar, файл не отправляется', (
      tester,
    ) async {
      var shareCalls = 0;
      await tester.pumpWidget(
        _app(
          onExport: () async => throw Exception('база испорчена'),
          shareFile: (_) async => shareCalls++,
        ),
      );

      await tester.tap(find.text(exportCsvItemLabel));
      await tester.pumpAndSettle();

      expect(find.text(exportCsvFailedMessage), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(shareCalls, 0);
      // После ошибки пункт снова доступен.
      expect(tester.widget<ListTile>(exportItem()).enabled, isTrue);
    });
  });
}
