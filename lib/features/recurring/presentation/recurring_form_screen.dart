import 'dart:async';

import 'package:flutter/material.dart';
import 'package:money_app/core/format/day_label.dart';
import 'package:money_app/core/id/id_generator.dart';
import 'package:money_app/core/money/currency_catalog.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/ui/amount_field.dart';
import 'package:money_app/core/ui/recurring_rule_text.dart';
import 'package:money_app/core/ui/runes_length_formatter.dart';
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/accounts/domain/default_account.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/recurring/domain/recurring_payment.dart';
import 'package:money_app/features/recurring/domain/recurring_repository.dart';
import 'package:money_app/features/recurring/domain/recurring_rules.dart';
import 'package:money_app/features/recurring/presentation/recurring_texts.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

/// Выбранные категория и (необязательная) подкатегория.
typedef RecurringCategoryChoice = ({Category category, Category? subcategory});

/// Выбор категории нужного вида: сетку показывает `lib/app/` (ADR 0002).
/// `null` - человек вернулся назад.
typedef RecurringCategoryPicker = Future<RecurringCategoryChoice?> Function(
  BuildContext context,
  TransactionType type,
);

/// Выбор счёта среди списка: лист показывает `lib/app/`. `null` - лист
/// закрыли без выбора, `id == null` - «Без счёта».
typedef RecurringAccountPicker = Future<({String? id})?> Function(
  BuildContext context,
  List<Account> accounts,
  String? selectedId,
);

/// Форма регулярного платежа: название, вид, сумма, категория, счёт, повтор,
/// первый платёж и окончание. «Сохранить» проверяет поля и пишет платёж в
/// [repository]; ошибки правил показываются над кнопкой.
class RecurringFormScreen extends StatefulWidget {
  const RecurringFormScreen({
    required this.currency,
    required this.today,
    required this.repository,
    required this.idGenerator,
    required this.categories,
    required this.accounts,
    required this.onPickCategory,
    required this.onPickAccount,
    this.defaultAccountId,
    super.key,
  });

  final RecurringRepository repository;
  final IdGenerator idGenerator;

  /// Все категории, включая архивные: по ним показываются названия.
  final Stream<List<Category>> categories;

  /// Все счета; в выбор попадают живые счета основной валюты.
  final Stream<List<Account>> accounts;
  final RecurringCategoryPicker onPickCategory;
  final RecurringAccountPicker onPickAccount;

  /// Основной счёт из настроек: у нового платежа выбран он.
  final String? defaultAccountId;

  /// Основная валюта (платёж создаётся в ней).
  final CurrencyInfo currency;

  /// Сегодняшний день: раньше него первый платёж не назначить.
  final DateOnly today;

  static const nameFieldKey = ValueKey('recurring-form-name');
  static const typeKey = ValueKey('recurring-form-type');
  static const repeatKey = ValueKey('recurring-form-repeat');
  static const firstKey = ValueKey('recurring-form-first');
  static const hintKey = ValueKey('recurring-form-hint');
  static const endKey = ValueKey('recurring-form-end');
  static const endErrorKey = ValueKey('recurring-form-end-error');
  static const endClearKey = ValueKey('recurring-form-end-clear');
  static const saveKey = ValueKey('recurring-form-save');
  static const categoryKey = ValueKey('recurring-form-category');
  static const accountKey = ValueKey('recurring-form-account');
  static const saveErrorKey = ValueKey('recurring-form-save-error');

  @override
  State<RecurringFormScreen> createState() => _RecurringFormScreenState();
}

class _RecurringFormScreenState extends State<RecurringFormScreen> {
  final _name = TextEditingController();
  late final AmountFieldController _amount = AmountFieldController(
    currency: widget.currency,
  );
  bool _income = false;
  int _repeat = 0;
  late DateOnly _first = widget.today;
  DateOnly? _end;
  String? _nameError;
  String? _amountError;
  String? _endError;
  String? _saveError;
  bool _saving = false;

  String? _categoryId;
  String? _subcategoryId;
  bool _categoryError = false;
  List<Category> _allCategories = const [];
  List<Account> _allAccounts = const [];
  String? _accountId;
  bool _accountTouched = false;
  final _subs = <StreamSubscription<Object?>>[];

  @override
  void initState() {
    super.initState();
    _subs.add(
      widget.categories.listen((all) {
        if (mounted) setState(() => _allCategories = all);
      }, onError: (Object e) => debugPrint('Категории для платежа: $e')),
    );
    _subs.add(
      widget.accounts.listen((all) {
        if (!mounted) return;
        setState(() {
          _allAccounts = all;
          if (!_accountTouched) {
            _accountId = resolveDefaultAccount(
              all,
              widget.defaultAccountId,
              widget.currency.code,
            )?.id;
          }
        });
      }, onError: (Object e) => debugPrint('Счета для платежа: $e')),
    );
  }

  @override
  void dispose() {
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<DateOnly?> _pickDate(DateOnly initial, DateOnly first) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.toDateTime(),
      firstDate: first.toDateTime(),
      lastDate: DateTime(9999, 12, 31),
    );
    return picked == null ? null : DateOnly.fromDateTime(picked);
  }

  Future<void> _pickFirst() async {
    final picked = await _pickDate(_first, widget.today);
    if (picked == null || !mounted) return;
    setState(() {
      _first = picked;
      _endError = null;
    });
  }

  Future<void> _pickEnd() async {
    final picked = await _pickDate(_end ?? _first, _first);
    if (picked == null || !mounted) return;
    setState(() {
      _end = picked;
      _endError = null;
    });
  }

  TransactionType get _type =>
      _income ? TransactionType.income : TransactionType.expense;

  Category? _categoryById(String? id) {
    for (final c in _allCategories) {
      if (c.id == id) return c;
    }
    return null;
  }

  String? get _categoryTitle {
    final category = _categoryById(_categoryId);
    if (category == null) return null;
    final sub = _categoryById(_subcategoryId);
    return sub == null ? category.name : '${category.name} · ${sub.name}';
  }

  List<Account> get _accountOptions => [
    for (final a in _allAccounts)
      if (!a.isArchived && a.currency == widget.currency.code) a,
  ];

  String get _accountTitle {
    for (final a in _allAccounts) {
      if (a.id == _accountId) return a.name;
    }
    return recurringFormAccountHint;
  }

  Future<void> _pickCategory() async {
    final picked = await widget.onPickCategory(context, _type);
    if (picked == null || !mounted) return;
    setState(() {
      _categoryId = picked.category.id;
      _subcategoryId = picked.subcategory?.id;
      // Названия берутся из потока; если он ещё не принёс выбранное, добавляем.
      for (final c in [picked.category, ?picked.subcategory]) {
        if (_categoryById(c.id) == null) {
          _allCategories = [..._allCategories, c];
        }
      }
      _categoryError = false;
      _saveError = null;
    });
  }

  Future<void> _pickAccount() async {
    final picked = await widget.onPickAccount(
      context,
      _accountOptions,
      _accountId,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _accountId = picked.id;
      _accountTouched = true;
      _saveError = null;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final title = _name.text.trim();
    final amount = _amount.submit();
    final categoryId = _categoryId;
    final end = _end;
    final nameError = title.isEmpty
        ? recurringErrorEmptyTitle
        : runesLength(title) > recurringTitleMaxLength
        ? recurringErrorTitleTooLong
        : null;
    // Пусто и неразборчиво показывает само поле суммы.
    final amountError = amount != null && amount.minorUnits <= 0
        ? recurringErrorAmountZero
        : null;
    final endError = end != null && end < _first
        ? recurringErrorEndsBeforeStart
        : null;
    setState(() {
      _nameError = nameError;
      _amountError = amountError;
      _endError = endError;
      _categoryError = categoryId == null;
      _saveError = null;
    });
    if (nameError != null ||
        amount == null ||
        amountError != null ||
        endError != null ||
        categoryId == null) {
      return;
    }
    setState(() => _saving = true);
    try {
      final option = recurringRepeatOptions[_repeat];
      await widget.repository.create(
        RecurringPayment(
          id: widget.idGenerator.newId(),
          title: title,
          type: _type,
          amount: amount,
          categoryId: categoryId,
          subcategoryId: _subcategoryId,
          accountId: _accountId,
          unit: option.unit,
          every: option.every,
          startsOn: _first,
          endsOn: end,
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } on RecurringRuleException catch (error) {
      _failSave(recurringRuleMessage(error.rule, type: _type));
    } on Object {
      _failSave(recurringSaveFailedText);
    }
  }

  void _failSave(String text) {
    if (!mounted) return;
    setState(() {
      _saving = false;
      _saveError = text;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final option = recurringRepeatOptions[_repeat];
    final showHint = option.unit == RepeatUnit.month && _first.day >= 29;
    final end = _end;
    return Scaffold(
      appBar: AppBar(title: const Text(recurringFormTitle)),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      key: RecurringFormScreen.nameFieldKey,
                      controller: _name,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.next,
                      inputFormatters: const [
                        RunesLengthFormatter(recurringTitleMaxLength),
                      ],
                      decoration: InputDecoration(
                        labelText: recurringFormNameLabel,
                        hintText: recurringFormNameHint,
                        errorText: _nameError,
                        errorMaxLines: 3,
                      ),
                      onChanged: (_) => setState(() => _nameError = null),
                    ),
                    const SizedBox(height: 16),
                    Semantics(
                      container: true,
                      label: recurringFormTypeLabel,
                      child: SegmentedButton<bool>(
                        key: RecurringFormScreen.typeKey,
                        showSelectedIcon: false,
                        style: const ButtonStyle(
                          minimumSize: WidgetStatePropertyAll(Size(48, 48)),
                        ),
                        segments: const [
                          ButtonSegment(
                            value: false,
                            icon: Icon(Icons.remove),
                            label: Text(recurringFormExpense),
                          ),
                          ButtonSegment(
                            value: true,
                            icon: Icon(Icons.add),
                            label: Text(recurringFormIncome),
                          ),
                        ],
                        selected: {_income},
                        onSelectionChanged: (s) => setState(() {
                          if (s.first == _income) return;
                          _income = s.first;
                          // Категории другого вида не подходят.
                          _categoryId = null;
                          _subcategoryId = null;
                          _categoryError = false;
                          _saveError = null;
                        }),
                      ),
                    ),
                    const SizedBox(height: 16),
                    AmountField(controller: _amount, isIncome: _income),
                    if (_amountError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          _amountError!,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ),
                    const SizedBox(height: 16),
                    ListTile(
                      key: RecurringFormScreen.categoryKey,
                      contentPadding: EdgeInsets.zero,
                      title: const Text(recurringFormCategoryLabel),
                      subtitle: Text(
                        _categoryError
                            ? recurringErrorCategory
                            : (_categoryTitle ?? recurringFormCategoryHint),
                        style: _categoryError
                            ? TextStyle(color: theme.colorScheme.error)
                            : null,
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _pickCategory,
                    ),
                    ListTile(
                      key: RecurringFormScreen.accountKey,
                      contentPadding: EdgeInsets.zero,
                      title: const Text(recurringFormAccountLabel),
                      subtitle: Text(_accountTitle),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _pickAccount,
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<int>(
                      key: RecurringFormScreen.repeatKey,
                      initialValue: _repeat,
                      decoration: const InputDecoration(
                        labelText: recurringFormRepeatLabel,
                      ),
                      items: [
                        for (var i = 0; i < recurringRepeatOptions.length; i++)
                          DropdownMenuItem(
                            value: i,
                            child: Text(recurringRepeatOptions[i].label),
                          ),
                      ],
                      onChanged: (v) => setState(() => _repeat = v ?? 0),
                    ),
                    ListTile(
                      key: RecurringFormScreen.firstKey,
                      contentPadding: EdgeInsets.zero,
                      title: const Text(recurringFormFirstLabel),
                      subtitle: Text(dayLabel(_first, today: widget.today)),
                      trailing: const Icon(Icons.calendar_today_outlined),
                      onTap: _pickFirst,
                    ),
                    if (showHint)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          recurringLastDayHint(_first.day),
                          key: RecurringFormScreen.hintKey,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ListTile(
                      key: RecurringFormScreen.endKey,
                      contentPadding: EdgeInsets.zero,
                      title: const Text(recurringFormEndLabel),
                      subtitle: Text(
                        end == null
                            ? recurringFormNoEnd
                            : dayLabel(end, today: widget.today),
                      ),
                      trailing: end == null
                          ? const Icon(Icons.calendar_today_outlined)
                          : IconButton(
                              key: RecurringFormScreen.endClearKey,
                              tooltip: recurringFormEndClear,
                              icon: const Icon(Icons.close),
                              onPressed: () => setState(() {
                                _end = null;
                                _endError = null;
                              }),
                            ),
                      onTap: _pickEnd,
                    ),
                    if (_endError != null)
                      Text(
                        _endError!,
                        key: RecurringFormScreen.endErrorKey,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_saveError != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        _saveError!,
                        key: RecurringFormScreen.saveErrorKey,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                  FilledButton(
                    key: RecurringFormScreen.saveKey,
                    onPressed: _save,
                    child: const Text(recurringFormSave),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
