import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/ui/category_icon_view.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/transactions/presentation/category_grid.dart';

import '../../../support/roboto_font.dart';

Category _category(String id, String name) => Category.topLevel(
  id: id,
  kind: CategoryKind.expense,
  name: name,
  iconKey: 'shopping_cart',
  sortOrder: 0,
);

Widget _app(Widget sliver) => MaterialApp(
  theme: AppTheme.light(),
  home: Scaffold(body: CustomScrollView(slivers: [sliver])),
);

void main() {
  testWidgets('плитка категории с ключом glyph:Ж показывает букву', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        CategoryGrid(
          categories: [
            Category.topLevel(
              id: 'z',
              kind: CategoryKind.expense,
              name: 'Жильё',
              iconKey: 'glyph:Ж',
              sortOrder: 0,
            ),
          ],
          onSelected: (_) {},
        ),
      ),
    );

    expect(find.text('Ж'), findsOneWidget);
    expect(find.byIcon(Icons.category_outlined), findsNothing);
  });

  testWidgets('ключ «Другое» - плитка с первой буквой, озвучка прежняя', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(
        CategoryGrid(
          categories: [
            Category.topLevel(
              id: 'k',
              kind: CategoryKind.expense,
              name: 'кафе',
              iconKey: 'more_horiz',
              sortOrder: 0,
            ),
            Category.topLevel(
              id: 'p',
              kind: CategoryKind.expense,
              name: 'Прочее',
              iconKey: 'more_horiz',
              sortOrder: 1,
            ),
          ],
          onSelected: (_) {},
        ),
      ),
    );

    expect(find.text('К'), findsOneWidget);
    expect(find.byIcon(Icons.more_horiz), findsOneWidget);
    // Буква скрыта от скринридера, читается только название плитки.
    expect(find.bySemanticsLabel('К'), findsNothing);
    expect(find.bySemanticsLabel('кафе'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('плитка подкатегории берёт значок из записи', (tester) async {
    await tester.pumpWidget(
      _app(
        CategoryGrid(
          categories: [
            Category(
              id: 'espresso',
              kind: CategoryKind.expense,
              name: 'Эспрессо',
              iconKey: 'local_cafe',
              parentId: 'food',
              sortOrder: 0,
            ),
          ],
          onSelected: (_) {},
        ),
      ),
    );

    final view = tester.widget<CategoryIconView>(find.byType(CategoryIconView));
    expect(view.iconKey, 'local_cafe');
  });

  testWidgets('подкатегория «Кофе» со значком «Другое» - буква «К»', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(
        CategoryGrid(
          categories: [
            Category(
              id: 'coffee',
              kind: CategoryKind.expense,
              name: 'Кофе',
              iconKey: 'more_horiz',
              parentId: 'food',
              sortOrder: 0,
            ),
          ],
          onSelected: (_) {},
          onSkip: () {},
        ),
      ),
    );

    expect(find.text('К'), findsOneWidget);
    expect(find.byIcon(Icons.more_horiz), findsNothing);
    // Плитка «Без подкатегории» без изменений: у неё свой значок.
    expect(find.text('Без подкатегории'), findsOneWidget);
    expect(find.bySemanticsLabel('К'), findsNothing);
    expect(find.bySemanticsLabel('Кофе'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('подпись плитки пропуска по умолчанию — «Без подкатегории»', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        CategoryGrid(
          categories: [_category('a', 'Продукты')],
          onSelected: (_) {},
          onSkip: () {},
        ),
      ),
    );

    expect(find.text('Без подкатегории'), findsOneWidget);
    expect(find.text(CategoryGrid.skipLabel), findsOneWidget);
  });

  testWidgets('плитка пропуска визуально отличается от обычной подкатегории', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        CategoryGrid(
          categories: [_category('a', 'Продукты')],
          onSelected: (_) {},
          onSkip: () {},
        ),
      ),
    );

    // Material и Container ближе к тексту — это плитка; дальше — от Scaffold.
    Material materialFor(String label) => tester.widget<Material>(
      find
          .ancestor(of: find.text(label), matching: find.byType(Material))
          .first,
    );
    Container containerFor(String label) => tester.widget<Container>(
      find
          .ancestor(of: find.text(label), matching: find.byType(Container))
          .first,
    );

    final skipMaterial = materialFor('Без подкатегории');
    final regularMaterial = materialFor('Продукты');
    // Плитка пропуска не залита цветом, в отличие от обычной подкатегории.
    expect(skipMaterial.color, Colors.transparent);
    expect(regularMaterial.color, isNot(Colors.transparent));

    final skipContainer = containerFor('Без подкатегории');
    final regularContainer = containerFor('Продукты');
    // У плитки пропуска есть контур (foregroundDecoration: рисуется поверх
    // содержимого и не отнимает у него места), у обычной подкатегории — нет.
    expect(
      (skipContainer.foregroundDecoration as BoxDecoration?)?.border,
      isNotNull,
    );
    expect(regularContainer.foregroundDecoration, isNull);
  });

  group('крупный шрифт: плитки по две, слова целиком (7.34)', () {
    setUpAll(loadRoboto);

    final names = ['Продукты', 'Развлечения', 'Кафе и рестораны', 'Дом'];

    Future<void> pumpAt(WidgetTester tester, double scale) async {
      tester.view.physicalSize = const Size(360, 1600);
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
            body: CustomScrollView(
              slivers: [
                CategoryGrid(
                  categories: [
                    for (final (i, name) in names.indexed)
                      _category('c$i', name),
                  ],
                  onSelected: (_) {},
                  onSkip: () {},
                ),
              ],
            ),
          ),
        ),
      );
    }

    /// Сколько плиток в первом ряду: у скольких верх совпадает с первой.
    int firstRow(WidgetTester tester) {
      final tops = [
        for (final label in [CategoryGrid.skipLabel, ...names])
          tester.getTopLeft(find.text(label)).dy,
      ];
      return tops.where((top) => (top - tops.first).abs() < 40).length;
    }

    /// Строки абзаца [label] — каждая целиком из слов: ни одно слово не
    /// разорвано между строками.
    List<String> lines(WidgetTester tester, String label) {
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: find.text(label), matching: find.byType(RichText)),
      );
      // Та же раскладка заново: границы строк знает TextPainter.
      final painter = TextPainter(
        text: paragraph.text,
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
        textScaler: paragraph.textScaler,
        maxLines: 2,
      )..layout(maxWidth: paragraph.constraints.maxWidth);
      final result = <String>[];
      var offset = 0;
      while (offset < label.length) {
        final line = painter.getLineBoundary(TextPosition(offset: offset));
        if (line.end <= offset) break;
        result.add(label.substring(line.start, line.end).trim());
        offset = line.end;
      }
      painter.dispose();
      expect(paragraph.didExceedMaxLines, isFalse, reason: label);
      return result;
    }

    testWidgets('100 %: три в ряд, как раньше', (tester) async {
      await pumpAt(tester, 1);
      expect(firstRow(tester), 3);
    });

    for (final scale in [1.3, 2.0]) {
      testWidgets('${scale * 100} %: две в ряд, слова не рвутся', (
        tester,
      ) async {
        await pumpAt(tester, scale);
        expect(tester.takeException(), isNull);
        expect(firstRow(tester), 2);
        expect(lines(tester, 'Развлечения'), ['Развлечения']);
        expect(lines(tester, 'Продукты'), ['Продукты']);
        for (final line in [
          ...lines(tester, 'Кафе и рестораны'),
          ...lines(tester, CategoryGrid.skipLabel),
        ]) {
          for (final word in line.split(' ')) {
            expect(
              ['Кафе', 'и', 'рестораны', 'Без', 'подкатегории'],
              contains(word),
              reason: 'слово «$word» разорвано',
            );
          }
        }
      });
    }

    testWidgets('200 %: «Развлечения» уменьшено, «Дом» — нет', (tester) async {
      await pumpAt(tester, 2);
      double size(String label) =>
          tester.widget<Text>(find.text(label)).style!.fontSize!;
      final full =
          Theme.of(tester.element(find.text('Дом')))
              .textTheme
              .labelLarge!
              .fontSize! *
          2;
      expect(size('Дом'), full);
      expect(size('Развлечения'), lessThanOrEqualTo(full));
    });
  });

  group('выбранная плитка', () {
    Finder tileOf(String label) =>
        find.ancestor(of: find.text(label), matching: find.byType(InkWell));

    testWidgets('выбрана только плитка с selectedId: галочка, рамка primary, '
        'озвучка', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(
          CategoryGrid(
            categories: [_category('a', 'Дом'), _category('b', 'Еда')],
            selectedId: 'a',
            onSelected: (_) {},
            onSkip: () {},
          ),
        ),
      );

      expect(
        find.descendant(
          of: tileOf('Дом'),
          matching: find.byIcon(Icons.check_circle),
        ),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Дом')),
        matchesSemantics(
          label: 'Дом',
          isButton: true,
          hasTapAction: true,
          isSelected: true,
          hasSelectedState: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('«Без подкатегории» рамка outlineVariant, а не primary', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          CategoryGrid(
            categories: [_category('a', 'Дом')],
            selectedId: 'a',
            onSelected: (_) {},
            onSkip: () {},
          ),
        ),
      );

      final scheme = Theme.of(tester.element(find.byType(CategoryGrid)))
          .colorScheme;
      Border borderOf(String label) {
        final container = tester.widget<Container>(
          find
              .descendant(of: tileOf(label), matching: find.byType(Container))
              .first,
        );
        return (container.foregroundDecoration! as BoxDecoration).border!
            as Border;
      }

      expect(borderOf(CategoryGrid.skipLabel).top.color, scheme.outlineVariant);
      expect(borderOf('Дом').top.color, scheme.primary);
    });
  });
}
