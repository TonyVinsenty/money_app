import 'package:flutter/material.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/ui/async_view.dart';
import 'package:money_app/core/ui/category_rule_text.dart';
import 'package:money_app/core/ui/theme/app_colors.dart';
import 'package:money_app/features/categories/domain/categories_repository.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';
import 'package:money_app/features/transactions/presentation/category_grid.dart';
import 'package:money_app/features/transactions/presentation/quick_add/amount_header.dart';

/// Экран выбора подкатегории: необязательный третий шаг быстрого ввода.
///
/// Открывается, только если у выбранной категории [parent] есть живые
/// подкатегории. Заголовок — имя категории, ниже сумма и день (как на экране
/// категорий), затем сетка: первой плиткой «Пропустить», дальше подкатегории
/// в порядке `sortOrder`. Комментарий здесь не показывается: он остался на
/// экране категорий под этим экраном и приходит в [onSelected] уже готовым
/// замыканием у того, кто открыл экран.
///
/// [onSelected] получает подкатегорию или `null` для «Пропустить». Сохраняет
/// операцию тот, кто открыл экран.
class SubcategoryPickerScreen extends StatefulWidget {
  const SubcategoryPickerScreen({
    required this.type,
    required this.amount,
    required this.day,
    required this.today,
    required this.parent,
    required this.categories,
    required this.onSelected,
    super.key,
  });

  final TransactionType type;
  final Money amount;
  final DateOnly day;
  final DateOnly today;

  /// Выбранная категория верхнего уровня.
  final Category parent;
  final CategoriesRepository categories;

  final void Function(Category? subcategory) onSelected;

  @override
  State<SubcategoryPickerScreen> createState() =>
      _SubcategoryPickerScreenState();
}

class _SubcategoryPickerScreenState extends State<SubcategoryPickerScreen> {
  /// Поток создаём один раз: в `build` каждая перерисовка подписывалась бы
  /// заново.
  late final Stream<List<Category>> _stream;

  @override
  void initState() {
    super.initState();
    _stream = widget.categories.watchSubcategories(widget.parent.id);
  }

  /// Репозиторий уже отдаёт только живые подкатегории; проверка здесь
  /// страхует экран от чужого потока.
  List<Category> _visible(List<Category> data) => [
    for (final c in data)
      if (!c.isArchived) c,
  ];

  void _skip() => widget.onSelected(null);

  @override
  Widget build(BuildContext context) {
    final isIncome = widget.type == TransactionType.income;
    final accent = isIncome
        ? context.appColors.income
        : context.appColors.expense;

    Widget scroll(List<Widget> content) => CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: AmountHeader(
            amount: widget.amount,
            day: widget.day,
            today: widget.today,
            isIncome: isIncome,
            color: accent,
          ),
        ),
        const SliverPadding(padding: EdgeInsets.only(top: 16)),
        ...content,
      ],
    );

    return Scaffold(
      appBar: AppBar(title: Text(widget.parent.name)),
      body: SafeArea(
        // Пока ответа нет, нижней части нет (как на экране категорий). Если
        // подкатегории кончились или поток упал, «Пропустить» остаётся:
        // сохранить только с категорией можно всегда.
        child: AsyncView<List<Category>>(
          stream: _stream,
          loadingBuilder: (context) => scroll(const []),
          errorBuilder: (context, error) => scroll([
            CategoryGrid(
              categories: const [],
              onSelected: (_) {},
              onSkip: _skip,
            ),
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  subcategoriesLoadErrorText,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ]),
          dataBuilder: (context, data) => scroll([
            CategoryGrid(
              categories: _visible(data),
              onSelected: widget.onSelected,
              onSkip: _skip,
            ),
          ]),
        ),
      ),
    );
  }
}
