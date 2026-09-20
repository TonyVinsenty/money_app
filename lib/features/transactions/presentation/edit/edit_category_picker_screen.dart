import 'package:flutter/material.dart';
import 'package:money_app/core/ui/async_view.dart';
import 'package:money_app/features/categories/domain/categories_repository.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/transactions/domain/category_kind_mapping.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';
import 'package:money_app/features/transactions/presentation/category_grid.dart';

/// Выбор новой категории при правке операции: сетка живых категорий верхнего
/// уровня того же вида, что и операция. Тап по плитке закрывает экран и
/// возвращает выбранную [Category] (`Navigator.pop`); «Назад» возвращает `null`.
class EditCategoryPickerScreen extends StatefulWidget {
  const EditCategoryPickerScreen({
    required this.type,
    required this.categories,
    super.key,
  });

  final TransactionType type;
  final CategoriesRepository categories;

  static const expenseTitle = 'Категория расхода';
  static const incomeTitle = 'Категория дохода';
  static const emptyText = 'Категорий пока нет';
  static const loadErrorText = 'Не удалось загрузить категории';

  @override
  State<EditCategoryPickerScreen> createState() =>
      _EditCategoryPickerScreenState();
}

class _EditCategoryPickerScreenState extends State<EditCategoryPickerScreen> {
  /// Поток создаём один раз: в `build` каждая перерисовка подписывалась бы
  /// заново, и экран мигал бы.
  late final Stream<List<Category>> _stream;

  @override
  void initState() {
    super.initState();
    _stream = widget.categories.watchTopLevel(widget.type.categoryKind);
  }

  /// Репозиторий уже отдаёт только живые категории верхнего уровня; проверка
  /// здесь страхует экран от чужого потока.
  List<Category> _visible(List<Category> data) => [
    for (final c in data)
      if (c.isTopLevel && !c.isArchived) c,
  ];

  @override
  Widget build(BuildContext context) {
    final title = widget.type == TransactionType.income
        ? EditCategoryPickerScreen.incomeTitle
        : EditCategoryPickerScreen.expenseTitle;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: AsyncView<List<Category>>(
          stream: _stream,
          errorBuilder: (context, error) =>
              const _Message(EditCategoryPickerScreen.loadErrorText),
          isEmpty: (data) => _visible(data).isEmpty,
          emptyBuilder: (context) =>
              const _Message(EditCategoryPickerScreen.emptyText),
          dataBuilder: (context, data) => CustomScrollView(
            slivers: [
              const SliverPadding(padding: EdgeInsets.only(top: 16)),
              CategoryGrid(
                categories: _visible(data),
                onSelected: (category) => Navigator.of(context).pop(category),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(text, textAlign: TextAlign.center),
      ),
    );
  }
}
