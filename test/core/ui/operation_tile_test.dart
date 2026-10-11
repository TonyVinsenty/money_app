import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/ui/category_avatar.dart';
import 'package:money_app/core/ui/masked_amount.dart';
import 'package:money_app/core/ui/operation_tile.dart';
import 'package:money_app/core/ui/theme/app_colors.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';

import '../../support/roboto_font.dart';

Widget _host(Widget child) => MaterialApp(
  theme: AppTheme.light(),
  home: Scaffold(body: child),
);

Money _rub(int minor) => Money.fromMinor(minor, 'RUB');

void main() {
  testWidgets('расход: настоящий минус и цвет расхода', (tester) async {
    await tester.pumpWidget(
      _host(
        OperationTile(
          title: 'Еда',
          amount: _rub(12345),
          isIncome: false,
          semanticLabel: 'подпись',
        ),
      ),
    );
    final text = '−${formatMoney(_rub(12345))}';
    final widget = tester.widget<Text>(find.text(text));
    expect(widget.style?.color, AppColors.light.expense);
  });

  testWidgets('доход: плюс и цвет дохода', (tester) async {
    await tester.pumpWidget(
      _host(
        OperationTile(
          title: 'Зарплата',
          amount: _rub(5000),
          isIncome: true,
          semanticLabel: 'подпись',
        ),
      ),
    );
    final widget = tester.widget<Text>(
      find.text('+${formatMoney(_rub(5000))}'),
    );
    expect(widget.style?.color, AppColors.light.income);
  });

  testWidgets('вторая строка показывается только если задана', (tester) async {
    await tester.pumpWidget(
      _host(
        OperationTile(
          title: 'Еда · Кафе',
          subtitle: 'Вчера · обед',
          amount: _rub(100),
          isIncome: false,
          semanticLabel: 'x',
        ),
      ),
    );
    expect(find.text('Еда · Кафе'), findsOneWidget);
    expect(find.text('Вчера · обед'), findsOneWidget);

    await tester.pumpWidget(
      _host(
        OperationTile(
          title: 'Еда',
          amount: _rub(100),
          isIncome: false,
          semanticLabel: 'x',
        ),
      ),
    );
    // Название и сумма, больше текстов нет.
    expect(find.byType(Text), findsNWidgets(2));
  });

  testWidgets('одна подпись для скринридера, внутренние тексты скрыты', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(
        OperationTile(
          title: 'Еда',
          subtitle: 'Сегодня',
          amount: _rub(100),
          isIncome: false,
          semanticLabel: 'Расход сто копеек, Еда',
          onTap: () {},
        ),
      ),
    );
    expect(find.bySemanticsLabel('Расход сто копеек, Еда'), findsOneWidget);
    expect(find.bySemanticsLabel('Сегодня'), findsNothing);
    handle.dispose();
  });

  testWidgets('касание вызывает onTap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(
        OperationTile(
          title: 'Еда',
          amount: _rub(100),
          isIncome: false,
          semanticLabel: 'x',
          onTap: () => taps++,
        ),
      ),
    );
    await tester.tap(find.byType(OperationTile));
    expect(taps, 1);
  });

  testWidgets('без onTap строка не нажимается (нет InkWell)', (tester) async {
    await tester.pumpWidget(
      _host(
        OperationTile(
          title: 'Еда',
          amount: _rub(100),
          isIncome: false,
          semanticLabel: 'x',
        ),
      ),
    );
    expect(find.byType(InkWell), findsNothing);
  });

  testWidgets('суммы скрыты: цифр нет, облачко, остальное на месте', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: AmountsVisibility(
            hidden: true,
            child: OperationTile(
              title: 'Еда',
              subtitle: 'Сегодня',
              amount: _rub(12345),
              isIncome: false,
              semanticLabel: 'Расход, сумма скрыта, Еда',
            ),
          ),
        ),
      ),
    );
    expect(find.textContaining(formatMoney(_rub(12345))), findsNothing);
    expect(find.byKey(const ValueKey('masked-amount-cloud')), findsOneWidget);
    expect(find.text('Еда'), findsOneWidget);
    expect(find.text('Сегодня'), findsOneWidget);
  });

  group('CategoryAvatar', () {
    testWidgets('по умолчанию нейтральный кружок со значком', (tester) async {
      await tester.pumpWidget(_host(const CategoryAvatar('restaurant')));
      expect(find.byIcon(Icons.restaurant), findsOneWidget);
      final box = tester.widget<Container>(find.byType(Container).first);
      final decoration = box.decoration! as BoxDecoration;
      expect(decoration.shape, BoxShape.circle);
      final ctx = tester.element(find.byType(CategoryAvatar));
      expect(
        decoration.color,
        Theme.of(ctx).colorScheme.surfaceContainerHighest,
      );
      expect(tester.getSize(find.byType(CategoryAvatar)), const Size(40, 40));
    });

    testWidgets('заданный цвет заливки применяется', (tester) async {
      await tester.pumpWidget(
        _host(const CategoryAvatar(null, color: Colors.red)),
      );
      final box = tester.widget<Container>(find.byType(Container).first);
      expect((box.decoration! as BoxDecoration).color, Colors.red);
    });
  });

  group('крупный шрифт: двухэтажная строка (7.32)', () {
    // Настоящий Roboto: тестовый шрифт рисует буквы квадратами, и ширину
    // суммы по нему не проверить.
    setUpAll(loadRoboto);

    Future<void> pumpAt(
      WidgetTester tester,
      double scale, {
      int minor = 123456789,
      double width = 360,
    }) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: ListView(
              children: [
                OperationTile(
                  title: 'Развлечения · Кино и театр',
                  subtitle: '12 октября',
                  amount: _rub(minor),
                  isIncome: false,
                  semanticLabel: 'подпись',
                ),
              ],
            ),
          ),
        ),
      );
    }

    final amount = find.byKey(OperationTile.amountKey);
    final title = find.text('Развлечения · Кино и театр');

    /// Во сколько раз сумма уменьшена: ширина на экране к ширине раскладки.
    double shrink(WidgetTester tester) =>
        tester.getRect(amount).width / tester.getSize(amount).width;

    testWidgets('100 %: сумма в той же строке справа', (tester) async {
      await pumpAt(tester, 1);
      expect(tester.takeException(), isNull);
      expect(
        tester.getTopLeft(amount).dx,
        greaterThan(tester.getTopRight(title).dx),
      );
      expect(
        tester.getTopLeft(amount).dy,
        lessThan(tester.getBottomLeft(title).dy),
      );
    });

    for (final scale in [1.3, 2.0]) {
      testWidgets('${scale * 100} %, 360 dp: сумма под названием целиком', (
        tester,
      ) async {
        await pumpAt(tester, scale);
        expect(tester.takeException(), isNull);
        // Под названием, с той же левой линии.
        expect(
          tester.getTopLeft(amount).dy,
          greaterThanOrEqualTo(tester.getBottomLeft(title).dy),
        );
        expect(tester.getTopLeft(amount).dx, tester.getTopLeft(title).dx);
        // В полный размер и в одну строку.
        expect(shrink(tester), moreOrLessEquals(1));
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(of: amount, matching: find.byType(RichText)),
        );
        final oneLine = TextPainter(
          text: paragraph.text,
          textDirection: TextDirection.ltr,
          textScaler: paragraph.textScaler,
        )..layout();
        expect(paragraph.size.height, moreOrLessEquals(oneLine.height));
        expect(tester.getTopRight(amount).dx, lessThanOrEqualTo(360 - 16));
        oneLine.dispose();
      });
    }

    testWidgets('200 %, 280 dp: сумма шире строки уменьшается, не рвётся', (
      tester,
    ) async {
      // 999 999 999,99 ₽ на 360 dp ещё помещается; на 280 dp — уже нет.
      await pumpAt(tester, 2, minor: 99999999999, width: 280);
      expect(tester.takeException(), isNull);
      expect(shrink(tester), lessThan(1));
      expect(tester.getTopRight(amount).dx, lessThanOrEqualTo(280 - 16));
    });

    testWidgets('порог: 129 % — ещё в строку', (tester) async {
      await pumpAt(tester, 1.29);
      expect(
        tester.getTopLeft(amount).dx,
        greaterThan(tester.getTopRight(title).dx),
      );
    });
  });
}
