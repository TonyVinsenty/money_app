import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:money_app/core/format/currency_label.dart';
import 'package:money_app/core/format/date_format.dart';
import 'package:money_app/core/format/percent_format.dart';
import 'package:money_app/core/money/currency_catalog.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/ui/currency_picker.dart';
import 'package:money_app/core/ui/tap_to_dismiss_snack_content.dart';
import 'package:money_app/core/ui/theme/app_spacing.dart';
import 'package:money_app/features/csv_import/domain/csv_import_result.dart';
import 'package:money_app/features/recurring/domain/reminder_plan.dart';
import 'package:money_app/features/settings/domain/home_balance_line.dart';
import 'package:money_app/features/settings/presentation/share_csv_file.dart';

/// Подзаголовки групп (тексты В10 утверждены 2026-10-11).
const appearanceGroupTitle = 'Внешний вид';
const bookkeepingGroupTitle = 'Учёт';
const dataGroupTitle = 'Данные';
const resetGroupTitle = 'Сброс';

/// Подписи вариантов темы («Как в системе» не помещается в одну строку).
const themeSystemLabel = 'Системная';
const themeLightLabel = 'Светлая';
const themeDarkLabel = 'Тёмная';

/// Заголовок раздела с выбором темы.
const themeSectionTitle = 'Тема';

/// Раздел «Вторая строка в кольце» (тексты Т1 утверждены 2026-10-11).
const homeBalanceSectionTitle = 'Вторая строка в кольце';
const homeBalanceAllTimeLabel = 'За всё время';
const homeBalanceAllTimeSubtitle = 'Все доходы минус все расходы';
const homeBalanceAccountsLabel = 'На счетах';
const homeBalanceAccountsSubtitle = 'Счета в основной валюте';

/// Переключатель «Скрыть суммы».
const hideAmountsLabel = 'Скрыть суммы';
const hideAmountsSubtitle =
    'Вместо цифр — облачко, как в банковских приложениях';
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

/// Пункт выбора времени напоминаний о регулярных платежах.
const reminderTimeItemLabel = 'Время напоминаний';

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

/// Строка внизу «Настроек»: из «0.1.0+19» получается «Версия 0.1.0 (19)».
String versionLabel(String version) {
  final parts = version.split('+');
  return parts.length == 2
      ? 'Версия ${parts[0]} (${parts[1]})'
      : 'Версия $version';
}

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

/// Через сколько дней без выгрузки напоминаем о копии (больше этого числа).
const staleExportDays = 14;

/// Нужно ли предупреждение «давно не было экспорта»: операции есть, а
/// выгрузки не было или с неё прошло больше [staleExportDays] дней.
bool isExportStale({
  required DateOnly? lastExportDay,
  required DateOnly today,
  required bool hasOperations,
}) {
  if (!hasOperations) return false;
  if (lastExportDay == null) return true;
  return lastExportDay.addDays(staleExportDays) < today;
}

/// Подпись под пунктом экспорта, когда нужна копия: слова, а не только цвет.
String staleExportLabel(DateOnly? day, DateOnly today) => day == null
    ? 'Последний экспорт: ещё не было — сделайте копию'
    : '${lastExportLabel(day, today)} — давно, сделайте копию';

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
    required this.version,
    this.hasOperations = false,
    this.shareFile = shareCsvFile,
    this.reminderTime,
    this.onReminderTimeChanged,
    this.hideAmounts = false,
    this.onHideAmountsChanged,
    super.key,
  });

  /// «Скрыть суммы» и обработчик; без обработчика пункта нет.
  final bool hideAmounts;
  final ValueChanged<bool>? onHideAmountsChanged;

  /// Время напоминаний и обработчик выбора; без обработчика пункта нет.
  final ReminderTime? reminderTime;
  final ValueChanged<ReminderTime>? onReminderTimeChanged;

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

  /// Есть ли в базе хотя бы одна операция (без неё предупреждать не о чем).
  final bool hasOperations;

  /// Версия приложения вида «0.1.0+19»; показывается внизу списка.
  final String version;

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

  Future<void> _pickReminderTime() async {
    final current = widget.reminderTime ?? ReminderTime.defaultTime();
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current.hour, minute: current.minute),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null) return;
    widget.onReminderTimeChanged?.call(
      ReminderTime(picked.hour, picked.minute),
    );
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
    final errorColor = Theme.of(context).colorScheme.error;
    return ListView(
      children: [
        const _GroupHeader(appearanceGroupTitle),
        _ThemeRow(
          value: widget.themeMode,
          onChanged: widget.onThemeModeChanged,
        ),
        const _SectionTitle(Icons.donut_large, homeBalanceSectionTitle),
        RadioGroup<HomeBalanceLine>(
          groupValue: widget.homeBalanceLine,
          onChanged: (value) {
            if (value != null) widget.onHomeBalanceLineChanged(value);
          },
          // Кружок (20 в зоне 40) — по центру колонки значков (24 от края 16),
          // текст — на линии названий остальных пунктов (16 + 24 + 16 = 56):
          // начало 8, промежуток 8.
          child: ListTileTheme.merge(
            contentPadding: const EdgeInsetsDirectional.only(
              start: AppSpacing.s,
              end: AppSpacing.xl,
            ),
            horizontalTitleGap: AppSpacing.s,
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
        ),
        if (widget.onHideAmountsChanged case final onChanged?)
          SwitchListTile.adaptive(
            secondary: const _ItemIcon(Icons.visibility_off_outlined),
            title: const Text(hideAmountsLabel),
            subtitle: const Text(hideAmountsSubtitle),
            value: widget.hideAmounts,
            onChanged: onChanged,
          ),
        const _GroupHeader(bookkeepingGroupTitle),
        ListTile(
          leading: const _ItemIcon(Icons.category_outlined),
          title: const Text(categoriesItemLabel),
          trailing: const ExcludeSemantics(child: Icon(Icons.chevron_right)),
          onTap: widget.onOpenCategories,
        ),
        ListTile(
          leading: const _ItemIcon(Icons.payments_outlined),
          title: const Text(mainCurrencyItemLabel),
          subtitle: Text(currencyNameWithSymbol(widget.mainCurrency)),
          trailing: const ExcludeSemantics(child: Icon(Icons.chevron_right)),
          onTap: _pickMainCurrency,
        ),
        if (widget.onReminderTimeChanged != null)
          ListTile(
            leading: const _ItemIcon(Icons.notifications_none),
            title: const Text(reminderTimeItemLabel),
            subtitle: Text(
              (widget.reminderTime ?? ReminderTime.defaultTime()).toString(),
            ),
            trailing: const ExcludeSemantics(child: Icon(Icons.chevron_right)),
            onTap: _pickReminderTime,
          ),
        const _GroupHeader(dataGroupTitle),
        ListTile(
          leading: const _ItemIcon(Icons.file_upload_outlined),
          title: const Text(exportCsvItemLabel),
          subtitle:
              isExportStale(
                lastExportDay: widget.lastExportDay,
                today: widget.today,
                hasOperations: widget.hasOperations,
              )
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Значок только для глаз: смысл несут слова.
                    ExcludeSemantics(
                      child: Padding(
                        padding: const EdgeInsets.only(
                          top: AppSpacing.xs,
                          right: AppSpacing.s,
                        ),
                        child: Icon(
                          Icons.info_outline,
                          size: 16,
                          color: Theme.of(context).colorScheme.tertiary,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        staleExportLabel(widget.lastExportDay, widget.today),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.tertiary,
                        ),
                      ),
                    ),
                  ],
                )
              : Text(lastExportLabel(widget.lastExportDay, widget.today)),
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
          leading: const _ItemIcon(Icons.file_download_outlined),
          title: const Text(importCsvItemLabel),
          subtitle: const Text(importCsvItemSubtitle),
          trailing: const ExcludeSemantics(child: Icon(Icons.chevron_right)),
          // Второе нажатие, пока открыто окно выбора, ничего не делает.
          enabled: !_busy,
          onTap: _busy ? null : _importCsv,
        ),
        const _GroupHeader(resetGroupTitle),
        ListTile(
          leading: const _ItemIcon(Icons.delete_forever_outlined),
          title: const Text(clearAllItemLabel),
          // Цвет ошибки только у доступного пункта; у недоступного ListTile
          // сам берёт цвет неактивного.
          textColor: _busy ? null : errorColor,
          iconColor: _busy ? null : errorColor,
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
        // «Версия» — внизу, вне групп.
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.l,
            AppSpacing.xl,
            AppSpacing.l,
            AppSpacing.xl,
          ),
          child: Text(
            versionLabel(widget.version),
            style: textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

/// Подзаголовок группы (design-style.md, 8.4): `titleSmall`, 600, цвет
/// акцента, слева, отступ сверху 24.
class _GroupHeader extends StatelessWidget {
  const _GroupHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.l,
        AppSpacing.xl,
        AppSpacing.l,
        AppSpacing.s,
      ),
      child: Semantics(
        header: true,
        child: Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

/// Заголовок пункта с вариантами внутри группы («Тема»): значок и название.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.icon, this.title);

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.l,
        AppSpacing.s,
        AppSpacing.l,
        AppSpacing.xs,
      ),
      child: Row(
        children: [
          // Цвет как у значков ListTile в соседних пунктах.
          IconTheme.merge(
            data: IconThemeData(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            child: _ItemIcon(icon),
          ),
          const SizedBox(width: AppSpacing.l),
          Expanded(
            child: Semantics(
              header: true,
              child: Text(title, style: Theme.of(context).textTheme.bodyLarge),
            ),
          ),
        ],
      ),
    );
  }
}

/// Как встаёт выбор темы относительно заголовка «Тема».
enum ThemeRowLayout {
  /// Сегменты справа от заголовка, в той же строке.
  beside,

  /// Сегменты под заголовком во всю ширину, по-прежнему в одну строку.
  below,

  /// Сегменты под заголовком столбиком: в строку не помещаются даже одни.
  stacked,
}

/// Тема — три сегмента «Системная · Светлая · Тёмная» (В10).
///
/// Ширину сегментов оцениваем заранее по ширине подписей (с запасом), чтобы
/// выбрать раскладку до построения: `beside`, если всё помещается в строку
/// с «Тема», иначе `below`, а при крупном шрифте на узком экране — `stacked`.
class _ThemeRow extends StatelessWidget {
  const _ThemeRow({required this.value, required this.onChanged});

  final ThemeMode value;
  final ValueChanged<ThemeMode> onChanged;

  static const _options = [
    (ThemeMode.system, themeSystemLabel),
    (ThemeMode.light, themeLightLabel),
    (ThemeMode.dark, themeDarkLabel),
  ];

  /// Отступ подписи сегмента слева и справа (задаём сами, чтобы оценка
  /// ширины не зависела от умолчаний Material).
  static const _segmentPadding = AppSpacing.m;

  /// Рамки и запас на округление у каждого сегмента. Значка «выбрано» нет:
  /// выбранный сегмент залит цветом, а скринридер говорит «выбрано».
  static const _segmentAllowance = 8.0;

  /// Запас строки «Тема + сегменты».
  static const _besideReserve = AppSpacing.xl;

  /// Значок пункта (24) и промежуток до названия, как у `ListTile`.
  static const _leadingWidth = 24.0 + AppSpacing.l;

  double _textWidth(BuildContext context, String text, TextStyle? style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  ThemeRowLayout _layout(BuildContext context, double width) {
    final textTheme = Theme.of(context).textTheme;
    var buttonWidth = 0.0;
    var widestSegment = 0.0;
    for (final (_, label) in _options) {
      final segment =
          _textWidth(context, label, textTheme.labelLarge) +
          2 * _segmentPadding +
          _segmentAllowance;
      buttonWidth += segment;
      if (segment > widestSegment) widestSegment = segment;
    }
    final titleWidth =
        _leadingWidth +
        _textWidth(context, themeSectionTitle, textTheme.bodyLarge);
    // Запас: оценка по тексту не учитывает всего, что рисует Material, а
    // ошибка здесь рвёт «Тема» посреди слова.
    if (titleWidth + AppSpacing.l + buttonWidth + _besideReserve <= width) {
      return ThemeRowLayout.beside;
    }
    // Во всю ширину сегменты равные: решает самый широкий.
    return widestSegment * _options.length <= width
        ? ThemeRowLayout.below
        : ThemeRowLayout.stacked;
  }

  @override
  Widget build(BuildContext context) {
    final title = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconTheme.merge(
          data: IconThemeData(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          child: const _ItemIcon(Icons.palette_outlined),
        ),
        const SizedBox(width: AppSpacing.l),
        Flexible(
          child: Semantics(
            header: true,
            child: Text(
              themeSectionTitle,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.l,
        vertical: AppSpacing.s,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final layout = _layout(context, constraints.maxWidth);
          final button = SegmentedButton<ThemeMode>(
            key: ValueKey(layout),
            segments: [
              for (final (mode, label) in _options)
                ButtonSegment(
                  value: mode,
                  label: Text(
                    label,
                    // «Тема: тёмная, выбрано»: состояние добавляет сама кнопка.
                    semanticsLabel:
                        '$themeSectionTitle: ${label.toLowerCase()}',
                  ),
                ),
            ],
            selected: {value},
            showSelectedIcon: false,
            onSelectionChanged: (selected) => onChanged(selected.single),
            direction: layout == ThemeRowLayout.stacked
                ? Axis.vertical
                : Axis.horizontal,
            // Во всю ширину — только в строку: столбик в прокручиваемом
            // списке растянулся бы и в бесконечную высоту.
            expandedInsets: layout == ThemeRowLayout.below
                ? EdgeInsets.zero
                : null,
            style: ButtonStyle(
              padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: _segmentPadding),
              ),
              // Столбиком «таблетка» раздувается в овал: скругление поля.
              shape: layout == ThemeRowLayout.stacked
                  ? const WidgetStatePropertyAll(
                      RoundedRectangleBorder(borderRadius: AppRadius.borderM),
                    )
                  : null,
            ),
          );
          if (layout == ThemeRowLayout.beside) {
            return Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: title,
                  ),
                ),
                const SizedBox(width: AppSpacing.l),
                button,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(alignment: AlignmentDirectional.centerStart, child: title),
              const SizedBox(height: AppSpacing.s),
              button,
            ],
          );
        },
      ),
    );
  }
}

/// Значок пункта — только для глаз: смысл несёт название.
class _ItemIcon extends StatelessWidget {
  const _ItemIcon(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(child: Icon(icon));
}
