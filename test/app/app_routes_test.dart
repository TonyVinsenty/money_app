import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/app/app.dart';
import 'package:money_app/app/app_routes.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/core/ui/theme/app_colors.dart';
import 'package:money_app/features/analytics/domain/analytics_period.dart';
import 'package:money_app/features/analytics/presentation/category_breakdown_screen.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/settings/presentation/app_settings_controller.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';
import 'package:money_app/features/transactions/presentation/quick_add/quick_add_screen.dart';

import '../support/fake_id_generator.dart';
import '../support/fakes.dart';
import '../support/fixed_clock.dart';
import '../support/in_memory_database.dart';

Future<void> _pumpApp(WidgetTester tester) async {
  final settings = AppSettingsController();
  addTearDown(settings.dispose);
  await tester.pumpWidget(
    MoneyApp(settings: settings, openDatabase: openInMemoryDatabase),
  );
  // Первый кадр — загрузка; второй — база открылась.
  await tester.pump();
}

void main() {
  group('onGenerateAppRoute', () {
    test('имя маршрута быстрого ввода — константа', () {
      expect(AppRoutes.quickAdd, '/quick-add');
    });

    test('неизвестный маршрут даёт null', () {
      expect(onGenerateAppRoute(const RouteSettings(name: '/nope')), isNull);
      expect(onGenerateAppRoute(const RouteSettings()), isNull);
    });

    test('маршрут быстрого ввода со своим типом даёт страницу', () {
      final route = onGenerateAppRoute(
        RouteSettings(
          name: AppRoutes.quickAdd,
          arguments: QuickAddRouteArguments(
            type: TransactionType.income,
            clock: FixedClock(DateTime(2026, 9, 20)),
            categories: FakeCategoriesRepository(),
            transactions: FakeTransactionsRepository(),
            idGenerator: FakeIdGenerator(),
          ),
        ),
      );
      expect(route, isA<MaterialPageRoute<void>>());
      expect(route!.settings.name, AppRoutes.quickAdd);
    });

    test('маршрут правки: имя, страница и понятная ArgumentError', () {
      expect(AppRoutes.editTransaction, '/edit-transaction');
      final route = onGenerateAppRoute(
        RouteSettings(
          name: AppRoutes.editTransaction,
          arguments: EditTransactionRouteArguments(
            transaction: Transaction(
              id: 'tx',
              type: TransactionType.expense,
              amount: Money.fromMinor(100, 'RUB'),
              occurredOn: DateOnly(2026, 9, 20),
              occurredAt: DateTime.utc(2026, 9, 20, 12),
              categoryId: 'c',
            ),
            clock: FixedClock(DateTime(2026, 9, 20)),
            categories: FakeCategoriesRepository(),
            transactions: FakeTransactionsRepository(),
          ),
        ),
      );
      expect(route, isA<MaterialPageRoute<void>>());
      expect(route!.settings.name, AppRoutes.editTransaction);
      for (final arguments in <Object?>[null, 'tx', 42]) {
        expect(
          () => onGenerateAppRoute(
            RouteSettings(
              name: AppRoutes.editTransaction,
              arguments: arguments,
            ),
          ),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.toString(),
              'сообщение',
              allOf(
                contains('/edit-transaction'),
                contains('EditTransactionRouteArguments'),
              ),
            ),
          ),
        );
      }
    });

    test('маршрут категорий: имя, страница и понятная ArgumentError', () {
      expect(AppRoutes.categories, '/categories');
      final route = onGenerateAppRoute(
        RouteSettings(
          name: AppRoutes.categories,
          arguments: CategoriesRouteArguments(
            categories: FakeCategoriesRepository(),
            idGenerator: FakeIdGenerator(),
          ),
        ),
      );
      expect(route, isA<MaterialPageRoute<void>>());
      expect(route!.settings.name, AppRoutes.categories);
      for (final arguments in <Object?>[null, 'categories']) {
        expect(
          () => onGenerateAppRoute(
            RouteSettings(name: AppRoutes.categories, arguments: arguments),
          ),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.toString(),
              'сообщение',
              allOf(
                contains('/categories'),
                contains('CategoriesRouteArguments'),
              ),
            ),
          ),
        );
      }
    });

    test('маршрут формы категории: имя, страница и понятная ArgumentError', () {
      expect(AppRoutes.categoryForm, '/category-form');
      final route = onGenerateAppRoute(
        RouteSettings(
          name: AppRoutes.categoryForm,
          arguments: CategoryFormRouteArguments(
            categories: FakeCategoriesRepository(),
            idGenerator: FakeIdGenerator(),
            kind: CategoryKind.income,
          ),
        ),
      );
      expect(route, isA<MaterialPageRoute<void>>());
      expect(route!.settings.name, AppRoutes.categoryForm);
      for (final arguments in <Object?>[null, 'income']) {
        expect(
          () => onGenerateAppRoute(
            RouteSettings(name: AppRoutes.categoryForm, arguments: arguments),
          ),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.toString(),
              'сообщение',
              allOf(
                contains('/category-form'),
                contains('CategoryFormRouteArguments'),
              ),
            ),
          ),
        );
      }
    });

    test('маршрут подкатегорий: имя, страница и понятная ArgumentError', () {
      expect(AppRoutes.subcategories, '/subcategories');
      final route = onGenerateAppRoute(
        RouteSettings(
          name: AppRoutes.subcategories,
          arguments: SubcategoriesRouteArguments(
            parent: Category.topLevel(
              id: 'food',
              kind: CategoryKind.expense,
              name: 'Продукты',
              iconKey: 'shopping_cart',
              sortOrder: 0,
            ),
            categories: FakeCategoriesRepository(),
            idGenerator: FakeIdGenerator(),
          ),
        ),
      );
      expect(route, isA<MaterialPageRoute<void>>());
      expect(route!.settings.name, AppRoutes.subcategories);
      for (final arguments in <Object?>[null, 'food']) {
        expect(
          () => onGenerateAppRoute(
            RouteSettings(name: AppRoutes.subcategories, arguments: arguments),
          ),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.toString(),
              'сообщение',
              allOf(
                contains('/subcategories'),
                contains('SubcategoriesRouteArguments'),
              ),
            ),
          ),
        );
      }
    });

    test('маршрут категории за период: неверный аргумент - ArgumentError', () {
      expect(AppRoutes.analyticsCategory, '/analytics-category');
      for (final arguments in <Object?>[null, 'food']) {
        expect(
          () => onGenerateAppRoute(
            RouteSettings(
              name: AppRoutes.analyticsCategory,
              arguments: arguments,
            ),
          ),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.toString(),
              'сообщение',
              allOf(
                contains('/analytics-category'),
                contains('CategoryBreakdownRouteArguments'),
              ),
            ),
          ),
        );
      }
    });

    testWidgets('маршрут категории за период открывает экран с заголовком', (
      tester,
    ) async {
      await initializeDateFormatting('ru');
      final route = onGenerateAppRoute(
        RouteSettings(
          name: AppRoutes.analyticsCategory,
          arguments: CategoryBreakdownRouteArguments(
            category: Category.topLevel(
              id: 'food',
              kind: CategoryKind.expense,
              name: 'Продукты',
              iconKey: 'shopping_cart',
              sortOrder: 0,
            ),
            period: AnalyticsPeriod(
              PeriodKind.month,
              monthRange(DateOnly(2026, 9, 1)),
            ),
            transactions: Stream.value(const <Transaction>[]),
            categories: Stream.value(const <Category>[]),
          ),
        ),
      );
      expect(route, isA<MaterialPageRoute<void>>());
      expect(route!.settings.name, AppRoutes.analyticsCategory);

      await tester.pumpWidget(MaterialApp(onGenerateRoute: (_) => route));
      await tester.pump();
      expect(find.byType(CategoryBreakdownScreen), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Продукты'),
        ),
        findsOneWidget,
      );
    });

    test('без аргумента или с чужим аргументом — понятная ArgumentError', () {
      for (final arguments in <Object?>[
        null,
        'expense',
        42,
        TransactionType.income,
      ]) {
        expect(
          () => onGenerateAppRoute(
            RouteSettings(name: AppRoutes.quickAdd, arguments: arguments),
          ),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.toString(),
              'сообщение',
              allOf(contains('/quick-add'), contains('QuickAddRouteArguments')),
            ),
          ),
        );
      }
    });
  });

  group('сквозной путь через MoneyApp', () {
    testWidgets('«Главная» показывает кнопки вместо заглушки', (tester) async {
      await _pumpApp(tester);

      expect(find.text('Доход'), findsOneWidget);
      expect(find.text('Расход'), findsOneWidget);
      expect(find.byType(QuickAddScreen), findsNothing);
    });

    testWidgets('«Расход» открывает «Новый расход», «Назад» возвращает', (
      tester,
    ) async {
      await _pumpApp(tester);

      await tester.tap(find.text('Расход'));
      await tester.pumpAndSettle();

      expect(find.byType(QuickAddScreen), findsOneWidget);
      final title = find.text('Новый расход');
      expect(title, findsOneWidget);
      final colors = tester.element(find.byType(QuickAddScreen)).appColors;
      expect(tester.widget<Text>(title).style?.color, colors.expense);
      final icon = find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.remove),
      );
      expect(tester.widget<Icon>(icon).color, colors.expense);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.byType(QuickAddScreen), findsNothing);
      expect(find.text('Доход'), findsOneWidget);
      expect(find.text('Расход'), findsOneWidget);
    });

    testWidgets('«Доход» открывает «Новый доход» цветом дохода', (
      tester,
    ) async {
      await _pumpApp(tester);

      await tester.tap(find.text('Доход'));
      await tester.pumpAndSettle();

      final title = find.text('Новый доход');
      expect(title, findsOneWidget);
      final colors = tester.element(find.byType(QuickAddScreen)).appColors;
      expect(tester.widget<Text>(title).style?.color, colors.income);
      final icon = find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.add),
      );
      expect(tester.widget<Icon>(icon).color, colors.income);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(QuickAddScreen), findsNothing);
    });
  });
}
