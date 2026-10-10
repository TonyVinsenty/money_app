import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/core/money/currency_catalog.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/features/csv_import/domain/csv_import_result.dart';
import 'package:money_app/features/settings/domain/home_balance_line.dart';
import 'package:money_app/features/settings/presentation/settings_screen.dart';
import 'package:money_app/features/settings/presentation/share_csv_file.dart';

Widget _app({
  ThemeMode mode = ThemeMode.system,
  ValueChanged<ThemeMode>? onChanged,
  HomeBalanceLine balanceLine = HomeBalanceLine.allTime,
  ValueChanged<HomeBalanceLine>? onBalanceLine,
  VoidCallback? onCategories,
  Future<String> Function()? onExport,
  ShareFile? shareFile,
  DateOnly? lastExportDay,
  VoidCallback? onExportShared,
  Future<CsvImportResult?> Function()? onImportCsv,
  Future<void> Function()? onClearAll,
  ValueChanged<CurrencyInfo>? onMainCurrency,
  double textScale = 1,
  bool screenReader = false,
}) {
  var main = catalogCurrency('RUB')!;
  return MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
        accessibleNavigation: screenReader,
      ),
      child: child!,
    ),
    home: Scaffold(
      body: StatefulBuilder(
        builder: (context, setState) => SettingsScreen(
          themeMode: mode,
          onThemeModeChanged: onChanged ?? (_) {},
          homeBalanceLine: balanceLine,
          onHomeBalanceLineChanged: onBalanceLine ?? (_) {},
          onOpenCategories: onCategories ?? () {},
          mainCurrency: main,
          onMainCurrencyChanged: (value) {
            onMainCurrency?.call(value);
            setState(() => main = value);
          },
          onExportCsv: onExport ?? () async => '/tmp/zuno-export.csv',
          shareFile: shareFile ?? (_) async => true,
          lastExportDay: lastExportDay,
          today: DateOnly(2026, 10, 7),
          onExportShared: onExportShared ?? () {},
          onImportCsv: onImportCsv ?? () async => null,
          onClearAll: onClearAll ?? () async {},
        ),
      ),
    ),
  );
}

/// Какая тема сейчас выбрана в группе переключателей.
ThemeMode _groupValue(WidgetTester tester) => tester
    .widget<RadioGroup<ThemeMode>>(find.byType(RadioGroup<ThemeMode>))
    .groupValue!;

void main() {
  // Высокое окно: после раздела «Строка «Баланс»» нижние пункты иначе
  // оказываются за экраном ленивого списка.
  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.physicalSize = const Size(800, 2400);
    view.devicePixelRatio = 1;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);
  });

  setUpAll(() => initializeDateFormatting('ru'));

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

  group('строка «Баланс» на Главной', () {
    testWidgets('раздел виден, тексты дословно, выбран текущий', (
      tester,
    ) async {
      await tester.pumpWidget(_app(balanceLine: HomeBalanceLine.accounts));

      expect(find.text('Строка «Баланс» на Главной'), findsOneWidget);
      expect(find.text('Все доходы минус все расходы'), findsOneWidget);
      expect(find.text('За всё время'), findsOneWidget);
      expect(find.text('Сумма на счетах'), findsOneWidget);
      expect(find.text('Счета в основной валюте'), findsOneWidget);
      expect(find.text('Не показывать'), findsOneWidget);
      expect(
        tester
            .widget<RadioGroup<HomeBalanceLine>>(
              find.byType(RadioGroup<HomeBalanceLine>),
            )
            .groupValue,
        HomeBalanceLine.accounts,
      );
    });

    for (final (label, line) in [
      ('Все доходы минус все расходы', HomeBalanceLine.allTime),
      ('Сумма на счетах', HomeBalanceLine.accounts),
      ('Не показывать', HomeBalanceLine.none),
    ]) {
      testWidgets('тап «$label» сообщает $line', (tester) async {
        final start = line == HomeBalanceLine.none
            ? HomeBalanceLine.allTime
            : HomeBalanceLine.none;
        final calls = <HomeBalanceLine>[];
        await tester.pumpWidget(
          _app(balanceLine: start, onBalanceLine: calls.add),
        );

        await tester.tap(find.text(label));
        await tester.pump();

        expect(calls, [line]);
      });
    }
  });

  testWidgets('пункт «Категории» вызывает переход', (tester) async {
    var opened = 0;
    await tester.pumpWidget(_app(onCategories: () => opened++));

    await tester.tap(find.text('Категории'));

    expect(opened, 1);
  });

  group('очистить всё', () {
    void tall(WidgetTester tester, {double width = 800}) {
      tester.view.physicalSize = Size(width, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    Future<void> openDialog(WidgetTester tester) async {
      await tester.tap(find.text('Очистить всё'));
      await tester.pumpAndSettle();
    }

    testWidgets('пункт внизу с подписью, цвет ошибки у заголовка', (
      tester,
    ) async {
      tall(tester);
      await tester.pumpWidget(_app());

      expect(find.text('Стереть операции, категории и счета'), findsOneWidget);
      expect(
        _titleColor(tester),
        Theme.of(tester.element(find.byType(SettingsScreen))).colorScheme.error,
      );
    });

    testWidgets('диалог: тексты дословно, кнопки по порядку', (tester) async {
      tall(tester);
      await tester.pumpWidget(_app());
      await openDialog(tester);

      expect(
        find.text('Стереть все операции, категории и счета?'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Это действие нельзя отменить. '
          'Восстановить данные можно только из файла экспорта CSV.',
        ),
        findsOneWidget,
      );
      final x = [
        for (final t in ['Сначала экспорт', 'Отмена', 'Стереть всё'])
          tester.getTopLeft(find.widgetWithText(TextButton, t)).dx,
      ];
      expect(x[0] < x[1] && x[1] < x[2], isTrue);
      final accept = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Стереть всё'),
      );
      final context = tester.element(find.byType(AlertDialog));
      expect(
        accept.style?.foregroundColor?.resolve({}),
        Theme.of(context).colorScheme.error,
      );
    });

    testWidgets('«Отмена», «Назад» и тап мимо не стирают', (tester) async {
      tall(tester);
      var erased = 0;
      await tester.pumpWidget(_app(onClearAll: () async => erased++));

      await openDialog(tester);
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);

      await openDialog(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);

      await openDialog(tester);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);

      expect(erased, 0);
    });

    testWidgets('«Сначала экспорт» запускает экспорт и не стирает', (
      tester,
    ) async {
      tall(tester);
      var exported = 0;
      var erased = 0;
      final shared = <String>[];
      await tester.pumpWidget(
        _app(
          onExport: () async {
            exported++;
            return '/tmp/a.csv';
          },
          shareFile: (path) async {
            shared.add(path);
            return true;
          },
          onClearAll: () async => erased++,
        ),
      );

      await openDialog(tester);
      await tester.tap(find.text('Сначала экспорт'));
      await tester.pumpAndSettle();

      expect(exported, 1);
      expect(shared, ['/tmp/a.csv']);
      expect(erased, 0);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('«Стереть всё»: один вызов, сообщение Н3', (tester) async {
      tall(tester);
      var erased = 0;
      await tester.pumpWidget(_app(onClearAll: () async => erased++));

      await openDialog(tester);
      await tester.tap(find.text('Стереть всё'));
      await tester.pump();
      await tester.pump();

      expect(erased, 1);
      expect(
        find.text('Данные стёрты. Категории — как при первом запуске'),
        findsOneWidget,
      );
    });

    testWidgets('во время стирания индикатор и повторное нажатие не работает', (
      tester,
    ) async {
      tall(tester);
      var erased = 0;
      final gate = Completer<void>();
      await tester.pumpWidget(
        _app(
          onClearAll: () {
            erased++;
            return gate.future;
          },
        ),
      );

      await openDialog(tester);
      await tester.tap(find.text('Стереть всё'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('Очистить всё'), warnIfMissed: false);
      await tester.pump();

      expect(erased, 1);
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        tester
            .widget<CircularProgressIndicator>(
              find.byType(CircularProgressIndicator),
            )
            .semanticsLabel,
        'Стираем данные',
      );
      gate.complete();
      await tester.pumpAndSettle();
      expect(erased, 1);
    });

    testWidgets('висевший SnackBar убирается, пока стирание ещё идёт', (
      tester,
    ) async {
      tall(tester);
      final gate = Completer<void>();
      await tester.pumpWidget(_app(onClearAll: () => gate.future));
      final ctx = tester.element(find.byType(SettingsScreen));
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(content: Text('Старое'), duration: Duration(minutes: 5)),
      );
      await tester.pump();
      expect(find.text('Старое'), findsOneWidget);

      await openDialog(tester);
      await tester.tap(find.text('Стереть всё'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Старое'), findsNothing);
      gate.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('ошибка стирания: сообщение Н4, экран жив', (tester) async {
      tall(tester);
      await tester.pumpWidget(
        _app(onClearAll: () async => throw Exception('boom')),
      );

      await openDialog(tester);
      await tester.tap(find.text('Стереть всё'));
      await tester.pump();
      await tester.pump();

      expect(
        find.text('Не удалось стереть данные. Ничего не изменилось'),
        findsOneWidget,
      );
      expect(find.text('Очистить всё'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('во время экспорта пункт недоступен', (tester) async {
      tall(tester);
      final gate = Completer<String>();
      await tester.pumpWidget(_app(onExport: () => gate.future));

      await tester.tap(find.text('Экспорт в CSV'));
      await tester.pump();
      await tester.tap(find.text('Очистить всё'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(AlertDialog), findsNothing);
      expect(
        _titleColor(tester),
        isNot(
          Theme.of(tester.element(find.byType(SettingsScreen)))
              .colorScheme
              .error,
        ),
      );
      gate.complete('/tmp/x.csv');
      await tester.pumpAndSettle();
    });

    testWidgets('два тапа по «Стереть всё» без pump: один вызов, каркас жив', (
      tester,
    ) async {
      tall(tester);
      var erased = 0;
      await tester.pumpWidget(_app(onClearAll: () async => erased++));

      await openDialog(tester);
      final accept = find.text('Стереть всё');
      await tester.tap(accept);
      await tester.tap(accept, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(erased, 1);
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final scale in [1.0, 2.0]) {
      testWidgets('360 dp, шрифт ${scale * 100} %: без переполнения', (
        tester,
      ) async {
        tall(tester, width: 360);
        await tester.pumpWidget(_app(textScale: scale));
        expect(
          find.text('Стереть операции, категории и счета'),
          findsOneWidget,
        );

        await openDialog(tester);

        expect(tester.takeException(), isNull);
        expect(find.text('Стереть всё'), findsOneWidget);
        if (scale == 2.0) {
          // Кнопки встают столбиком.
          final a = tester.getTopLeft(find.text('Сначала экспорт'));
          final b = tester.getTopLeft(find.text('Стереть всё'));
          expect(a.dy != b.dy, isTrue);
        }
      });
    }
  });

  group('основная валюта', () {
    Future<void> openPicker(WidgetTester tester) async {
      await tester.tap(find.text('Основная валюта'));
      await tester.pumpAndSettle();
    }

    testWidgets('подпись пункта по умолчанию', (tester) async {
      await tester.pumpWidget(_app());

      expect(find.text('Основная валюта'), findsOneWidget);
      expect(find.text('Российский рубль, ₽'), findsOneWidget);
    });

    testWidgets('лист: заголовок «Основная валюта», крипты нет', (
      tester,
    ) async {
      await tester.pumpWidget(_app());
      await openPicker(tester);

      // Один текст в пункте настроек под листом и один заголовок листа.
      expect(find.text('Основная валюта'), findsNWidgets(2));
      expect(find.text('Криптовалюты'), findsNothing);
      expect(find.text('Своя валюта…'), findsNothing);
      expect(find.text('Биткоин'), findsNothing);
    });

    testWidgets('выбор USD: подтверждение с утверждёнными текстами', (
      tester,
    ) async {
      await tester.pumpWidget(_app());
      await openPicker(tester);

      await tester.tap(find.text('Доллар США').first);
      await tester.pumpAndSettle();

      expect(
        find.text('Сделать основной валютой «Доллар США»?'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Новые доходы и расходы будут вноситься в этой валюте. '
          'В быстрый ввод попадут только счета в этой валюте. '
          '«Главная», «История» и «Аналитика» покажут только операции в ней. '
          'Операции в других валютах сохранятся и снова появятся, '
          'если вернуть их валюту.',
        ),
        findsOneWidget,
      );
      expect(find.text('Отмена'), findsOneWidget);
      expect(find.text('Сменить'), findsOneWidget);
    });

    testWidgets('«Отмена»: остаётся рубль', (tester) async {
      final changes = <CurrencyInfo>[];
      await tester.pumpWidget(_app(onMainCurrency: changes.add));
      await openPicker(tester);
      await tester.tap(find.text('Доллар США').first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();

      expect(changes, isEmpty);
      expect(find.text('Российский рубль, ₽'), findsOneWidget);
    });

    testWidgets('«Сменить»: подпись «Доллар США, \$»', (tester) async {
      final changes = <CurrencyInfo>[];
      await tester.pumpWidget(_app(onMainCurrency: changes.add));
      await openPicker(tester);
      await tester.tap(find.text('Доллар США').first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Сменить'));
      await tester.pumpAndSettle();

      expect(changes.map((c) => c.code), ['USD']);
      expect(find.text('Доллар США, \$'), findsOneWidget);
    });

    testWidgets('та же валюта: диалога нет', (tester) async {
      final changes = <CurrencyInfo>[];
      await tester.pumpWidget(_app(onMainCurrency: changes.add));
      await openPicker(tester);

      await tester.tap(find.text('Российский рубль').first);
      await tester.pumpAndSettle();

      expect(find.text('Сменить'), findsNothing);
      expect(changes, isEmpty);
    });
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
    tester.view.physicalSize = const Size(240, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(textScale: 2));

    expect(tester.takeException(), isNull);
    final tiles = {
      for (final label in ['Как в системе', 'Светлая', 'Тёмная'])
        label: find.widgetWithText(RadioListTile<ThemeMode>, label),
      for (final label in [
        'Все доходы минус все расходы',
        'Сумма на счетах',
        'Не показывать',
      ])
        label: find.widgetWithText(RadioListTile<HomeBalanceLine>, label),
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
          shareFile: (path) async {
            shared.add(path);
            return true;
          },
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
          shareFile: (_) async {
            shareCalls++;
            return true;
          },
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

    testWidgets('подпись: выгрузки ещё не было', (tester) async {
      await tester.pumpWidget(_app());

      expect(find.text('Последний экспорт: ещё не было'), findsOneWidget);
    });

    testWidgets('подпись: день этого года без года', (tester) async {
      await tester.pumpWidget(_app(lastExportDay: DateOnly(2026, 10, 7)));

      expect(find.text('Последний экспорт: 7 октября'), findsOneWidget);
    });

    testWidgets('подпись: день прошлого года с годом', (tester) async {
      await tester.pumpWidget(_app(lastExportDay: DateOnly(2025, 10, 5)));

      // Перед «г.» intl ставит узкий неразрывный пробел, поэтому не точное
      // совпадение, а начало строки.
      expect(
        find.textContaining('Последний экспорт: 5 октября 2025'),
        findsOneWidget,
      );
    });

    testWidgets('успешный экспорт вызывает onExportShared один раз', (
      tester,
    ) async {
      var shared = 0;
      await tester.pumpWidget(_app(onExportShared: () => shared++));

      await tester.tap(find.text(exportCsvItemLabel));
      await tester.pumpAndSettle();

      expect(shared, 1);
    });

    testWidgets(
      'отмена «Поделиться»: onExportShared не вызван, без сообщений',
      (tester) async {
        var shared = 0;
        await tester.pumpWidget(
          _app(shareFile: (_) async => false, onExportShared: () => shared++),
        );

        await tester.tap(find.text(exportCsvItemLabel));
        await tester.pumpAndSettle();

        expect(shared, 0);
        expect(find.byType(SnackBar), findsNothing);
        expect(tester.widget<ListTile>(exportItem()).enabled, isTrue);
      },
    );

    testWidgets('ошибка подготовки файла: onExportShared не вызван', (
      tester,
    ) async {
      var shared = 0;
      await tester.pumpWidget(
        _app(
          onExport: () async => throw Exception('нет места'),
          onExportShared: () => shared++,
        ),
      );

      await tester.tap(find.text(exportCsvItemLabel));
      await tester.pumpAndSettle();

      expect(shared, 0);
    });

    testWidgets('экран закрыт, пока «Поделиться» открыто: без исключений', (
      tester,
    ) async {
      final gate = Completer<bool>();
      var shared = 0;
      await tester.pumpWidget(
        _app(shareFile: (_) => gate.future, onExportShared: () => shared++),
      );

      await tester.tap(find.text(exportCsvItemLabel));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());

      gate.complete(true);
      await tester.pumpAndSettle();

      expect(shared, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('«Поделиться» не открылось: SnackBar, дата не меняется', (
      tester,
    ) async {
      var shared = 0;
      await tester.pumpWidget(
        _app(
          shareFile: (_) async => throw PlatformException(code: 'share'),
          onExportShared: () => shared++,
        ),
      );

      await tester.tap(find.text(exportCsvItemLabel));
      await tester.pumpAndSettle();

      expect(find.text(shareFailedMessage), findsOneWidget);
      expect(shared, 0);
      expect(tester.widget<ListTile>(exportItem()).enabled, isTrue);
    });
  });

  group('загрузка из CSV', () {
    testWidgets('отмена: сообщения нет', (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        _app(
          onImportCsv: () async {
            calls++;
            return null;
          },
        ),
      );
      await tester.tap(find.text(importCsvItemLabel));
      await tester.pumpAndSettle();

      expect(calls, 1);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('загружено: «Загружены 3 операции»', (tester) async {
      await tester.pumpWidget(
        _app(onImportCsv: () async => const CsvImportResult(transactions: 3)),
      );
      await tester.tap(find.text(importCsvItemLabel));
      await tester.pumpAndSettle();

      expect(find.text('Загружены 3 операции'), findsOneWidget);
    });

    testWidgets('итог без скринридера исчезает сам', (tester) async {
      await tester.pumpWidget(
        _app(onImportCsv: () async => const CsvImportResult(transactions: 3)),
      );
      await tester.tap(find.text(importCsvItemLabel));
      await tester.pumpAndSettle();

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text('Загружены 3 операции'), findsNothing);
    });

    testWidgets('со скринридером итог не исчезает, закрывается касанием', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          onImportCsv: () async => const CsvImportResult(transactions: 3),
          screenReader: true,
        ),
      );
      await tester.tap(find.text(importCsvItemLabel));
      await tester.pumpAndSettle();

      await tester.pump(const Duration(minutes: 1));
      await tester.pumpAndSettle();
      expect(find.text('Загружены 3 операции'), findsOneWidget);

      await tester.tap(find.text('Загружены 3 операции'));
      await tester.pumpAndSettle();
      expect(find.text('Загружены 3 операции'), findsNothing);
    });

    testWidgets('со скринридером новое сообщение заменяет прежнее', (
      tester,
    ) async {
      var calls = 0;
      await tester.pumpWidget(
        _app(
          onImportCsv: () async {
            if (++calls == 1) return const CsvImportResult(transactions: 3);
            throw PlatformException(code: 'busy');
          },
          screenReader: true,
        ),
      );
      await tester.tap(find.text(importCsvItemLabel));
      await tester.pumpAndSettle();
      await tester.tap(find.text(importCsvItemLabel));
      await tester.pumpAndSettle();

      expect(find.text('Загружены 3 операции'), findsNothing);
      expect(find.text(importOpenFailedMessage), findsOneWidget);
    });

    testWidgets('файл не открылся: SnackBar с текстом', (tester) async {
      await tester.pumpWidget(
        _app(onImportCsv: () async => throw PlatformException(code: 'busy')),
      );
      await tester.tap(find.text(importCsvItemLabel));
      await tester.pumpAndSettle();

      expect(find.text(importOpenFailedMessage), findsOneWidget);
    });

    testWidgets('пока идёт загрузка, второе нажатие ничего не делает', (
      tester,
    ) async {
      final done = Completer<CsvImportResult?>();
      var calls = 0;
      await tester.pumpWidget(
        _app(
          onImportCsv: () {
            calls++;
            return done.future;
          },
        ),
      );
      await tester.tap(find.text(importCsvItemLabel));
      await tester.pump();
      await tester.tap(find.text(importCsvItemLabel));
      await tester.pump();
      expect(calls, 1);

      done.complete(null);
      await tester.pumpAndSettle();
      await tester.tap(find.text(importCsvItemLabel));
      await tester.pump();
      expect(calls, 2);
    });

    test('итог по числу: 1, 3, 5, 1 234', () {
      final nbsp = String.fromCharCode(0x00A0);
      expect(importDoneMessage(1), 'Загружена 1 операция');
      expect(importDoneMessage(3), 'Загружены 3 операции');
      expect(importDoneMessage(5), 'Загружено 5 операций');
      expect(importDoneMessage(1234), 'Загружены 1${nbsp}234 операции');
    });

    test('итог со счетами (П8)', () {
      String message(int tx, int acc) =>
          importResultMessage(CsvImportResult(transactions: tx, accounts: acc));
      expect(message(5, 2), 'Загружено 5 операций, создано 2 счёта');
      expect(message(1, 1), 'Загружена 1 операция, создан 1 счёт');
      expect(message(3, 5), 'Загружены 3 операции, создано 5 счетов');
      expect(message(0, 1), 'Создан 1 счёт');
      expect(message(0, 2), 'Созданы 2 счёта');
      expect(message(0, 5), 'Создано 5 счетов');
      expect(message(5, 0), 'Загружено 5 операций');
    });

    test('итог с переводами (5.25b)', () {
      String message(int tx, int tr, int acc) => importResultMessage(
        CsvImportResult(transactions: tx, transfers: tr, accounts: acc),
      );
      expect(message(5, 2, 0), 'Загружено 5 операций и 2 перевода');
      expect(message(1, 1, 0), 'Загружена 1 операция и 1 перевод');
      expect(message(3, 5, 0), 'Загружены 3 операции и 5 переводов');
      expect(
        message(5, 2, 2),
        'Загружено 5 операций и 2 перевода, создано 2 счёта',
      );
      expect(message(0, 2, 0), 'Загружены 2 перевода');
      expect(message(0, 1, 0), 'Загружен 1 перевод');
      expect(message(0, 5, 0), 'Загружено 5 переводов');
      expect(message(0, 2, 1), 'Загружены 2 перевода, создан 1 счёт');
      expect(message(0, 0, 2), 'Созданы 2 счёта');
    });

    test('итог с регулярными платежами', () {
      String message({int tx = 0, int acc = 0, required int rec}) =>
          importResultMessage(
            CsvImportResult(transactions: tx, accounts: acc, recurring: rec),
          );
      expect(message(rec: 3), 'Добавлены регулярные платежи: 3');
      expect(
        message(tx: 5, rec: 2),
        'Загружено 5 операций, регулярные платежи: 2',
      );
      expect(message(acc: 2, rec: 1), 'Созданы 2 счёта, регулярные платежи: 1');
    });

    testWidgets('только счета: SnackBar «Созданы 2 счёта»', (tester) async {
      await tester.pumpWidget(
        _app(
          onImportCsv: () async =>
              const CsvImportResult(transactions: 0, accounts: 2),
        ),
      );
      await tester.tap(find.text(importCsvItemLabel));
      await tester.pumpAndSettle();

      expect(find.text('Созданы 2 счёта'), findsOneWidget);
    });
  });
}

/// Цвет, которым нарисован заголовок пункта «Очистить всё».
Color? _titleColor(WidgetTester tester) => tester
    .renderObject<RenderParagraph>(find.text('Очистить всё'))
    .text
    .style
    ?.color;
