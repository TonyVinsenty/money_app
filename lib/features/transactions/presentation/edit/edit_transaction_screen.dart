import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/format/money_spoken.dart';
import 'package:money_app/core/money/currency_catalog.dart';
import 'package:money_app/core/time/clock.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/ui/amount_field.dart';
import 'package:money_app/core/ui/category_icon_view.dart';
import 'package:money_app/core/ui/category_labels.dart';
import 'package:money_app/core/ui/category_rule_text.dart';
import 'package:money_app/core/ui/date_chip.dart';
import 'package:money_app/core/ui/tap_to_dismiss_snack_content.dart';
import 'package:money_app/core/ui/theme/app_colors.dart';
import 'package:money_app/core/ui/transaction_rule_text.dart';
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/categories/domain/categories_repository.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/transactions/domain/edited_transaction.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_rules.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';
import 'package:money_app/features/transactions/domain/transactions_repository.dart';
import 'package:money_app/features/transactions/presentation/edit/edit_category_picker_screen.dart';
import 'package:money_app/features/transactions/presentation/edit/edit_subcategory_picker_screen.dart';
import 'package:money_app/features/transactions/presentation/quick_add/account_chip.dart';
import 'package:money_app/features/transactions/presentation/quick_add/note_field.dart';
import 'package:money_app/features/transactions/presentation/quick_add/saved_snack_bar.dart';

/// Экран правки операции (открывается тапом по строке «Истории»).
///
/// Меняются тип (доход/расход), сумма, дата, категория, подкатегория и
/// комментарий. Тип виден тремя способами, как в быстром вводе (слово в
/// заголовке, цвет, знак). При смене типа категория и подкатегория сбрасываются
/// (у доходов и расходов разные наборы), и без выбора новой категории сохранить
/// нельзя; если вернуть исходный тип, исходные категория и подкатегория
/// возвращаются. Смена категории сбрасывает подкатегорию, повторный выбор той
/// же категории её не трогает. Строка «Подкатегория» видна, если у категории
/// есть живые подкатегории или подкатегория у операции уже есть (в том числе
/// архивная: её можно оставить или снять, но выбрать заново нельзя). Выход без
/// сохранения («Назад») ничего не меняет и подтверждения не просит.
class EditTransactionScreen extends StatefulWidget {
  const EditTransactionScreen({
    required this.transaction,
    required this.clock,
    required this.categories,
    required this.transactions,
    this.onSaved,
    this.accounts,
    super.key,
  });

  /// Поток счетов (все, фильтруем здесь). Без него строки «Счёт» нет.
  final Stream<List<Account>>? accounts;

  static const accountLabel = 'Счёт';
  static const accountArchivedSuffix = ' (в архиве)';
  static const accountUnknownText = 'не найден';
  static const accountRowKey = ValueKey('edit-account-row');

  /// Правка сохранена, операция теперь на этот день (удаление и «Назад» его
  /// не вызывают; «Отменить» в сообщении месяц не возвращает).
  final ValueChanged<DateOnly>? onSaved;

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
  static const subcategoryLabel = 'Подкатегория';
  static const subcategoryNoneText = 'Не выбрана';
  static const subcategoryResetAnnouncement = 'Подкатегория сброшена';
  static const deleteTooltip = 'Удалить';
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
  // Правка идёт в валюте самой операции, а не основной.
  late final _amount = AmountFieldController(
    currency:
        catalogCurrency(widget.transaction.amount.currency) ??
        currencyInfoFor(widget.transaction.amount.currency, digits: 2),
  );
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

  /// Названия не удалось загрузить (ошибка базы): в озвучке удаления тогда
  /// категорию не называем, чтобы не сказать неверное «Без категории».
  bool _categoryLoadFailed = false;

  /// Завершается, когда загрузка названий закончилась (успешно или нет).
  late final Future<void> _categoriesLoaded;

  final _noteFocus = FocusNode();

  /// Последний известный текст полей: слушатели контроллера срабатывают и на
  /// смену выделения, а ошибку сохранения нужно сбрасывать только на правку.
  late String _lastAmountText;
  late String _lastNoteText;

  /// Выделять ли число целиком при первом получении фокуса полем суммы.
  bool _selectAmountOnFocus = true;

  /// Тип операции в правке (может отличаться от исходного).
  late TransactionType _type;

  /// Категория, выбранная в правке; `null` — не меняли (или сбросили сменой
  /// типа).
  Category? _picked;

  /// Подкатегория, выбранная в правке, действует только при [_subOverridden]
  /// (`true`); `null` при `_subOverridden == true` значит «без подкатегории».
  /// Пока [_subOverridden] равно `false`, подкатегория исходная (если тип и
  /// категория не менялись).
  Category? _pickedSub;
  bool _subOverridden = false;

  /// Есть ли живые подкатегории у категории (по её id); заполняется по мере
  /// того, как категории показываются. Не прочитали (ошибка) — записи нет, и
  /// строка «Подкатегория» без уже выбранной подкатегории скрыта.
  final _hasSubcategories = <String, bool>{};

  /// Подсветить поле категории: человек нажал «Сохранить» без категории.
  bool _categoryError = false;

  /// Текст ошибки сохранения. Показывается над кнопкой, а не в SnackBar: он
  /// перекрыл бы саму кнопку «Сохранить».
  String? _error;

  /// Счета из потока (null - ещё не пришли) и выбранный счёт операции.
  List<Account>? _allAccounts;
  StreamSubscription<List<Account>>? _accountsSub;
  bool _accountsFailed = false;
  late String? _accountId = widget.transaction.accountId;

  /// Счета, на которые можно перенести операцию: не архивные, в её валюте.
  List<Account> get _accountOptions => [
    for (final a in _allAccounts ?? const <Account>[])
      if (!a.isArchived && a.currency == widget.transaction.amount.currency) a,
  ];

  String _accountTitle() {
    final id = _accountId;
    if (id == null) return accountChipNone;
    for (final a in _allAccounts ?? const <Account>[]) {
      if (a.id == id) {
        return a.isArchived
            ? '${a.name}${EditTransactionScreen.accountArchivedSuffix}'
            : a.name;
      }
    }
    // Счетов нет в ответе или поток упал: не вечная «Загрузка…». Сохранение
    // счёт не трогает.
    return _allAccounts != null || _accountsFailed
        ? EditTransactionScreen.accountUnknownText
        : EditTransactionScreen.categoryLoadingLabel;
  }

  Future<void> _pickAccount() async {
    final picked = await showAccountSheet(
      context,
      accounts: _accountOptions,
      selectedId: _accountId,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _accountId = picked.id;
      _error = null;
    });
  }

  @override
  void initState() {
    super.initState();
    _accountsSub = widget.accounts?.listen(
      (all) {
        if (mounted) setState(() => _allAccounts = all);
      },
      onError: (Object error) {
        debugPrint('Не удалось загрузить счета для правки: $error');
        if (mounted) setState(() => _accountsFailed = true);
      },
    );
    final t = widget.transaction;
    _today = widget.clock.today();
    _day = t.occurredOn;
    _type = t.type;
    _amount.text.text = formatMoney(t.amount, withCurrencySymbol: false);
    _note = TextEditingController(text: t.note);
    _lastAmountText = _amount.text.text;
    _lastNoteText = _note.text;
    _amount.text.addListener(_onAmountTextChanged);
    _note.addListener(_onNoteTextChanged);
    _amount.focusNode.addListener(_onAmountFocusChanged);
    _categoriesLoaded = _loadCategories();
    unawaited(_rememberSubcategories(t.categoryId));
    // Сообщение «Изменения сохранены» от прошлой правки закрыло бы кнопку
    // «Сохранить» на этом экране. `context` для messenger в `initState` брать
    // нельзя, поэтому после первого кадра (как в быстром вводе).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();
    });
  }

  @override
  void dispose() {
    unawaited(_accountsSub?.cancel());
    _amount.text.removeListener(_onAmountTextChanged);
    _note.removeListener(_onNoteTextChanged);
    _amount.focusNode.removeListener(_onAmountFocusChanged);
    _amount.dispose();
    _note.dispose();
    _noteFocus.dispose();
    super.dispose();
  }

  /// Ошибка сохранения относилась к прежним данным: любая правка её снимает.
  void _clearError() {
    if (_error != null && mounted) setState(() => _error = null);
  }

  void _onAmountTextChanged() {
    final text = _amount.text.text;
    if (text == _lastAmountText) return;
    _lastAmountText = text;
    _clearError();
  }

  void _onNoteTextChanged() {
    final text = _note.text;
    if (text == _lastNoteText) return;
    _lastNoteText = text;
    _clearError();
  }

  /// При первом получении фокуса выделяем всё число: чтобы поправить сумму,
  /// не нужно стирать «,00» вручную. Выделение ставим после кадра: тап, который
  /// дал фокус, сам ставит курсор, и наше выделение должно прийти позже него.
  void _onAmountFocusChanged() {
    if (!_selectAmountOnFocus || !_amount.focusNode.hasFocus) return;
    _selectAmountOnFocus = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final text = _amount.text;
      text.selection = TextSelection(
        baseOffset: 0,
        extentOffset: text.text.length,
      );
    });
  }

  Future<void> _loadCategories() async {
    final t = widget.transaction;
    Category? category;
    Category? subcategory;
    var failed = false;
    try {
      category = await widget.categories.findById(t.categoryId);
      final subId = t.subcategoryId;
      if (subId != null) subcategory = await widget.categories.findById(subId);
    } on Object {
      // Название не загрузилось: показываем запасной текст, сохранение при
      // этом работает (ему нужен только id категории).
      failed = true;
    }
    void apply() {
      _currentCategory = category;
      _currentSubcategory = subcategory;
      _categoryLoadFailed = failed;
      _loaded = true;
    }

    // Результат нужен и закрывшемуся экрану: удаление досказывает сообщение
    // после закрытия.
    if (mounted) {
      setState(apply);
    } else {
      apply();
    }
  }

  /// Живые подкатегории категории [parentId] (архивные не в счёте).
  Future<List<Category>> _liveSubcategories(String parentId) async => [
    for (final s in await widget.categories.watchSubcategories(parentId).first)
      if (!s.isArchived) s,
  ];

  /// Узнаёт, есть ли у категории живые подкатегории, чтобы показать строку
  /// «Подкатегория». Ошибку чтения глотаем: строка просто не появится.
  Future<void> _rememberSubcategories(String categoryId) async {
    if (_hasSubcategories.containsKey(categoryId)) return;
    try {
      final subs = await _liveSubcategories(categoryId);
      if (!mounted) return;
      final has = subs.isNotEmpty;
      setState(() => _hasSubcategories[categoryId] = has);
    } on Object {
      // Не узнали: считаем, что подкатегорий нет.
    }
  }

  bool get _typeChanged => _type != widget.transaction.type;

  bool get _categoryChanged =>
      _picked != null && _picked!.id != widget.transaction.categoryId;

  /// Категория для показа: при смене типа старая не годится, остаётся только
  /// выбранная заново (или ничего).
  Category? get _shownCategory =>
      _typeChanged ? _picked : (_picked ?? _currentCategory);

  /// Подкатегория для показа: выбранная в правке, а без выбора — исходная, но
  /// только пока не сменились тип и категория (тогда её нет).
  Category? get _shownSubcategory => _subOverridden
      ? _pickedSub
      : (_typeChanged || _categoryChanged ? null : _currentSubcategory);

  /// Скринридеру сообщаем о сбросе подкатегории: иначе он прошёл бы молча.
  void _announceSubcategoryReset() {
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        EditTransactionScreen.subcategoryResetAnnouncement,
        Directionality.of(context),
      ),
    );
  }

  void _setType(TransactionType type) {
    if (type == _type) return;
    final hadSubcategory = _shownSubcategory != null;
    setState(() {
      _type = type;
      // Выбор относился к другому виду категорий. Возврат к исходному типу
      // снова показывает исходную категорию (она хранится в `_currentCategory`)
      // и подкатегорию.
      _picked = null;
      _pickedSub = null;
      _subOverridden = false;
      _categoryError = false;
      _error = null;
    });
    if (hadSubcategory) _announceSubcategoryReset();
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
    // Та же категория, что уже выбрана, подкатегорию не сбрасывает.
    // Сравниваем по id, а не по загруженному объекту: `_currentCategory` может
    // быть пуст (категории ещё грузятся или не загрузились).
    final shownCategoryId = _typeChanged
        ? _picked?.id
        : (_picked?.id ?? widget.transaction.categoryId);
    final sameCategory = shownCategoryId == picked.id;
    final hadSubcategory = _shownSubcategory != null;
    setState(() {
      _picked = picked;
      if (!sameCategory) {
        _pickedSub = null;
        _subOverridden = true;
      }
      _categoryError = false;
      _error = null;
    });
    unawaited(_rememberSubcategories(picked.id));
    if (!sameCategory && hadSubcategory) _announceSubcategoryReset();
  }

  /// Идёт чтение подкатегорий или открыта их сетка: повторный тап игнорируется.
  bool _subcategoriesBusy = false;

  Future<void> _pickSubcategory() async {
    final parent = _shownCategory;
    if (parent == null || _subcategoriesBusy) return;
    _subcategoriesBusy = true;
    try {
      final List<Category> subcategories;
      try {
        subcategories = await _liveSubcategories(parent.id);
      } on Object {
        // Список не прочитался: сетку не открываем, состояние правки цело.
        if (mounted) {
          setState(() => _error = subcategoriesLoadErrorText);
        }
        return;
      }
      if (!mounted) return;
      final choice = await Navigator.of(context).push<SubcategoryChoice>(
        MaterialPageRoute<SubcategoryChoice>(
          builder: (_) => EditSubcategoryPickerScreen(
            parent: parent,
            subcategories: subcategories,
          ),
        ),
      );
      if (choice == null || !mounted) return;
      setState(() {
        _pickedSub = choice.subcategory;
        _subOverridden = true;
        _error = null;
      });
    } finally {
      _subcategoriesBusy = false;
    }
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
        newSubcategory: _pickedSub,
        clearSubcategory: _subOverridden && _pickedSub == null,
      ).withAccount(_accountId);
      // Операцию могли удалить, пока экран был открыт: репозиторий на такое
      // отвечает общей ArgumentError, а человеку нужно объяснение.
      if (await widget.transactions.findById(edited.id) == null) {
        _fail(EditTransactionScreen.goneText);
        return;
      }
      await widget.transactions.update(edited);
      widget.onSaved?.call(edited.occurredOn);
      // Если человек успел нажать «Назад», закрывать уже нечего (иначе `pop`
      // закрыл бы «Историю»). Сообщение при этом всё равно показываем.
      if (mounted) navigator.pop();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: TapToDismissSnackContent(
              child: Text(EditTransactionScreen.savedText),
            ),
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
    // Масштаб шрифта берём до `await`: после него контекст трогать нельзя.
    final textScaler = MediaQuery.textScalerOf(context);
    final navigator = Navigator.of(context);
    final transactions = widget.transactions;
    final t = widget.transaction;
    setState(() => _error = null);
    var alreadyGone = false;
    String? categoryName;
    try {
      // Репозиторий на повторное удаление молча ничего не делает, поэтому
      // «уже удалена» узнаём заранее (`findById` мягко удалённых не отдаёт).
      alreadyGone = await transactions.findById(t.id) == null;
      if (!alreadyGone) {
        await transactions.softDelete(t.id);
      }
      // Название категории для озвучки: если оно ещё грузится (ранний тап),
      // дожидаемся. Не загрузилось из-за ошибки — говорим без названия, а не
      // «Без категории»; это слово только для категории, которой нет в базе.
      await _categoriesLoaded;
      categoryName = _categoryLoadFailed
          ? null
          : (_currentCategory?.name ?? noCategoryLabel);
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
        const SnackBar(
          content: TapToDismissSnackContent(
            child: Text(EditTransactionScreen.alreadyDeletedText),
          ),
        ),
      );
      return;
    }
    messenger.showSnackBar(
      SavedSnackBar.build(
        text: EditTransactionScreen.deletedText,
        spokenText:
            '${EditTransactionScreen.deletedText}: '
            '${t.type == TransactionType.income ? 'доход' : 'расход'} '
            '${spokenMoney(t.amount)}'
            '${categoryName == null ? '' : ', $categoryName'}',
        textScaler: textScaler,
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
          const SnackBar(
            content: TapToDismissSnackContent(
              child: Text(SavedSnackBar.undoFailedText),
            ),
          ),
        );
    }
  }

  String get _categoryTitle {
    if (_typeChanged) {
      return _picked?.name ??
          transactionRuleMessage(TransactionRule.emptyCategoryId, type: _type);
    }
    if (!_loaded) return EditTransactionScreen.categoryLoadingLabel;
    return (_picked ?? _currentCategory)?.name ?? noCategoryLabel;
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
    final subcategory = _shownSubcategory;
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
        // «Удалить» в углу, далеко от «Сохранить»: внизу рядом с ним над
        // клавиатурой легко промахнуться. Иконка 48 dp, цвет ошибки; скринридер
        // читает «Удалить операцию» (подпись иконки), долгое нажатие показывает
        // «Удалить».
        actions: [
          IconButton(
            tooltip: EditTransactionScreen.deleteTooltip,
            color: theme.colorScheme.error,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: () => unawaited(_delete()),
            icon: const Icon(
              Icons.delete_outline,
              semanticLabel: EditTransactionScreen.deleteSemanticLabel,
            ),
          ),
        ],
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
                        // «Далее» при верной сумме ведёт к комментарию; при
                        // ошибке фокус остаётся в поле (см. AmountField).
                        onSubmitted: (_) => _noteFocus.requestFocus(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    DateChip(
                      value: _day,
                      today: _today,
                      onChanged: (day) => setState(() {
                        _day = day;
                        _error = null;
                      }),
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
                          leading: CategoryIconView(
                            category?.iconKey,
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
                    if (category != null &&
                        (_hasSubcategories[category.id] == true ||
                            subcategory != null))
                      _SubcategoryRow(
                        subcategory: subcategory,
                        onTap: () => unawaited(_pickSubcategory()),
                      ),
                    // Есть счета этой валюты или у операции уже есть счёт.
                    if (_accountOptions.isNotEmpty || _accountId != null)
                      _AccountRow(
                        title: _accountTitle(),
                        onTap: () => unawaited(_pickAccount()),
                      ),
                    NoteField(controller: _note, focusNode: _noteFocus),
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
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Строка «Счёт» под категорией: «Карта», «Без счёта» или «Карта (в
/// архиве)». Скринридер читает «Счёт: Карта» как кнопку.
class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.title, required this.onTap});

  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Semantics(
        button: true,
        label: '${EditTransactionScreen.accountLabel}: $title',
        onTap: onTap,
        excludeSemantics: true,
        child: Material(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            key: EditTransactionScreen.accountRowKey,
            leading: Icon(
              Icons.account_balance_wallet_outlined,
              color: theme.colorScheme.primary,
            ),
            title: Text(title),
            subtitle: const Text(EditTransactionScreen.accountLabel),
            trailing: const Icon(Icons.chevron_right),
            onTap: onTap,
          ),
        ),
      ),
    );
  }
}

/// Строка «Подкатегория» под полем категории: в том же стиле. Скринридер
/// читает «Подкатегория: Овощи» или «Подкатегория: не выбрана» как кнопку.
class _SubcategoryRow extends StatelessWidget {
  const _SubcategoryRow({required this.subcategory, required this.onTap});

  final Category? subcategory;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sub = subcategory;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Semantics(
        button: true,
        label:
            '${EditTransactionScreen.subcategoryLabel}: '
            '${sub?.name ?? EditTransactionScreen.subcategoryNoneText.toLowerCase()}',
        onTap: onTap,
        excludeSemantics: true,
        child: Material(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            leading: CategoryIconView(
              sub?.iconKey,
              color: theme.colorScheme.primary,
            ),
            title: Text(sub?.name ?? EditTransactionScreen.subcategoryNoneText),
            subtitle: const Text(EditTransactionScreen.subcategoryLabel),
            trailing: const Icon(Icons.chevron_right),
            onTap: onTap,
          ),
        ),
      ),
    );
  }
}
