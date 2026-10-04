import 'package:flutter/material.dart';

/// Описание одной вкладки нижней панели: подпись, две иконки и содержимое.
@immutable
class AppTab {
  const AppTab({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.builder,
    this.actionsBuilder,
  });

  final String label;

  /// Иконка невыбранной вкладки.
  final IconData icon;

  /// Иконка выбранной вкладки (обычно закрашенный вариант).
  final IconData selectedIcon;

  /// Строит содержимое вкладки. Своего `Scaffold` внутри быть не должно:
  /// он один, в [AppShell].
  ///
  /// Строитель вызывается ОДИН раз, при первом открытии вкладки, и получает
  /// контекст каркаса; построенный виджет затем кэшируется. Поэтому данные из
  /// `AppScope`, `Theme`, `MediaQuery`, локали нужно читать в собственном
  /// `build` виджета вкладки, а не в замыкании строителя: иначе прочитанное
  /// «замрёт» и не обновится при смене темы, языка или сервисов.
  ///
  /// ```dart
  /// // Правильно: виджет сам читает AppScope в своём build.
  /// builder: (_) => const HomeTab(),
  /// // class HomeTab ... build(context) { AppScope.of(context)... }
  ///
  /// // Неправильно: значение прочитано один раз и «замёрзло».
  /// builder: (context) => HomeTab(services: AppScope.of(context)),
  /// ```
  final WidgetBuilder builder;

  /// Необязательная панель действий над нижней навигацией, пока вкладка
  /// выбрана (на «Главной» — кнопки «Доход» и «Расход»). Строится при каждой
  /// перерисовке каркаса, поэтому лучше возвращать маленький виджет, который
  /// сам читает всё нужное в своём `build`.
  final WidgetBuilder? actionsBuilder;
}

/// Каркас приложения: содержимое выбранной вкладки и нижняя панель навигации.
class AppShell extends StatefulWidget {
  // Конструктор не const: длину списка нельзя проверить на этапе компиляции.
  // Проверка явная (не assert), чтобы работала и в релизной сборке.
  AppShell({required this.tabs, super.key}) {
    if (tabs.length < 3 || tabs.length > 5) {
      throw ArgumentError.value(
        tabs.length,
        'tabs',
        'NavigationBar в Material поддерживает от 3 до 5 вкладок',
      );
    }
  }

  final List<AppTab> tabs;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;

  /// Уже построенное содержимое открытых вкладок по индексу. Ключи этой карты
  /// и есть «множество открытых вкладок»: индекса нет — вкладку ещё не
  /// показывали, и её строитель не вызывался. Один и тот же виджет отдаётся
  /// в [IndexedStack] при каждой перерисовке, поэтому строитель вызывается
  /// ровно один раз на вкладку, а состояние вкладки не теряется.
  final Map<int, Widget> _openedTabs = {};

  @override
  void didUpdateWidget(AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Тот же набор вкладок (даже в новом списке) кэш не сбрасывает. Другой
    // набор: старые индексы указывают уже на другие вкладки, кэш забываем.
    if (!_sameTabs(oldWidget.tabs, widget.tabs)) {
      _openedTabs.clear();
      if (_selectedIndex >= widget.tabs.length) {
        _selectedIndex = widget.tabs.length - 1;
      }
    }
  }

  static bool _sameTabs(List<AppTab> a, List<AppTab> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    // Выбранная вкладка строится при первом показе и дальше берётся из кэша.
    _openedTabs.putIfAbsent(
      _selectedIndex,
      () => widget.tabs[_selectedIndex].builder(context),
    );
    // «Назад» на Android: пока выбрана не «Главная», перехватываем его и
    // возвращаем на первую вкладку; на «Главной» пропускаем как обычно
    // (приложение уходит на задний план). Если поверх каркаса открыт другой
    // экран, «Назад» сначала закроет его: PopScope работает, только пока
    // каркас — верхний маршрут.
    return PopScope(
      canPop: _selectedIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        setState(() => _selectedIndex = 0);
      },
      child: _buildScaffold(),
    );
  }

  Widget _buildScaffold() {
    return Scaffold(
      // Верхней панели (AppBar) нет, поэтому без SafeArea содержимое уехало бы
      // под системную строку состояния. Низ не защищаем: этим занимается сама
      // NavigationBar.
      body: SafeArea(
        bottom: false,
        // IndexedStack держит в дереве все свои дочерние виджеты и показывает
        // один. Ещё не открытые вкладки — пустые заглушки, открытые — их
        // кэшированное содержимое (оно остаётся в дереве скрытым).
        child: IndexedStack(
          index: _selectedIndex,
          children: [
            for (var i = 0; i < widget.tabs.length; i++)
              _openedTabs[i] ?? const SizedBox.shrink(),
          ],
        ),
      ),
      // Панель действий вкладки (если есть) лежит в том же слоте, что и
      // навигация: SnackBar Flutter ставит над слотом целиком, то есть над
      // панелью действий, и сообщение её не закрывает.
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.tabs[_selectedIndex].actionsBuilder != null)
            widget.tabs[_selectedIndex].actionsBuilder!(context),
          NavigationBar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (index) {
              setState(() => _selectedIndex = index);
            },
            destinations: [
              for (final tab in widget.tabs)
                NavigationDestination(
                  icon: Icon(tab.icon),
                  selectedIcon: Icon(tab.selectedIcon),
                  label: tab.label,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
