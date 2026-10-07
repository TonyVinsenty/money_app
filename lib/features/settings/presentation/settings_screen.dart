import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:money_app/core/format/date_format.dart';
import 'package:money_app/core/format/percent_format.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/ui/tap_to_dismiss_snack_content.dart';
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
const exportCsvFailedMessage =
    'Не удалось подготовить файл экспорта. Файл не создан';

/// Сообщение, если системное окно «Поделиться» открыть не удалось.
const shareFailedMessage =
    'Не удалось открыть окно «Поделиться». Файл не отправлен';

/// Подпись индикатора для скринридера, пока готовится файл.
const exportPreparingLabel = 'Готовим файл';

/// Пункт, открывающий выбор файла для загрузки операций, и подпись под ним.
const importCsvItemLabel = 'Загрузить из CSV';
const importCsvItemSubtitle = 'Добавить операции из файла';

/// Сообщение, если окно выбора файла не открылось или файл не скопировался.
const importOpenFailedMessage = 'Не удалось открыть файл. Попробуйте ещё раз';

/// Итог загрузки: «Загружена 1 операция», «Загружены 3 операции»,
/// «Загружено 1 234 операции».
String importDoneMessage(int count) {
  final verb = pluralRu(count, 'Загружена', 'Загружены', 'Загружено');
  final noun = pluralRu(count, 'операция', 'операции', 'операций');
  return '$verb ${_countFormat.format(count)} $noun';
}

final NumberFormat _countFormat = NumberFormat.decimalPattern('ru');

/// Подпись под пунктом экспорта. Без года, если выгрузка в текущем году
/// (год берётся из [today]); если выгрузки не было — «ещё не было».
String lastExportLabel(DateOnly? day, DateOnly today) {
  if (day == null) return 'Последний экспорт: ещё не было';
  final text = day.year == today.year ? formatDayMonth(day) : formatDate(day);
  return 'Последний экспорт: $text';
}

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
    required this.lastExportDay,
    required this.today,
    required this.onExportShared,
    required this.onImportCsv,
    this.shareFile = shareCsvFile,
    super.key,
  });

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final VoidCallback onOpenCategories;

  /// Готовит файл экспорта и возвращает путь к нему. Бросает исключение,
  /// если подготовить не удалось.
  final Future<String> Function() onExportCsv;

  /// День последней выгрузки; `null` — ещё не было.
  final DateOnly? lastExportDay;

  /// Сегодняшний день: по нему решаем, показывать ли год.
  final DateOnly today;

  /// Вызывается после того, как окно «Поделиться» открылось без ошибки.
  final VoidCallback onExportShared;

  /// Отправляет готовый файл наружу.
  final ShareFile shareFile;

  /// Выбор файла и загрузка из него. Возвращает число добавленных операций
  /// или `null`, если ничего не загружено (отмена). Бросает исключение, если
  /// файл не удалось открыть.
  final Future<int?> Function() onImportCsv;

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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: TapToDismissSnackContent(
                child: Text(exportCsvFailedMessage),
              ),
            ),
          );
        }
        return;
      }
      try {
        await widget.shareFile(path);
      } on Exception {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: TapToDismissSnackContent(
                child: Text(shareFailedMessage),
              ),
            ),
          );
        }
        return;
      }
      widget.onExportShared();
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// Идёт загрузка (открыто окно выбора или экран загрузки).
  bool _importing = false;

  Future<void> _importCsv() async {
    setState(() => _importing = true);
    try {
      final int? added;
      try {
        added = await widget.onImportCsv();
      } on Exception {
        _showMessage(importOpenFailedMessage);
        return;
      }
      if (added != null) _showMessage(importDoneMessage(added));
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: TapToDismissSnackContent(child: Text(text))),
    );
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
          subtitle: Text(lastExportLabel(widget.lastExportDay, widget.today)),
          // Пока идёт выгрузка, вместо стрелки крутится индикатор, а пункт
          // недоступен: повторное нажатие не запустит вторую выгрузку.
          trailing: _exporting
              ? const SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    semanticsLabel: exportPreparingLabel,
                  ),
                )
              : const ExcludeSemantics(child: Icon(Icons.chevron_right)),
          enabled: !_exporting,
          onTap: _exporting ? null : _exportCsv,
        ),
        ListTile(
          title: const Text(importCsvItemLabel),
          subtitle: const Text(importCsvItemSubtitle),
          trailing: const ExcludeSemantics(child: Icon(Icons.chevron_right)),
          // Второе нажатие, пока открыто окно выбора, ничего не делает.
          onTap: _importing ? null : _importCsv,
        ),
      ],
    );
  }
}
