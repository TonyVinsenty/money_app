import 'dart:async';

import 'package:flutter/material.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/ui/async_view.dart';
import 'package:money_app/core/ui/category_rule_text.dart';
import 'package:money_app/core/ui/tap_to_dismiss_snack_content.dart';
import 'package:money_app/core/ui/theme/app_colors.dart';
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/accounts/domain/account_rules.dart';
import 'package:money_app/features/accounts/domain/accounts_repository.dart';
import 'package:money_app/features/accounts/domain/default_account.dart';
import 'package:money_app/features/accounts/presentation/account_adjust_dialog.dart';
import 'package:money_app/features/accounts/presentation/account_texts.dart';

/// Экран одного счёта: название, крупный остаток и три действия — «Изменить»,
/// «Поправить остаток», «В архив». Данные живые (потоки репозитория). Если
/// счёт пропал или ушёл в архив, тело экрана пустое: закрывает экран тот, кто
/// отправил счёт в архив (кнопка «В архив»).
class AccountScreen extends StatefulWidget {
  const AccountScreen({
    required this.accounts,
    required this.accountId,
    required this.onEdit,
    this.defaultAccountId,
    this.mainCurrency = 'RUB',
    this.onMakeDefault,
    super.key,
  });

  /// Id основного счёта из настроек и основная валюта: вместе они решают,
  /// основной ли этот счёт и можно ли его таким сделать.
  final String? defaultAccountId;
  final String mainCurrency;

  /// Делает счёт основным; `false` - запись не удалась. Без неё кнопки нет.
  final Future<bool> Function(Account account)? onMakeDefault;

  static const makeDefaultKey = ValueKey('account-make-default');
  static const defaultHintKey = ValueKey('account-default-hint');

  final AccountsRepository accounts;
  final String accountId;

  /// Открывает форму правки; завершается, когда форму закрыли.
  final Future<void> Function(Account account) onEdit;

  static const balanceKey = ValueKey('account-balance');
  static const editKey = ValueKey('account-edit');
  static const adjustKey = ValueKey('account-adjust');
  static const archiveKey = ValueKey('account-archive');

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  late final Stream<List<Account>> _accounts = widget.accounts.watchAll();
  late final Stream<Map<String, Money>> _balances = widget.accounts
      .watchBalances();

  // Защита от двойных тапов: пока идёт действие, новое не стартует.
  bool _busy = false;

  Future<void> _guarded(Future<void> Function() action) async {
    if (_busy) return;
    _busy = true;
    try {
      await action();
    } finally {
      _busy = false;
    }
  }

  void _showMessage(ScaffoldMessengerState messenger, String text) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: TapToDismissSnackContent(child: Text(text))),
      );
  }

  Future<void> _adjust(Account account, Money balance) async {
    final entered = await showDialog<Money>(
      context: context,
      builder: (_) => AccountAdjustDialog(
        current: balance,
        currencyInfo: account.currencyInfo,
      ),
    );
    if (entered == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.accounts.adjustCurrentBalance(widget.accountId, entered);
    } on Object {
      _showMessage(messenger, categorySaveFailedText);
    }
  }

  Future<void> _makeDefault(Account account) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await widget.onMakeDefault!(account);
    if (!ok && mounted) _showMessage(messenger, categorySaveFailedText);
  }

  Future<void> _restore(
    Account account,
    ScaffoldMessengerState messenger,
  ) async {
    try {
      await widget.accounts.restore(account.id);
    } on AccountRuleException catch (error) {
      _showMessage(
        messenger,
        error.rule == AccountRule.duplicateName
            ? accountRestoreDuplicateText
            : accountRuleMessage(error.rule),
      );
    } on Object {
      _showMessage(messenger, categorySaveFailedText);
    }
  }

  Future<void> _archive(Account account, Money balance) async {
    if (!balance.isZero) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(accountArchiveDialogTitle(account.name)),
          content: Text(
            accountArchiveDialogText(balance, account.currencyInfo),
          ),
          scrollable: true,
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text(accountCancelLabel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text(accountArchiveButton),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    // Берём заранее: после закрытия экрана контекст недоступен, а сообщение
    // с «Вернуть» должно жить дальше.
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await widget.accounts.archive(account.id);
    } on Object {
      _showMessage(messenger, categorySaveFailedText);
      return;
    }
    // Пользователь мог уйти назад во время записи: тогда закрывать нечего.
    if (mounted) navigator.pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: TapToDismissSnackContent(
            child: Text(accountArchivedMessage(account.name)),
          ),
          duration: const Duration(seconds: 6),
          persist: false,
          action: SnackBarAction(
            label: accountUndoAction,
            onPressed: () => unawaited(_restore(account, messenger)),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return AsyncView<List<Account>>(
      stream: _accounts,
      loadingBuilder: (_) => _frame(null, const AsyncLoading()),
      errorBuilder: (context, _) => _frame(null, const Text(accountsLoadError)),
      dataBuilder: (context, all) {
        Account? account;
        for (final a in all) {
          if (a.id == widget.accountId && !a.isArchived) account = a;
        }
        if (account == null) return _frame(null, const AsyncLoading());
        final shown = account;
        return AsyncView<Map<String, Money>>(
          stream: _balances,
          loadingBuilder: (_) => _frame(shown, const AsyncLoading()),
          errorBuilder: (context, _) =>
              _frame(shown, const Text(accountsLoadError)),
          dataBuilder: (context, byId) {
            final balance = byId[shown.id];
            if (balance == null) return _frame(shown, const AsyncLoading());
            return _frame(shown, _content(context, shown, balance));
          },
        );
      },
    );
  }

  Widget _frame(Account? account, Widget body) => Scaffold(
    appBar: AppBar(title: Text(account?.name ?? '')),
    body: SafeArea(
      child: ListView(padding: const EdgeInsets.all(16), children: [body]),
    ),
  );

  Widget _content(BuildContext context, Account account, Money balance) {
    final theme = Theme.of(context);
    final buttonStyle = ButtonStyle(
      minimumSize: WidgetStateProperty.all(const Size.fromHeight(48)),
    );
    final isDefault =
        resolveDefaultAccount(
          [account],
          widget.defaultAccountId,
          widget.mainCurrency,
        ) !=
        null;
    final canMakeDefault =
        !isDefault &&
        widget.onMakeDefault != null &&
        account.currency == widget.mainCurrency;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          accountBalanceCaption,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Semantics(
          container: true,
          label: accountRowSemantics(
            account.name,
            balance,
            account.currencyInfo,
            isDefault: isDefault,
          ),
          excludeSemantics: true,
          child: Text(
            formatMoney(balance, currency: account.currencyInfo),
            key: AccountScreen.balanceKey,
            style: theme.textTheme.headlineMedium?.copyWith(
              color: balance.isNegative ? context.appColors.expense : null,
            ),
          ),
        ),
        if (isDefault) ...[
          const SizedBox(height: 4),
          Text(
            accountDefaultHint,
            key: AccountScreen.defaultHintKey,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 24),
        // Все три кнопки не ниже 48 dp (зона нажатия), вид у них разный
        // намеренно: главное действие, второстепенное, редкое.
        FilledButton.tonal(
          key: AccountScreen.editKey,
          style: buttonStyle,
          onPressed: () => unawaited(_guarded(() => widget.onEdit(account))),
          child: const Text(accountEditButton),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          key: AccountScreen.adjustKey,
          style: buttonStyle,
          onPressed: () => unawaited(_guarded(() => _adjust(account, balance))),
          child: const Text(accountAdjustButton),
        ),
        if (canMakeDefault) ...[
          const SizedBox(height: 8),
          OutlinedButton(
            key: AccountScreen.makeDefaultKey,
            style: buttonStyle,
            onPressed: () => unawaited(_guarded(() => _makeDefault(account))),
            child: const Text(accountMakeDefaultButton),
          ),
        ],
        const SizedBox(height: 8),
        TextButton(
          key: AccountScreen.archiveKey,
          style: buttonStyle,
          onPressed: () =>
              unawaited(_guarded(() => _archive(account, balance))),
          child: const Text(accountArchiveButton),
        ),
      ],
    );
  }
}
