import 'dart:async';

import 'package:flutter/material.dart';
import 'package:money_app/core/id/id_generator.dart';
import 'package:money_app/core/time/clock.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/features/analytics/domain/analytics_period.dart';
import 'package:money_app/features/analytics/presentation/category_breakdown_screen.dart';
import 'package:money_app/features/categories/domain/categories_repository.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/categories/presentation/categories_screen.dart';
import 'package:money_app/features/categories/presentation/category_form_screen.dart';
import 'package:money_app/features/categories/presentation/subcategories_screen.dart';
import 'package:money_app/features/transactions/domain/category_kind_mapping.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';
import 'package:money_app/features/transactions/domain/transactions_repository.dart';
import 'package:money_app/features/transactions/presentation/edit/edit_transaction_screen.dart';
import 'package:money_app/features/transactions/presentation/quick_add/quick_add_screen.dart';

/// Имена маршрутов приложения. Живут в `lib/app/`, потому что только
/// приложение знает, какие экраны разных фич как связаны (ADR 0002).
abstract final class AppRoutes {
  /// Экран быстрого ввода. Аргумент маршрута — [QuickAddRouteArguments].
  static const quickAdd = '/quick-add';

  /// Экран правки операции. Аргумент маршрута — [EditTransactionRouteArguments].
  static const editTransaction = '/edit-transaction';

  /// Экран управления категориями. Аргумент маршрута —
  /// [CategoriesRouteArguments].
  static const categories = '/categories';

  /// Форма категории (создание или переименование). Аргумент маршрута —
  /// [CategoryFormRouteArguments].
  static const categoryForm = '/category-form';

  /// Экран подкатегорий одной категории. Аргумент маршрута —
  /// [SubcategoriesRouteArguments].
  static const subcategories = '/subcategories';

  /// Экран «Категория за период» (подкатегории). Аргумент маршрута —
  /// [CategoryBreakdownRouteArguments].
  static const analyticsCategory = '/analytics-category';
}

/// Аргументы маршрута [AppRoutes.analyticsCategory]: категория, период, сегодняшний
/// день и два потока (операции периода и все категории, включая архивные). Потоки
/// создаёт тот, кто открывает маршрут, и держит одними и теми же.
final class CategoryBreakdownRouteArguments {
  const CategoryBreakdownRouteArguments({
    required this.category,
    required this.period,
    required this.today,
    required this.transactions,
    required this.categories,
  });

  final Category category;
  final AnalyticsPeriod period;
  final DateOnly today;
  final Stream<List<Transaction>> transactions;
  final Stream<List<Category>> categories;
}

/// Аргументы маршрута [AppRoutes.categories]: репозиторий и генератор id
/// достаёт тот, кто открывает маршрут (см. [QuickAddRouteArguments]).
final class CategoriesRouteArguments {
  const CategoriesRouteArguments({
    required this.categories,
    required this.idGenerator,
  });

  final CategoriesRepository categories;

  /// Нужен форме новой категории, которую открывает экран категорий.
  final IdGenerator idGenerator;
}

/// Аргументы маршрута [AppRoutes.categoryForm]. Если [renaming] задана,
/// форма переименовывает её, иначе создаёт новую категорию вида [kind]. Если
/// задан [parent], форма работает с подкатегорией этого родителя.
final class CategoryFormRouteArguments {
  const CategoryFormRouteArguments({
    required this.categories,
    required this.idGenerator,
    required this.kind,
    this.renaming,
    this.parent,
  });

  final CategoriesRepository categories;
  final IdGenerator idGenerator;
  final CategoryKind kind;
  final Category? renaming;
  final Category? parent;
}

/// Аргументы маршрута [AppRoutes.subcategories]: категория-родитель и те же
/// сервисы, что у [CategoriesRouteArguments] (нужны форме подкатегории).
final class SubcategoriesRouteArguments {
  const SubcategoriesRouteArguments({
    required this.parent,
    required this.categories,
    required this.idGenerator,
  });

  final Category parent;
  final CategoriesRepository categories;
  final IdGenerator idGenerator;
}

/// Аргументы маршрута [AppRoutes.quickAdd].
///
/// Зачем тут часы и репозитории: открытый по имени экран лежит в `Navigator`
/// рядом с главным экраном, а не под `AppScope`, поэтому сам достать сервисы он
/// не может. Их достаёт тот, кто открывает маршрут (он стоит под `AppScope`), и
/// передаёт сюда. Всё это интерфейсы из `domain` и `core`, а не реализации.
final class QuickAddRouteArguments {
  const QuickAddRouteArguments({
    required this.type,
    required this.clock,
    required this.categories,
    required this.transactions,
    required this.idGenerator,
    this.onSaved,
  });

  /// Операция сохранена на этот день (отмена записи месяц не возвращает).
  final ValueChanged<DateOnly>? onSaved;

  final TransactionType type;
  final Clock clock;
  final CategoriesRepository categories;

  /// Вместе с [idGenerator] нужен шагу 2.25 (сохранение операции).
  final TransactionsRepository transactions;
  final IdGenerator idGenerator;
}

/// Аргументы маршрута [AppRoutes.editTransaction]: те же соображения, что у
/// [QuickAddRouteArguments] (сервисы достаёт тот, кто открывает маршрут).
final class EditTransactionRouteArguments {
  const EditTransactionRouteArguments({
    required this.transaction,
    required this.clock,
    required this.categories,
    required this.transactions,
    this.onSaved,
  });

  /// Правка сохранена; операция теперь на этом дне.
  final ValueChanged<DateOnly>? onSaved;

  final Transaction transaction;
  final Clock clock;
  final CategoriesRepository categories;
  final TransactionsRepository transactions;
}

/// Собирает маршрут по имени: подключается как `MaterialApp.onGenerateRoute`.
/// Неизвестное имя — `null`, тогда Flutter пробует другие способы или
/// сообщает об ошибке сам.
Route<dynamic>? onGenerateAppRoute(RouteSettings settings) {
  switch (settings.name) {
    case AppRoutes.quickAdd:
      final arguments = settings.arguments;
      if (arguments is! QuickAddRouteArguments) {
        // Ошибка программиста, а не пользователя: показываем понятную причину
        // вместо падения где-то глубже из-за null.
        throw ArgumentError.value(
          arguments,
          'arguments',
          'Маршрут ${AppRoutes.quickAdd} ожидает аргумент '
              'QuickAddRouteArguments (тип операции TransactionType и часы)',
        );
      }
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (context) => QuickAddScreen(
          type: arguments.type,
          clock: arguments.clock,
          categories: arguments.categories,
          transactions: arguments.transactions,
          idGenerator: arguments.idGenerator,
          onSaved: arguments.onSaved,
          // «Добавить категорию» в пустом выборе категории: форма нужного вида.
          onCreateCategory: () => unawaited(
            Navigator.of(context).pushNamed(
              AppRoutes.categoryForm,
              arguments: CategoryFormRouteArguments(
                categories: arguments.categories,
                idGenerator: arguments.idGenerator,
                kind: arguments.type.categoryKind,
              ),
            ),
          ),
        ),
      );
    case AppRoutes.editTransaction:
      final arguments = settings.arguments;
      if (arguments is! EditTransactionRouteArguments) {
        throw ArgumentError.value(
          arguments,
          'arguments',
          'Маршрут ${AppRoutes.editTransaction} ожидает аргумент '
              'EditTransactionRouteArguments (операция Transaction и сервисы)',
        );
      }
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => EditTransactionScreen(
          transaction: arguments.transaction,
          clock: arguments.clock,
          categories: arguments.categories,
          transactions: arguments.transactions,
          onSaved: arguments.onSaved,
        ),
      );
    case AppRoutes.categories:
      final arguments = settings.arguments;
      if (arguments is! CategoriesRouteArguments) {
        throw ArgumentError.value(
          arguments,
          'arguments',
          'Маршрут ${AppRoutes.categories} ожидает аргумент '
              'CategoriesRouteArguments (репозиторий категорий)',
        );
      }
      return MaterialPageRoute<void>(
        settings: settings,
        // Форму открывают из этого экрана, но только приложение знает её
        // маршрут (фичи друг друга не импортируют).
        builder: (context) => CategoriesScreen(
          categories: arguments.categories,
          // Future завершается, когда форму закрыли: экран «Категории» не
          // даёт открыть вторую форму, пока первая на экране.
          onCreate: (kind) => Navigator.of(context).pushNamed<void>(
            AppRoutes.categoryForm,
            arguments: CategoryFormRouteArguments(
              categories: arguments.categories,
              idGenerator: arguments.idGenerator,
              kind: kind,
            ),
          ),
          onRename: (category) => Navigator.of(context).pushNamed<void>(
            AppRoutes.categoryForm,
            arguments: CategoryFormRouteArguments(
              categories: arguments.categories,
              idGenerator: arguments.idGenerator,
              kind: category.kind,
              renaming: category,
            ),
          ),
          onOpenSubcategories: (parent) =>
              Navigator.of(context).pushNamed<void>(
                AppRoutes.subcategories,
                arguments: SubcategoriesRouteArguments(
                  parent: parent,
                  categories: arguments.categories,
                  idGenerator: arguments.idGenerator,
                ),
              ),
        ),
      );
    case AppRoutes.subcategories:
      final arguments = settings.arguments;
      if (arguments is! SubcategoriesRouteArguments) {
        throw ArgumentError.value(
          arguments,
          'arguments',
          'Маршрут ${AppRoutes.subcategories} ожидает аргумент '
              'SubcategoriesRouteArguments (родитель, репозиторий и '
              'генератор id)',
        );
      }
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (context) => SubcategoriesScreen(
          parent: arguments.parent,
          categories: arguments.categories,
          onCreate: () => Navigator.of(context).pushNamed<void>(
            AppRoutes.categoryForm,
            arguments: CategoryFormRouteArguments(
              categories: arguments.categories,
              idGenerator: arguments.idGenerator,
              kind: arguments.parent.kind,
              parent: arguments.parent,
            ),
          ),
          onRename: (subcategory) => Navigator.of(context).pushNamed<void>(
            AppRoutes.categoryForm,
            arguments: CategoryFormRouteArguments(
              categories: arguments.categories,
              idGenerator: arguments.idGenerator,
              kind: arguments.parent.kind,
              renaming: subcategory,
              parent: arguments.parent,
            ),
          ),
        ),
      );
    case AppRoutes.analyticsCategory:
      final arguments = settings.arguments;
      if (arguments is! CategoryBreakdownRouteArguments) {
        throw ArgumentError.value(
          arguments,
          'arguments',
          'Маршрут ${AppRoutes.analyticsCategory} ожидает аргумент '
              'CategoryBreakdownRouteArguments (категория, период и потоки)',
        );
      }
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => CategoryBreakdownScreen(
          category: arguments.category,
          period: arguments.period,
          today: arguments.today,
          transactions: arguments.transactions,
          categories: arguments.categories,
        ),
      );
    case AppRoutes.categoryForm:
      final arguments = settings.arguments;
      if (arguments is! CategoryFormRouteArguments) {
        throw ArgumentError.value(
          arguments,
          'arguments',
          'Маршрут ${AppRoutes.categoryForm} ожидает аргумент '
              'CategoryFormRouteArguments (репозиторий, генератор id и вид)',
        );
      }
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => CategoryFormScreen(
          categories: arguments.categories,
          idGenerator: arguments.idGenerator,
          initialKind: arguments.kind,
          renaming: arguments.renaming,
          parent: arguments.parent,
        ),
      );
  }
  return null;
}
