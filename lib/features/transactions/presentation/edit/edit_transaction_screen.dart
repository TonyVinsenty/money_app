import 'dart:async';

import 'package:flutter/material.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/format/money_spoken.dart';
import 'package:money_app/core/time/clock.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/ui/amount_field.dart';
import 'package:money_app/core/ui/category_icons.dart';
import 'package:money_app/core/ui/date_chip.dart';
import 'package:money_app/core/ui/theme/app_colors.dart';
import 'package:money_app/core/ui/transaction_rule_text.dart';
import 'package:money_app/features/categories/domain/categories_repository.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/transactions/domain/edited_transaction.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_rules.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';
import 'package:money_app/features/transactions/domain/transactions_repository.dart';
import 'package:money_app/features/transactions/presentation/edit/edit_category_picker_screen.dart';
import 'package:money_app/features/transactions/presentation/history/history_screen.dart'
    show noCategoryLabel;
import 'package:money_app/features/transactions/presentation/quick_add/note_field.dart';
import 'package:money_app/features/transactions/presentation/quick_add/saved_snack_bar.dart';

/// Экран правки операции (открывается тапом по строке «Истории»).
///
/// Меняются тип (доход/расход), сумма, дата, категория и комментарий. Тип
/// виден тремя способами, как в быстром вводе (слово в заголовке, цвет, знак).
/// При смене типа категория сбрасывается (у доходов и расходов разные наборы),
/// и без выбора новой сохранить нельзя; если вернуть исходный тип, исходная
/// категория возвращается. Выход без сохранения («Назад») ничего не меняет и
/// подтверждения не просит.
class EditTransactionScreen extends StatefulWidget {
  const EditTransactionScreen({
    required this.transaction,
    required this.clock,
    required this.categories,
    required this.transactions,
    super.key,
  });

  /// Операция в том виде, в каком её показывала «История».
  final Transaction transaction;

  /// Источник «сегодня» для плашки даты и момента при смене дня.
  final Clock clock;
  final CategoriesRepository categories;
  final TransactionsRepository transactions;

  static const expenseTitle = 'Правка расхода';
  static const incomeTitle = 'Правка дохода';
  static const saveLabel = 'Сохранить';
  static const savedText = 'Изменения сохранены';
  static const savedDuration = Duration(seconds: 4);
  static const categoryLabel = 'Категория';
  static const categoryLoadingLabel = 'Загрузка…';
  static const deleteLabel = 'Удалить';
  static const deleteSemanticLabel = 'Удалить операцию';
  static const deletedText = 'Операция удалена';
  static const alreadyDeletedText = 'Эта операция уже удалена';
  static const deleteFailedText = 'Не удалось удалить. Попробуйте ещё раз';
  static const goneText = 'Эта операция уже удалена, сохранить нечего';
  static const typeLabel = 'Тип операции';
  static const expenseLabel = 'Расход';
  static const incomeLabel = 'Доход';

  @override
  State<EditTransactionScreen> createState() => _EditTransactionScreenState();
}

class _EditTransactionScreenState extends State<EditTransactionScreen> {
  final _amount = AmountFieldController();
  late final TextEditingController _note;

  /// «Сегодня» на момент открытия (как в быстром вводе: через полночь не
  /// обновляется).
  late final DateOnly _today;
  late DateOnly _day;

  /// Текущая категория и подкатегория операции для показа (в том числе
  /// архивные: `findById` их отдаёт). Пока грузятся, [_loaded] равно `false`.
  Category? _currentCategory;
  Category? _currentSubcategory;
  bool _loaded = false;

  /// Тип операции в правке (может отличаться от исходного).
  late TransactionType _type;

  /// Категория, выбранная в правке; `null` — не меняли (или сбросили сменой
  /// типа).
  Category? _picked;

  /// Подсветить поле категории: человек нажал «Сохранить» без категории.
  bool _categoryError = false;

  /// Текст ошибки сохранения. Показывается над кнопкой, а не в SnackBar: он
  /// перекрыл бы саму кнопку «Сохранить».
  String? _error;

  @override
  void initState() {
    super.initState();
    final t = widget.transaction;
    _today = widget.clock.today();
    _day = t.occurredOn;
    _type = t.type;
    _amount.text.text = formatMoney(t.amount, withCurrencySymbol: false);
    _note = TextEditingController(text: t.note);
    unawaited(_loadCategories());
    // Сообщение «Изменения сохранены» от прошлой правки закрыло бы кнопку
    // «Сохранить» на этом экране. `context` для messenger в `initState` брать
    // нельзя, поэтому после первого кадра (как в быстром вводе).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();
    });
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    final t = widget.transaction;
    Category? category;
    Category? subcategory;
    try {
      category = await widget.categories.findById(t.categoryId);
      final subId = t.subcategoryId;
      if (subId != null) subcategory = await widget.categories.findById(subId);
    } on Object {
      // Название не загрузилось: показываем запасной текст, сохранение при
      // этом работает (ему нужен только id категории).
    }
    if (!mounted) return;
    setState(() {
      _currentCategory = category;
      _currentSubcategory = subcategory;
      _loaded = true;
    });
  }

  bool get _typeChanged => _type != widget.transaction.type;

  bool get _categoryChanged =>
      _picked != null && _picked!.id != widget.transaction.categoryId;

  /// Категория для показа: при смене типа старая не годится, остаётся только
  /// выбранная заново (или ничего).
  Category? get _shownCategory =>
      _typeChanged ? _picked : (_picked ?? _currentCategory);

  void _setType(TransactionType type) {
    if (type == _type) return;
    setState(() {
      _type = type;
      // Выбор относился к другому виду категорий. Возврат к исходному типу
      // снова показывает исходную категорию (она хранится в `_currentCategory`).
      _picked = null;
      _categoryError = false;
      _error = null;
    });
  }

  Future<void> _pickCategory() async {
    final picked = await Navigator.of(context).push<Category>(
      MaterialPageRoute<Category>(
        builder: (_) => EditCategoryPickerScreen(
          type: _type,
          categories: widget.categories,
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _picked = picked;
      _categoryError = false;
      _error = null;
    });
  }

  /// Идёт сохранение (или оно уже удалось): повторные тапы игнорируются. После
  /// успеха флаг не сбрасывается, экран закрывается; при ошибке — сбрасывается.
  bool _saving = false;

  Future<void> _save() async {
    if (_saving || _deleting) return;
    // Пустая или неразобранная сумма: ошибка под полем, ничего не пишем.
    final amount = _amount.submit();
    final type = _type;
    // Тип сменили, а категорию не выбрали: сохранять нельзя. Кнопка остаётся
    // активной, чтобы причина была видна и слышна (текст под ошибкой).
    if (_typeChanged && _picked == null) {
      setState(() {
        _categoryError = true;
        _error = transactionRuleMessage(
          TransactionRule.emptyCategoryId,
          type: type,
        );
      });
      return;
    }
    if (amount == null) return;
    _saving = true;
    // Навигатор и messenger берём до первого await: после закрытия экрана
    // его context использовать нельзя.
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _error = null);
    try {
      final edited = buildEditedTransaction(
        original: widget.transaction,
        amount: amount,
        day: _day,
        clock: widget.clock,
        note: _note.text,
        newCategory: _picked,
        newType: type,
      );
      // Операцию могли удалить, пока экран был открыт: репозиторий на такое
      // отвечает общей ArgumentError, а человеку нужно объяснение.
      if (await widget.transactions.findById(edited.id) == null) {
        _fail(EditTransactionScreen.goneText);
        return;
      }
      await widget.transactions.update(edited);
      navigator.pop();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(EditTransactionScreen.savedText),
            duration: EditTransactionScreen.savedDuration,
          ),
        );
    } on TransactionRuleException catch (error) {
      _fail(transactionRuleMessage(error.rule, type: type));
    } on Object {
      // Ошибки базы, ArgumentError и всё прочее: пользователь их исправить не
      // может. Экран остаётся открытым, введённое не теряется.
      _fail(transactionSaveFailedText);
    }
  }

  void _fail(String text) {
    _saving = false;
    if (mounted) setState(() => _error = text);
  }

  /// Идёт удаление (или оно уже удалось): второй тап по «Удалить» игнорируется.
  /// После успеха флаг не сбрасывается, экран закрывается; при ошибке —
  /// сбрасывается.
  bool _deleting = false;

  /// Удаляет операцию сразу (мягко, без вопроса «Вы уверены?») и возвращает на
  /// «Историю» с сообщением «Операция удалена» и кнопкой «Отменить».
  ///
  /// Удаляется именно сохранённая операция: несохранённые правки на экране
  /// игнорируются. `messenger` и `navigator` берём до первого `await`.
  Future<void> _delete() async {
    if (_deleting || _saving) return;
    _deleting = true;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final transactions = widget.transactions;
    final t = widget.transaction;
    final categoryName = _currentCategory?.name ?? noCategoryLabel;
    setState(() => _error = null);
    var alreadyGone = false;
    try {
      // Репозиторий на повторное удаление молча ничего не делает, поэтому
      // «уже удалена» узнаём заранее (`findById` мягко удалённых не отдаёт).
      alreadyGone = await transactions.findById(t.id) == null;
      if (!alreadyGone) {
        await transactions.softDelete(t.id);
      }
    } on Object {
      _deleting = false;
      if (mounted) {
        setState(() => _error = EditTransactionScreen.deleteFailedText);
      }
      return;
    }
    // Если человек успел нажать «Назад», закрывать уже нечего (иначе `pop`
    // закрыл бы «Историю»).
    if (mounted) navigator.pop();
    // Предыдущее сообщение убираем, чтобы новое не встало в очередь за ним.
    // «Отменить» возвращает именно эту запись (id из замыкания).
    messenger.hideCurrentSnackBar();
    if (alreadyGone) {
      messenger.showSnackBar(
        const SnackBar(content: Text(EditTransactionScreen.alreadyDeletedText)),
      );
      return;
    }
    messenger.showSnackBar(
      SavedSnackBar.build(
        text: EditTransactionScreen.deletedText,
        spokenText:
            '${EditTransactionScreen.deletedText}: '
            '${t.type == TransactionType.income ? 'доход' : 'расход'} '
            '${spokenMoney(t.amount)}, $categoryName',
        onUndo: () => unawaited(_undoDelete(messenger, transactions, t.id)),
      ),
    );
  }

  /// «Отменить»: возвращает удалённую запись. Экран к этому времени закрыт,
  /// поэтому всё нужное приходит аргументами.
  Future<void> _undoDelete(
    ScaffoldMessengerState messenger,
    TransactionsRepository transactions,
    String id,
  ) async {
    try {
      await transactions.restore(id);
    } on Object {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text(SavedSnackBar.undoFailedText)),
        );
    }
  }

  String get _categoryTitle {
    if (_typeChanged) {
      return _picked?.name ??
          transactionRuleMessage(TransactionRule.emptyCategoryId, type: _type);
    }
    if (!_loaded) return EditTransactionScreen.categoryLoadingLabel;
    final category = _picked ?? _currentCategory;
    if (category == null) return noCategoryLabel;
    // Подкатегория остаётся, пока категорию не сменили.
    final sub = _categoryChanged ? null : _currentSubcategory;
    return sub == null ? category.name : '${category.name} · ${sub.name}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isIncome = _type == TransactionType.income;
    final accent = isIncome
        ? context.appColors.income
        : context.appColors.expense;
    final title = isIncome
        ? EditTransactionScreen.incomeTitle
        : EditTransactionScreen.expenseTitle;
    final category = _shownCategory;
    final error = _error;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: Icon(isIncome ? Icons.add : Icons.remove, color: accent),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                title,
                style: TextStyle(color: accent, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
      // Тело сжимается под клавиатуру, поэтому «Сохранить» всегда прямо над ней.
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Semantics(
                        container: true,
                        label: EditTransactionScreen.typeLabel,
                        child: SizedBox(
                          width: double.infinity,
                          child: SegmentedButton<TransactionType>(
                            showSelectedIcon: false,
                            style: const ButtonStyle(
                              minimumSize: WidgetStatePropertyAll(Size(48, 48)),
                            ),
                            segments: const [
                              ButtonSegment(
                                value: TransactionType.expense,
                                icon: Icon(Icons.remove),
                                label: Text(EditTransactionScreen.expenseLabel),
                              ),
                              ButtonSegment(
                                value: TransactionType.income,
                                icon: Icon(Icons.add),
                                label: Text(EditTransactionScreen.incomeLabel),
                              ),
                            ],
                            selected: {_type},
                            onSelectionChanged: (s) => _setType(s.first),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: AmountField(
                        controller: _amount,
                        isIncome: isIncome,
                      ),
                    ),
                    const SizedBox(height: 8),
                    DateChip(
                      value: _day,
                      today: _today,
                      onChanged: (day) => setState(() => _day = day),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Material(
                        color: theme.colorScheme.surfaceContainerHighest,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: _categoryError
                              ? BorderSide(
                                  color: theme.colorScheme.error,
                                  width: 2,
                                )
                              : BorderSide.none,
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: ListTile(
                          leading: Icon(
                            category == null
                                ? fallbackCategoryIcon
                                : categoryIconFor(category.iconKey),
                            color: theme.colorScheme.primary,
                          ),
                          title: Text(
                            _categoryTitle,
                            style: _categoryError
                                ? TextStyle(color: theme.colorScheme.error)
                                : null,
                          ),
                          subtitle: const Text(
                            EditTransactionScreen.categoryLabel,
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => unawaited(_pickCategory()),
                        ),
                      ),
                    ),
                    NoteField(controller: _note),
                  ],
                ),
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    error,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => unawaited(_save()),
                  child: const Text(EditTransactionScreen.saveLabel),
                ),
              ),
            ),
            // «Удалить» — вторичная кнопка под «Сохранить»: без заливки, цвет
            // ошибки, отдельная полоса, чтобы не нажать случайно.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                    minimumSize: const Size(48, 48),
                  ),
                  onPressed: () => unawaited(_delete()),
                  icon: const Icon(Icons.delete_outline),
                  label: Semantics(
                    label: EditTransactionScreen.deleteSemanticLabel,
                    excludeSemantics: true,
                    child: const Text(EditTransactionScreen.deleteLabel),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
