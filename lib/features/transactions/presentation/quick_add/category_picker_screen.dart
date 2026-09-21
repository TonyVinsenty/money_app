import 'package:flutter/material.dart';
import 'package:money_app/core/format/day_label.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/format/money_spoken.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/ui/async_view.dart';
import 'package:money_app/core/ui/theme/app_colors.dart';
import 'package:money_app/features/categories/domain/categories_repository.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/transactions/domain/category_kind_mapping.dart';
import 'package:money_app/features/transactions/domain/transaction_rules.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';
import 'package:money_app/features/transactions/presentation/category_grid.dart';
import 'package:money_app/features/transactions/presentation/quick_add/note_field.dart';

/// Экран выбора категории: второй шаг быстрого ввода.
///
/// Сверху крупно видна уже введённая сумма (со знаком и цветом типа), ниже
/// сетка плиток «иконка + название» из живых категорий верхнего уровня нужного
/// вида. Порядок плиток — порядок репозитория (`sortOrder`).
///
/// Между суммой и сеткой — необязательная строка комментария ([NoteField]).
/// Тап по плитке вызывает [onCategorySelected] с категорией и комментарием.
/// Само сохранение делает тот, кто открыл экран (`QuickAddScreen`); пока
/// колбэк не задан, тап ничего не делает.
class CategoryPickerScreen extends StatefulWidget {
  const CategoryPickerScreen({
    required this.type,
    required this.amount,
    required this.day,
    required this.today,
    required this.categories,
    this.onCategorySelected,
    this.onCreateCategory,
    super.key,
  });

  /// Открывает форму новой категории; кнопка «Создать категорию» в пустом
  /// состоянии показывается, только если колбэк задан.
  final VoidCallback? onCreateCategory;

  final TransactionType type;
  final Money amount;

  /// Выбранный на предыдущем экране день. Экран только показывает его под
  /// суммой: операция собирается на `QuickAddScreen`.
  final DateOnly day;

  /// «Сегодня» с предыдущего экрана: нужно, чтобы подписать день словом
  /// («Сегодня»/«Вчера») и не читать часы второй раз.
  final DateOnly today;

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
        // Сумма и комментарий видны всегда, поэтому в каждом состоянии
        // AsyncView строится один и тот же `CustomScrollView`, меняется только
        // нижняя часть. Пока ответа нет, нижней части нет: не мигает
        // «Категорий нет».
        child: AsyncView<List<Category>>(
          stream: _stream,
          loadingBuilder: (context) =>
              _scrollView(context, isIncome, accent, const []),
          errorBuilder: (context, error) =>
              _scrollView(context, isIncome, accent, const [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _CenteredMessage(
                    text: CategoryPickerScreen.loadErrorText,
                  ),
                ),
              ]),
          isEmpty: (data) => _visible(data).isEmpty,
          emptyBuilder: (context) => _scrollView(context, isIncome, accent, [
            SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyState(onCreate: widget.onCreateCategory),
            ),
          ]),
          dataBuilder: (context, data) => _scrollView(
            context,
            isIncome,
            accent,
            _gridSlivers(context, data),
          ),
        ),
      ),
    );
  }

  Widget _scrollView(
    BuildContext context,
    bool isIncome,
    Color accent,
    List<Widget> content,
  ) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _AmountHeader(
            amount: widget.amount,
            day: widget.day,
            today: widget.today,
            isIncome: isIncome,
            color: accent,
          ),
        ),
        // Строка комментария. Ниже, в этом же месте, позже появится
        // умная подсказка категории (этап 6).
        SliverToBoxAdapter(child: NoteField(controller: _note)),
        ...content,
      ],
    );
  }

  /// Репозиторий уже отдаёт только живые категории верхнего уровня; проверка
  /// здесь страхует экран от чужого потока.
  List<Category> _visible(List<Category> data) => [
    for (final c in data)
      if (c.isTopLevel && !c.isArchived) c,
  ];

  List<Widget> _gridSlivers(BuildContext context, List<Category> data) {
    return [CategoryGrid(categories: _visible(data), onSelected: _select)];
  }
}

/// Введённая сумма крупно: знак, число, валюта.
class _AmountHeader extends StatelessWidget {
  const _AmountHeader({
    required this.amount,
    required this.day,
    required this.today,
    required this.isIncome,
    required this.color,
  });

  final Money amount;
  final DateOnly day;
  final DateOnly today;
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
      child: Column(
        children: [
          Semantics(
            label: '$word ${spokenMoney(amount)}',
            child: ExcludeSemantics(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('$sign${formatMoney(amount)}', style: style),
              ),
            ),
          ),
          // День операции: «Сегодня», «Вчера» или дата. Скринридер читает его
          // отдельной строкой.
          const SizedBox(height: 4),
          Text(
            dayLabel(day, today: today),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCreate});

  final VoidCallback? onCreate;

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
            if (onCreate != null) ...[
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: onCreate,
                child: const Text(CategoryPickerScreen.createLabel),
              ),
            ],
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
