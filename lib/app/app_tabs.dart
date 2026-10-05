import 'package:flutter/material.dart';
import 'package:money_app/app/app_routes.dart';
import 'package:money_app/app/app_scope.dart';
import 'package:money_app/app/app_shell.dart';
import 'package:money_app/app/browse_scope.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/clock.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/features/analytics/domain/analytics_period.dart';
import 'package:money_app/features/categories/domain/categories_repository.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/export/data/transactions_exporter.dart';
import 'package:money_app/features/home/presentation/home_action_bar.dart';
import 'package:money_app/features/home/presentation/home_screen.dart';
import 'package:money_app/features/settings/presentation/settings_screen.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';
import 'package:money_app/features/transactions/domain/transactions_repository.dart';
import 'package:money_app/features/transactions/presentation/history/history_screen.dart';

/// Номер вкладки «История» в [defaultAppTabs].
const historyTabIndex = 1;

/// Вкладки приложения в порядке слева направо. Пока внутри только заглушки.
/// Список неизменяемый: случайно добавить или убрать вкладку нельзя.
final List<AppTab> defaultAppTabs = List.unmodifiable(<AppTab>[
  AppTab(
    label: 'Главная',
    icon: Icons.home_outlined,
    selectedIcon: Icons.home,
    builder: (_) => const HomeTab(),
    actionsBuilder: (_) => const HomeActions(),
  ),
  AppTab(
    label: 'История',
    icon: Icons.receipt_long_outlined,
    selectedIcon: Icons.receipt_long,
    builder: (_) => const HistoryTab(),
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
    builder: (_) => const SettingsTab(),
  ),
]);

/// Вкладка «Настройки»: связывает экран фичи `settings` с настройками
/// приложения и маршрутами. Сам `SettingsScreen` их не знает (ADR 0002).
class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    // AppScope.of подписывает вкладку на настройки: выбранная тема в списке
    // обновляется сразу после нажатия.
    final services = AppScope.of(context);
    final settings = services.settings;
    return SettingsScreen(
      themeMode: settings.themeMode,
      onThemeModeChanged: settings.setThemeMode,
      // Экспортёр собирает файл из репозиториев; создаём его здесь, под
      // AppScope, и только при нажатии.
      onExportCsv: () => TransactionsExporter(
        transactions: services.transactions,
        categories: services.categories,
        clock: services.clock,
      ).exportToTempFile(),
      // Репозиторий берём здесь, под AppScope: открытый маршрут его не видит.
      onOpenCategories: () => Navigator.of(context).pushNamed(
        AppRoutes.categories,
        arguments: CategoriesRouteArguments(
          categories: services.categories,
          idGenerator: services.idGenerator,
        ),
      ),
    );
  }
}

/// Вкладка «Главная»: связывает экран фичи `home` с маршрутами приложения.
/// Сам `HomeScreen` маршрутов не знает: ему передаётся только функция.
///
/// Он же даёт экрану потоки «расходы» и «доходы за текущий месяц» из
/// репозитория.
class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  TransactionsRepository? _repository;
  DateRange? _month;
  late Stream<Money> _monthExpenses;
  late Stream<Money> _monthIncome;
  late Stream<List<Transaction>> _monthTransactions;
  CategoriesRepository? _categoriesRepository;
  late Stream<List<Category>> _categories;

  // Потоки создаём один раз (и заново только при смене репозитория или
  // выбранного месяца): если создавать их в build, каждая перерисовка начинала
  // бы подписку заново и итог мигал бы. didChangeDependencies вызывается и при
  // смене фильтра «Истории» (BrowseScope уведомляет обо всём), но месяц тогда
  // тот же, и потоки остаются прежними.
  //
  // Месяц выбирает BrowseController, «сегодня» он берёт из часов один раз при
  // создании: полночь при открытом экране осознанно не отслеживаем.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = AppScope.of(context);
    final month = BrowseScope.of(context).month;
    if (!identical(services.transactions, _repository) || month != _month) {
      _repository = services.transactions;
      _month = month;
      _monthExpenses = services.transactions.watchTotal(
        type: TransactionType.expense,
        period: month,
      );
      _monthIncome = services.transactions.watchTotal(
        type: TransactionType.income,
        period: month,
      );
      _monthTransactions = services.transactions.watchInPeriod(month);
    }
    if (!identical(services.categories, _categoriesRepository)) {
      _categoriesRepository = services.categories;
      _categories = services.categories.watchAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    final browse = BrowseScope.of(context);
    final month = _month!;
    return HomeScreen(
      monthExpenses: _monthExpenses,
      monthIncome: _monthIncome,
      monthTransactions: _monthTransactions,
      categories: _categories,
      month: month.start,
      isCurrentMonth: month == monthRange(browse.today),
      onPreviousMonth: browse.canGoBack ? browse.previousMonth : null,
      onNextMonth: browse.canGoForward ? browse.nextMonth : null,
      // Потоки месяца и категорий общие с экраном категории: drift отдаёт их
      // нескольким слушателям, новые запросы не создаются.
      onOpenCategory: (category) => Navigator.of(context).pushNamed(
        AppRoutes.analyticsCategory,
        arguments: CategoryBreakdownRouteArguments(
          category: category,
          period: AnalyticsPeriod(PeriodKind.month, month),
          transactions: _monthTransactions,
          categories: _categories,
        ),
      ),
    );
  }
}

/// Кнопки «Доход» и «Расход» «Главной»: каркас ставит их над нижней навигацией
/// (см. AppTab.actionsBuilder), чтобы SnackBar не закрывал их. Связывает
/// панель фичи home с маршрутом быстрого ввода.
class HomeActions extends StatelessWidget {
  const HomeActions({super.key});

  @override
  Widget build(BuildContext context) {
    // Сервисы берём здесь, под AppScope: открытый маршрут AppScope не видит.
    final services = AppScope.of(context);
    return HomeActionBar(
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

/// Вкладка «История»: даёт экрану фичи `transactions` потоки из репозиториев.
/// Сам `HistoryScreen` репозиториев не знает (ADR 0002).
class HistoryTab extends StatefulWidget {
  const HistoryTab({super.key});

  @override
  State<HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<HistoryTab> {
  TransactionsRepository? _transactionsRepository;
  CategoriesRepository? _categoriesRepository;
  Clock? _clock;
  DateRange? _month;
  late DateOnly _today;
  late Stream<List<Transaction>> _transactions;
  late Stream<List<Category>> _categories;

  // Потоки создаём один раз (и заново только при смене сервисов или выбранного
  // месяца): в build каждая перерисовка начинала бы подписку заново, и список
  // мигал бы. didChangeDependencies вызывается и при смене фильтра (BrowseScope
  // уведомляет обо всём), но месяц тогда тот же, и поток остаётся прежним.
  //
  // «Сегодня» берётся по часам в момент создания. Если приложение открыто через
  // полночь, заголовки «Сегодня»/«Вчера» обновятся, только когда вкладка
  // пересоздастся (как и месяц на «Главной»): редкий случай, не усложняем.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = AppScope.of(context);
    final month = BrowseScope.of(context).month;
    if (!identical(services.transactions, _transactionsRepository) ||
        !identical(services.categories, _categoriesRepository) ||
        !identical(services.clock, _clock) ||
        month != _month) {
      _transactionsRepository = services.transactions;
      _categoriesRepository = services.categories;
      _clock = services.clock;
      _month = month;
      _today = services.clock.today();
      // Фильтр и порядок применяет сам экран: поток от них не зависит.
      _transactions = services.transactions.watchInPeriod(month);
      _categories = services.categories.watchAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Сервисы берём здесь, под AppScope: открытый маршрут AppScope не видит.
    final services = AppScope.of(context);
    final browse = BrowseScope.of(context);
    return HistoryScreen(
      transactions: _transactions,
      categories: _categories,
      today: _today,
      month: _month!.start,
      hasAnyTransactions: browse.firstDay != null,
      filter: browse.historyFilter,
      sort: browse.historySort,
      onResetFilter: browse.resetHistoryFilter,
      onSortChanged: browse.setHistorySort,
      onFilterChanged: browse.setHistoryFilter,
      onPreviousMonth: browse.canGoBack ? browse.previousMonth : null,
      onNextMonth: browse.canGoForward ? browse.nextMonth : null,
      onTransactionTap: (transaction) => Navigator.of(context).pushNamed(
        AppRoutes.editTransaction,
        arguments: EditTransactionRouteArguments(
          transaction: transaction,
          clock: services.clock,
          categories: services.categories,
          transactions: services.transactions,
        ),
      ),
    );
  }
}

/// Подпись над текстом заглушки: приложение пока не показывают другим людям,
/// но незаконченная вкладка должна честно так и называться.
const tabInDevelopmentLabel = 'В разработке';

/// Заглушка вкладки: «В разработке» и пояснение по центру.
class TabPlaceholder extends StatelessWidget {
  const TabPlaceholder(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tabInDevelopmentLabel,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(text, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
