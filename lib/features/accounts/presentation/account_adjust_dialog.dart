import 'package:flutter/material.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/money/currency_catalog.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/money/parse_amount.dart';
import 'package:money_app/core/ui/amount_failure_text.dart';
import 'package:money_app/core/ui/amount_input_formatter.dart';
import 'package:money_app/features/accounts/presentation/account_texts.dart';

/// Диалог «Поправить остаток»: поле суммы (заполнено текущим остатком) и
/// переключатель «Минус (долг)». Закрывается введённой суммой [Money] или
/// `null` (отмена).
class AccountAdjustDialog extends StatefulWidget {
  const AccountAdjustDialog({
    required this.current,
    this.currencyInfo,
    super.key,
  });

  /// Описание валюты счёта (знаки после запятой, символ); по умолчанию -
  /// запись каталога по коду остатка.
  final CurrencyInfo? currencyInfo;

  /// Текущий остаток: из него заполняются поле и переключатель.
  final Money current;

  static const fieldKey = ValueKey('account-adjust-field');
  static const minusKey = ValueKey('account-adjust-minus');
  static const saveKey = ValueKey('account-adjust-save');

  @override
  State<AccountAdjustDialog> createState() => _AccountAdjustDialogState();
}

class _AccountAdjustDialogState extends State<AccountAdjustDialog> {
  CurrencyInfo get _info =>
      widget.currencyInfo ?? currencyInfoFor(widget.current.currency);

  late final TextEditingController _text;
  late bool _minus;
  String? _error;

  @override
  void initState() {
    super.initState();
    final current = widget.current;
    _minus = current.isNegative;
    _text = TextEditingController(
      text: formatMoney(
        current.isNegative ? -current : current,
        currency: _info,
        withCurrencySymbol: false,
      ),
    );
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _save() {
    final parsed = parseAmount(
      _text.text,
      currency: widget.current.currency,
      currencyInfo: _info,
    );
    if (parsed is AmountParsed) {
      Navigator.of(context).pop(_minus ? -parsed.amount : parsed.amount);
    } else if (parsed is AmountParseFailed) {
      setState(
        () => _error = amountFailureMessage(parsed.failure, currency: _info),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(accountAdjustTitle),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: AccountAdjustDialog.fieldKey,
            controller: _text,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [AmountInputFormatter(maxDecimals: _info.digits)],
            decoration: InputDecoration(
              labelText: accountFormBalanceLabel,
              floatingLabelBehavior: FloatingLabelBehavior.always,
              hintText: '0',
              suffixText: _info.symbol,
              helperText: accountAdjustHelper,
              helperMaxLines: 4,
              errorText: _error,
              errorMaxLines: 3,
            ),
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _save(),
          ),
          SwitchListTile(
            key: AccountAdjustDialog.minusKey,
            contentPadding: EdgeInsets.zero,
            title: const Text(accountFormMinusTitle),
            subtitle: const Text(accountFormMinusHelper),
            value: _minus,
            onChanged: (v) => setState(() => _minus = v),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(accountCancelLabel),
        ),
        FilledButton(
          key: AccountAdjustDialog.saveKey,
          onPressed: _save,
          child: const Text(accountFormSaveLabel),
        ),
      ],
    );
  }
}
