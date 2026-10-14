import 'package:flutter/material.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/money/currency_catalog.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/ui/account_avatar.dart';
import 'package:money_app/core/ui/async_view.dart';
import 'package:money_app/core/ui/font_scale.dart';
import 'package:money_app/core/ui/masked_amount.dart';
import 'package:money_app/core/ui/section_card.dart';
import 'package:money_app/core/ui/theme/app_colors.dart';
import 'package:money_app/core/ui/theme/app_spacing.dart';
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/accounts/domain/account_balances.dart';
import 'package:money_app/features/accounts/domain/default_account.dart';
import 'package:money_app/features/accounts/domain/transfer_options.dart';
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
    this.defaultAccountId,
    this.onRestoreAccount,
    this.onDeleteAccount,
    this.onOpenOrder,
    this.onTransfer,
    this.onOpenJournal,
    super.key,
  });

  /// «История счетов»: пункт меню «⋮», виден, если есть хотя бы один счёт
  /// (в том числе только архивные).
  final VoidCallback? onOpenJournal;

  static const journalKey = ValueKey('accounts-journal');

  /// «Перевод»: открыть форму перевода. Кнопка видна, если есть два не
  /// архивных счёта одной валюты.
  final VoidCallback? onTransfer;

  static const transferKey = ValueKey('accounts-transfer');
  static const transferHintKey = ValueKey('accounts-transfer-hint');

  /// Открывает экран «Порядок счетов»; пункт меню «⋮» виден при двух и более
  /// активных счетах.
  final VoidCallback? onOpenOrder;

  static const orderKey = ValueKey('accounts-order');
  static const moreKey = ValueKey('accounts-more');
  static const addIconKey = ValueKey('accounts-add-icon');

  /// «Вернуть из архива» у счёта из раздела «Архив»; без него раздела нет.
  final ValueChanged<Account>? onRestoreAccount;

  /// «Удалить» у счёта из раздела «Архив»; без него кнопки нет.
  final ValueChanged<Account>? onDeleteAccount;

  static const archiveKey = ValueKey('accounts-archive');
  static ValueKey<String> restoreKey(String id) =>
      ValueKey('accounts-restore-$id');
  static ValueKey<String> deleteKey(String id) =>
      ValueKey('accounts-delete-$id');

  /// Остаток в строке счёта (для тестов раскладки).
  static ValueKey<String> rowBalanceKey(String id) =>
      ValueKey('accounts-balance-$id');

  /// Id основного счёта из настроек; годен ли он, section решает сама
  /// (не в архиве, основная валюта).
  final String? defaultAccountId;

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AsyncView<List<Account>>(
          stream: accounts,
          loadingBuilder: (_) => _withAdd(context, const AsyncLoading()),
          errorBuilder: (context, error) =>
              _withAdd(context, _error(context, error)),
          // Пусто - когда нет вообще никаких счетов: если все в архиве, раздел
          // «Архив» всё равно нужен.
          isEmpty: (all) => all.isEmpty,
          emptyBuilder: (context) => _withAdd(context, _emptyText(context)),
          dataBuilder: (context, all) => AsyncView<Map<String, Money>>(
            stream: balances,
            loadingBuilder: (_) => _withAdd(
              context,
              const AsyncLoading(),
              menu: _menu(hasAny: true, shownCount: 0),
            ),
            errorBuilder: (context, error) => _withAdd(
              context,
              _error(context, error),
              menu: _menu(hasAny: true, shownCount: 0),
            ),
            dataBuilder: (context, byId) {
              final shown = _visible(all);
              final archived = [
                for (final a in all)
                  if (a.isArchived) a,
              ];
              // Счёт уже появился, а его остаток ещё считается: ждём.
              if (shown.any((a) => !byId.containsKey(a.id))) {
                return _withAdd(
                  context,
                  const AsyncLoading(),
                  menu: _menu(hasAny: true, shownCount: shown.length),
                );
              }
              final withTransfer = _hasTransfer(shown);
              return SectionCard(
                title: accountsSectionTitle,
                trailing: _trailing(
                  menu: _menu(hasAny: true, shownCount: shown.length),
                  showPlus: withTransfer,
                ),
                children: [
                  if (shown.isEmpty)
                    _emptyText(context)
                  else ...[
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
                    const SizedBox(height: AppSpacing.s),
                    for (final a in shown)
                      _AccountRow(
                        a,
                        byId[a.id]!,
                        () => onOpenAccount(a),
                        isDefault:
                            resolveDefaultAccount(
                              shown,
                              defaultAccountId,
                              mainCurrency,
                            )?.id ==
                            a.id,
                      ),
                  ],
                  _buttons(context, shown),
                  if (archived.isNotEmpty && onRestoreAccount != null)
                    _ArchiveTile(
                      archived,
                      onRestore: onRestoreAccount!,
                      onDelete: onDeleteAccount,
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  /// «Перевод» - главная кнопка, когда счетов два и больше; иначе главная
  /// «Добавить счёт», а значок «+» в заголовке не нужен (был бы дублем).
  bool _hasTransfer(List<Account> shown) =>
      onTransfer != null && shown.length >= 2;

  /// Пункты меню «⋮»: журнал (есть любой счёт, в том числе архивный) и порядок
  /// (два и больше активных). Без пунктов меню нет.
  List<_MenuEntry> _menu({required bool hasAny, required int shownCount}) => [
    if (hasAny && onOpenJournal != null) _MenuEntry.journal,
    if (shownCount >= 2 && onOpenOrder != null) _MenuEntry.order,
  ];

  Widget? _trailing({required List<_MenuEntry> menu, required bool showPlus}) {
    if (menu.isEmpty && !showPlus) return null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showPlus)
          IconButton(
            key: addIconKey,
            tooltip: accountsAddButton,
            onPressed: onAddAccount,
            icon: const Icon(Icons.add),
          ),
        if (menu.isNotEmpty)
          PopupMenuButton<_MenuEntry>(
            key: moreKey,
            tooltip: accountsMoreTooltip,
            onSelected: (entry) => switch (entry) {
              _MenuEntry.journal => onOpenJournal?.call(),
              _MenuEntry.order => onOpenOrder?.call(),
            },
            itemBuilder: (_) => [
              for (final entry in menu)
                switch (entry) {
                  _MenuEntry.journal => const PopupMenuItem(
                    key: journalKey,
                    value: _MenuEntry.journal,
                    child: Text(balanceJournalButtonSpoken),
                  ),
                  _MenuEntry.order => const PopupMenuItem(
                    key: orderKey,
                    value: _MenuEntry.order,
                    child: Text(accountsOrderTitle),
                  ),
                },
            ],
          ),
      ],
    );
  }

  Widget _addButton() => FilledButton.tonalIcon(
    key: addButtonKey,
    style: _buttonStyle,
    onPressed: onAddAccount,
    icon: const Icon(Icons.add),
    label: const Text(accountsAddButton),
  );

  static final _buttonStyle = ButtonStyle(
    minimumSize: WidgetStateProperty.all(const Size(0, 48)),
  );

  /// Состояния без ряда кнопок (загрузка, ошибка, нет счетов): «Добавить
  /// счёт» под ними на всю ширину.
  Widget _withAdd(
    BuildContext context,
    Widget body, {
    List<_MenuEntry> menu = const [],
  }) => SectionCard(
    title: accountsSectionTitle,
    trailing: _trailing(menu: menu, showPlus: false),
    children: [
      body,
      const SizedBox(height: AppSpacing.s),
      _addButton(),
    ],
  );

  /// Одна главная кнопка карточки: «Перевод» при двух и больше счетах, иначе
  /// «Добавить счёт». Есть два счёта, но нет пары одной валюты - «Перевод»
  /// неактивна с подсказкой.
  Widget _buttons(BuildContext context, List<Account> shown) {
    final add = _addButton();
    if (!_hasTransfer(shown)) {
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.s),
        child: add,
      );
    }
    final canTransfer = canTransferAny(shown);
    final transferButton = FilledButton.tonalIcon(
      key: transferKey,
      style: _buttonStyle,
      onPressed: canTransfer ? onTransfer : null,
      icon: const Icon(Icons.swap_horiz),
      label: const Text(transferButtonLabel),
    );
    // Причина неактивной кнопки читается вместе с ней, а строка под рядом для
    // скринридера скрыта (ниже), чтобы не звучать дважды.
    final transfer = canTransfer
        ? transferButton
        : Semantics(
            label: transferButtonLabel,
            hint: transferNeedPairHint,
            button: true,
            enabled: false,
            excludeSemantics: true,
            child: transferButton,
          );
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          transfer,
          if (!canTransfer)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: ExcludeSemantics(
                child: Text(
                  transferNeedPairHint,
                  key: transferHintKey,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _emptyText(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(
      accountsEmptyText,
      style: Theme.of(context).textTheme.bodyLarge
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );
}

/// Пункты меню «⋮» в заголовке карточки «Счета».
enum _MenuEntry { journal, order }

/// Свёрнутый раздел «Архив (N)» внизу списка, как у категорий: каждый счёт —
/// одна строка (аватар, название, кнопки-значки «Вернуть из архива» и
/// «Удалить»).
class _ArchiveTile extends StatelessWidget {
  const _ArchiveTile(this.accounts, {required this.onRestore, this.onDelete});

  final List<Account> accounts;
  final ValueChanged<Account> onRestore;
  final ValueChanged<Account>? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ExpansionTile(
      key: AccountsSection.archiveKey,
      title: Text(accountsArchiveTitle(accounts.length)),
      children: [
        for (final a in accounts)
          // Без отступов: аватар на одной линии с аватарами счетов выше,
          // справа поле дают сами кнопки (значок 24 в зоне 48).
          Row(
            children: [
              AccountAvatar(a.iconKey, name: a.name),
              const SizedBox(width: AppSpacing.m),
              // Длинное название переносится, кнопки остаются на месте.
              Expanded(child: Text(a.name, style: theme.textTheme.bodyLarge)),
              _ArchiveAction(
                key: AccountsSection.restoreKey(a.id),
                icon: Icons.unarchive_outlined,
                tooltip: accountRestoreAction,
                label: accountRestoreLabel(a.name),
                onPressed: () => onRestore(a),
              ),
              if (onDelete case final delete?)
                _ArchiveAction(
                  key: AccountsSection.deleteKey(a.id),
                  icon: Icons.delete_outline,
                  tooltip: accountDeleteAction,
                  label: accountDeleteLabel(a.name),
                  color: theme.colorScheme.error,
                  onPressed: () => delete(a),
                ),
            ],
          ),
      ],
    );
  }
}

/// Кнопка-значок строки архива 48 × 48: подсказка короткая, а скринридер
/// читает с названием счёта («Удалить «Тест»»).
class _ArchiveAction extends StatelessWidget {
  const _ArchiveAction({
    required this.icon,
    required this.tooltip,
    required this.label,
    required this.onPressed,
    this.color,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final String label;
  final VoidCallback onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      button: true,
      excludeSemantics: true,
      onTap: onPressed,
      child: IconButton(
        icon: Icon(icon),
        color: color,
        tooltip: tooltip,
        constraints: const BoxConstraints.tightFor(width: 48, height: 48),
        onPressed: onPressed,
      ),
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
      // Остаток - не доход: без «+» и нейтральным цветом (как в кольце);
      // отрицательный - цветом расхода. Минус ставит formatMoney (U+2212).
      final color = total.isNegative ? colors.expense : null;
      final text = formatMoney(total, currency: info);
      lines.add(
        // Длинная сумма (BTC) при крупном шрифте уменьшается, а не обрезается.
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: MaskedAmount(
            text,
            // Первая строка (основная валюта) - прежний ключ, остальные - по
            // коду.
            textKey: index == 0
                ? AccountsSection.totalKey
                : ValueKey('accounts-total-${total.currency}'),
            style: theme.textTheme.titleLarge?.copyWith(color: color),
          ),
        ),
      );
    }
    return Semantics(
      container: true,
      label: accountsTotalSemantics(
        totals,
        hidden: AmountsVisibility.hiddenOf(context),
      ),
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
  const _AccountRow(
    this.account,
    this.balance,
    this.onTap, {
    required this.isDefault,
  });

  final bool isDefault;
  final Account account;
  final Money balance;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final twoLine = useTwoLineRows(context);
    final amount = MaskedAmount(
      formatMoney(balance, currency: account.currencyInfo),
      textKey: AccountsSection.rowBalanceKey(account.id),
      softWrap: false,
      textAlign: TextAlign.end,
      style: theme.textTheme.bodyLarge?.copyWith(
        color: balance.isNegative ? context.appColors.expense : null,
      ),
    );
    return Semantics(
      container: true,
      label: accountRowSemantics(
        account.name,
        balance,
        account.currencyInfo,
        isDefault: isDefault,
        hidden: AmountsVisibility.hiddenOf(context),
      ),
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
                AccountAvatar(account.iconKey, name: account.name),
                const SizedBox(width: AppSpacing.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        account.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge,
                      ),
                      // «Основной» относится к счёту, поэтому стоит до суммы.
                      if (isDefault)
                        Text(
                          accountDefaultLabel,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      // Крупный шрифт: остаток под названием в полный
                      // размер; шире строки — уменьшается, а не рвётся.
                      if (twoLine)
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: AlignmentDirectional.centerStart,
                          child: amount,
                        ),
                    ],
                  ),
                ),
                if (!twoLine) ...[
                  const SizedBox(width: 12),
                  // Сумма не переносится: название уступает ей место, а
                  // совсем длинная сумма сжимается до 60 % ширины экрана.
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.sizeOf(context).width * 0.6,
                    ),
                    child: FittedBox(fit: BoxFit.scaleDown, child: amount),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
