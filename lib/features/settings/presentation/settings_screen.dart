import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:money_app/core/format/currency_label.dart';
import 'package:money_app/core/format/date_format.dart';
import 'package:money_app/core/format/percent_format.dart';
import 'package:money_app/core/money/currency_catalog.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/ui/adaptive_dialog_action.dart';
import 'package:money_app/core/ui/currency_picker.dart';
import 'package:money_app/core/ui/tap_to_dismiss_snack_content.dart';
import 'package:money_app/core/ui/theme/app_spacing.dart';
import 'package:money_app/features/csv_import/domain/csv_import_result.dart';
import 'package:money_app/features/recurring/domain/reminder_plan.dart';
import 'package:money_app/features/settings/domain/home_balance_line.dart';
import 'package:money_app/features/settings/presentation/group_header.dart';
import 'package:money_app/features/settings/presentation/open_external_link.dart';
import 'package:money_app/features/settings/presentation/reminder_time_wheel.dart';
import 'package:money_app/features/settings/presentation/share_csv_file.dart';

/// Подзаголовки групп (тексты В10 утверждены 2026-10-11).
const appearanceGroupTitle = 'Внешний вид';
const ringGroupTitle = 'Кольцо на «Главной»';
const bookkeepingGroupTitle = 'Учёт';
const dataGroupTitle = 'Данные';
const resetGroupTitle = 'Сброс';
const aboutGroupTitle = 'О приложении';

/// Пункт «Информация о разработчике» (шаг 8.0): ведёт на страницу автора.
/// Слов о донате и оплате нет (правила App Store 3.1.1).
const developerInfoItemLabel = 'Информация о разработчике';
const developerPageLabel = 'boosty.to/tony_vinsenty';
const developerPageUrl = 'https://boosty.to/tony_vinsenty';
const openLinkFailedMessage = 'Не удалось открыть страницу';

/// Пункт «Спасибо» (шаг 8.33): виден всегда, даже при пустом списке имён.
const thanksItemLabel = 'Спасибо';
const thanksItemSubtitle = 'Люди, которые помогают Zuno';

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
/// (год берётся из [today]); если выгрузки не было — «Экспорта ещё не было».
String lastExportLabel(DateOnly? day, DateOnly today) {
  if (day == null) return 'Экспорта ещё не было';
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
    ? 'Экспорта ещё не было — сделайте копию'
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
    required this.onOpenThanks,
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
    this.openLink = openExternalLink,
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

  /// Открывает экран «Спасибо».
  final VoidCallback onOpenThanks;

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

  /// Открывает адрес во внешнем браузере.
  final OpenLink openLink;

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
    final choice = await showAdaptiveDialog<_ClearAllChoice>(
      context: context,
      builder: (context) => AlertDialog.adaptive(
        title: const Text(clearAllConfirmTitle),
        content: const Text(clearAllConfirmText),
        actions: [
          AdaptiveDialogAction(
            onPressed: () =>
                Navigator.of(context).pop(_ClearAllChoice.exportFirst),
            label: clearAllExportFirst,
          ),
          AdaptiveDialogAction(
            onPressed: () => Navigator.of(context).pop(),
            label: clearAllCancel,
          ),
          AdaptiveDialogAction(
            onPressed: () => Navigator.of(context).pop(_ClearAllChoice.erase),
            label: clearAllAccept,
            destructive: true,
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
    final confirmed = await showAdaptiveDialog<bool>(
      context: context,
      builder: (context) => AlertDialog.adaptive(
        title: Text(mainCurrencyConfirmTitle(picked.name)),
        content: const Text(mainCurrencyConfirmText),
        actions: [
          AdaptiveDialogAction(
            onPressed: () => Navigator.of(context).pop(false),
            label: mainCurrencyConfirmCancel,
          ),
          AdaptiveDialogAction(
            onPressed: () => Navigator.of(context).pop(true),
            label: mainCurrencyConfirmAccept,
          ),
        ],
      ),
    );
    if (confirmed == true) widget.onMainCurrencyChanged(picked);
  }

  Future<void> _pickReminderTime() async {
    final current = widget.reminderTime ?? ReminderTime.defaultTime();
    // На iPhone время выбирают колесом, как в будильнике; на Android —
    // привычный циферблат.
    if (Theme.of(context).platform == TargetPlatform.iOS) {
      final wheel = await showReminderTimeWheel(
        context,
        initial: current,
        title: reminderTimeItemLabel,
      );
      if (wheel != null) widget.onReminderTimeChanged?.call(wheel);
      return;
    }
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

  Future<void> _openDeveloperPage() async {
    if (!await widget.openLink(developerPageUrl)) {
      _showMessage(openLinkFailedMessage);
    }
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
    final mutedColor = Theme.of(context).colorScheme.onSurfaceVariant;
    return ListView(
      children: [
        const GroupHeader(appearanceGroupTitle),
        _SegmentedChoice<ThemeMode>(
          title: themeSectionTitle,
          options: const [
            (ThemeMode.system, themeSystemLabel, null),
            (ThemeMode.light, themeLightLabel, null),
            (ThemeMode.dark, themeDarkLabel, null),
          ],
          value: widget.themeMode,
          onChanged: widget.onThemeModeChanged,
        ),
        if (widget.onHideAmountsChanged case final onChanged?)
          SwitchListTile.adaptive(
            secondary: const _ItemIcon(Icons.visibility_off_outlined),
            title: const Text(hideAmountsLabel),
            subtitle: const Text(hideAmountsSubtitle),
            value: widget.hideAmounts,
            onChanged: onChanged,
          ),
        const GroupHeader(ringGroupTitle),
        _SegmentedChoice<HomeBalanceLine>(
          title: homeBalanceSectionTitle,
          options: const [
            (
              HomeBalanceLine.allTime,
              homeBalanceAllTimeLabel,
              homeBalanceAllTimeSubtitle,
            ),
            (
              HomeBalanceLine.accounts,
              homeBalanceAccountsLabel,
              homeBalanceAccountsSubtitle,
            ),
            (HomeBalanceLine.none, homeBalanceNoneLabel, null),
          ],
          value: widget.homeBalanceLine,
          onChanged: widget.onHomeBalanceLineChanged,
        ),
        const GroupHeader(bookkeepingGroupTitle),
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
        const GroupHeader(dataGroupTitle),
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
                  child: CircularProgressIndicator.adaptive(
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
        const GroupHeader(resetGroupTitle),
        ListTile(
          // Красные только значок и название, и только у доступного пункта;
          // подпись и шеврон обычные, у недоступного ListTile сам берёт цвет
          // неактивного.
          leading: _busy
              ? const _ItemIcon(Icons.delete_forever_outlined)
              : IconTheme.merge(
                  data: IconThemeData(color: errorColor),
                  child: const _ItemIcon(Icons.delete_forever_outlined),
                ),
          title: _busy
              ? const Text(clearAllItemLabel)
              : Text(clearAllItemLabel, style: TextStyle(color: errorColor)),
          subtitle: const Text(clearAllItemSubtitle),
          trailing: _erasing
              ? const SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator.adaptive(
                    strokeWidth: 2,
                    semanticsLabel: clearAllErasingLabel,
                  ),
                )
              : const ExcludeSemantics(child: Icon(Icons.chevron_right)),
          enabled: !_busy,
          onTap: _busy ? null : _clearAll,
        ),
        const GroupHeader(aboutGroupTitle),
        ListTile(
          leading: const _ItemIcon(Icons.person_outline),
          title: const Text(developerInfoItemLabel),
          subtitle: const Text(developerPageLabel),
          trailing: ExcludeSemantics(
            child: Icon(
              Theme.of(context).platform == TargetPlatform.iOS
                  ? Icons.north_east
                  : Icons.open_in_new,
            ),
          ),
          onTap: _openDeveloperPage,
        ),
        ListTile(
          leading: const _ItemIcon(Icons.favorite_border),
          title: const Text(thanksItemLabel),
          subtitle: const Text(thanksItemSubtitle),
          trailing: const ExcludeSemantics(child: Icon(Icons.chevron_right)),
          onTap: widget.onOpenThanks,
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
            style: textTheme.bodySmall?.copyWith(color: mutedColor),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

/// Как встают сегменты выбора под заголовком.
enum ChoiceLayout {
  /// Во всю ширину, в одну строку, сегменты равные.
  below,

  /// Столбиком: в строку не помещаются даже равные сегменты.
  stacked,
}

/// Вариант выбора: значение, подпись сегмента и пояснение под сегментами
/// (`null` — пояснения нет, место строки всё равно занято).
typedef ChoiceOption<T> = (T value, String label, String? description);

/// Выбор одного из вариантов (7.30e): подпись-заголовок без значка, под ней
/// сегменты во всю ширину, под ними — пояснение выбранного варианта.
///
/// Ширину сегментов оцениваем заранее по ширине подписей, чтобы выбрать
/// раскладку до построения: в строку, если самая широкая подпись помещается
/// в равную долю ширины, иначе столбиком.
class _SegmentedChoice<T> extends StatelessWidget {
  const _SegmentedChoice({
    required this.title,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final List<ChoiceOption<T>> options;
  final T value;
  final ValueChanged<T> onChanged;

  /// Отступ подписи сегмента слева и справа (задаём сами, чтобы оценка
  /// ширины не зависела от умолчаний Material).
  static const _segmentPadding = AppSpacing.xs;

  /// Рамки сегмента и запас на округление. Значка «выбрано» нет: выбранный
  /// сегмент залит цветом, а скринридер говорит «выбрано».
  static const _segmentAllowance = 4.0;

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

  ChoiceLayout _layout(BuildContext context, double width) {
    final style = Theme.of(context).textTheme.labelLarge;
    var widest = 0.0;
    for (final (_, label, _) in options) {
      final segment =
          _textWidth(context, label, style) +
          2 * _segmentPadding +
          _segmentAllowance;
      if (segment > widest) widest = segment;
    }
    return widest * options.length <= width
        ? ChoiceLayout.below
        : ChoiceLayout.stacked;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasDescriptions = options.any((option) => option.$3 != null);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.l,
        AppSpacing.m,
        AppSpacing.l,
        AppSpacing.s,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final layout = _layout(context, constraints.maxWidth);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Заголовок, а не кнопка: значка нет, нажать нечего. Свой узел,
              // чтобы пояснение под сегментами не склеилось с заголовком.
              Semantics(
                container: true,
                header: true,
                child: Text(
                  title,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.s),
              SegmentedButton<T>(
                key: ValueKey((title, layout)),
                segments: [
                  for (final (option, label, _) in options)
                    ButtonSegment(
                      value: option,
                      label: Text(
                        label,
                        maxLines: 1,
                        softWrap: false,
                        // «Тема: тёмная, выбрано»: состояние добавляет кнопка.
                        semanticsLabel: '$title: ${label.toLowerCase()}',
                      ),
                    ),
                ],
                selected: {value},
                showSelectedIcon: false,
                onSelectionChanged: (selected) => onChanged(selected.single),
                direction: layout == ChoiceLayout.stacked
                    ? Axis.vertical
                    : Axis.horizontal,
                // Во всю ширину — только в строку: столбик в прокручиваемом
                // списке растянулся бы и в бесконечную высоту.
                expandedInsets: layout == ChoiceLayout.below
                    ? EdgeInsets.zero
                    : null,
                style: ButtonStyle(
                  padding: const WidgetStatePropertyAll(
                    EdgeInsets.symmetric(horizontal: _segmentPadding),
                  ),
                  // Столбиком «таблетка» раздувается в овал: скругление поля.
                  shape: layout == ChoiceLayout.stacked
                      ? const WidgetStatePropertyAll(
                          RoundedRectangleBorder(
                            borderRadius: AppRadius.borderM,
                          ),
                        )
                      : null,
                ),
              ),
              if (hasDescriptions) ...[
                const SizedBox(height: AppSpacing.s),
                // Все пояснения лежат друг на друге, видно только выбранное:
                // высота — по самому длинному, экран не прыгает при выборе.
                Stack(
                  children: [
                    for (final (option, _, description) in options)
                      Visibility(
                        visible: option == value,
                        maintainSize: true,
                        maintainAnimation: true,
                        maintainState: true,
                        child: Text(
                          description ?? '',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
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
