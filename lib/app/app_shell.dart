import 'package:flutter/material.dart';

/// Описание одной вкладки нижней панели: подпись, две иконки и содержимое.
@immutable
class AppTab {
  const AppTab({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.builder,
  });

  final String label;

  /// Иконка невыбранной вкладки.
  final IconData icon;

  /// Иконка выбранной вкладки (обычно закрашенный вариант).
  final IconData selectedIcon;

  /// Строит содержимое вкладки. Своего `Scaffold` внутри быть не должно:
  /// он один, в [AppShell].
  final WidgetBuilder builder;
}

/// Каркас приложения: содержимое выбранной вкладки и нижняя панель навигации.
class AppShell extends StatefulWidget {
  // Конструктор не const: длину списка нельзя проверить на этапе компиляции,
  // поэтому assert стоит в теле конструктора.
  AppShell({required this.tabs, super.key}) {
    assert(
      tabs.length >= 3 && tabs.length <= 5,
      'NavigationBar в Material поддерживает от 3 до 5 вкладок',
    );
  }

  final List<AppTab> tabs;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Верхней панели (AppBar) нет, поэтому без SafeArea содержимое уехало бы
      // под системную строку состояния. Низ не защищаем: этим занимается сама
      // NavigationBar.
      body: SafeArea(
        bottom: false,
        // IndexedStack держит в дереве все вкладки сразу и показывает одну.
        child: IndexedStack(
          index: _selectedIndex,
          children: [for (final tab in widget.tabs) tab.builder(context)],
        ),
      ),
      bottomNavigationBar: NavigationBar(
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
    );
  }
}
