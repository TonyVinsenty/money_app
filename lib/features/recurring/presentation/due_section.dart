import 'dart:async';

import 'package:flutter/material.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/money/currency_catalog.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/ui/account_icons.dart';
import 'package:money_app/core/ui/amount_field.dart';
import 'package:money_app/core/ui/date_chip.dart';
import 'package:money_app/core/ui/tap_to_dismiss_snack_content.dart';
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/recurring/domain/recurring_payment.dart';
import 'package:money_app/features/recurring/domain/recurring_repository.dart';
import 'package:money_app/features/recurring/presentation/recurring_form_screen.dart';
import 'package:money_app/features/recurring/presentation/recurring_texts.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

/// «Оплачено»: возвращает текст ошибки или `null`, если всё получилось.
/// Сообщение «Сохранено...» с «Отменить» показывает вызывающий (`lib/app`).
typedef DuePay = Future<String?> Function(
  RecurringDue due, {
  required Money amount,
  required DateOnly day,
  required String? accountId,
});

/// «Пропустить»: текст ошибки или `null`.
typedef DueSkip = Future<String?> Function(RecurringDue due);

/// Блок «К оплате (N)» на «Балансе» (ADR 0011, п. 6): наступившие платежи с
/// кнопками «Оплачено» и «Пропустить»; тап по строке открывает лист «Оплата».
/// Если записей нет, блока нет совсем.
class DueSection extends StatefulWidget {
  const DueSection({
    required this.dues,
    required this.categories,
    required this.accounts,
    required this.today,
    required this.onPay,
    required this.onSkip,
    required this.onEdit,
    required this.onPickAccount,
    super.key,
  });

  final Stream<List<RecurringDue>> dues;

  /// Все категории, включая архивные: по ним видно, что платёж «застрял».
  final Stream<List<Category>> categories;
  final Stream<List<Account>> accounts;
  final DateOnly today;
  final DuePay onPay;
  final DueSkip onSkip;

  /// «Изменить» у платежа с архивной категорией или счётом.
  final ValueChanged<RecurringPayment> onEdit;
  final RecurringAccountPicker onPickAccount;

  static const titleKey = ValueKey('due-title');
  static ValueKey<String> rowKey(String id) => ValueKey('due-row-$id');
  static ValueKey<String> payKey(String id) => ValueKey('due-pay-$id');
  static ValueKey<String> skipKey(String id) => ValueKey('due-skip-$id');
  static ValueKey<String> editKey(String id) => ValueKey('due-edit-$id');
  static ValueKey<String> noteKey(String id) => ValueKey('due-note-$id');
  static const sheetAmountKey = ValueKey('due-sheet-amount');
  static const sheetAccountKey = ValueKey('due-sheet-account');
  static const sheetPayKey = ValueKey('due-sheet-pay');
  static const sheetErrorKey = ValueKey('due-sheet-error');

  @override
  State<DueSection> createState() => _DueSectionState();
}

class _DueSectionState extends State<DueSection> {
  List<RecurringDue> _dues = const [];
  List<Category> _categories = const [];
  List<Account> _accounts = const [];
  final _busy = <String>{};
  final _subs = <StreamSubscription<Object?>>[];

  @override
  void initState() {
    super.initState();
    _subs.add(
      widget.dues.listen((v) {
        if (mounted) setState(() => _dues = v);
      }, onError: (Object e) => debugPrint('К оплате: $e')),
    );
    _subs.add(
      widget.categories.listen((v) {
        if (mounted) setState(() => _categories = v);
      }, onError: (Object e) => debugPrint('Категории для «К оплате»: $e')),
    );
    _subs.add(
      widget.accounts.listen((v) {
        if (mounted) setState(() => _accounts = v);
      }, onError: (Object e) => debugPrint('Счета для «К оплате»: $e')),
    );
  }

  @override
  void dispose() {
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    super.dispose();
  }

  /// Название архивной категории, подкатегории или счёта платежа; `null`,
  /// если всё живое.
  String? _archivedText(RecurringPayment p) {
    for (final id in [p.categoryId, p.subcategoryId]) {
      for (final c in _categories) {
        if (c.id == id && c.isArchived) return dueCategoryArchivedText(c.name);
      }
    }
    for (final a in _accounts) {
      if (a.id == p.accountId && a.isArchived) {
        return dueAccountArchivedText(a.name);
      }
    }
    return null;
  }

  void _error(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: TapToDismissSnackContent(child: Text(text))),
      );
  }

  /// Пока идёт запись, повторные касания по записи игнорируются.
  Future<String?> _guard(String id, Future<String?> Function() action) async {
    if (!_busy.add(id)) return null;
    try {
      return await action();
    } finally {
      _busy.remove(id);
    }
  }

  Future<void> _payQuick(RecurringDue due) async {
    final p = due.payment;
    final error = await _guard(
      due.id,
      () => widget.onPay(
        due,
        amount: p.amount,
        day: due.dueOn,
        accountId: p.accountId,
      ),
    );
    if (error != null && mounted) _error(error);
  }

  Future<void> _skip(RecurringDue due) async {
    final error = await _guard(due.id, () => widget.onSkip(due));
    if (error != null && mounted) _error(error);
  }

  Future<void> _openSheet(RecurringDue due) async {
    final accounts = [
      for (final a in _accounts)
        if (!a.isArchived && a.currency == due.payment.amount.currency) a,
    ];
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => _PaySheet(
        due: due,
        today: widget.today,
        accounts: accounts,
        onPickAccount: widget.onPickAccount,
        onPay: (amount, day, accountId) => _guard(
          due.id,
          () =>
              widget.onPay(due, amount: amount, day: day, accountId: accountId),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_dues.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Semantics(
              header: true,
              child: Text(
                dueSectionTitle(_dues.length),
                key: DueSection.titleKey,
                style: theme.textTheme.titleMedium,
              ),
            ),
          ),
        ),
        for (final due in _dues) _buildRow(context, due),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildRow(BuildContext context, RecurringDue due) {
    final theme = Theme.of(context);
    final p = due.payment;
    final archived = _archivedText(p);
    return Padding(
      key: DueSection.rowKey(due.id),
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            label: dueRowSemantics(p, due.dueOn, widget.today),
            button: true,
            onTap: () => archived == null ? _openSheet(due) : widget.onEdit(p),
            excludeSemantics: true,
            child: InkWell(
              onTap: () =>
                  archived == null ? _openSheet(due) : widget.onEdit(p),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dueRowText(p),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge,
                      ),
                      Text(
                        dueDayText(due.dueOn, widget.today),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (archived != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                archived,
                key: DueSection.noteKey(due.id),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (archived == null)
                FilledButton.tonal(
                  key: DueSection.payKey(due.id),
                  style: ButtonStyle(
                    minimumSize: WidgetStateProperty.all(const Size(0, 48)),
                  ),
                  onPressed: () => unawaited(_payQuick(due)),
                  child: const Text(duePayButton),
                )
              else
                FilledButton.tonal(
                  key: DueSection.editKey(due.id),
                  style: ButtonStyle(
                    minimumSize: WidgetStateProperty.all(const Size(0, 48)),
                  ),
                  onPressed: () => widget.onEdit(p),
                  child: const Text(dueEditButton),
                ),
              TextButton(
                key: DueSection.skipKey(due.id),
                style: ButtonStyle(
                  minimumSize: WidgetStateProperty.all(const Size(0, 48)),
                ),
                onPressed: () => unawaited(_skip(due)),
                child: const Text(dueSkipButton),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Лист «Оплата»: сумма, день и счёт этой записи; платёж не меняется.
class _PaySheet extends StatefulWidget {
  const _PaySheet({
    required this.due,
    required this.today,
    required this.accounts,
    required this.onPickAccount,
    required this.onPay,
  });

  final RecurringDue due;
  final DateOnly today;
  final List<Account> accounts;
  final RecurringAccountPicker onPickAccount;
  final Future<String?> Function(Money amount, DateOnly day, String? accountId)
  onPay;

  @override
  State<_PaySheet> createState() => _PaySheetState();
}

class _PaySheetState extends State<_PaySheet> {
  late final AmountFieldController _amount = AmountFieldController(
    currency: currencyInfoFor(widget.due.payment.amount.currency),
  );
  late DateOnly _day = widget.due.dueOn;
  late String? _accountId = widget.due.payment.accountId;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _amount.text.text = formatMoney(
      widget.due.payment.amount,
      withCurrencySymbol: false,
    );
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Account? get _account {
    for (final a in widget.accounts) {
      if (a.id == _accountId) return a;
    }
    return null;
  }

  Future<void> _pickAccount() async {
    final picked = await widget.onPickAccount(
      context,
      widget.accounts,
      _account?.id,
    );
    if (picked != null && mounted) setState(() => _accountId = picked.id);
  }

  Future<void> _pay() async {
    if (_saving) return;
    final amount = _amount.submit();
    if (amount == null) return;
    if (amount.minorUnits <= 0) {
      setState(() => _error = recurringErrorAmountZero);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final navigator = Navigator.of(context);
    final error = await widget.onPay(amount, _day, _accountId);
    if (!mounted) return;
    if (error == null) {
      navigator.pop();
    } else {
      setState(() {
        _saving = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final payment = widget.due.payment;
    final account = _account;
    final label = theme.textTheme.labelLarge;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          24,
          0,
          24,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                dueSheetTitle(payment.title),
                style: theme.textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 12),
            Text(dueSheetAmountLabel, style: label),
            AmountField(
              key: DueSection.sheetAmountKey,
              controller: _amount,
              isIncome: payment.type == TransactionType.income,
            ),
            const SizedBox(height: 12),
            Text(dueSheetDateLabel, style: label),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: DateChip(
                value: _day,
                today: widget.today,
                onChanged: (d) => setState(() => _day = d),
              ),
            ),
            const SizedBox(height: 12),
            Text(dueSheetAccountLabel, style: label),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: ActionChip(
                  key: DueSection.sheetAccountKey,
                  avatar: Icon(
                    account == null
                        ? Icons.account_balance_wallet_outlined
                        : accountIconFor(account.iconKey).icon,
                    size: 18,
                  ),
                  label: Text(account?.name ?? recurringFormAccountHint),
                  onPressed: () => unawaited(_pickAccount()),
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  key: DueSection.sheetErrorKey,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            const SizedBox(height: 16),
            FilledButton(
              key: DueSection.sheetPayKey,
              style: ButtonStyle(
                minimumSize: WidgetStateProperty.all(const Size(0, 48)),
              ),
              onPressed: _saving ? null : () => unawaited(_pay()),
              child: const Text(duePayButton),
            ),
          ],
        ),
      ),
    );
  }
}
