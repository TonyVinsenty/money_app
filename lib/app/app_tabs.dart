import 'package:flutter/material.dart';
import 'package:money_app/app/app_routes.dart';
import 'package:money_app/app/app_scope.dart';
import 'package:money_app/app/app_shell.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/clock.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/features/home/presentation/home_screen.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';
import 'package:money_app/features/transactions/domain/transactions_repository.dart';

/// Вкладки приложения в порядке слева направо. Пока внутри только заглушки.
/// Список неизменяемый: случайно добавить или убрать вкладку нельзя.
final List<AppTab> defaultAppTabs = List.unmodifiable(<AppTab>[
  AppTab(
    label: 'Главная',
    icon: Icons.home_outlined,
    selectedIcon: Icons.home,
    builder: (_) => const HomeTab(),
  ),
  AppTab(
    label: 'История',
    icon: Icons.receipt_long_outlined,
    selectedIcon: Icons.receipt_long,
    builder: (_) =>
        const TabPlaceholder('Здесь будет список доходов и расходов'),
  ),
  AppTab(
    label: 'Аналитика',
    icon: Icons.pie_chart_outline,
    selectedIcon: Icons.pie_chart,
    builder: (_) => const TabPlaceholder(
      'Здесь будут итоги по периодам и диаграмма по категориям',
    ),
  ),
  AppTab(
    label: 'Баланс',
    icon: Icons.account_balance_wallet_outlined,
    selectedIcon: Icons.account_balance_wallet,
    builder: (_) => const TabPlaceholder(
      'Здесь будут источники денег и регулярные платежи',
    ),
  ),
  AppTab(
    label: 'Настройки',
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings,
    builder: (_) => const TabPlaceholder(
      'Здесь будут тема, порядок категорий и другие настройки',
    ),
  ),
]);

/// Вкладка «Главная»: связывает экран фичи `home` с маршрутами приложения.
/// Сам `HomeScreen` маршрутов не знает: ему передаётся только функция.
///
/// Он же даёт экрану поток «расходы за текущий месяц» из репозитория.
class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  TransactionsRepository? _repository;
  Clock? _clock;
  late DateOnly _month;
  late Stream<Money> _monthExpenses;

  // Поток создаём один раз (и заново только при смене репозитория или часов):
  // если создавать его в build, каждая перерисовка начинала бы подписку заново
  // и итог мигал бы.
  //
  // Месяц берётся по часам в момент создания потока. Если приложение остаётся
  // открытым через полночь границы месяца, итог не переключится сам до
  // следующего пересоздания вкладки: полночь при открытом экране осознанно не
  // отслеживаем (редкий случай, усложнение не оправдано).
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = AppScope.of(context);
    if (!identical(services.transactions, _repository) ||
        !identical(services.clock, _clock)) {
      _repository = services.transactions;
      _clock = services.clock;
      _month = services.clock.today();
      _monthExpenses = services.transactions.watchTotal(
        type: TransactionType.expense,
        period: monthRange(_month),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Сервисы берём здесь, под AppScope: открытый маршрут AppScope уже не видит.
    final services = AppScope.of(context);
    return HomeScreen(
      monthExpenses: _monthExpenses,
      month: _month,
      onAddTransaction: (type) => Navigator.of(context).pushNamed(
        AppRoutes.quickAdd,
        arguments: QuickAddRouteArguments(
          type: type,
          clock: services.clock,
          categories: services.categories,
          transactions: services.transactions,
          idGenerator: services.idGenerator,
        ),
      ),
    );
  }
}

/// Заглушка вкладки: текст по центру.
class TabPlaceholder extends StatelessWidget {
  const TabPlaceholder(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(text, textAlign: TextAlign.center),
      ),
    );
  }
}
