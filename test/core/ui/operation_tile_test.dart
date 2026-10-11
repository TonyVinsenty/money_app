import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/ui/category_avatar.dart';
import 'package:money_app/core/ui/masked_amount.dart';
import 'package:money_app/core/ui/operation_tile.dart';
import 'package:money_app/core/ui/theme/app_colors.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';

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
}
