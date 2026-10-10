import 'dart:io';

import 'package:flutter/material.dart';
import 'package:money_app/app/app_routes.dart';
import 'package:money_app/app/app_scope.dart';
import 'package:money_app/app/app_services.dart';
import 'package:money_app/app/app_shell.dart';
import 'package:money_app/app/app_tab_indices.dart';
import 'package:money_app/app/balance_tab.dart';
import 'package:money_app/app/browse_scope.dart';
import 'package:money_app/app/home_balance_stream.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/core/ui/transaction_rule_text.dart';
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/accounts/domain/accounts_repository.dart';
import 'package:money_app/features/analytics/domain/analytics_period.dart';
import 'package:money_app/features/analytics/presentation/analytics_controller.dart';
import 'package:money_app/features/analytics/presentation/analytics_screen.dart';
import 'package:money_app/features/categories/domain/categories_repository.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/csv_import/domain/csv_import_result.dart';
import 'package:money_app/features/csv_import/presentation/pick_csv_file.dart';
import 'package:money_app/features/export/data/transactions_exporter.dart';
import 'package:money_app/features/home/presentation/home_action_bar.dart';
import 'package:money_app/features/home/presentation/home_screen.dart';
import 'package:money_app/features/recurring/presentation/due_banner.dart';
import 'package:money_app/features/recurring/presentation/due_tab_badge.dart';
import 'package:money_app/features/settings/domain/home_balance_line.dart';
import 'package:money_app/features/settings/presentation/settings_screen.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';
import 'package:money_app/features/transactions/domain/transactions_repository.dart';
import 'package:money_app/features/transactions/presentation/history/history_screen.dart';

export 'package:money_app/app/app_tab_indices.dart';

/// Вкладки приложения в порядке слева направо. Часть вкладок пока заглушки.
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
    builder: (_) => const AnalyticsTab(),
  ),
  AppTab(
    label: 'Баланс',
    icon: Icons.account_balance_wallet_outlined,
    selectedIcon: Icons.account_balance_wallet,
    builder: (_) => const BalanceTab(),
    decorateIcon: (context, icon) =>
        DueTabBadge(dues: BrowseScope.duesOf(context), icon: icon),
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
  const SettingsTab({this.pickFile = pickCsvFile, super.key});

  /// Окно выбора файла для загрузки из CSV; в тестах — фейк.
  final PickFile pickFile;

  /// Выбор файла → экран «Загрузка из CSV» → итог загрузки или `null`.
  /// Копия файла удаляется после закрытия экрана.
  Future<CsvImportResult?> _importCsv(
    BuildContext context,
    AppServices services,
  ) async {
    final navigator = Navigator.of(context);
    final path = await pickFile();
    if (path == null) return null;
    try {
      return await navigator.pushNamed<CsvImportResult>(
        AppRoutes.csvImport,
        arguments: CsvImportRouteArguments(
          path: path,
          clock: services.clock,
          store: services.csvImport,
          categories: services.categories.watchAll(),
        ),
      );
    } finally {
      // Синхронно: асинхронный ввод-вывод в widget-тестах не завершается.
      try {
        File(path).deleteSync();
      } on FileSystemException {
        // Копии уже нет — удалять нечего.
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // AppScope.of подписывает вкладку на настройки: выбранная тема в списке
    // обновляется сразу после нажатия.
    final services = AppScope.of(context);
    final settings = services.settings;
    return SettingsScreen(
      themeMode: settings.themeMode,
      onThemeModeChanged: settings.setThemeMode,
      homeBalanceLine: settings.homeBalanceLine,
      onHomeBalanceLineChanged: settings.setHomeBalanceLine,
      mainCurrency: settings.mainCurrency,
      onMainCurrencyChanged: (currency) async {
        final messenger = ScaffoldMessenger.of(context);
        final saved = await settings.setMainCurrency(currency);
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                saved
                    ? 'Основная валюта: ${currency.name}'
                    : transactionSaveFailedText,
              ),
            ),
          );
      },
      lastExportDay: settings.lastExportDay,
      today: services.clock.today(),
      onExportShared: () => settings.setLastExportDay(services.clock.today()),
      // Экспортёр собирает файл из репозиториев; создаём его здесь, под
      // AppScope, и только при нажатии.
      onExportCsv: () => TransactionsExporter(
        transactions: services.transactions,
        categories: services.categories,
        accounts: services.accounts,
        transfers: services.transfers,
        clock: services.clock,
      ).exportToTempFile(),
      onImportCsv: () => _importCsv(context, services),
      onClearAll: () async {
        final browse = BrowseScope.controllerOf(context);
        await services.dataEraser.eraseAll();
        browse.updateToday(services.clock.today());
        browse.resetAfterEraseAll();
      },
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
  String? _currency;
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
    // Основная валюта из настроек: при её смене потоки создаются заново.
    final currency = services.settings.mainCurrencyCode;
    if (!identical(services.transactions, _repository) ||
        month != _month ||
        currency != _currency) {
      _repository = services.transactions;
      _month = month;
      _currency = currency;
      _monthExpenses = services.transactions.watchTotal(
        type: TransactionType.expense,
        period: month,
        currency: currency,
      );
      _monthIncome = services.transactions.watchTotal(
        type: TransactionType.income,
        period: month,
        currency: currency,
      );
      _monthTransactions = services.transactions.watchInPeriod(
        month,
        currency: currency,
      );
    }
    if (!identical(services.categories, _categoriesRepository)) {
      _categoriesRepository = services.categories;
      _categories = services.categories.watchAll();
    }
    // Строка «Баланс» не зависит от месяца: поток новый только при смене
    // настройки, основной валюты или репозиториев.
    final line = services.settings.homeBalanceLine;
    if (line != _balanceLine ||
        currency != _balanceCurrency ||
        !identical(services.transactions, _balanceTransactions) ||
        !identical(services.accounts, _balanceAccounts)) {
      _balanceLine = line;
      _balanceCurrency = currency;
      _balanceTransactions = services.transactions;
      _balanceAccounts = services.accounts;
      _balance = watchHomeBalance(
        line: line,
        currency: currency,
        transactions: services.transactions,
        accounts: services.accounts,
      );
    }
  }

  HomeBalanceLine? _balanceLine;
  String? _balanceCurrency;
  TransactionsRepository? _balanceTransactions;
  AccountsRepository? _balanceAccounts;
  late Stream<Money?> _balance;

  @override
  Widget build(BuildContext context) {
    final browse = BrowseScope.of(context);
    final month = _month!;
    return HomeScreen(
      balanceLine: _balance,
      monthExpenses: _monthExpenses,
      monthIncome: _monthIncome,
      monthTransactions: _monthTransactions,
      categories: _categories,
      month: month.start,
      isCurrentMonth: month == monthRange(browse.today),
      currency: _currency!,
      onPreviousMonth: browse.canGoBack ? browse.previousMonth : null,
      onNextMonth: browse.canGoForward ? browse.nextMonth : null,
      // Месяц и порядок «Истории» не меняются; новый экран не открывается.
      onOpenCategory: (ids) {
        browse.showCategoryExpenses(ids);
        BrowseScope.selectedTabOf(context).value = historyTabIndex;
      },
      banner: DueBanner(
        dues: BrowseScope.duesOf(context),
        onTap: () => BrowseScope.selectedTabOf(context).value = balanceTabIndex,
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
    final browse = BrowseScope.of(context);
    return HomeActionBar(
      onAddTransaction: (type) => Navigator.of(context).pushNamed(
        AppRoutes.quickAdd,
        arguments: QuickAddRouteArguments(
          type: type,
          clock: services.clock,
          categories: services.categories,
          transactions: services.transactions,
          idGenerator: services.idGenerator,
          currency: services.settings.mainCurrency,
          accounts: services.accounts.watchAll(),
          defaultAccountId: services.settings.defaultAccountId,
          // Общий месяц переключается на месяц новой операции.
          onSaved: (day) {
            // Приложение могло пережить полночь: сначала свежее «сегодня».
            browse.updateToday(services.clock.today());
            browse.showMonthOf(day);
          },
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
  String? _currency;
  CategoriesRepository? _categoriesRepository;
  DateRange? _month;
  bool _searching = false;
  late Stream<List<Transaction>> _transactions;
  late Stream<List<Category>> _categories;
  late Stream<bool> _hasOther;

  // Потоки создаём один раз (и заново только при смене сервисов, выбранного
  // месяца или при начале и конце поиска): в build каждая перерисовка
  // начинала бы подписку заново, и список мигал бы. didChangeDependencies
  // вызывается и при смене фильтра или каждой буквы поиска (BrowseScope
  // уведомляет обо всём), но поток тогда остаётся прежним.
  //
  // «Сегодня» берётся из BrowseController (обновляется при возврате в приложение).
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = AppScope.of(context);
    final browse = BrowseScope.of(context);
    final month = browse.month;
    final searching = browse.isSearchingHistory;
    // Основная валюта из настроек: только её операции; при смене поток новый.
    final currency = services.settings.mainCurrencyCode;
    final repositoriesChanged =
        !identical(services.transactions, _transactionsRepository) ||
        !identical(services.categories, _categoriesRepository);
    // Во время поиска смена месяца поток не трогает: он и так за все месяцы.
    final sourceChanged =
        searching != _searching ||
        currency != _currency ||
        (!searching && month != _month);
    if (repositoriesChanged || currency != _currency) {
      _hasOther = services.transactions.watchHasOtherCurrency(currency);
    }
    _month = month;
    if (repositoriesChanged || sourceChanged) {
      _transactionsRepository = services.transactions;
      _categoriesRepository = services.categories;
      _searching = searching;
      _currency = currency;
      // Фильтр, порядок и сам запрос применяет экран: поток от них не зависит.
      _transactions = searching
          ? services.transactions.watchAll(currency: currency)
          : services.transactions.watchInPeriod(month, currency: currency);
    }
    if (repositoriesChanged) _categories = services.categories.watchAll();
    if (!identical(services.accounts, _accountsRepository)) {
      _accountsRepository = services.accounts;
      _accounts = services.accounts.watchAll();
    }
  }

  AccountsRepository? _accountsRepository;
  late Stream<List<Account>> _accounts;

  @override
  Widget build(BuildContext context) {
    // Сервисы берём здесь, под AppScope: открытый маршрут AppScope не видит.
    final services = AppScope.of(context);
    final browse = BrowseScope.of(context);
    return HistoryScreen(
      transactions: _transactions,
      categories: _categories,
      today: browse.today,
      month: _month!.start,
      hasAnyTransactions: browse.firstDayKnown ? browse.firstDay != null : null,
      filter: browse.historyFilter,
      sort: browse.historySort,
      onResetFilter: browse.resetHistoryFilter,
      onSortChanged: browse.setHistorySort,
      onFilterChanged: browse.setHistoryFilter,
      searchQuery: browse.historySearch,
      onSearchChanged: browse.setHistorySearch,
      onPreviousMonth: browse.canGoBack ? browse.previousMonth : null,
      onNextMonth: browse.canGoForward ? browse.nextMonth : null,
      hasOtherCurrencies: _hasOther,
      accounts: _accounts,
      currencySymbol: services.settings.mainCurrency.symbol,
      currencyCode: services.settings.mainCurrencyCode,
      onTransactionTap: (transaction) => Navigator.of(context).pushNamed(
        AppRoutes.editTransaction,
        arguments: EditTransactionRouteArguments(
          transaction: transaction,
          clock: services.clock,
          categories: services.categories,
          transactions: services.transactions,
          accounts: services.accounts.watchAll(),
          // Перенос в другой месяц: «История» идёт за операцией.
          onSaved: (day) {
            browse.updateToday(services.clock.today());
            browse.showMonthOf(day);
          },
        ),
      ),
    );
  }
}

/// Вкладка «Аналитика»: держит выбранный период ([AnalyticsController]) и
/// связывает его с экраном. «Сегодня» и день первой операции берёт у общего
/// [BrowseScope]. Вкладки лежат в IndexedStack, поэтому период сохраняется
/// при переходах между вкладками.
class AnalyticsTab extends StatefulWidget {
  const AnalyticsTab({super.key});

  @override
  State<AnalyticsTab> createState() => _AnalyticsTabState();
}

class _AnalyticsTabState extends State<AnalyticsTab> {
  String? _currency;
  String? _streamCurrency;
  AnalyticsController? _controller;
  int _generation = 0;
  TransactionsRepository? _transactionsRepository;
  CategoriesRepository? _categoriesRepository;
  late Stream<PeriodTransactions> _transactions;
  late Stream<bool> _hasOther;
  late Stream<List<Category>> _categories;
  AnalyticsPeriod? _streamPeriod;
  TransactionsRepository? _streamRepository;

  // Потоки создаём один раз и заново только при смене периода или сервисов:
  // в build каждая перерисовка начинала бы подписку заново. Слушатель
  // контроллера добавлен раньше, чем ListenableBuilder, поэтому к моменту
  // перерисовки поток уже новый.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = AppScope.of(context);
    final browse = BrowseScope.of(context);
    final servicesChanged =
        !identical(services.transactions, _transactionsRepository) ||
        services.settings.mainCurrencyCode != _currency;
    if (servicesChanged) {
      _hasOther = services.transactions.watchHasOtherCurrency(
        services.settings.mainCurrencyCode,
      );
    }
    _currency = services.settings.mainCurrencyCode;
    _transactionsRepository = services.transactions;
    if (!identical(services.categories, _categoriesRepository)) {
      _categoriesRepository = services.categories;
      _categories = services.categories.watchAll();
    }
    // «Очистить всё»: период и выбор вида — как при запуске.
    if (_controller != null && browse.eraseGeneration != _generation) {
      _controller!.dispose();
      _controller = null;
      _streamPeriod = null;
    }
    _generation = browse.eraseGeneration;
    final controller = _controller;
    if (controller == null) {
      _controller = AnalyticsController(
        today: browse.today,
        firstDay: browse.firstDay,
        firstDayKnown: browse.firstDayKnown,
      )..addListener(_refreshTransactions);
      _refreshTransactions();
    } else {
      controller.updateToday(browse.today);
      controller.updateFirstDay(browse.firstDay, known: browse.firstDayKnown);
      if (servicesChanged) _refreshTransactions();
    }
  }

  void _refreshTransactions() {
    final period = _controller!.period;
    final repository = _transactionsRepository!;
    final currency = _currency!;
    if (period == _streamPeriod &&
        identical(repository, _streamRepository) &&
        currency == _streamCurrency) {
      return;
    }
    _streamPeriod = period;
    _streamRepository = repository;
    _streamCurrency = currency;
    final range = period.range;
    _transactions = repository
        .watchInPeriod(range, currency: currency)
        .map((list) => (range: range, transactions: list));
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller!;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => AnalyticsScreen(
        period: controller.period,
        today: controller.today,
        transactions: _transactions,
        categories: _categories,
        onKindSelected: controller.selectKind,
        onPrevious: controller.canGoBack ? controller.previous : null,
        onNext: controller.canGoForward ? controller.next : null,
        onOpenCategory: (category) => _openCategory(context, category),
        firstDay: controller.firstDay,
        firstDayKnown: controller.firstDayKnown,
        type: controller.type,
        onTypeSelected: controller.selectType,
        onCustomRangeSelected: controller.selectCustomRange,
        currency: _currency!,
        hasOtherCurrencies: _hasOther,
        currencySymbol: AppScope.of(context).settings.mainCurrency.symbol,
      ),
    );
  }

  // Экран категории получает выбранный период и свои потоки: они создаются при
  // нажатии, а не в build, и не зависят от потока вкладки (тот уже слушается).
  void _openCategory(BuildContext context, Category category) {
    final services = AppScope.of(context);
    final controller = _controller!;
    Navigator.of(context).pushNamed(
      AppRoutes.analyticsCategory,
      arguments: CategoryBreakdownRouteArguments(
        category: category,
        period: controller.period,
        today: controller.today,
        transactions: services.transactions.watchInPeriod(
          controller.period.range,
          currency: services.settings.mainCurrencyCode,
        ),
        categories: services.categories.watchAll(),
        currency: services.settings.mainCurrencyCode,
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
