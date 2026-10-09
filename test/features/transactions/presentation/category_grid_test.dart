import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/ui/category_icon_view.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/transactions/presentation/category_grid.dart';

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
}
