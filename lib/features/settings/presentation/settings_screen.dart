import 'package:flutter/material.dart';

/// Подписи вариантов темы.
const themeSystemLabel = 'Как в системе';
const themeLightLabel = 'Светлая';
const themeDarkLabel = 'Тёмная';

/// Заголовок раздела с выбором темы.
const themeSectionTitle = 'Тема';

/// Пункт, ведущий к управлению категориями.
const categoriesItemLabel = 'Категории';

/// Экран (вкладка) «Настройки»: выбор темы и переход к категориям.
///
/// Экран не знает, где хранится тема и куда ведёт «Категории»: приложение
/// (`lib/app`) передаёт текущее значение и функции (ADR 0002).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.onOpenCategories,
    super.key,
  });

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final VoidCallback onOpenCategories;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Semantics(
            header: true,
            child: Text(themeSectionTitle, style: textTheme.titleMedium),
          ),
        ),
        // RadioGroup держит выбранное значение для всех переключателей внутри.
        RadioGroup<ThemeMode>(
          groupValue: themeMode,
          onChanged: (value) {
            if (value != null) onThemeModeChanged(value);
          },
          child: const Column(
            children: [
              RadioListTile<ThemeMode>(
                value: ThemeMode.system,
                title: Text(themeSystemLabel),
              ),
              RadioListTile<ThemeMode>(
                value: ThemeMode.light,
                title: Text(themeLightLabel),
              ),
              RadioListTile<ThemeMode>(
                value: ThemeMode.dark,
                title: Text(themeDarkLabel),
              ),
            ],
          ),
        ),
        const Divider(),
        ListTile(
          title: const Text(categoriesItemLabel),
          trailing: const ExcludeSemantics(child: Icon(Icons.chevron_right)),
          onTap: onOpenCategories,
        ),
      ],
    );
  }
}
