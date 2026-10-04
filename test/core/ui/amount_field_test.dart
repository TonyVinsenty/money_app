import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/money/currency.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/money/parse_amount.dart';
import 'package:money_app/core/ui/amount_failure_text.dart';
import 'package:money_app/core/ui/amount_field.dart';
import 'package:money_app/core/ui/theme/app_colors.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';

import '../../support/contrast.dart';

final String _minus = String.fromCharCode(0x2212);
final String _nbsp = String.fromCharCode(0x00A0);

Widget _host(
  AmountFieldController controller, {
  bool isIncome = false,
  ValueChanged<Money>? onSubmitted,
  double textScale = 1,
  ThemeMode mode = ThemeMode.light,
}) {
  return MaterialApp(
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    themeMode: mode,
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: AmountField(
              controller: controller,
              isIncome: isIncome,
              onSubmitted: onSubmitted,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  late AmountFieldController controller;

  setUp(() => controller = AmountFieldController());
  tearDown(() => controller.dispose());

  Future<void> pumpHost(WidgetTester tester) =>
      tester.pumpWidget(_host(controller));

  testWidgets('буква не печатается, цифры группируются', (tester) async {
    await tester.pumpWidget(_host(controller));

    await tester.enterText(find.byType(TextField), 'abc');
    expect(controller.text.text, '');

    await tester.enterText(find.byType(TextField), '1234,5');
    expect(controller.text.text, '1${_nbsp}234,5');
  });

  testWidgets('«0» ошибкой не считается', (tester) async {
    await tester.pumpWidget(_host(controller));

    await tester.enterText(find.byType(TextField), '0');
    await tester.pump();
    controller.submit();
    await tester.pump();

    expect(controller.visibleFailure, isNull);
    expect(
      find.text(amountFailureMessage(AmountParseFailure.empty)),
      findsNothing,
    );
    final result = controller.result;
    expect(result, isA<AmountParsed>());
    expect((result as AmountParsed).amount, Money.zero(rubCurrencyCode));
  });

  testWidgets('пустое поле: «0» бледный и не похож на введённое значение', (
    tester,
  ) async {
    await tester.pumpWidget(_host(controller));

    final hint = tester.widget<Text>(find.text('0'));
    final entered = tester.widget<EditableText>(find.byType(EditableText));
    expect(hint.style!.color, isNot(entered.style.color));
    expect(hint.style!.color!.a, lessThan(1));

    // После ввода подсказки нет: остаётся только введённый текст.
    await tester.enterText(find.byType(TextField), '5');
    await tester.pump();
    expect(find.text('0'), findsNothing);
  });

  testWidgets('введён именно «0»: подсказки нет, в поле настоящий «0»', (
    tester,
  ) async {
    await tester.pumpWidget(_host(controller));
    final hint = find.byWidgetPredicate((w) => w is Text && w.data == '0');
    expect(hint, findsOneWidget);

    await tester.enterText(find.byType(TextField), '0');
    await tester.pump();

    expect(hint, findsNothing);
    expect(controller.text.text, '0');
    // Единственный «0» на экране — текст самого поля.
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      '0',
    );
  });

  testWidgets('подсказка «0» заметна в обеих темах, но бледнее цифр', (
    tester,
  ) async {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      await tester.pumpWidget(_host(controller, mode: mode));
      // Смена темы плавная: ждём конца анимации.
      await tester.pumpAndSettle();

      final surface = Theme.of(tester.element(find.byType(AmountField)))
          .colorScheme
          .surface;
      final hint = tester.widget<Text>(find.text('0')).style!.color!;
      final entered = tester
          .widget<EditableText>(find.byType(EditableText))
          .style
          .color!;

      final hintContrast = contrastRatio(hint, surface);
      final enteredContrast = contrastRatio(entered, surface);
      // Для отчёта: фактические числа.
      debugPrint('contrast $mode: hint $hintContrast, digits $enteredContrast');
      expect(hintContrast, greaterThanOrEqualTo(2), reason: '$mode');
      expect(hintContrast, lessThan(enteredContrast - 1), reason: '$mode');
    }
  });

  testWidgets('«Введите сумму» появляется только после попытки продолжить', (
    tester,
  ) async {
    await tester.pumpWidget(_host(controller));
    final message = amountFailureMessage(AmountParseFailure.empty);

    // Пока не пробовали продолжить, ошибки нет.
    expect(find.text(message), findsNothing);

    // Попытка, как кнопка «Далее» снаружи виджета.
    expect(controller.submit(), isNull);
    await tester.pump();
    expect(find.text(message), findsOneWidget);

    // После ввода суммы ошибка пропадает.
    await tester.enterText(find.byType(TextField), '5');
    await tester.pump();
    expect(find.text(message), findsNothing);
  });

  testWidgets('клавиша «Далее» на клавиатуре тоже считается попыткой', (
    tester,
  ) async {
    final submitted = <Money>[];
    await tester.pumpWidget(_host(controller, onSubmitted: submitted.add));

    await tester.tap(find.byType(TextField));
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pump();

    expect(
      find.text(amountFailureMessage(AmountParseFailure.empty)),
      findsOneWidget,
    );
    expect(submitted, isEmpty);

    await tester.enterText(find.byType(TextField), '12,5');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pump();

    expect(submitted, [Money.fromMinor(1250, rubCurrencyCode)]);
  });

  group('зона нажатия', () {
    testWidgets('тап по знаку ставит фокус в поле', (tester) async {
      await pumpHost(tester);
      expect(controller.focusNode.hasFocus, isFalse);

      await tester.tap(find.text(_minus));
      await tester.pump();

      expect(controller.focusNode.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
    });

    testWidgets('тап по «₽» тоже, и клавиатура возвращается после «Назад»', (
      tester,
    ) async {
      await pumpHost(tester);
      await tester.tap(find.text('₽'));
      await tester.pump();
      expect(controller.focusNode.hasFocus, isTrue);

      // Клавиатуру закрыли жестом «Назад»: фокус остался, клавиатуры нет.
      tester.testTextInput.hide();
      await tester.pump();
      expect(tester.testTextInput.isVisible, isFalse);

      await tester.tap(find.text(_minus));
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);
    });

    testWidgets('область нажатия не ниже 48 dp и охватывает всю строку', (
      tester,
    ) async {
      await pumpHost(tester);

      final area = tester.getRect(
        find.ancestor(
          of: find.text(_minus),
          matching: find.byType(GestureDetector),
        ),
      );
      expect(area.height, greaterThanOrEqualTo(48));
      expect(
        area.left,
        lessThanOrEqualTo(tester.getRect(find.text(_minus)).left),
      );
      expect(
        area.right,
        greaterThanOrEqualTo(tester.getRect(find.text('₽')).right),
      );
    });

    testWidgets('семантика поля не задвоилась', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpHost(tester);

      expect(find.bySemanticsLabel('Сумма расхода'), findsOneWidget);
      semantics.dispose();
    });
  });

  testWidgets('слишком большая сумма показывает ошибку сразу, без попытки', (
    tester,
  ) async {
    await tester.pumpWidget(_host(controller));

    await tester.enterText(find.byType(TextField), '1000000000001');
    await tester.pump();

    expect(
      find.text(amountFailureMessage(AmountParseFailure.tooLarge)),
      findsOneWidget,
    );
  });

  testWidgets('на клавиатуре есть десятичный разделитель', (tester) async {
    await tester.pumpWidget(_host(controller));

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.keyboardType.decimal, isTrue);
    expect(field.inputFormatters?.single, isA<TextInputFormatter>());
  });

  testWidgets(
    'системный шрифт 200 % не ломает верстку даже с огромной суммой',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_host(controller, textScale: 2));
      await tester.enterText(find.byType(TextField), '999999999999,99');
      await tester.pump();
      // Заодно ошибка под полем при таком шрифте.
      controller.text.text = '9999999999999,99';
      await tester.pump();

      expect(tester.takeException(), isNull);
      final fieldBox = tester.getRect(find.byType(TextField));
      expect(fieldBox.right, lessThanOrEqualTo(360));
      expect(fieldBox.left, greaterThanOrEqualTo(0));
    },
  );

  group('знак и подпись для скринридера', () {
    testWidgets('расход: знак «\u2212» виден, «+» нет', (tester) async {
      await tester.pumpWidget(_host(controller));

      expect(find.text(_minus), findsOneWidget);
      expect(find.text('+'), findsNothing);
      final colors = tester.element(find.byType(AmountField)).appColors;
      expect(
        tester.widget<Text>(find.text(_minus)).style?.color,
        colors.expense,
      );
    });

    testWidgets('доход: знак «+» виден, «\u2212» нет', (tester) async {
      await tester.pumpWidget(_host(controller, isIncome: true));

      expect(find.text('+'), findsOneWidget);
      expect(find.text(_minus), findsNothing);
      final colors = tester.element(find.byType(AmountField)).appColors;
      expect(tester.widget<Text>(find.text('+')).style?.color, colors.income);
    });

    testWidgets('расход читается прописью', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(_host(controller));

      // Пусто: только название поля.
      expect(find.bySemanticsLabel('Сумма расхода'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '1234,5');
      await tester.pump();
      expect(
        find.bySemanticsLabel('Расход 1234 рубля 50 копеек'),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('доход читается прописью, ошибка не озвучивается мусором', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(_host(controller, isIncome: true));

      expect(find.bySemanticsLabel('Сумма дохода'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '5');
      await tester.pump();
      expect(find.bySemanticsLabel('Доход 5 рублей'), findsOneWidget);

      // Слишком большая сумма: снова только название поля.
      await tester.enterText(find.byType(TextField), '1000000000001');
      await tester.pump();
      expect(find.bySemanticsLabel('Сумма дохода'), findsOneWidget);
      semantics.dispose();
    });
  });
}
