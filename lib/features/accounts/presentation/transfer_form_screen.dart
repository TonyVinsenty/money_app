import 'dart:async';

import 'package:flutter/material.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/id/id_generator.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/money/parse_amount.dart';
import 'package:money_app/core/time/clock.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/ui/amount_failure_text.dart';
import 'package:money_app/core/ui/amount_input_formatter.dart';
import 'package:money_app/core/ui/date_chip.dart';
import 'package:money_app/core/ui/font_scale.dart';
import 'package:money_app/core/ui/runes_length_formatter.dart';
import 'package:money_app/core/ui/tap_to_dismiss_snack_content.dart';
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/accounts/domain/transfer.dart';
import 'package:money_app/features/accounts/domain/transfer_options.dart';
import 'package:money_app/features/accounts/domain/transfer_rules.dart';
import 'package:money_app/features/accounts/domain/transfers_repository.dart';
import 'package:money_app/features/accounts/presentation/account_texts.dart';
import 'package:money_app/features/transactions/domain/occurrence.dart';
import 'package:money_app/features/transactions/domain/transaction_rules.dart';

/// Форма перевода между счетами: новый ([editing] пуст) или правка.
///
/// «Откуда» — не архивные счета; «Куда» — не архивные счета валюты «Откуда»,
/// кроме самого «Откуда». Смена «Откуда» на другую валюту сбрасывает «Куда» и
/// переводит сумму в формат новой валюты. Удаления здесь пока нет (шаг 5.23).
class TransferFormScreen extends StatefulWidget {
  const TransferFormScreen({
    required this.accounts,
    required this.transfers,
    required this.idGenerator,
    required this.clock,
    this.fromAccountId,
    this.editing,
    super.key,
  });

  /// Все счета (в том числе архивные: они нужны старому переводу).
  final Stream<List<Account>> accounts;
  final TransfersRepository transfers;
  final IdGenerator idGenerator;
  final Clock clock;

  /// Какой счёт подставить в «Откуда» (кнопка на экране счёта).
  final String? fromAccountId;

  /// Правим этот перевод; `null` — создаём новый.
  final Transfer? editing;

  static const fromKey = ValueKey('transfer-from');
  static const toKey = ValueKey('transfer-to');
  static const amountKey = ValueKey('transfer-amount');
  static const noteKey = ValueKey('transfer-note');
  static const saveKey = ValueKey('transfer-save');

  @override
  State<TransferFormScreen> createState() => _TransferFormScreenState();
}

class _TransferFormScreenState extends State<TransferFormScreen> {
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _note = TextEditingController();
  StreamSubscription<List<Account>>? _sub;
  List<Account>? _all;
  bool _failedToLoad = false;

  String? _fromId;
  String? _toId;
  late final DateOnly _today;
  late DateOnly _day;
  bool _saving = false;
  String? _amountError;
  String? _toError;
  String? _saveError;

  /// Сумма правки уже подставлена из перевода (делается один раз).
  bool _amountPrefilled = false;

  /// «Откуда» сменили на другую валюту: «Куда» и сумма сброшены, под «Куда»
  /// стоит подсказка, пока не выбран счёт или не введена сумма.
  bool _currencyChanged = false;

  Transfer? get _editing => widget.editing;

  @override
  void initState() {
    super.initState();
    _today = widget.clock.today();
    final editing = _editing;
    _day = editing?.occurredOn ?? _today;
    _fromId = editing?.fromAccountId ?? widget.fromAccountId;
    _toId = editing?.toAccountId;
    _note.text = editing?.note ?? '';
    _sub = widget.accounts.listen(
      (all) {
        if (!mounted) return;
        setState(() {
          _all = all;
          _fromId ??= _firstWithPair(all);
          if (editing == null) _autoPickTarget();
          if (editing != null && !_amountPrefilled) {
            final from = _byId(editing.fromAccountId);
            if (from != null) {
              _amount.text = formatMoney(
                editing.amount,
                currency: from.currencyInfo,
                withCurrencySymbol: false,
              );
              _amountPrefilled = true;
            }
          }
        });
      },
      onError: (Object error) {
        debugPrint('Не удалось загрузить счета для перевода: $error');
        if (mounted) setState(() => _failedToLoad = true);
      },
    );
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  String? _firstWithPair(List<Account> all) {
    for (final a in all) {
      if (hasTransferPair(all, a)) return a.id;
    }
    return null;
  }

  Account? _byId(String? id) {
    for (final a in _all ?? const <Account>[]) {
      if (a.id == id) return a;
    }
    return null;
  }

  /// Счета для выбора: не архивные, плюс архивный, который уже выбран в
  /// старом переводе (его можно оставить).
  List<Account> _selectable(Iterable<Account> accounts, String? keepId) => [
    for (final a in accounts)
      if (!a.isArchived || a.id == keepId) a,
  ];

  String _name(Account a) =>
      a.isArchived ? transferArchivedAccountName(a.name) : a.name;

  /// «Куда» подставляется сам, если подходящий счёт ровно один.
  void _autoPickTarget() {
    final from = _byId(_fromId);
    if (from == null || _toId != null) return;
    final targets = transferTargets(_all ?? const [], from);
    if (targets.length == 1) _toId = targets.single.id;
  }

  /// Смена «Откуда»: «Куда» сбрасывается, если больше не подходит; при смене
  /// валюты сумма очищается (другие знаки после запятой).
  void _onFromChanged(String? id) {
    final next = _byId(id);
    final prev = _byId(_fromId);
    setState(() {
      _fromId = id;
      _amountError = null;
      _saveError = null;
      final to = _byId(_toId);
      if (next == null ||
          to == null ||
          to.id == next.id ||
          to.currency != next.currency) {
        _toId = null;
      }
      if (prev != null && next != null && prev.currency != next.currency) {
        _amount.clear();
        _currencyChanged = true;
      }
      _autoPickTarget();
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final from = _byId(_fromId);
    final to = _byId(_toId);
    if (from == null) return;
    final info = from.currencyInfo;
    final parsed = parseAmount(
      _amount.text,
      currency: info.code,
      currencyInfo: info,
    );
    String? amountError;
    Money? amount;
    if (parsed is AmountParsed) {
      if (parsed.amount.isZero) {
        amountError = transferZeroAmountText;
      } else {
        amount = parsed.amount;
      }
    } else if (parsed is AmountParseFailed) {
      amountError = amountFailureMessage(parsed.failure, currency: info);
    }
    final toError = to == null ? transferToMissingText : null;
    if (amount == null || to == null) {
      setState(() {
        _amountError = amountError;
        _toError = toError;
      });
      return;
    }
    setState(() {
      _saving = true;
      _amountError = null;
      _toError = null;
      _saveError = null;
    });
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final transfers = widget.transfers;
    final editing = _editing;
    try {
      final unchangedDay = editing != null && editing.occurredOn == _day;
      final occurrence = unchangedDay
          ? null
          : Occurrence.onDay(_day, clock: widget.clock);
      final transfer = Transfer(
        id: editing?.id ?? widget.idGenerator.newId(),
        fromAccountId: from.id,
        toAccountId: to.id,
        amount: amount,
        occurredOn: occurrence?.occurredOn ?? editing!.occurredOn,
        occurredAt: occurrence?.occurredAt ?? editing!.occurredAt,
        note: _note.text,
      );
      if (editing == null) {
        await transfers.add(transfer);
      } else {
        await transfers.update(transfer);
      }
      // Пользователь мог уйти назад во время записи: закрывать нечего.
      if (mounted) navigator.pop();
      messenger.hideCurrentSnackBar();
      if (editing != null) {
        messenger.showSnackBar(
          SnackBar(
            content: TapToDismissSnackContent(
              child: const Text(transferEditSavedText),
            ),
          ),
        );
        return;
      }
      final text = transferSavedText(amount, info, from.name, to.name);
      final spoken = transferSavedSpoken(amount, info, from.name, to.name);
      messenger.showSnackBar(
        _undoSnackBar(
          text,
          spoken,
          textScaler,
          () => unawaited(_undo(messenger, transfers, transfer.id)),
        ),
      );
    } on Object catch (error) {
      // Правила и сбои базы человек исправить не может: общий текст.
      if (error is! TransferRuleException) {
        debugPrint('Не удалось сохранить перевод: $error');
      }
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = transferSaveFailedText;
      });
    }
  }

  SnackBar _undoSnackBar(
    String text,
    String spoken,
    TextScaler textScaler,
    VoidCallback onUndo,
  ) {
    return SnackBar(
      content: TapToDismissSnackContent(
        child: Semantics(
          label: spoken,
          excludeSemantics: true,
          child: Text(text),
        ),
      ),
      duration: const Duration(seconds: 6),
      persist: false,
      // Крупный шрифт: «Отменить» на отдельной строке (как у операций).
      actionOverflowThreshold: fontScaleFrom(textScaler) > 1.3 ? 0 : 1,
      action: SnackBarAction(label: transferUndoLabel, onPressed: onUndo),
    );
  }

  void _showMessage(ScaffoldMessengerState messenger, String text) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: TapToDismissSnackContent(child: Text(text))),
      );
  }

  /// «Удалить» в правке: без подтверждения, «Отменить» возвращает перевод.
  Future<void> _delete() async {
    final editing = _editing;
    if (editing == null || _saving) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final transfers = widget.transfers;
    try {
      await transfers.softDelete(editing.id);
    } on Object catch (error) {
      debugPrint('Не удалось удалить перевод: $error');
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = transferDeleteFailedText;
      });
      return;
    }
    if (mounted) navigator.pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        _undoSnackBar(
          transferDeletedText,
          transferDeletedText,
          textScaler,
          () => unawaited(_restore(messenger, transfers, editing.id)),
        ),
      );
  }

  Future<void> _restore(
    ScaffoldMessengerState messenger,
    TransfersRepository transfers,
    String id,
  ) async {
    try {
      await transfers.restore(id);
    } on Object {
      _showMessage(messenger, transferUndoFailedText);
    }
  }

  Future<void> _undo(
    ScaffoldMessengerState messenger,
    TransfersRepository transfers,
    String id,
  ) async {
    try {
      await transfers.softDelete(id);
    } on Object {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: TapToDismissSnackContent(
              child: const Text(transferUndoFailedText),
            ),
          ),
        );
    }
  }

  Widget _accountField({
    required Key key,
    required String label,
    required List<Account> options,
    required String? value,
    required ValueChanged<String?> onChanged,
    String? errorText,
    String? helperText,
  }) {
    return KeyedSubtree(
      key: key,
      child: DropdownButtonFormField<String>(
        // Новый ключ при смене значения: иначе поле держало бы старое
        // (initialValue читается только при создании).
        key: ValueKey('$label-${value ?? 'none'}'),
        initialValue: options.any((a) => a.id == value) ? value : null,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          errorText: errorText,
          errorMaxLines: 3,
          helperText: helperText,
          helperMaxLines: 3,
        ),
        items: [
          for (final a in options)
            DropdownMenuItem(
              value: a.id,
              child: Text(
                _name(a),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: onChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final all = _all;
    final from = _byId(_fromId);
    final title = _editing == null
        ? transferFormCreateTitle
        : transferFormEditTitle;
    Widget body;
    if (_failedToLoad) {
      body = const Text(accountsLoadError);
    } else if (all == null || from == null) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      final info = from.currencyInfo;
      final fromOptions = _selectable(all, _editing?.fromAccountId);
      final toOptions = _selectable([
        for (final a in all)
          if (a.id != from.id && a.currency == from.currency) a,
      ], _editing?.toAccountId);
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _accountField(
            key: TransferFormScreen.fromKey,
            label: transferFromLabel,
            options: fromOptions,
            value: _fromId,
            onChanged: _onFromChanged,
          ),
          const SizedBox(height: 16),
          _accountField(
            key: TransferFormScreen.toKey,
            label: transferToLabel,
            options: toOptions,
            value: _toId,
            errorText: _toError,
            helperText: _currencyChanged ? transferCurrencyChangedHint : null,
            onChanged: (id) => setState(() {
              _toId = id;
              _toError = null;
              _currencyChanged = false;
            }),
          ),
          const SizedBox(height: 16),
          TextField(
            key: TransferFormScreen.amountKey,
            controller: _amount,
            autofocus: _editing == null,
            keyboardType: TextInputType.numberWithOptions(
              decimal: info.digits > 0,
            ),
            textInputAction: TextInputAction.next,
            inputFormatters: [AmountInputFormatter(maxDecimals: info.digits)],
            decoration: InputDecoration(
              labelText: transferAmountLabel,
              suffixText: info.symbol,
              errorText: _amountError,
              errorMaxLines: 3,
            ),
            onChanged: (_) => setState(() {
              _amountError = null;
              _currencyChanged = false;
            }),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: DateChip(
              value: _day,
              today: _today,
              onChanged: (day) => setState(() => _day = day),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            key: TransferFormScreen.noteKey,
            controller: _note,
            maxLines: 1,
            textInputAction: TextInputAction.done,
            textCapitalization: TextCapitalization.sentences,
            inputFormatters: const [
              RunesLengthFormatter(transactionNoteMaxLength),
            ],
            decoration: const InputDecoration(labelText: transferNoteLabel),
          ),
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (_editing != null)
            // Скринридер читает только «Удалить перевод»; подсказка «Удалить»
            // остаётся для глаз (при долгом нажатии).
            Semantics(
              label: transferDeleteSemantic,
              button: true,
              enabled: !_saving,
              onTap: _saving ? null : () => unawaited(_delete()),
              excludeSemantics: true,
              child: Tooltip(
                message: transferDeleteTooltip,
                excludeFromSemantics: true,
                child: IconButton(
                  onPressed: _saving ? null : () => unawaited(_delete()),
                  icon: const Icon(Icons.delete_outline),
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: body,
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
                    key: TransferFormScreen.saveKey,
                    onPressed: _saving || from == null
                        ? null
                        : () => unawaited(_save()),
                    child: const Text(transferSaveLabel),
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
