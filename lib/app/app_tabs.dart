import 'package:flutter/material.dart';
import 'package:money_app/app/app_routes.dart';
import 'package:money_app/app/app_scope.dart';
import 'package:money_app/app/app_shell.dart';
import 'package:money_app/features/home/presentation/home_screen.dart';

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
class HomeTab extends StatelessWidget {
  const HomeTab({super.key});

  @override
  Widget build(BuildContext context) {
    // Сервисы берём здесь, под AppScope: открытый маршрут AppScope уже не видит.
    final services = AppScope.of(context);
    return HomeScreen(
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
