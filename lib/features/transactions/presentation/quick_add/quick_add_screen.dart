import 'dart:async';

import 'package:flutter/material.dart';
import 'package:money_app/core/id/id_generator.dart';
import 'package:money_app/core/money/currency_catalog.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/clock.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/ui/amount_field.dart';
import 'package:money_app/core/ui/date_chip.dart';
import 'package:money_app/core/ui/tap_to_dismiss_snack_content.dart';
import 'package:money_app/core/ui/theme/app_colors.dart';
import 'package:money_app/core/ui/transaction_rule_text.dart';
import 'package:money_app/features/categories/domain/categories_repository.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/transactions/domain/occurrence.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_rules.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';
import 'package:money_app/features/transactions/domain/transactions_repository.dart';
import 'package:money_app/features/transactions/presentation/quick_add/category_picker_screen.dart';
import 'package:money_app/features/transactions/presentation/quick_add/saved_snack_bar.dart';
import 'package:money_app/features/transactions/presentation/quick_add/subcategory_picker_screen.dart';

/// Экран быстрого ввода операции.
///
/// Тип операции виден тремя способами сразу, чтобы его нельзя было спутать:
/// словом («Новый расход»), цветом (цвет расхода/дохода из темы) и знаком
/// («\u2212» или «+» перед заголовком и перед суммой).
class QuickAddScreen extends StatefulWidget {
  const QuickAddScreen({
    required this.type,
    required this.clock,
    required this.categories,
    required this.transactions,
    required this.idGenerator,
    this.onCreateCategory,
    this.onSaved,
    this.currency,
    super.key,
  });

  /// Валюта новой операции (основная валюта из настроек); `null` — рубль.
  final CurrencyInfo? currency;

  final TransactionType type;

  /// Операция сохранена на этот день (до закрытия экрана). Даёт приложение:
  /// например, чтобы «Главная» показала месяц новой операции.
  final ValueChanged<DateOnly>? onSaved;

  /// Открывает форму новой категории (кнопка в пустом выборе категории). Даёт
  /// приложение: маршрут формы чужой фичи знает только оно. Если `null`,
  /// кнопки нет.
  final VoidCallback? onCreateCategory;

  /// Источник «сегодня» для плашки даты. Приходит из `AppServices.clock` через
  /// маршрут (`lib/app`): фича не знает про `AppScope`, а в тестах сюда
  /// подставляются фиксированные часы.
  final Clock clock;

  /// Категории для экрана выбора категории.
  final CategoriesRepository categories;

  /// Куда сохраняется операция и откуда берётся её id.
  final TransactionsRepository transactions;
  final IdGenerator idGenerator;

  static const incomeTitle = 'Новый доход';
  static const expenseTitle = 'Новый расход';

  /// Подпись видимой кнопки над клавиатурой. На iOS у числовой клавиатуры нет
  /// кнопки «Готово», поэтому продолжить нужно чем-то ещё.
  static const nextLabel = 'Далее';

  @override
  State<QuickAddScreen> createState() => _QuickAddScreenState();
}

class _QuickAddScreenState extends State<QuickAddScreen> {
  late final _amount = AmountFieldController(currency: widget.currency);

  /// «Сегодня» на момент открытия экрана. Если экран простоит открытым через
  /// полночь, «сегодня» и выбранный день намеренно не обновляются: ввод
  /// занимает секунды, а при сохранении момент всё равно берётся из часов
  /// через `Occurrence.onDay`.
  late final DateOnly _today;

  /// Выбранный день операции. При сохранении из него и из часов выводятся обе
  /// величины операции: `Occurrence.onDay(_day, clock: ...)`.
  late DateOnly _day;

  @override
  void initState() {
    super.initState();
    _today = widget.clock.today();
    _day = _today;
    // Сообщение о прошлом сохранении с кнопкой «Отменить» осталось бы висеть
    // поверх этого экрана и закрывало бы кнопку «Далее». Человек начал новый
    // ввод, значит, с прошлым он закончил. `context` для messenger в
    // `initState` брать нельзя, поэтому после первого кадра.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();
    });
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  /// Попытка продолжить: и кнопка, и клавиша на клавиатуре идут через
  /// [AmountFieldController.submit]. Если сумма разобрана — открываем выбор
  /// категории, иначе поле само покажет причину («Введите сумму»).
  void _next() {
    final amount = _amount.submit();
    if (amount != null) _openCategoryPicker(amount);
  }

  /// Экран категорий уже открыт (или открывается). Двойной тап по «Далее» иначе
  /// положил бы в стек два таких экрана. Флаг снимается, когда экран закрыт.
  bool _pickerOpen = false;

  void _openCategoryPicker(Money amount) {
    if (_pickerOpen) return;
    _pickerOpen = true;
    unawaited(
      Navigator.of(context)
          .push(
            MaterialPageRoute<void>(
              builder: (_) => CategoryPickerScreen(
                type: widget.type,
                amount: amount,
                day: _day,
                today: _today,
                categories: widget.categories,
                onCreateCategory: widget.onCreateCategory,
                onCategorySelected: (category, note) =>
                    unawaited(_onCategory(amount, category, note)),
              ),
            ),
          )
          .whenComplete(() => _pickerOpen = false),
    );
  }

  /// Тап по категории уже обрабатывается (читаем подкатегории) или сетка
  /// подкатегорий открыта. Двойной тап иначе открыл бы два таких экрана.
  bool _subcategoriesBusy = false;

  /// Тап по плитке категории: если у неё есть живые подкатегории, открываем их
  /// сетку, иначе сохраняем сразу. Комментарий [note] уже прочитан на экране
  /// категорий и остаётся в замыкании, сам тот экран лежит под сеткой.
  Future<void> _onCategory(
    Money amount,
    Category category,
    String? note,
  ) async {
    if (_saving || _subcategoriesBusy) return;
    _subcategoriesBusy = true;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    // Флаг сбрасывается в `finally` на любом выходе; кроме случая, когда сетку
    // открыли: тогда его сбросит закрытие сетки.
    var gridOpened = false;
    try {
      List<Category> subcategories;
      try {
        subcategories = [
          for (final s
              in await widget.categories.watchSubcategories(category.id).first)
            if (!s.isArchived) s,
        ];
      } on Object {
        // Не смогли узнать, есть ли подкатегории: молча сохранить без них
        // нельзя. Остаёмся на выборе категории, можно повторить.
        _showError(messenger, transactionSaveFailedText);
        return;
      }
      if (subcategories.isEmpty) {
        await _save(amount, category, null, note);
        return;
      }
      if (!mounted) return;
      gridOpened = true;
      unawaited(
        navigator
            .push(
              MaterialPageRoute<void>(
                builder: (_) => SubcategoryPickerScreen(
                  type: widget.type,
                  amount: amount,
                  day: _day,
                  today: _today,
                  parent: category,
                  categories: widget.categories,
                  onSelected: (subcategory) =>
                      unawaited(_save(amount, category, subcategory, note)),
                ),
              ),
            )
            .whenComplete(() => _subcategoriesBusy = false),
      );
    } finally {
      if (!gridOpened) _subcategoriesBusy = false;
    }
  }

  /// Идёт сохранение (или оно уже удалось): повторные тапы по плиткам
  /// игнорируются, иначе два быстрых тапа создали бы две записи. После успеха
  /// флаг не сбрасывается: экран сразу закрывается и второго сохранения быть
  /// не должно. Сбрасывается только при ошибке, чтобы можно было повторить.
  bool _saving = false;

  /// Сохраняет операцию и возвращает на «Главную» с сообщением «Сохранено: ...».
  ///
  /// `ScaffoldMessenger` и `Navigator` берутся ДО первого `await`: после
  /// закрытия экрана его `context` уже нельзя использовать, а сообщение
  /// принадлежит корневому messenger приложения и переживает закрытие.
  Future<void> _save(
    Money amount,
    Category category,
    Category? subcategory,
    String? note,
  ) async {
    if (_saving) return;
    _saving = true;
    final messenger = ScaffoldMessenger.of(context);
    // Масштаб шрифта берём до `await`: после него контекст трогать нельзя.
    final textScaler = MediaQuery.textScalerOf(context);
    final navigator = Navigator.of(context);
    final transactions = widget.transactions;
    final type = widget.type;
    try {
      // День и момент выводятся вместе из выбранного дня и часов.
      final occurrence = Occurrence.onDay(_day, clock: widget.clock);
      final transaction = Transaction.create(
        id: widget.idGenerator.newId(),
        type: type,
        amount: amount,
        occurredOn: occurrence.occurredOn,
        occurredAt: occurrence.occurredAt,
        category: category,
        subcategory: subcategory,
        note: note,
      );
      // Тексты собираем до записи: если они не соберутся, ничего не сохранено.
      final text = SavedSnackBar.text(
        type: type,
        amount: amount,
        categoryName: category.name,
        subcategoryName: subcategory?.name,
      );
      final spokenText = SavedSnackBar.spokenText(
        type: type,
        amount: amount,
        categoryName: category.name,
        subcategoryName: subcategory?.name,
      );
      await transactions.add(transaction);
      widget.onSaved?.call(occurrence.occurredOn);

      navigator.popUntil((route) => route.isFirst);
      // Предыдущее сообщение убираем, чтобы новое не встало в очередь за ним.
      // Каждое сообщение отменяет именно свою запись (id из замыкания).
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SavedSnackBar.build(
            text: text,
            spokenText: spokenText,
            textScaler: textScaler,
            onUndo: () =>
                unawaited(_undo(messenger, transactions, transaction.id)),
          ),
        );
    } on TransactionRuleException catch (error) {
      _saving = false;
      _showError(messenger, transactionRuleMessage(error.rule, type: type));
    } on Object {
      // Ошибки базы, ArgumentError и всё прочее: пользователь их исправить не
      // может. Экран остаётся открытым, введённое не теряется.
      _saving = false;
      _showError(messenger, transactionSaveFailedText);
    }
  }

  /// «Отменить»: мягкое удаление только что созданной записи.
  Future<void> _undo(
    ScaffoldMessengerState messenger,
    TransactionsRepository transactions,
    String id,
  ) async {
    try {
      await transactions.softDelete(id);
    } on Object {
      _showError(messenger, SavedSnackBar.undoFailedText);
    }
  }

  void _showError(ScaffoldMessengerState messenger, String text) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: TapToDismissSnackContent(child: Text(text))),
      );
  }

  @override
  Widget build(BuildContext context) {
    final isIncome = widget.type == TransactionType.income;
    final accent = isIncome
        ? context.appColors.income
        : context.appColors.expense;
    final title = isIncome
        ? QuickAddScreen.incomeTitle
        : QuickAddScreen.expenseTitle;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Знак — для глаз; скринридеру он не нужен, слово читается в
            // заголовке.
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
      // Тело сжимается, когда появляется клавиатура, поэтому кнопка «Далее»
      // внизу всегда оказывается прямо над ней.
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    AmountField(
                      controller: _amount,
                      isIncome: isIncome,
                      autofocus: true,
                      // Клавиша «Далее» на клавиатуре сама делает submit();
                      // сумма разобрана - открываем выбор категории.
                      onSubmitted: _openCategoryPicker,
                    ),
                    const SizedBox(height: 8),
                    DateChip(
                      value: _day,
                      today: _today,
                      onChanged: (day) => setState(() => _day = day),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _next,
                  child: const Text(QuickAddScreen.nextLabel),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
