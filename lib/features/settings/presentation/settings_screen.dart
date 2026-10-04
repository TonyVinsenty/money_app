import 'package:flutter/material.dart';
import 'package:money_app/features/settings/presentation/share_csv_file.dart';

/// Подписи вариантов темы.
const themeSystemLabel = 'Как в системе';
const themeLightLabel = 'Светлая';
const themeDarkLabel = 'Тёмная';

/// Заголовок раздела с выбором темы.
const themeSectionTitle = 'Тема';

/// Пункт, ведущий к управлению категориями.
const categoriesItemLabel = 'Категории';

/// Пункт, запускающий выгрузку всех операций в CSV-файл.
const exportCsvItemLabel = 'Экспорт в CSV';

/// Сообщение, если файл экспорта не получилось подготовить.
/// Новый текст: ждёт утверждения пользователя.
const exportCsvFailedMessage =
    'Не удалось подготовить файл экспорта. Файл не создан';

/// Экран (вкладка) «Настройки»: выбор темы, переход к категориям и экспорт CSV.
///
/// Экран не знает, где хранится тема, как устроена база и как отправляется файл:
/// приложение (`lib/app`) передаёт функции (ADR 0002). Отправка по умолчанию —
/// системное «Поделиться»; в тестах её подменяют.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.onOpenCategories,
    required this.onExportCsv,
    this.shareFile = shareCsvFile,
    super.key,
  });

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final VoidCallback onOpenCategories;

  /// Готовит файл экспорта и возвращает путь к нему. Бросает исключение,
  /// если подготовить не удалось.
  final Future<String> Function() onExportCsv;

  /// Отправляет готовый файл наружу.
  final ShareFile shareFile;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  /// Идёт выгрузка (или открыто «Поделиться»): второе нажатие не нужно.
  bool _exporting = false;

  Future<void> _exportCsv() async {
    setState(() => _exporting = true);
    try {
      final String path;
      try {
        path = await widget.onExportCsv();
      } on Exception {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text(exportCsvFailedMessage)));
        }
        return;
      }
      await widget.shareFile(path);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

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
          groupValue: widget.themeMode,
          onChanged: (value) {
            if (value != null) widget.onThemeModeChanged(value);
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
          onTap: widget.onOpenCategories,
        ),
        const Divider(),
        ListTile(
          title: const Text(exportCsvItemLabel),
          // Пока идёт выгрузка, вместо стрелки крутится индикатор, а пункт
          // недоступен: повторное нажатие не запустит вторую выгрузку.
          trailing: _exporting
              ? const SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const ExcludeSemantics(child: Icon(Icons.chevron_right)),
          enabled: !_exporting,
          onTap: _exporting ? null : _exportCsv,
        ),
      ],
    );
  }
}
