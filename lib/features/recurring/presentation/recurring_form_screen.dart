import 'package:flutter/material.dart';
import 'package:money_app/core/format/day_label.dart';
import 'package:money_app/core/money/currency_catalog.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/ui/amount_field.dart';
import 'package:money_app/core/ui/runes_length_formatter.dart';
import 'package:money_app/features/recurring/domain/recurring_payment.dart';
import 'package:money_app/features/recurring/domain/recurring_rules.dart';
import 'package:money_app/features/recurring/presentation/recurring_texts.dart';

/// Форма регулярного платежа, часть 1 (шаг 6.11): название, вид, сумма,
/// повтор, первый платёж и окончание. Категория и счёт пока заглушки, а
/// «Сохранить» только проверяет поля: запись в базу появится в 6.12 вместе с
/// выбором категории.
class RecurringFormScreen extends StatefulWidget {
  const RecurringFormScreen({
    required this.currency,
    required this.today,
    super.key,
  });

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

  @override
  void dispose() {
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

  /// Проверка полей; запись в базу - шаг 6.12.
  void _save() {
    final title = _name.text.trim();
    final amount = _amount.submit();
    setState(() {
      _nameError = title.isEmpty
          ? recurringErrorEmptyTitle
          : runesLength(title) > recurringTitleMaxLength
          ? recurringErrorTitleTooLong
          : null;
      // Пусто и неразборчиво показывает само поле суммы.
      _amountError = amount != null && amount.minorUnits <= 0
          ? recurringErrorAmountZero
          : null;
      final end = _end;
      _endError = end != null && end < _first
          ? recurringErrorEndsBeforeStart
          : null;
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
                        onSelectionChanged: (s) =>
                            setState(() => _income = s.first),
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
                    // Заглушки: выбор категории и счёта - шаг 6.12.
                    const ListTile(
                      contentPadding: EdgeInsets.zero,
                      enabled: false,
                      title: Text(recurringFormCategoryLabel),
                      subtitle: Text(recurringFormCategoryHint),
                      trailing: Icon(Icons.chevron_right),
                    ),
                    const ListTile(
                      contentPadding: EdgeInsets.zero,
                      enabled: false,
                      title: Text(recurringFormAccountLabel),
                      subtitle: Text(recurringFormAccountHint),
                      trailing: Icon(Icons.chevron_right),
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
              child: FilledButton(
                key: RecurringFormScreen.saveKey,
                onPressed: _save,
                child: const Text(recurringFormSave),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
