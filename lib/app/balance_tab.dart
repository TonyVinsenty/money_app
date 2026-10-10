import 'dart:async';

import 'package:flutter/material.dart';
import 'package:money_app/app/app_routes.dart';
import 'package:money_app/app/app_scope.dart';
import 'package:money_app/app/app_tab_indices.dart';
import 'package:money_app/app/browse_scope.dart';
import 'package:money_app/core/money/currency_catalog.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/ui/category_rule_text.dart';
import 'package:money_app/core/ui/tap_to_dismiss_snack_content.dart';
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/accounts/domain/account_rules.dart';
import 'package:money_app/features/accounts/domain/accounts_repository.dart';
import 'package:money_app/features/accounts/presentation/account_texts.dart';
import 'package:money_app/features/accounts/presentation/accounts_section.dart';
import 'package:money_app/features/recurring/domain/recurring_payment.dart';
import 'package:money_app/features/recurring/domain/recurring_repository.dart';
import 'package:money_app/features/recurring/presentation/recurring_section.dart';
import 'package:money_app/features/settings/presentation/app_settings_controller.dart';

/// Новый счёт [created] становится основным, если он в основной валюте, а
/// основного счёта ещё нет (первый счёт этой валюты; или прежний основной
/// ушёл в архив). Звать после сохранения счёта.
Future<void> adoptFirstAccountAsDefault(
  Account created,
  AccountsRepository accounts,
  AppSettingsController settings,
) async {
  if (created.currency != settings.mainCurrencyCode) return;
  final all = await accounts.watchAll().first;
  // Ключ не стираем (ADR 0010, п. 16.9): пишем, только если его нет или он
  // указывает на несуществующий либо архивный счёт. Живой счёт другой валюты
  // остаётся основным «про запас»: вернут валюту - он снова основной.
  final stored = settings.defaultAccountId;
  final storedIsLive =
      stored != null &&
      all.any((a) => a.id == stored && a.id != created.id && !a.isArchived);
  if (!storedIsLive) await settings.setDefaultAccountId(created.id);
}

/// Вкладка «Баланс»: берёт потоки счетов и остатков из репозитория и отдаёт
/// их секции «Счета» (ADR 0002). Сама секция репозитория не знает.
class BalanceTab extends StatefulWidget {
  const BalanceTab({super.key});

  @override
  State<BalanceTab> createState() => _BalanceTabState();
}

class _BalanceTabState extends State<BalanceTab> {
  AccountsRepository? _repository;
  late Stream<List<Account>> _accounts;
  late Stream<Map<String, Money>> _balances;
  RecurringRepository? _recurringRepository;
  late Stream<List<RecurringListItem>> _recurring;

  // Потоки создаём один раз и заново только при смене репозитория: в build
  // каждая перерисовка начинала бы подписку заново.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repository = AppScope.of(context).accounts;
    if (!identical(repository, _repository)) {
      _repository = repository;
      _accounts = repository.watchAll();
      _balances = repository.watchBalances();
    }
    final recurring = AppScope.of(context).recurring;
    if (!identical(recurring, _recurringRepository)) {
      _recurringRepository = recurring;
      _recurring = recurring.watchAll();
    }
  }

  Future<void> _restore(Account account) async {
    final messenger = ScaffoldMessenger.of(context);
    void say(String text) => messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: TapToDismissSnackContent(child: Text(text))),
      );
    try {
      await _repository!.restore(account.id);
      say(accountRestoredMessage(account.name));
    } on AccountRuleException catch (error) {
      say(
        error.rule == AccountRule.duplicateName
            ? accountRestoreDuplicateText
            : accountRuleMessage(error.rule),
      );
    } on Object {
      say(categorySaveFailedText);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Без BrowseScope (в части тестов) день берём из часов; в приложении он
    // обновляется при возврате и смене дня.
    final today =
        context
            .dependOnInheritedWidgetOfExactType<BrowseScope>()
            ?.notifier
            ?.today ??
        AppScope.of(context).clock.today();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        AccountsSection(
          accounts: _accounts,
          balances: _balances,
          mainCurrency: AppScope.of(context).settings.mainCurrencyCode,
          defaultAccountId: AppScope.of(context).settings.defaultAccountId,
          onRestoreAccount: (account) => unawaited(_restore(account)),
          onOpenOrder: () => unawaited(
            Navigator.of(context).pushNamed<void>(
              AppRoutes.accountsOrder,
              arguments: AccountsOrderRouteArguments(
                accounts: AppScope.of(context).accounts,
              ),
            ),
          ),
          onOpenJournal: () {
            final services = AppScope.of(context);
            unawaited(
              Navigator.of(context).pushNamed<void>(
                AppRoutes.balanceJournal,
                arguments: BalanceJournalRouteArguments(
                  accounts: services.accounts,
                  transfers: services.transfers,
                  idGenerator: services.idGenerator,
                  clock: services.clock,
                  settings: services.settings,
                  onShowTransactions: (id) {
                    BrowseScope.of(context).showAccountTransactions(id);
                    BrowseScope.selectedTabOf(context).value = historyTabIndex;
                  },
                ),
              ),
            );
          },
          onTransfer: () {
            final services = AppScope.of(context);
            unawaited(
              Navigator.of(context).pushNamed<void>(
                AppRoutes.transferForm,
                arguments: TransferFormRouteArguments(
                  accounts: services.accounts,
                  transfers: services.transfers,
                  idGenerator: services.idGenerator,
                  clock: services.clock,
                ),
              ),
            );
          },
          onOpenAccount: (account) {
            final services = AppScope.of(context);
            unawaited(
              Navigator.of(context).pushNamed<void>(
                AppRoutes.account,
                arguments: AccountRouteArguments(
                  accounts: services.accounts,
                  idGenerator: services.idGenerator,
                  accountId: account.id,
                  settings: services.settings,
                  transfers: services.transfers,
                  clock: services.clock,
                  onShowTransactions: (id) {
                    BrowseScope.of(context).showAccountTransactions(id);
                    BrowseScope.selectedTabOf(context).value = historyTabIndex;
                  },
                ),
              ),
            );
          },
          onAddAccount: () {
            final services = AppScope.of(context);
            unawaited(
              Navigator.of(context).pushNamed<void>(
                AppRoutes.accountForm,
                arguments: AccountFormRouteArguments(
                  accounts: services.accounts,
                  idGenerator: services.idGenerator,
                  currency: services.settings.mainCurrencyCode,
                  onCreated: (created) => adoptFirstAccountAsDefault(
                    created,
                    services.accounts,
                    services.settings,
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 24),
        RecurringSection(
          items: _recurring,
          today: today,
          onAdd: () => _openRecurringForm(today),
          onOpen: (payment) => _openRecurringForm(today, editing: payment),
        ),
      ],
    );
  }

  /// Форма платежа: новый (в основной валюте) или правка [editing] (в валюте
  /// самого платежа).
  void _openRecurringForm(DateOnly today, {RecurringPayment? editing}) {
    final services = AppScope.of(context);
    unawaited(
      Navigator.of(context).pushNamed<void>(
        AppRoutes.recurringForm,
        arguments: RecurringFormRouteArguments(
          currency: currencyInfoFor(
            editing?.amount.currency ?? services.settings.mainCurrencyCode,
          ),
          today: today,
          recurring: services.recurring,
          categories: services.categories,
          accounts: services.accounts,
          idGenerator: services.idGenerator,
          defaultAccountId: services.settings.defaultAccountId,
          editing: editing,
        ),
      ),
    );
  }
}
