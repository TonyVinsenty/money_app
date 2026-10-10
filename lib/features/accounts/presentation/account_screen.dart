import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/ui/async_view.dart';
import 'package:money_app/core/ui/category_rule_text.dart';
import 'package:money_app/core/ui/tap_to_dismiss_snack_content.dart';
import 'package:money_app/core/ui/theme/app_colors.dart';
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/accounts/domain/account_rules.dart';
import 'package:money_app/features/accounts/domain/accounts_repository.dart';
import 'package:money_app/features/accounts/domain/default_account.dart';
import 'package:money_app/features/accounts/domain/transfer.dart';
import 'package:money_app/features/accounts/domain/transfer_options.dart';
import 'package:money_app/features/accounts/domain/transfers_repository.dart';
import 'package:money_app/features/accounts/presentation/account_adjust_dialog.dart';
import 'package:money_app/features/accounts/presentation/account_texts.dart';
import 'package:money_app/features/accounts/presentation/account_transfers_list.dart';

/// Новый основной счёт после архивации прежнего: его `name` для сообщения и
/// `undo`, которое возвращает прежний основной (зовётся после «Вернуть»).
typedef ArchivedDefault = ({String name, Future<void> Function() undo});

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
    this.onShowTransactions,
    this.onArchivedDefault,
    this.onTransfer,
    this.transfers,
    this.today,
    this.onEditTransfer,
    super.key,
  });

  /// «Перевод»: открыть форму с этим счётом в «Откуда». Кнопка видна, если
  /// есть ещё не архивный счёт той же валюты.
  final Future<void> Function(Account account)? onTransfer;

  static const transferKey = ValueKey('account-transfer');

  /// Репозиторий переводов, сегодняшний день и открытие формы правки: все три
  /// нужны для раздела «Переводы»; без них раздела нет.
  final TransfersRepository? transfers;
  final DateOnly? today;
  final Future<void> Function(Transfer transfer)? onEditTransfer;

  /// Вызывается после архивации счёта со списком счетов до неё. Если архивный
  /// счёт был основным, выбирает нового и возвращает его имя и действие
  /// `undo` (вернуть прежний основной); иначе `null`.
  final Future<ArchivedDefault?> Function(
    Account archived,
    List<Account> before,
  )?
  onArchivedDefault;

  /// «Операции»: показать операции счёта в «Истории». Кнопка есть только у
  /// счетов основной валюты («История» показывает только её).
  final ValueChanged<Account>? onShowTransactions;

  static const operationsKey = ValueKey('account-operations');

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

  late final Stream<List<Transfer>>? _transfers = widget.transfers
      ?.watchForAccount(widget.accountId);

  // Последний список счетов (для выбора нового основного при архивации).
  List<Account> _latestAccounts = const [];

  // «Операции» уже нажаты: экран закрывается, повторный тап игнорируется.
  bool _operationsOpened = false;

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
    final view = View.of(context);
    final direction = Directionality.of(context);
    final ok = await widget.onMakeDefault!(account);
    if (!ok) {
      if (mounted) _showMessage(messenger, categorySaveFailedText);
      return;
    }
    unawaited(
      SemanticsService.sendAnnouncement(
        view,
        accountMadeDefaultAnnouncement(account.name),
        direction,
      ),
    );
  }

  /// `true`, если счёт вернулся из архива (иначе сообщение уже показано).
  Future<bool> _restore(
    Account account,
    ScaffoldMessengerState messenger,
  ) async {
    try {
      await widget.accounts.restore(account.id);
      return true;
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
    return false;
  }

  /// «Вернуть» в сообщении об архиве: счёт возвращается, а если архив сменил
  /// основной счёт - и прежний основной тоже.
  Future<void> _undoArchive(
    Account account,
    ScaffoldMessengerState messenger,
    ArchivedDefault? changedDefault,
  ) async {
    final restored = await _restore(account, messenger);
    if (!restored || changedDefault == null) return;
    try {
      await changedDefault.undo();
    } on Object catch (error) {
      debugPrint('Не удалось вернуть прежний основной счёт: $error');
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
    // Список до архивации: из него выбирается новый основной счёт.
    final before = _latestAccounts;
    try {
      await widget.accounts.archive(account.id);
    } on Object {
      _showMessage(messenger, categorySaveFailedText);
      return;
    }
    // Ушёл в архив основной счёт: приложение само выбирает нового и называет
    // его (`null` - основной не менялся).
    ArchivedDefault? changedDefault;
    try {
      changedDefault = await widget.onArchivedDefault?.call(account, before);
    } on Object catch (error) {
      debugPrint('Не удалось выбрать новый основной счёт: $error');
    }
    // Пользователь мог уйти назад во время записи: тогда закрывать нечего.
    if (mounted) navigator.pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: TapToDismissSnackContent(
            child: Text(
              changedDefault == null
                  ? accountArchivedMessage(account.name)
                  : accountDefaultChangedMessage(changedDefault.name),
            ),
          ),
          duration: const Duration(seconds: 6),
          persist: false,
          action: SnackBarAction(
            label: accountUndoAction,
            onPressed: () =>
                unawaited(_undoArchive(account, messenger, changedDefault)),
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
        _latestAccounts = all;
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
        if (widget.onTransfer != null &&
            hasTransferPair(_latestAccounts, account)) ...[
          OutlinedButton(
            key: AccountScreen.transferKey,
            style: buttonStyle,
            onPressed: () =>
                unawaited(_guarded(() => widget.onTransfer!(account))),
            child: const Text(transferButtonLabel),
          ),
          const SizedBox(height: 8),
        ],
        if (widget.onShowTransactions != null &&
            account.currency == widget.mainCurrency) ...[
          OutlinedButton(
            key: AccountScreen.operationsKey,
            style: buttonStyle,
            onPressed: () {
              // Переход закрывает этот экран: второй тап не должен закрыть
              // ещё и экран под ним.
              if (_operationsOpened) return;
              _operationsOpened = true;
              widget.onShowTransactions!(account);
            },
            child: const Text(accountOperationsButton),
          ),
          const SizedBox(height: 8),
        ],
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
        if (_transfers != null &&
            widget.today != null &&
            widget.onEditTransfer != null)
          AccountTransfersList(
            transfers: _transfers,
            accounts: _latestAccounts,
            accountId: account.id,
            currency: account.currencyInfo,
            today: widget.today!,
            onOpen: (t) => unawaited(_guarded(() => widget.onEditTransfer!(t))),
          ),
      ],
    );
  }
}
