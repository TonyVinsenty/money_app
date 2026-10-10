import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:money_app/core/format/currency_label.dart';
import 'package:money_app/core/format/date_format.dart';
import 'package:money_app/core/format/percent_format.dart';
import 'package:money_app/core/money/currency_catalog.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/ui/currency_picker.dart';
import 'package:money_app/core/ui/tap_to_dismiss_snack_content.dart';
import 'package:money_app/features/csv_import/domain/csv_import_result.dart';
import 'package:money_app/features/settings/domain/home_balance_line.dart';
import 'package:money_app/features/settings/presentation/share_csv_file.dart';

/// Подписи вариантов темы.
const themeSystemLabel = 'Как в системе';
const themeLightLabel = 'Светлая';
const themeDarkLabel = 'Тёмная';

/// Заголовок раздела с выбором темы.
const themeSectionTitle = 'Тема';

/// Раздел «Строка «Баланс» на Главной» (тексты утверждены 2026-10-10).
const homeBalanceSectionTitle = 'Строка «Баланс» на Главной';
const homeBalanceAllTimeLabel = 'Все доходы минус все расходы';
const homeBalanceAllTimeSubtitle = 'За всё время';
const homeBalanceAccountsLabel = 'Сумма на счетах';
const homeBalanceAccountsSubtitle = 'Счета в основной валюте';
const homeBalanceNoneLabel = 'Не показывать';

/// Пункт, ведущий к управлению категориями.
const categoriesItemLabel = 'Категории';

/// Пункт выбора основной валюты (его подпись и заголовок листа).
const mainCurrencyItemLabel = 'Основная валюта';

/// Подтверждение смены основной валюты (тексты утверждены).
String mainCurrencyConfirmTitle(String name) =>
    'Сделать основной валютой «$name»?';
const mainCurrencyConfirmText =
    'Новые доходы и расходы будут вноситься в этой валюте. '
    'В быстрый ввод попадут только счета в этой валюте. '
    '«Главная», «История» и «Аналитика» покажут только операции в ней. '
    'Операции в других валютах сохранятся и снова появятся, '
    'если вернуть их валюту.';
const mainCurrencyConfirmCancel = 'Отмена';
const mainCurrencyConfirmAccept = 'Сменить';

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

/// Итог загрузки с переводами: «Загружено 5 операций и 2 перевода», только
/// переводы — «Загружены 2 перевода» (глагол по первому числу); счета
/// добавляются в конце: «…, создано 2 счёта».
String importResultMessage(CsvImportResult result) {
  final recurring = result.recurring;
  if (recurring == 0) return _importCountsMessage(result);
  final tail = 'регулярные платежи: ${_countFormat.format(recurring)}';
  if (result.transactions == 0 &&
      result.transfers == 0 &&
      result.accounts == 0) {
    return 'Добавлены $tail';
  }
  return '${_importCountsMessage(result)}, $tail';
}

String _importCountsMessage(CsvImportResult result) {
  final accounts = result.accounts;
  final transactions = result.transactions;
  final transfers = result.transfers;
  if (transactions == 0 && transfers == 0 && accounts > 0) {
    final verb = pluralRu(accounts, 'Создан', 'Созданы', 'Создано');
    return '$verb ${_countFormat.format(accounts)} ${_accountNoun(accounts)}';
  }
  final String main;
  if (transfers == 0) {
    main = importDoneMessage(transactions);
  } else {
    final transferText =
        '${_countFormat.format(transfers)} '
        '${pluralRu(transfers, 'перевод', 'перевода', 'переводов')}';
    if (transactions == 0) {
      final verb = pluralRu(transfers, 'Загружен', 'Загружены', 'Загружено');
      main = '$verb $transferText';
    } else {
      main = '${importDoneMessage(transactions)} и $transferText';
    }
  }
  if (accounts == 0) return main;
  final verb = pluralRu(accounts, 'создан', 'создано', 'создано');
  return '$main, $verb ${_countFormat.format(accounts)} '
      '${_accountNoun(accounts)}';
}

/// Пункт «Очистить всё» и подпись под ним (Н1).
const clearAllItemLabel = 'Очистить всё';
const clearAllItemSubtitle = 'Стереть операции, категории и счета';

/// Подтверждение стирания (Н2): заголовок, текст и кнопки.
const clearAllConfirmTitle = 'Стереть все операции, категории и счета?';
const clearAllConfirmText =
    'Это действие нельзя отменить. '
    'Восстановить данные можно только из файла экспорта CSV.';
const clearAllExportFirst = 'Сначала экспорт';
const clearAllCancel = 'Отмена';
const clearAllAccept = 'Стереть всё';

/// Сообщения после стирания (Н3) и при сбое (Н4).
const clearAllDoneMessage = 'Данные стёрты. Категории — как при первом запуске';
const clearAllFailedMessage = 'Не удалось стереть данные. Ничего не изменилось';

/// Подпись индикатора для скринридера, пока идёт стирание (Н5).
const clearAllErasingLabel = 'Стираем данные';

enum _ClearAllChoice { exportFirst, erase }

String _accountNoun(int count) => pluralRu(count, 'счёт', 'счёта', 'счетов');

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
    required this.homeBalanceLine,
    required this.onHomeBalanceLineChanged,
    required this.onOpenCategories,
    required this.mainCurrency,
    required this.onMainCurrencyChanged,
    required this.onExportCsv,
    required this.lastExportDay,
    required this.today,
    required this.onExportShared,
    required this.onImportCsv,
    required this.onClearAll,
    this.shareFile = shareCsvFile,
    super.key,
  });

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  /// Что показывать строкой «Баланс» на «Главной» и обработчик выбора.
  final HomeBalanceLine homeBalanceLine;
  final ValueChanged<HomeBalanceLine> onHomeBalanceLineChanged;
  final VoidCallback onOpenCategories;

  /// Текущая основная валюта и обработчик подтверждённой смены.
  final CurrencyInfo mainCurrency;
  final ValueChanged<CurrencyInfo> onMainCurrencyChanged;

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
  final Future<CsvImportResult?> Function() onImportCsv;

  /// Стирает все данные пользователя. Бросает исключение, если не удалось.
  final Future<void> Function() onClearAll;

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
      final bool shared;
      try {
        shared = await widget.shareFile(path);
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
      // Отмена (false) не ошибка: ничего не показываем и «последний экспорт» не ставим.
      if (shared) widget.onExportShared();
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// Идёт загрузка (открыто окно выбора или экран загрузки).
  bool _importing = false;

  Future<void> _importCsv() async {
    setState(() => _importing = true);
    try {
      final CsvImportResult? added;
      try {
        added = await widget.onImportCsv();
      } on Exception {
        _showMessage(importOpenFailedMessage);
        return;
      }
      if (added != null) _showMessage(importResultMessage(added));
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  /// Идёт стирание.
  bool _erasing = false;

  bool get _busy => _exporting || _importing || _erasing;

  Future<void> _clearAll() async {
    if (_busy) return;
    final choice = await showDialog<_ClearAllChoice>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(clearAllConfirmTitle),
        content: const Text(clearAllConfirmText),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(_ClearAllChoice.exportFirst),
            child: const Text(clearAllExportFirst),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(clearAllCancel),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(_ClearAllChoice.erase),
            child: const Text(clearAllAccept),
          ),
        ],
      ),
    );
    if (!mounted || choice == null || _busy) return;
    if (choice == _ClearAllChoice.exportFirst) {
      await _exportCsv();
      return;
    }
    setState(() => _erasing = true);
    try {
      // Старое «Отменить» ссылалось бы на стёртые строки.
      ScaffoldMessenger.of(context).clearSnackBars();
      try {
        await widget.onClearAll();
      } on Exception {
        _showMessage(clearAllFailedMessage);
        return;
      }
      _showMessage(clearAllDoneMessage);
    } finally {
      if (mounted) setState(() => _erasing = false);
    }
  }

  Future<void> _pickMainCurrency() async {
    final picked = await showCurrencyPicker(
      context,
      fiatOnly: true,
      selected: widget.mainCurrency.code,
      title: mainCurrencyItemLabel,
    );
    if (picked == null || picked.code == widget.mainCurrency.code) return;
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(mainCurrencyConfirmTitle(picked.name)),
        content: const Text(mainCurrencyConfirmText),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(mainCurrencyConfirmCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(mainCurrencyConfirmAccept),
          ),
        ],
      ),
    );
    if (confirmed == true) widget.onMainCurrencyChanged(picked);
  }

  void _showMessage(String text) {
    if (!mounted) return;
    // Прежнее сообщение могло остаться (persist ниже): новое его заменяет,
    // а не ждёт в очереди.
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: TapToDismissSnackContent(child: Text(text)),
          // Со скринридером итог не исчезает через 4 с, пока его не дочитали:
          // закрывается двойным касанием (TapToDismissSnackContent).
          persist: MediaQuery.accessibleNavigationOf(context),
        ),
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
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Semantics(
            header: true,
            child: Text(homeBalanceSectionTitle, style: textTheme.titleMedium),
          ),
        ),
        RadioGroup<HomeBalanceLine>(
          groupValue: widget.homeBalanceLine,
          onChanged: (value) {
            if (value != null) widget.onHomeBalanceLineChanged(value);
          },
          child: const Column(
            children: [
              RadioListTile<HomeBalanceLine>(
                value: HomeBalanceLine.allTime,
                title: Text(homeBalanceAllTimeLabel),
                subtitle: Text(homeBalanceAllTimeSubtitle),
              ),
              RadioListTile<HomeBalanceLine>(
                value: HomeBalanceLine.accounts,
                title: Text(homeBalanceAccountsLabel),
                subtitle: Text(homeBalanceAccountsSubtitle),
              ),
              RadioListTile<HomeBalanceLine>(
                value: HomeBalanceLine.none,
                title: Text(homeBalanceNoneLabel),
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
        ListTile(
          title: const Text(mainCurrencyItemLabel),
          subtitle: Text(currencyNameWithSymbol(widget.mainCurrency)),
          trailing: const ExcludeSemantics(child: Icon(Icons.chevron_right)),
          onTap: _pickMainCurrency,
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
          enabled: !_busy,
          onTap: _busy ? null : _exportCsv,
        ),
        ListTile(
          title: const Text(importCsvItemLabel),
          subtitle: const Text(importCsvItemSubtitle),
          trailing: const ExcludeSemantics(child: Icon(Icons.chevron_right)),
          // Второе нажатие, пока открыто окно выбора, ничего не делает.
          enabled: !_busy,
          onTap: _busy ? null : _importCsv,
        ),
        const Divider(),
        ListTile(
          title: const Text(clearAllItemLabel),
          // Цвет ошибки только у доступного пункта; у недоступного ListTile
          // сам берёт цвет неактивного.
          textColor: _busy ? null : Theme.of(context).colorScheme.error,
          subtitle: const Text(clearAllItemSubtitle),
          trailing: _erasing
              ? const SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    semanticsLabel: clearAllErasingLabel,
                  ),
                )
              : const ExcludeSemantics(child: Icon(Icons.chevron_right)),
          enabled: !_busy,
          onTap: _busy ? null : _clearAll,
        ),
      ],
    );
  }
}
