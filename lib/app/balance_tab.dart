import 'dart:async';

import 'package:flutter/material.dart';
import 'package:money_app/app/app_routes.dart';
import 'package:money_app/app/app_scope.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/accounts/domain/accounts_repository.dart';
import 'package:money_app/features/accounts/domain/default_account.dart';
import 'package:money_app/features/accounts/presentation/accounts_section.dart';
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
  final others = all.where((a) => a.id != created.id);
  final current = resolveDefaultAccount(
    others,
    settings.defaultAccountId,
    settings.mainCurrencyCode,
  );
  if (current == null) await settings.setDefaultAccountId(created.id);
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
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        AccountsSection(
          accounts: _accounts,
          balances: _balances,
          mainCurrency: AppScope.of(context).settings.mainCurrencyCode,
          defaultAccountId: AppScope.of(context).settings.defaultAccountId,
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
      ],
    );
  }
}
