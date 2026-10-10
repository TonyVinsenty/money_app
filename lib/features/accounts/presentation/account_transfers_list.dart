import 'package:flutter/material.dart';
import 'package:money_app/core/format/date_format.dart';
import 'package:money_app/core/format/day_label.dart';
import 'package:money_app/core/money/currency_catalog.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/accounts/domain/transfer.dart';
import 'package:money_app/features/accounts/presentation/account_texts.dart';

/// Раздел «Переводы» на экране счёта: переводы, где счёт [accountId] — «откуда»
/// или «куда», по дням. Пусто или ошибка потока — раздела нет (ошибку здесь
/// показывать нечем: остаток и кнопки экрана от неё не зависят).
class AccountTransfersList extends StatelessWidget {
  const AccountTransfersList({
    required this.transfers,
    required this.accounts,
    required this.accountId,
    required this.currency,
    required this.today,
    required this.onOpen,
    super.key,
  });

  final Stream<List<Transfer>> transfers;

  /// Все счета, включая архивные: из них берутся имена партнёров.
  final List<Account> accounts;
  final String accountId;
  final CurrencyInfo currency;
  final DateOnly today;
  final ValueChanged<Transfer> onOpen;

  static const sectionKey = ValueKey('account-transfers');
  static ValueKey<String> rowKey(String id) => ValueKey('transfer-row-$id');

  String _partnerName(String id) {
    for (final a in accounts) {
      if (a.id == id) {
        return a.isArchived ? transferArchivedAccountName(a.name) : a.name;
      }
    }
    return '';
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
    return StreamBuilder<List<Transfer>>(
      stream: transfers,
      builder: (context, snapshot) {
        final list = snapshot.data;
        if (list == null || list.isEmpty) return const SizedBox.shrink();
        final children = <Widget>[];
        DateOnly? shownDay;
        for (final t in list) {
          if (t.occurredOn != shownDay) {
            shownDay = t.occurredOn;
            children.add(
              Semantics(
                header: true,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    historyDayLabel(t.occurredOn, today: today),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            );
          }
          final outgoing = t.fromAccountId == accountId;
          final partner = _partnerName(
            outgoing ? t.toAccountId : t.fromAccountId,
          );
          children.add(
            Semantics(
              label: transferRowSpoken(
                outgoing,
                partner,
                t.amount,
                currency,
                _spokenDay(t.occurredOn),
                note: t.note,
              ),
              button: true,
              excludeSemantics: true,
              onTap: () => onOpen(t),
              child: ListTile(
                key: rowKey(t.id),
                contentPadding: EdgeInsets.zero,
                minTileHeight: 48,
                title: Text(
                  transferRowTitle(outgoing, partner),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.sizeOf(context).width * 0.4,
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      transferRowAmount(outgoing, t.amount, currency),
                    ),
                  ),
                ),
                subtitle: t.note == null
                    ? null
                    : Text(
                        t.note!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                onTap: () => onOpen(t),
              ),
            ),
          );
        }
        return Column(
          key: sectionKey,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 24),
            Semantics(
              header: true,
              child: Text(
                transfersSectionTitle,
                style: theme.textTheme.titleMedium,
              ),
            ),
            ...children,
          ],
        );
      },
    );
  }
}
