import 'dart:async';

import 'package:flutter/material.dart';
import 'package:money_app/core/id/id_generator.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/money/parse_amount.dart';
import 'package:money_app/core/ui/account_icons.dart';
import 'package:money_app/core/ui/amount_failure_text.dart';
import 'package:money_app/core/ui/amount_input_formatter.dart';
import 'package:money_app/core/ui/category_rule_text.dart';
import 'package:money_app/core/ui/runes_length_formatter.dart';
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/accounts/domain/account_rules.dart';
import 'package:money_app/features/accounts/domain/accounts_repository.dart';
import 'package:money_app/features/accounts/presentation/account_texts.dart';

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
    this.editing,
    super.key,
  });

  final AccountsRepository accounts;
  final IdGenerator idGenerator;

  /// Валюта нового счёта.
  final String currency;

  /// Счёт, который правим; `null` — создаём новый.
  final Account? editing;

  static const nameFieldKey = ValueKey('account-form-name');
  static const balanceFieldKey = ValueKey('account-form-balance');
  static const minusSwitchKey = ValueKey('account-form-minus');
  static const saveButtonKey = ValueKey('account-form-save');

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
    var opening = Money.zero(widget.currency);
    if (!_isEdit) {
      final parsed = parseAmount(_balance.text, currency: widget.currency);
      if (parsed is AmountParsed) {
        opening = _minus ? -parsed.amount : parsed.amount;
      } else if (parsed is AmountParseFailed &&
          parsed.failure != AmountParseFailure.empty) {
        setState(() => _balanceError = amountFailureMessage(parsed.failure));
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
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        for (final option in accountIconOptions)
                          _IconChoice(
                            key: ValueKey<String>('icon-${option.key}'),
                            option: option,
                            selected: option.key == _iconKey,
                            onTap: () => setState(() => _iconKey = option.key),
                          ),
                      ],
                    ),
                    if (!_isEdit) ...[
                      const SizedBox(height: 16),
                      TextField(
                        key: AccountFormScreen.balanceFieldKey,
                        controller: _balance,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        textInputAction: TextInputAction.done,
                        inputFormatters: const [AmountInputFormatter()],
                        decoration: InputDecoration(
                          labelText: accountFormBalanceLabel,
                          suffixText: '₽',
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
    return Semantics(
      label: accountFormIconSemantics(option.label, selected: selected),
      button: true,
      selected: selected,
      onTap: onTap,
      excludeSemantics: true,
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
    );
  }
}
