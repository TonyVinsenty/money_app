import 'dart:async';

import 'package:flutter/material.dart';
import 'package:money_app/core/id/id_generator.dart';
import 'package:money_app/core/money/currency_catalog.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/money/parse_amount.dart';
import 'package:money_app/core/ui/account_icons.dart';
import 'package:money_app/core/ui/amount_failure_text.dart';
import 'package:money_app/core/ui/amount_input_formatter.dart';
import 'package:money_app/core/ui/category_rule_text.dart';
import 'package:money_app/core/ui/currency_picker.dart';
import 'package:money_app/core/ui/runes_length_formatter.dart';
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/accounts/domain/account_rules.dart';
import 'package:money_app/features/accounts/domain/accounts_repository.dart';
import 'package:money_app/features/accounts/presentation/account_texts.dart';
import 'package:money_app/features/accounts/presentation/custom_currency_dialog.dart';

/// Форма счёта: новый счёт или правка имени и значка существующего.
///
/// Новый: название, значок, «Сколько на счёте сейчас» (пусто — 0) и
/// переключатель «Минус (долг)» (стартовый остаток станет отрицательным).
/// Правка ([editing] задана): только название и значок; остаток правится
/// отдельно. Правила проверяют `domain` и репозиторий, форма показывает их
/// текстом под полем. Успех закрывает экран, ошибка оставляет открытым.
class AccountFormScreen extends StatefulWidget {
  const AccountFormScreen({
    required this.accounts,
    required this.idGenerator,
    required this.currency,
    this.currencyInfo,
    this.editing,
    super.key,
  });

  final AccountsRepository accounts;
  final IdGenerator idGenerator;

  /// Валюта нового счёта по умолчанию (позже - основная валюта); пользователь
  /// может выбрать другую.
  final String currency;

  /// Описание валюты (знаки, символ); по умолчанию - счёта в правке или
  /// запись каталога по коду [currency].
  final CurrencyInfo? currencyInfo;

  /// Счёт, который правим; `null` — создаём новый.
  final Account? editing;

  static const nameFieldKey = ValueKey('account-form-name');
  static const balanceFieldKey = ValueKey('account-form-balance');
  static const minusSwitchKey = ValueKey('account-form-minus');
  static const saveButtonKey = ValueKey('account-form-save');
  static const currencyRowKey = ValueKey('account-form-currency');

  @override
  State<AccountFormScreen> createState() => _AccountFormScreenState();
}

class _AccountFormScreenState extends State<AccountFormScreen> {
  late final TextEditingController _name;
  final TextEditingController _balance = TextEditingController();
  late String _iconKey;
  bool _minus = false;
  bool _saving = false;
  String? _nameError;
  String? _balanceError;
  String? _saveError;

  bool get _isEdit => widget.editing != null;

  CurrencyInfo? _picked;

  CurrencyInfo get _info =>
      _picked ??
      widget.currencyInfo ??
      widget.editing?.currencyInfo ??
      currencyInfoFor(widget.currency);

  Future<void> _pickCurrency() async {
    var all = <Account>[];
    try {
      // Все счета, в том числе архивные: из них собираются «Ваши валюты».
      all = await widget.accounts.watchAll().first;
    } on Object {
      // Без списка счетов лист работает, просто без «Ваших валют».
    }
    if (!mounted) return;
    final yours = <String, CurrencyInfo>{
      for (final a in all)
        if (catalogCurrency(a.currency) == null) a.currency: a.currencyInfo,
    };
    final picked = await showCurrencyPicker(
      context,
      selected: _info.code,
      yourCurrencies: yours.values.toList(),
      onCustom: () => showCustomCurrencyDialog(context, accounts: all),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _picked = picked;
      // Сумма не обрезается: лишние знаки - обычная ошибка поля.
      _balanceError = null;
      final parsed = parseAmount(
        _balance.text,
        currency: picked.code,
        currencyInfo: picked,
      );
      if (parsed is AmountParseFailed &&
          parsed.failure != AmountParseFailure.empty) {
        _balanceError = amountFailureMessage(parsed.failure, currency: picked);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.editing?.name ?? '');
    _iconKey = widget.editing?.iconKey ?? accountIconOptions.first.key;
  }

  @override
  void dispose() {
    _name.dispose();
    _balance.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    // Сумма нужна только новому счёту; пусто — 0.
    var opening = Money.zero(_info.code);
    if (!_isEdit) {
      final parsed = parseAmount(
        _balance.text,
        currency: _info.code,
        currencyInfo: _info,
      );
      if (parsed is AmountParsed) {
        opening = _minus ? -parsed.amount : parsed.amount;
      } else if (parsed is AmountParseFailed &&
          parsed.failure != AmountParseFailure.empty) {
        setState(
          () => _balanceError = amountFailureMessage(
            parsed.failure,
            currency: _info,
          ),
        );
        return;
      }
    }
    setState(() {
      _saving = true;
      _nameError = null;
      _balanceError = null;
      _saveError = null;
    });
    final navigator = Navigator.of(context);
    try {
      final editing = widget.editing;
      if (editing != null) {
        await widget.accounts.update(
          editing.id,
          name: _name.text,
          iconKey: _iconKey,
        );
      } else {
        final sortOrder = await widget.accounts.nextSortOrder();
        await widget.accounts.create(
          Account(
            id: widget.idGenerator.newId(),
            name: _name.text,
            iconKey: _iconKey,
            openingBalance: opening,
            sortOrder: sortOrder,
            currencyDigits: _info.digits,
          ),
        );
      }
      if (!mounted) return;
      navigator.pop();
    } on AccountRuleException catch (error) {
      if (!mounted) return;
      final text = accountRuleMessage(error.rule);
      setState(() {
        _saving = false;
        switch (error.rule) {
          case AccountRule.emptyName:
          case AccountRule.nameTooLong:
          case AccountRule.duplicateName:
            _nameError = text;
          case AccountRule.emptyIconKey:
          case AccountRule.currencyDigitsMismatch:
          case AccountRule.negativeSortOrder:
            _saveError = text;
        }
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = categorySaveFailedText;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? accountFormEditTitle : accountFormCreateTitle),
      ),
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
                      key: AccountFormScreen.nameFieldKey,
                      controller: _name,
                      autofocus: true,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.next,
                      inputFormatters: const [
                        RunesLengthFormatter(accountNameMaxLength),
                      ],
                      decoration: InputDecoration(
                        labelText: accountFormNameLabel,
                        hintText: accountFormNameHint,
                        errorText: _nameError,
                        errorMaxLines: 3,
                        counterText:
                            '${runesLength(_name.text)}/$accountNameMaxLength',
                      ),
                      onChanged: (_) => setState(() => _nameError = null),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      accountFormIconTitle,
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    // Ровная сетка 4 в ряд: ширина ячейки считается из доступной
                    // ширины (округляем вниз, чтобы ряд не «распух» на долю пикселя).
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final cellWidth = (constraints.maxWidth / 4)
                            .floorToDouble();
                        return Wrap(
                          children: [
                            for (final option in accountIconOptions)
                              SizedBox(
                                width: cellWidth,
                                child: Center(
                                  child: _IconChoice(
                                    key: ValueKey<String>('icon-${option.key}'),
                                    option: option,
                                    selected: option.key == _iconKey,
                                    onTap: () =>
                                        setState(() => _iconKey = option.key),
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    ListTile(
                      key: AccountFormScreen.currencyRowKey,
                      contentPadding: EdgeInsets.zero,
                      title: const Text(accountFormCurrencyTitle),
                      subtitle: Text(
                        _isEdit
                            ? accountFormCurrencyLocked(_info)
                            : accountFormCurrencyValue(_info),
                      ),
                      trailing: _isEdit
                          ? null
                          : const Icon(Icons.chevron_right),
                      onTap: _isEdit ? null : () => unawaited(_pickCurrency()),
                    ),
                    if (!_isEdit) ...[
                      const SizedBox(height: 16),
                      TextField(
                        key: AccountFormScreen.balanceFieldKey,
                        controller: _balance,
                        keyboardType: TextInputType.numberWithOptions(
                          decimal: _info.digits > 0,
                        ),
                        textInputAction: TextInputAction.done,
                        inputFormatters: [
                          AmountInputFormatter(maxDecimals: _info.digits),
                        ],
                        decoration: InputDecoration(
                          labelText: accountFormBalanceLabel,
                          // Символ виден и при пустом поле без фокуса.
                          floatingLabelBehavior: FloatingLabelBehavior.always,
                          hintText: '0',
                          suffixText: _info.symbol,
                          helperText: accountFormBalanceHelper,
                          helperMaxLines: 3,
                          errorText: _balanceError,
                          errorMaxLines: 3,
                        ),
                        onChanged: (_) => setState(() => _balanceError = null),
                        onSubmitted: (_) => unawaited(_save()),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        key: AccountFormScreen.minusSwitchKey,
                        contentPadding: EdgeInsets.zero,
                        title: const Text(accountFormMinusTitle),
                        subtitle: const Text(accountFormMinusHelper),
                        value: _minus,
                        onChanged: (v) => setState(() => _minus = v),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_saveError != null)
                    Semantics(
                      liveRegion: true,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          _saveError!,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ),
                    ),
                  FilledButton(
                    key: AccountFormScreen.saveButtonKey,
                    onPressed: _saving ? null : () => unawaited(_save()),
                    child: const Text(accountFormSaveLabel),
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

/// Один значок в сетке выбора: зона 48 x 48 dp, выбранный выделен цветом и
/// рамкой.
class _IconChoice extends StatelessWidget {
  const _IconChoice({
    required this.option,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final AccountIconOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    // Выбранность говорит `selected`, в подпись слово «выбрана» не кладём.
    return Semantics(
      label: accountFormIconSemantics(option.label),
      button: true,
      selected: selected,
      onTap: onTap,
      excludeSemantics: true,
      child: Tooltip(
        message: option.label,
        excludeFromSemantics: true,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? colors.primaryContainer : null,
              border: Border.all(
                color: selected ? colors.primary : Colors.transparent,
                width: 2,
              ),
            ),
            child: Icon(
              option.icon,
              color: selected
                  ? colors.onPrimaryContainer
                  : colors.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
