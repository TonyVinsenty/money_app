import 'dart:async';

import 'package:flutter/material.dart';
import 'package:money_app/app/app_routes.dart';
import 'package:money_app/app/app_scope.dart';
import 'package:money_app/core/money/currency.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/accounts/domain/accounts_repository.dart';
import 'package:money_app/features/accounts/presentation/accounts_section.dart';

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
      _balances = repository.watchBalances(currency: rubCurrencyCode);
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
          currency: rubCurrencyCode,
          onOpenAccount: (account) {
            final services = AppScope.of(context);
            unawaited(
              Navigator.of(context).pushNamed<void>(
                AppRoutes.account,
                arguments: AccountRouteArguments(
                  accounts: services.accounts,
                  idGenerator: services.idGenerator,
                  accountId: account.id,
                  currency: rubCurrencyCode,
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
                  currency: rubCurrencyCode,
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
