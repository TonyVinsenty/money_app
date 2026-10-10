import 'package:flutter/material.dart';
import 'package:money_app/core/format/date_format.dart';
import 'package:money_app/core/format/day_label.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/money/currency_catalog.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/ui/account_icons.dart';
import 'package:money_app/core/ui/async_view.dart';
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/accounts/domain/balance_journal.dart';
import 'package:money_app/features/accounts/domain/transfer.dart';
import 'package:money_app/features/accounts/presentation/account_texts.dart';

/// Экран «История счетов»: одна лента за всё время, от новых к старым, по дням
/// (ADR 0010, п. 18). Получает потоки и колбэки; куда вести по тапу, решает
/// вызывающий (`lib/app/`). Колбэк `null` - строка не нажимается.
class BalanceJournalScreen extends StatelessWidget {
  const BalanceJournalScreen({
    required this.accounts,
    required this.transfers,
    required this.today,
    this.onOpenTransfer,
    this.onOpenAccount,
    this.dayOf,
    super.key,
  });

  /// Все счета, включая архивные.
  final Stream<List<Account>> accounts;

  /// Все живые переводы.
  final Stream<List<Transfer>> transfers;
  final DateOnly today;
  final ValueChanged<Transfer>? onOpenTransfer;
  final ValueChanged<Account>? onOpenAccount;

  /// Перевод момента в день; `null` - местный день (для тестов).
  final DateOnly Function(DateTime moment)? dayOf;

  static ValueKey<String> rowKey(BalanceJournalEntry e) =>
      ValueKey('journal-${e.runtimeType}-${e.id}');

  static Widget _error(BuildContext context, Object error) => const Center(
    child: Padding(
      padding: EdgeInsets.all(16),
      child: Text(balanceJournalLoadError, textAlign: TextAlign.center),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(balanceJournalTitle)),
      body: AsyncView<List<Account>>(
        stream: accounts,
        errorBuilder: _error,
        loadingBuilder: (_) => const AsyncLoading(),
        dataBuilder: (context, accountList) => AsyncView<List<Transfer>>(
          stream: transfers,
          errorBuilder: _error,
          loadingBuilder: (_) => const AsyncLoading(),
          dataBuilder: (context, transferList) {
            final entries = buildBalanceJournal(
              accountList,
              transferList,
              dayOf: dayOf,
            );
            if (entries.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    balanceJournalEmptyText,
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            return _JournalList(
              entries: entries,
              accounts: accountList,
              today: today,
              onOpenTransfer: onOpenTransfer,
              onOpenAccount: onOpenAccount,
            );
          },
        ),
      ),
    );
  }
}

class _JournalList extends StatelessWidget {
  const _JournalList({
    required this.entries,
    required this.accounts,
    required this.today,
    required this.onOpenTransfer,
    required this.onOpenAccount,
  });

  final List<BalanceJournalEntry> entries;
  final List<Account> accounts;
  final DateOnly today;
  final ValueChanged<Transfer>? onOpenTransfer;
  final ValueChanged<Account>? onOpenAccount;

  Account? _find(String id) {
    for (final a in accounts) {
      if (a.id == id) return a;
    }
    return null;
  }

  String _name(String id) {
    final a = _find(id);
    if (a == null) return transferUnknownPartner;
    return a.isArchived ? transferArchivedAccountName(a.name) : a.name;
  }

  /// День для озвучки: «сегодня», «вчера», «7 октября» (год, если не текущий).
  String _spokenDay(DateOnly day) {
    if (day == today || day == today.addDays(-1)) {
      return dayLabel(day, today: today).toLowerCase();
    }
    return day.year == today.year ? formatDayMonth(day) : formatDate(day);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Плоский список: перед первой строкой каждого дня - заголовок дня.
    final items = <Object>[];
    DateOnly? shown;
    for (final e in entries) {
      if (e.day != shown) {
        shown = e.day;
        items.add(e.day);
      }
      items.add(e);
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = items[i];
        if (item is DateOnly) {
          return Semantics(
            header: true,
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                historyDayLabel(item, today: today),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          );
        }
        return _row(context, item as BalanceJournalEntry);
      },
    );
  }

  Widget _row(BuildContext context, BalanceJournalEntry e) {
    final day = _spokenDay(e.day);
    final (
      IconData icon,
      String title,
      String spoken,
      VoidCallback? onTap,
    ) = switch (e) {
      // Экран счёта показывает только не архивные счета, поэтому строки
      // архивного счёта не нажимаются.
      AccountCreatedEntry(:final account) => (
        accountIconFor(account.iconKey).icon,
        journalCreatedTitle(account.name),
        journalCreatedSpoken(account.name, day),
        onOpenAccount == null || account.isArchived
            ? null
            : () => onOpenAccount!(account),
      ),
      AccountArchivedEntry(:final account) => (
        Icons.archive_outlined,
        journalArchivedTitle(account.name),
        journalArchivedSpoken(account.name, day),
        null,
      ),
      TransferEntry(:final transfer) => (
        Icons.swap_horiz,
        journalTransferTitle(
          _name(transfer.fromAccountId),
          _name(transfer.toAccountId),
        ),
        journalTransferSpoken(
          _name(transfer.fromAccountId),
          _name(transfer.toAccountId),
          transfer.amount,
          _currency(transfer),
          day,
          note: transfer.note,
        ),
        onOpenTransfer == null ? null : () => onOpenTransfer!(transfer),
      ),
    };
    final transfer = e is TransferEntry ? e.transfer : null;
    return Semantics(
      label: spoken,
      button: onTap != null,
      excludeSemantics: true,
      onTap: onTap,
      child: ListTile(
        key: BalanceJournalScreen.rowKey(e),
        contentPadding: EdgeInsets.zero,
        minTileHeight: 48,
        leading: Icon(icon),
        title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: transfer?.note == null
            ? null
            : Text(
                transfer!.note!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
        trailing: transfer == null
            ? null
            : ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width * 0.4,
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    formatMoney(transfer.amount, currency: _currency(transfer)),
                  ),
                ),
              ),
        onTap: onTap,
      ),
    );
  }

  /// Валюта перевода - валюта счёта «Откуда» (знаки после запятой из него);
  /// если его нет - счёта «Куда» (валюта у них общая).
  CurrencyInfo _currency(Transfer t) =>
      (_find(t.fromAccountId) ?? _find(t.toAccountId))?.currencyInfo ??
      currencyInfoFor(t.amount.currency, digits: 2);
}
