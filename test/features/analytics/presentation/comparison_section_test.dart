import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/core/ui/app_card.dart';
import 'package:money_app/core/ui/category_avatar.dart';
import 'package:money_app/core/ui/theme/app_colors.dart';
import 'package:money_app/core/ui/theme/app_spacing.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/analytics/presentation/comparison_section.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

import '../../../support/roboto_font.dart';

final _today = DateOnly(2026, 10, 11);
final _october = monthRange(DateOnly(2026, 10, 1));
final _sept11 = DateRange(DateOnly(2026, 9, 1), DateOnly(2026, 9, 11));
final _nbsp = String.fromCharCode(0x00A0);
final _minus = String.fromCharCode(0x2212);

final _categories = [
  Category.topLevel(
    id: 'cafe',
    kind: CategoryKind.expense,
    name: 'Кафе',
    iconKey: 'icon',
    sortOrder: 0,
  ),
  Category.topLevel(
    id: 'cinema',
    kind: CategoryKind.expense,
    name: 'Кино',
    iconKey: 'icon',
    sortOrder: 1,
  ),
  Category.topLevel(
    id: 'pay',
    kind: CategoryKind.income,
    name: 'Зарплата',
    iconKey: 'icon',
    sortOrder: 2,
  ),
];

/// Операция [minor] копеек в категории [categoryId] в день [day] (месяц и год
/// берутся из [month]).
Transaction _tx(
  String id,
  String categoryId,
  int minor,
  DateOnly day, {
  TransactionType type = TransactionType.expense,
}) => Transaction(
  id: id,
  type: type,
  amount: Money.fromMinor(minor, 'RUB'),
  occurredOn: day,
  occurredAt: DateTime.utc(day.year, day.month, day.day, 9),
  categoryId: categoryId,
);

Future<void> _pump(
  WidgetTester tester, {
  required List<Transaction> transactions,
  DateRange? range,
  DateRange? previousRange,
  DateOnly? today,
  TransactionType type = TransactionType.expense,
  ValueChanged<TransactionType>? onType,
  ValueChanged<Category>? onOpen,
  double textScale = 1,
}) async {
  tester.view.physicalSize = const Size(360, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ComparisonSection(
              transactions: transactions,
              range: range ?? _october,
              previousRange: previousRange ?? _sept11,
              categories: _categories,
              today: today ?? _today,
              type: type,
              onTypeSelected: onType,
              onOpenCategory: onOpen,
            ),
          ],
        ),
      ),
    ),
  );
}

String _textOf(WidgetTester tester, Key key) => tester
    .widgetList<Text>(
      find.descendant(of: find.byKey(key), matching: find.byType(Text)),
    )
    .map((t) => t.data)
    .join('\n');

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  final oct = DateOnly(2026, 10, 5);
  final sep = DateOnly(2026, 9, 5);

  testWidgets('аватар строки вровень с краем карточки, как заголовок (8.9)', (
    tester,
  ) async {
    await _pump(
      tester,
      transactions: [
        _tx('a', 'cafe', 800000, oct),
        _tx('b', 'cafe', 570000, sep),
      ],
    );
    final avatars = find.byType(CategoryAvatar);
    expect(avatars, findsWidgets);
    for (final avatar in avatars.evaluate().map(
      (e) => find.byElementPredicate((x) => x == e),
    )) {
      final card = find.ancestor(of: avatar, matching: find.byType(AppCard));
      expect(
        tester.getTopLeft(avatar).dx,
        tester.getTopLeft(card.first).dx + AppSpacing.l,
      );
    }
  });

  testWidgets('больше: итог, процент и строка категории', (tester) async {
    await _pump(
      tester,
      transactions: [
        _tx('a', 'cafe', 800000, oct),
        _tx('b', 'cafe', 570000, sep),
      ],
    );

    expect(
      _textOf(tester, ComparisonSection.totalKey),
      'Расходы\n'
      '8${_nbsp}000,00$_nbsp₽\n'
      'на 2${_nbsp}300,00$_nbsp₽ больше (+40$_nbsp%), чем 1\u2013\u206011$_nbspсентября',
    );
    expect(find.text('Кафе'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(ComparisonSection.rowKey('cafe')),
        matching: find.text('8${_nbsp}000,00$_nbsp₽'),
      ),
      findsOneWidget,
    );
    expect(
      find.text('↑ на 2${_nbsp}300,00$_nbsp₽ (+40$_nbsp%)'),
      findsOneWidget,
    );
  });

  testWidgets('строка категории с нейтральным аватаром', (tester) async {
    await _pump(tester, transactions: [_tx('a', 'cafe', 800000, oct)]);

    final avatar = tester.widget<CategoryAvatar>(find.byType(CategoryAvatar));
    expect(avatar.iconKey, 'icon');
    expect(avatar.color, isNull);
  });

  testWidgets('меньше, целый прошлый месяц: «чем в августе»', (tester) async {
    await _pump(
      tester,
      range: monthRange(DateOnly(2026, 9, 1)),
      previousRange: monthRange(DateOnly(2026, 8, 1)),
      transactions: [
        _tx('a', 'cafe', 210000, sep),
        _tx('b', 'cafe', 250000, DateOnly(2026, 8, 5)),
      ],
    );

    expect(
      _textOf(tester, ComparisonSection.totalKey),
      contains('на 400,00$_nbsp₽ меньше (${_minus}16$_nbsp%), чем в августе'),
    );
    expect(
      find.text('↓ на 400,00$_nbsp₽ (${_minus}16$_nbsp%)'),
      findsOneWidget,
    );
  });

  testWidgets('столько же', (tester) async {
    await _pump(
      tester,
      transactions: [_tx('a', 'cafe', 1000, oct), _tx('b', 'cafe', 1000, sep)],
    );

    expect(
      _textOf(tester, ComparisonSection.totalKey),
      contains('столько же, сколько 1\u2013\u206011$_nbspсентября'),
    );
    expect(find.text('= столько же'), findsOneWidget);
  });

  testWidgets('в прошлом пусто: «расходов не было» и «раньше не было»', (
    tester,
  ) async {
    await _pump(tester, transactions: [_tx('a', 'cafe', 1000, oct)]);

    expect(
      _textOf(tester, ComparisonSection.totalKey),
      contains('1\u2013\u206011$_nbspсентября расходов не было'),
    );
    expect(find.text('раньше не было'), findsOneWidget);
  });

  testWidgets('исчезнувшая категория: «0,00 ₽ · было …» и в конце списка', (
    tester,
  ) async {
    await _pump(
      tester,
      transactions: [
        _tx('a', 'cafe', 1000, oct),
        _tx('b', 'cinema', 300000, sep),
      ],
    );

    expect(
      find.text('0,00$_nbsp₽ · было 3${_nbsp}000,00$_nbsp₽'),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(find.byKey(ComparisonSection.rowKey('cafe'))).dy,
      lessThan(
        tester.getTopLeft(find.byKey(ComparisonSection.rowKey('cinema'))).dy,
      ),
    );
    expect(
      find.text('↓ на 3${_nbsp}000,00$_nbsp₽ (${_minus}100$_nbsp%)'),
      findsOneWidget,
    );
  });

  testWidgets('доходы: свой итог и свои слова', (tester) async {
    await _pump(
      tester,
      type: TransactionType.income,
      transactions: [
        _tx('a', 'pay', 5000000, oct, type: TransactionType.income),
        _tx('b', 'cafe', 1000, oct),
      ],
    );

    expect(
      _textOf(tester, ComparisonSection.totalKey),
      'Доходы\n'
      '50${_nbsp}000,00$_nbsp₽\n'
      '1\u2013\u206011$_nbspсентября доходов не было',
    );
    expect(find.text('Зарплата'), findsOneWidget);
    expect(find.byKey(ComparisonSection.rowAmountKey), findsOneWidget);
    expect(find.textContaining('Кафе'), findsNothing);
  });

  testWidgets('нет ни сейчас, ни в прошлом: текст вместо списка', (
    tester,
  ) async {
    await _pump(
      tester,
      type: TransactionType.income,
      transactions: [_tx('a', 'cafe', 1000, oct)],
    );

    expect(find.text('За этот период доходов нет'), findsOneWidget);
    expect(find.byKey(ComparisonSection.listKey), findsNothing);
  });

  testWidgets('разница не красится цветом расхода или дохода', (tester) async {
    await _pump(
      tester,
      transactions: [
        _tx('a', 'cafe', 800000, oct),
        _tx('b', 'cafe', 570000, sep),
      ],
    );

    final colors = AppColors.light;
    final scheme = Theme.of(tester.element(find.byType(ComparisonSection)))
        .colorScheme;
    final delta = tester.widget<Text>(find.textContaining('↑ на'));
    expect(delta.style?.color, scheme.onSurfaceVariant);
    expect(delta.style?.color, isNot(colors.expense));
    expect(delta.style?.color, isNot(colors.income));
    final summary = tester.widget<Text>(find.textContaining('больше'));
    expect(summary.style?.color, scheme.onSurfaceVariant);
  });

  testWidgets('скринридер читает строку и итог одним узлом', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      transactions: [
        _tx('a', 'cafe', 800000, oct),
        _tx('b', 'cafe', 570000, sep),
      ],
      onOpen: (_) {},
    );

    expect(
      find.bySemanticsLabel(
        'Кафе, 8000 рублей, больше на 2300 рублей, плюс 40 процентов',
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        'Расходы: 8000 рублей. '
        'на 2300 рублей больше, плюс 40 процентов, чем 1\u2013\u206011$_nbspсентября',
      ),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('касание строки зовёт колбэк с категорией', (tester) async {
    final opened = <Category>[];
    await _pump(
      tester,
      transactions: [_tx('a', 'cafe', 1000, oct)],
      onOpen: opened.add,
    );

    await tester.tap(find.byKey(ComparisonSection.rowKey('cafe')));

    expect(opened.map((c) => c.id), ['cafe']);
  });

  testWidgets('без колбэка строки не кнопки', (tester) async {
    await _pump(tester, transactions: [_tx('a', 'cafe', 1000, oct)]);

    expect(
      find.descendant(
        of: find.byKey(ComparisonSection.rowKey('cafe')),
        matching: find.byType(InkWell),
      ),
      findsNothing,
    );
  });

  testWidgets('переключатель типа зовёт колбэк', (tester) async {
    final calls = <TransactionType>[];
    await _pump(
      tester,
      transactions: [_tx('a', 'cafe', 1000, oct)],
      onType: calls.add,
    );

    await tester.tap(
      find.descendant(
        of: find.byKey(ComparisonSection.typeKey),
        matching: find.text('Доходы'),
      ),
    );

    expect(calls, [TransactionType.income]);
  });

  testWidgets('шрифт 200% на 360 dp: без переполнения', (tester) async {
    await _pump(
      tester,
      textScale: 2,
      transactions: [
        _tx('a', 'cafe', 800000, oct),
        _tx('b', 'cafe', 570000, sep),
        _tx('c', 'cinema', 300000, sep),
      ],
      onOpen: (_) {},
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('строки не меньше 48 dp высотой', (tester) async {
    await _pump(
      tester,
      transactions: [_tx('a', 'cafe', 1000, oct)],
      onOpen: (_) {},
    );

    expect(
      tester.getSize(find.byKey(ComparisonSection.rowKey('cafe'))).height,
      greaterThanOrEqualTo(48),
    );
  });

  group('крупный шрифт: двухэтажная строка (7.33)', () {
    setUpAll(loadRoboto);

    final rows = [
      _tx('a', 'cafe', 123456789, oct),
      _tx('b', 'cafe', 100000000, sep),
    ];
    final amount = find.byKey(ComparisonSection.rowAmountKey);

    testWidgets('100 %: название слева, сумма справа в той же строке', (
      tester,
    ) async {
      await _pump(tester, transactions: rows, onOpen: (_) {});
      expect(tester.takeException(), isNull);
      final name = find.text('Кафе');
      expect(amount, findsOneWidget);
      expect(
        tester.getTopLeft(amount).dx,
        greaterThan(tester.getTopRight(name).dx),
      );
    });

    for (final scale in [1.3, 2.0]) {
      testWidgets('${scale * 100} %: название, под ним сумма и разница', (
        tester,
      ) async {
        await _pump(
          tester,
          transactions: rows,
          onOpen: (_) {},
          textScale: scale,
        );
        expect(tester.takeException(), isNull);
        final row = find.byKey(ComparisonSection.rowKey('cafe'));
        final name = find.descendant(of: row, matching: find.text('Кафе'));
        expect(name, findsOneWidget);
        expect(
          tester.getTopLeft(amount).dy,
          greaterThanOrEqualTo(tester.getBottomLeft(name).dy),
        );
        // Сумма в полный размер, не шире строки.
        expect(
          tester.getRect(amount).width,
          moreOrLessEquals(tester.getSize(amount).width),
        );
        expect(
          tester.getTopRight(amount).dx,
          lessThanOrEqualTo(tester.getTopRight(row).dx),
        );
        // Разница целиком: ни одна строка строки не обрезана многоточием.
        for (final paragraph in tester.renderObjectList<RenderParagraph>(
          find.descendant(of: row, matching: find.byType(RichText)),
        )) {
          expect(paragraph.didExceedMaxLines, isFalse);
          expect(
            paragraph.size.width,
            lessThanOrEqualTo(tester.getSize(row).width),
          );
        }
        expect(find.textContaining('↑ на'), findsOneWidget);
      });
    }
  });
}
