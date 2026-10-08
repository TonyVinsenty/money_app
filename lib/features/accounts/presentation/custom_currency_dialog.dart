import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:money_app/core/money/currency.dart';
import 'package:money_app/core/money/currency_catalog.dart';
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/accounts/presentation/account_texts.dart';

/// Диалог «Своя валюта» (ADR 0010, п. 16.2): код и число знаков.
///
/// Возвращает запись каталога (если код из каталога - введённые знаки не
/// используются), валюту со знаками существующего счёта или новую свою
/// валюту; `null` при отмене. [accounts] - все счета, в том числе архивные.
Future<CurrencyInfo?> showCustomCurrencyDialog(
  BuildContext context, {
  required List<Account> accounts,
}) {
  return showDialog<CurrencyInfo>(
    context: context,
    builder: (context) => CustomCurrencyDialog(accounts: accounts),
  );
}

/// Буквы сами становятся заглавными, длина - до 10 символов.
class _CodeFormatter extends TextInputFormatter {
  const _CodeFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final upper = newValue.text.toUpperCase();
    if (upper.length > 10) return oldValue;
    return newValue.copyWith(text: upper);
  }
}

class CustomCurrencyDialog extends StatefulWidget {
  const CustomCurrencyDialog({required this.accounts, super.key});

  final List<Account> accounts;

  static const codeFieldKey = ValueKey('custom-currency-code');
  static const digitsFieldKey = ValueKey('custom-currency-digits');
  static const doneKey = ValueKey('custom-currency-done');

  @override
  State<CustomCurrencyDialog> createState() => _CustomCurrencyDialogState();
}

class _CustomCurrencyDialogState extends State<CustomCurrencyDialog> {
  final TextEditingController _code = TextEditingController();
  final TextEditingController _digits = TextEditingController(text: '2');
  String _typedDigits = '2';
  String? _codeError;
  String? _digitsError;

  /// Счёт с введённым кодом (если код не из каталога).
  Account? get _sameCode {
    final code = _code.text;
    if (catalogCurrency(code) != null) return null;
    for (final a in widget.accounts) {
      if (a.currency == code) return a;
    }
    return null;
  }

  @override
  void dispose() {
    _code.dispose();
    _digits.dispose();
    super.dispose();
  }

  void _onCodeChanged(String _) {
    setState(() {
      _codeError = null;
      _digitsError = null;
      final same = _sameCode;
      _digits.text = same == null ? _typedDigits : '${same.currencyDigits}';
    });
  }

  void _done() {
    final code = _code.text;
    if (!isValidCurrencyCode(code)) {
      setState(() => _codeError = customCurrencyCodeError);
      return;
    }
    final known = catalogCurrency(code);
    if (known != null) {
      Navigator.of(context).pop(known);
      return;
    }
    final same = _sameCode;
    if (same != null) {
      Navigator.of(context).pop(same.currencyInfo);
      return;
    }
    final digits = int.tryParse(_digits.text);
    if (digits == null || digits < 0 || digits > 8) {
      setState(() => _digitsError = customCurrencyDigitsError);
      return;
    }
    Navigator.of(context).pop(currencyInfoFor(code, digits: digits));
  }

  @override
  Widget build(BuildContext context) {
    final same = _sameCode;
    return AlertDialog(
      scrollable: true,
      title: const Text(customCurrencyTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(customCurrencyExplain),
          const SizedBox(height: 16),
          TextField(
            key: CustomCurrencyDialog.codeFieldKey,
            controller: _code,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.next,
            inputFormatters: const [_CodeFormatter()],
            decoration: InputDecoration(
              labelText: customCurrencyCodeLabel,
              hintText: customCurrencyCodeHint,
              errorText: _codeError,
              errorMaxLines: 3,
            ),
            onChanged: _onCodeChanged,
          ),
          const SizedBox(height: 16),
          TextField(
            key: CustomCurrencyDialog.digitsFieldKey,
            controller: _digits,
            enabled: same == null,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(1),
            ],
            decoration: InputDecoration(
              labelText: customCurrencyDigitsLabel,
              helperText: same == null
                  ? customCurrencyDigitsHelper
                  : customCurrencyLikeAccount(same.name),
              helperMaxLines: 3,
              errorText: _digitsError,
              errorMaxLines: 3,
            ),
            onChanged: (text) => setState(() {
              _typedDigits = text;
              _digitsError = null;
            }),
            onSubmitted: (_) => _done(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(accountCancelLabel),
        ),
        FilledButton(
          key: CustomCurrencyDialog.doneKey,
          onPressed: _done,
          child: const Text(customCurrencyDone),
        ),
      ],
    );
  }
}
