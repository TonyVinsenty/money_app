import 'package:flutter/material.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/money/currency_catalog.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/ui/account_icons.dart';
import 'package:money_app/core/ui/async_view.dart';
import 'package:money_app/core/ui/theme/app_colors.dart';
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/accounts/domain/account_balances.dart';
import 'package:money_app/features/accounts/presentation/account_texts.dart';

/// Секция «Счета» вкладки «Баланс»: «Всего на счетах», список счетов с
/// остатками и кнопка «Добавить счёт». Показаны все не архивные счета в своих
/// валютах; «Всего» - строкой на каждую валюту (основная первой).
///
/// Потоки приносит вызывающий (`lib/app`, ADR 0002) и держит их одними и теми
/// же между перерисовками.
class AccountsSection extends StatelessWidget {
  const AccountsSection({
    required this.accounts,
    required this.balances,
    required this.mainCurrency,
    required this.onAddAccount,
    required this.onOpenAccount,
    super.key,
  });

  final Stream<List<Account>> accounts;
  final Stream<Map<String, Money>> balances;

  /// Основная валюта: её строка «Всего» идёт первой.
  final String mainCurrency;

  /// Нажатие «Добавить счёт».
  final VoidCallback onAddAccount;

  /// Нажатие на строку счёта.
  final ValueChanged<Account> onOpenAccount;

  static const totalKey = ValueKey('accounts-total');
  static const addButtonKey = ValueKey('accounts-add');

  List<Account> _visible(List<Account> all) => [
    for (final a in all)
      if (!a.isArchived) a,
  ];

  // Знаки валюты берём у её счёта: у своей валюты их знает только счёт.
  CurrencyInfo _infoOf(List<Account> accounts, String currency) =>
      accounts.firstWhere((a) => a.currency == currency).currencyInfo;

  Widget _error(BuildContext context, Object error) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
        const SizedBox(width: 8),
        const Expanded(child: Text(accountsLoadError)),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final addButton = FilledButton.tonalIcon(
      key: addButtonKey,
      onPressed: onAddAccount,
      icon: const Icon(Icons.add),
      label: const Text(accountsAddButton),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          accountsSectionTitle,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        AsyncView<List<Account>>(
          stream: accounts,
          loadingBuilder: (_) => const AsyncLoading(),
          errorBuilder: _error,
          isEmpty: (all) => _visible(all).isEmpty,
          emptyBuilder: (context) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              accountsEmptyText,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          dataBuilder: (context, all) => AsyncView<Map<String, Money>>(
            stream: balances,
            loadingBuilder: (_) => const AsyncLoading(),
            errorBuilder: _error,
            dataBuilder: (context, byId) {
              final shown = _visible(all);
              // Счёт уже появился, а его остаток ещё считается: ждём.
              if (shown.any((a) => !byId.containsKey(a.id))) {
                return const AsyncLoading();
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Totals(
                    totals: [
                      for (final total in totalsByCurrency(
                        shown,
                        byId,
                        mainCurrency,
                      ))
                        (total, _infoOf(shown, total.currency)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  for (final a in shown)
                    _AccountRow(a, byId[a.id]!, () => onOpenAccount(a)),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        addButton,
      ],
    );
  }
}

class _Totals extends StatelessWidget {
  const _Totals({required this.totals});

  /// Сумма и знаки её валюты; основная валюта первая.
  final List<(Money, CurrencyInfo)> totals;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    final lines = <Widget>[];
    for (final (index, (total, info)) in totals.indexed) {
      // Как «Всего» на «Главной»: плюс цветом дохода, минус цветом расхода,
      // ноль нейтрально. Минус ставит formatMoney (U+2212).
      final color = total.isZero
          ? null
          : total.isNegative
          ? colors.expense
          : colors.income;
      final shown = formatMoney(total, currency: info);
      final text = total.isZero || total.isNegative ? shown : '+$shown';
      lines.add(
        // Длинная сумма (BTC) при крупном шрифте уменьшается, а не обрезается.
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            text,
            // Первая строка (основная валюта) - прежний ключ, остальные - по
            // коду.
            key: index == 0
                ? AccountsSection.totalKey
                : ValueKey('accounts-total-${total.currency}'),
            style: theme.textTheme.titleLarge?.copyWith(color: color),
          ),
        ),
      );
    }
    return Semantics(
      container: true,
      label: accountsTotalSemantics(totals),
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            accountsTotalLabel,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          ...lines,
        ],
      ),
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow(this.account, this.balance, this.onTap);

  final Account account;
  final Money balance;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      label: accountRowSemantics(account.name, balance, account.currencyInfo),
      button: true,
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Icon(
                  accountIconFor(account.iconKey).icon,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    account.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
                const SizedBox(width: 12),
                // Сумма не переносится: название уступает ей место, а
                // совсем длинная сумма сжимается до 60 % ширины экрана.
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.sizeOf(context).width * 0.6,
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      formatMoney(balance, currency: account.currencyInfo),
                      softWrap: false,
                      textAlign: TextAlign.end,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: balance.isNegative
                            ? context.appColors.expense
                            : null,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
