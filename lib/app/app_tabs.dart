import 'package:flutter/material.dart';
import 'package:money_app/app/app_routes.dart';
import 'package:money_app/app/app_scope.dart';
import 'package:money_app/app/app_shell.dart';
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
  Clock? _clock;
  late DateOnly _month;
  late Stream<Money> _monthExpenses;
  late Stream<Money> _monthIncome;
  late Stream<List<Transaction>> _monthTransactions;
  CategoriesRepository? _categoriesRepository;
  late Stream<List<Category>> _categories;

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
      _monthIncome = services.transactions.watchTotal(
        type: TransactionType.income,
        period: monthRange(_month),
      );
      _monthTransactions = services.transactions.watchInPeriod(
        monthRange(_month),
      );
    }
    if (!identical(services.categories, _categoriesRepository)) {
      _categoriesRepository = services.categories;
      _categories = services.categories.watchAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    return HomeScreen(
      monthExpenses: _monthExpenses,
      monthIncome: _monthIncome,
      monthTransactions: _monthTransactions,
      categories: _categories,
      month: _month,
      // Потоки месяца и категорий общие с экраном категории: drift отдаёт их
      // нескольким слушателям, новые запросы не создаются.
      onOpenCategory: (category) => Navigator.of(context).pushNamed(
        AppRoutes.analyticsCategory,
        arguments: CategoryBreakdownRouteArguments(
          category: category,
          period: currentPeriod(PeriodKind.month, _month),
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

/// Сколько последних операций показывает «История». Постраничной подгрузки
/// пока нет, поэтому предел большой: список строится лениво (по мере
/// прокрутки), и 500 строк ему не тяжелы.
const int historyLimit = 500;

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
  late DateOnly _today;
  late Stream<List<Transaction>> _transactions;
  late Stream<List<Category>> _categories;

  // Потоки создаём один раз (и заново только при смене сервисов): в build
  // каждая перерисовка начинала бы подписку заново, и список мигал бы.
  //
  // «Сегодня» берётся по часам в момент создания. Если приложение открыто через
  // полночь, заголовки «Сегодня»/«Вчера» обновятся, только когда вкладка
  // пересоздастся (как и месяц на «Главной»): редкий случай, не усложняем.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = AppScope.of(context);
    if (!identical(services.transactions, _transactionsRepository) ||
        !identical(services.categories, _categoriesRepository) ||
        !identical(services.clock, _clock)) {
      _transactionsRepository = services.transactions;
      _categoriesRepository = services.categories;
      _clock = services.clock;
      _today = services.clock.today();
      _transactions = services.transactions.watchRecent(limit: historyLimit);
      _categories = services.categories.watchAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Сервисы берём здесь, под AppScope: открытый маршрут AppScope не видит.
    final services = AppScope.of(context);
    return HistoryScreen(
      transactions: _transactions,
      categories: _categories,
      today: _today,
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
