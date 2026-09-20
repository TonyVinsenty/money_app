import 'package:flutter/material.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/format/money_spoken.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/ui/category_icons.dart';
import 'package:money_app/core/ui/theme/app_colors.dart';
import 'package:money_app/features/categories/domain/categories_repository.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/transactions/domain/category_kind_mapping.dart';
import 'package:money_app/features/transactions/domain/transaction_rules.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';
import 'package:money_app/features/transactions/presentation/quick_add/note_field.dart';

/// Экран выбора категории: второй шаг быстрого ввода.
///
/// Сверху крупно видна уже введённая сумма (со знаком и цветом типа), ниже
/// сетка плиток «иконка + название» из живых категорий верхнего уровня нужного
/// вида. Порядок плиток — порядок репозитория (`sortOrder`).
///
/// Между суммой и сеткой — необязательная строка комментария ([NoteField]).
/// Тап по плитке вызывает [onCategorySelected] с категорией и комментарием.
/// Сохранение операции подключает шаг 2.25; пока колбэк не задан, тап ничего
/// не делает.
class CategoryPickerScreen extends StatefulWidget {
  const CategoryPickerScreen({
    required this.type,
    required this.amount,
    required this.day,
    required this.categories,
    this.onCategorySelected,
    super.key,
  });

  final TransactionType type;
  final Money amount;

  /// Выбранный на предыдущем экране день. Здесь он только «едет» дальше до
  /// шага 2.25, где из него и из часов собирается операция.
  final DateOnly day;

  final CategoriesRepository categories;

  /// Вызывается при тапе по плитке: выбранная категория и комментарий в том
  /// виде, в каком его хранит `domain` (без пробелов по краям; `null`, если
  /// комментария нет).
  final void Function(Category category, String? note)? onCategorySelected;

  static const expenseTitle = 'Категория расхода';
  static const incomeTitle = 'Категория дохода';
  static const emptyText = 'Категорий пока нет';
  static const emptyHint =
      'Создайте первую категорию, чтобы записывать операции';
  static const createLabel = 'Создать категорию';

  /// Экран категорий появится в вехе 2E; пока кнопка честно об этом говорит.
  static const createSoonMessage = 'Создание категорий — скоро';
  static const loadErrorText = 'Не удалось загрузить категории';

  @override
  State<CategoryPickerScreen> createState() => _CategoryPickerScreenState();
}

class _CategoryPickerScreenState extends State<CategoryPickerScreen> {
  /// Поток создаём один раз: если получать его в `build`, каждая перерисовка
  /// подписывалась бы заново и экран мигал бы.
  late final Stream<List<Category>> _stream;

  /// Текст комментария. Живёт в состоянии экрана, поэтому не теряется, пока
  /// сетка перерисовывается.
  final _note = TextEditingController();

  @override
  void initState() {
    super.initState();
    _stream = widget.categories.watchTopLevel(widget.type.categoryKind);
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _select(Category category) {
    // Снимаем фокус: клавиатура закрывается и не «возвращается» сама, когда
    // человек вернётся на этот экран.
    FocusScope.of(context).unfocus();
    widget.onCategorySelected?.call(
      category,
      normalizeTransactionNote(_note.text),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isIncome = widget.type == TransactionType.income;
    final accent = isIncome
        ? context.appColors.income
        : context.appColors.expense;
    final title = isIncome
        ? CategoryPickerScreen.incomeTitle
        : CategoryPickerScreen.expenseTitle;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: StreamBuilder<List<Category>>(
          stream: _stream,
          builder: (context, snapshot) {
            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: _AmountHeader(
                    amount: widget.amount,
                    isIncome: isIncome,
                    color: accent,
                  ),
                ),
                // Строка комментария. Ниже, в этом же месте, позже появится
                // умная подсказка категории (этап 6).
                SliverToBoxAdapter(child: NoteField(controller: _note)),
                ..._contentSlivers(snapshot),
              ],
            );
          },
        ),
      ),
    );
  }

  List<Widget> _contentSlivers(AsyncSnapshot<List<Category>> snapshot) {
    if (snapshot.hasError) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _CenteredMessage(text: CategoryPickerScreen.loadErrorText),
        ),
      ];
    }
    final data = snapshot.data;
    // Ответа ещё нет: не показываем ничего, чтобы не мигало «Категорий нет».
    if (data == null) return const [];
    // Репозиторий уже отдаёт только живые категории верхнего уровня;
    // проверка здесь страхует экран от чужого потока.
    final categories = [
      for (final c in data)
        if (c.isTopLevel && !c.isArchived) c,
    ];
    if (categories.isEmpty) {
      return [SliverFillRemaining(hasScrollBody: false, child: _EmptyState())];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        sliver: SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            // Высота плитки растёт с системным шрифтом: считаем её из
            // масштаба текста, а не задаём числом.
            mainAxisExtent: _CategoryTile.extentFor(context),
          ),
          delegate: SliverChildBuilderDelegate((context, index) {
            final category = categories[index];
            return _CategoryTile(
              category: category,
              onTap: () => _select(category),
            );
          }, childCount: categories.length),
        ),
      ),
    ];
  }
}

/// Введённая сумма крупно: знак, число, валюта.
class _AmountHeader extends StatelessWidget {
  const _AmountHeader({
    required this.amount,
    required this.isIncome,
    required this.color,
  });

  final Money amount;
  final bool isIncome;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final sign = isIncome ? '+' : String.fromCharCode(0x2212);
    final style = Theme.of(context).textTheme.displaySmall
        ?.copyWith(color: color, fontWeight: FontWeight.w600);
    final word = isIncome ? 'Доход' : 'Расход';
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Semantics(
        label: '$word ${spokenMoney(amount)}',
        child: ExcludeSemantics(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text('$sign${formatMoney(amount)}', style: style),
          ),
        ),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category, required this.onTap});

  final Category category;
  final VoidCallback onTap;

  static const _iconSize = 32.0;
  static const _verticalPadding = 12.0;
  static const _gap = 8.0;
  static const _lines = 2;

  /// Стиль названия. Общий для плитки и для расчёта её высоты.
  static TextStyle? _labelStyle(BuildContext context) =>
      Theme.of(context).textTheme.labelLarge;

  /// Высота плитки: иконка + две строки названия с учётом системного масштаба
  /// текста. Не меньше 96 dp, поэтому зона нажатия всегда больше 48 dp.
  static double extentFor(BuildContext context) {
    final style = _labelStyle(context);
    final scaler = MediaQuery.textScalerOf(context);
    final lineHeight =
        scaler.scale(style?.fontSize ?? 14) * (style?.height ?? 1.4);
    final extent =
        _verticalPadding * 2 + _iconSize + _gap + lineHeight * _lines;
    return extent < 96 ? 96 : extent;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: category.name,
      excludeSemantics: true,
      // Тап задан явно: excludeSemantics убирает и действия InkWell внутри.
      onTap: onTap,
      child: Material(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 4,
              vertical: _verticalPadding,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ExcludeSemantics(
                  child: Icon(
                    categoryIconFor(category.iconKey),
                    size: _iconSize,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(height: _gap),
                Text(
                  category.name,
                  maxLines: _lines,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: _labelStyle(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              CategoryPickerScreen.emptyText,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              CategoryPickerScreen.emptyHint,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            // Экран категорий — веха 2E. Пока кнопка не притворяется рабочей:
            // она объясняет, что создание категорий ещё впереди.
            FilledButton.tonal(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(CategoryPickerScreen.createSoonMessage),
                  ),
                );
              },
              child: const Text(CategoryPickerScreen.createLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({required this.text});

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
