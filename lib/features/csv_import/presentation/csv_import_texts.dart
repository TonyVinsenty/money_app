import 'package:intl/intl.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/format/money_spoken.dart';
import 'package:money_app/core/format/percent_format.dart';
import 'package:money_app/core/money/currency_catalog.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/money/parse_amount.dart';
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/accounts/domain/account_rules.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/categories/domain/category_rules.dart';
import 'package:money_app/features/csv_import/domain/csv_import_failures.dart';
import 'package:money_app/features/export/domain/transactions_export.dart';
import 'package:money_app/features/recurring/domain/recurring_rules.dart';
import 'package:money_app/features/transactions/domain/transaction_rules.dart';

/// Тексты экрана загрузки из CSV (шаг i.15). Здесь же — как превратить ошибки
/// разбора и плана в понятные пользователю строки.

const csvImportTitle = 'Загрузка из CSV';
const csvImportCheckingLabel = 'Проверяем файл…';
const csvImportWritingLabel = 'Загружаем…';
const csvImportLoadButton = 'Загрузить';
const csvImportCancelButton = 'Отмена';
const csvImportCloseButton = 'Закрыть';

const csvImportReadFailedMessage =
    'Не удалось прочитать файл. Попробуйте выбрать его ещё раз';
const csvImportWriteFailedMessage =
    'Не удалось загрузить. Ничего не добавлено, попробуйте ещё раз';
const csvImportErrorsIntro =
    'В файле есть ошибки, поэтому ничего не загружено. '
    'Исправьте их в файле и загрузите его снова.';
const csvImportNoRowsMessage =
    'В файле нет операций: есть только строка с названиями колонок';
const csvImportNothingToAddMessage =
    'Нечего добавлять: всё из файла уже есть в приложении';
const csvImportNewCategoriesTitle = 'Будут созданы категории';
const csvImportNewAccountsTitle = 'Будут созданы счета';

/// Сколько имён счетов называем в объявлении скринридеру; остальные — «и ещё N».
const csvImportAnnouncedAccountsLimit = 5;

/// Сколько ошибок строк показывать; остальные — одной строкой «… и ещё K».
const csvImportShownErrorsLimit = 20;

/// Самое длинное значение поля, которое цитируем в ошибке целиком.
const _quotedMaxLength = 30;

final NumberFormat _countFormat = NumberFormat.decimalPattern('ru');

/// Число с разделителем разрядов: «1 234».
String formatCount(int n) => _countFormat.format(n);

String csvImportMoreErrors(int count) => '… и ещё ${formatCount(count)}';

/// «Будет добавлена 1 операция», «Будут добавлены 2 операции»,
/// «Будет добавлено 5 операций».
String csvImportWillAdd(int count) {
  final verb = pluralRu(
    count,
    'Будет добавлена',
    'Будут добавлены',
    'Будет добавлено',
  );
  final noun = pluralRu(count, 'операция', 'операции', 'операций');
  return '$verb ${formatCount(count)} $noun';
}

/// «Будет добавлен 1 перевод», «Будут добавлены 3 перевода»,
/// «Будет добавлено 5 переводов».
String csvImportWillAddTransfers(int count) {
  final verb = pluralRu(
    count,
    'Будет добавлен',
    'Будут добавлены',
    'Будет добавлено',
  );
  final noun = pluralRu(count, 'перевод', 'перевода', 'переводов');
  return '$verb ${formatCount(count)} $noun';
}

/// Одна форма для любого числа: «Будут добавлены регулярные платежи: 2».
String csvImportWillAddRecurring(int count) =>
    'Будут добавлены регулярные платежи: ${formatCount(count)}';

/// «Будет создан 1 счёт», «Будут созданы 2 счёта», «Будет создано 5 счетов».
String csvImportWillCreateAccounts(int count) {
  final verb = pluralRu(
    count,
    'Будет создан',
    'Будут созданы',
    'Будет создано',
  );
  final noun = pluralRu(count, 'счёт', 'счёта', 'счетов');
  return '$verb ${formatCount(count)} $noun';
}

/// Счета по алфавиту (без учёта регистра).
List<Account> csvImportSortedAccounts(List<Account> accounts) =>
    [...accounts]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

/// Строка счёта в предпросмотре: «Карта (остаток 12 000,00 ₽)»; без остатка
/// (нулевой) — просто имя. Остаток — в валюте счёта.
String csvImportAccountLine(Account account) {
  final balance = account.openingBalance;
  if (balance.minorUnits == 0) return account.name;
  final text = formatMoney(balance, currency: account.currencyInfo);
  return '${account.name} (остаток $text)';
}

/// Та же строка для скринридера: «Карта, остаток 12000 рублей».
String csvImportAccountSpoken(Account account) {
  final balance = account.openingBalance;
  if (balance.minorUnits == 0) return account.name;
  final text = spokenMoney(balance, currency: account.currencyInfo);
  return '${account.name}, остаток $text';
}

/// Объявление скринридеру о предпросмотре: «Будет добавлено 5 операций. Будут
/// созданы 2 счёта: Карта, Наличные». Без операций — только вторая фраза;
/// больше [csvImportAnnouncedAccountsLimit] счетов — «…, Д, Е и ещё 3».
String csvImportPreviewAnnouncement({
  required int transactions,
  required List<Account> accounts,
  int transfers = 0,
  int recurring = 0,
}) {
  final parts = <String>[];
  if (transactions > 0) parts.add(csvImportWillAdd(transactions));
  if (transfers > 0) parts.add(csvImportWillAddTransfers(transfers));
  if (recurring > 0) parts.add(csvImportWillAddRecurring(recurring));
  if (accounts.isNotEmpty) {
    final names = [for (final a in csvImportSortedAccounts(accounts)) a.name];
    final shown = names.take(csvImportAnnouncedAccountsLimit).join(', ');
    final rest = names.length - csvImportAnnouncedAccountsLimit;
    final tail = rest > 0 ? ' и ещё ${formatCount(rest)}' : '';
    parts.add('${csvImportWillCreateAccounts(accounts.length)}: $shown$tail');
  }
  return parts.join('. ');
}

String csvImportSkippedExisting(int count) =>
    'Пропущено (уже есть в приложении): ${formatCount(count)}';

String csvImportSkippedDeleted(int count) =>
    'Пропущено (удалены в приложении): ${formatCount(count)}';

/// Новые категории одного вида для предпросмотра: заголовок вида и строки.
typedef CsvImportCategoryGroup = ({String title, List<String> lines});

/// Список новых категорий: сначала расходы, потом доходы. Одна строка на
/// категорию верхнего уровня, по алфавиту: «Кафе: Кофе, Обед» (родитель уже
/// есть, новые только подкатегории), «Хобби (новая): Кисти, Краски»,
/// «Аптека (новая)». Родителя ищем среди новых категорий и среди
/// [existing]. Вида без новых категорий в списке нет.
List<CsvImportCategoryGroup> csvImportNewCategoryGroups(
  List<Category> toCreate,
  List<Category> existing,
) {
  final names = {
    for (final c in existing) c.id: c.name,
    for (final c in toCreate) c.id: c.name,
  };
  int byName(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());
  final groups = <CsvImportCategoryGroup>[];
  for (final (kind, title) in [
    (CategoryKind.expense, 'Расходы'),
    (CategoryKind.income, 'Доходы'),
  ]) {
    // id категории верхнего уровня → новая ли она и её новые подкатегории.
    final isNew = <String, bool>{};
    final subs = <String, List<String>>{};
    for (final c in toCreate) {
      if (c.kind != kind) continue;
      final topId = c.parentId ?? c.id;
      isNew[topId] = (isNew[topId] ?? false) || c.parentId == null;
      if (c.parentId != null) (subs[topId] ??= []).add(c.name);
    }
    final lines = [
      for (final topId in isNew.keys)
        _newCategoryLine(
          names[topId] ?? '?',
          isNew: isNew[topId]!,
          subs: (subs[topId] ?? [])..sort(byName),
        ),
    ]..sort(byName);
    if (lines.isNotEmpty) groups.add((title: title, lines: lines));
  }
  return groups;
}

String _newCategoryLine(
  String name, {
  required bool isNew,
  required List<String> subs,
}) {
  final head = isNew ? '$name (новая)' : name;
  return subs.isEmpty ? head : '$head: ${subs.join(', ')}';
}

/// Ошибка всего файла: что случилось и что сделать.
String csvFileFailureMessage(CsvFileFailure failure) => switch (failure) {
  CsvNotUtf8() =>
    'Файл сохранён не в той кодировке. В Excel сохраните его заново: '
        '«Файл» → «Сохранить как» → тип «CSV UTF-8 (разделитель - запятая)»',
  CsvMalformed() =>
    'Не получилось разобрать файл: похоже, в нём не закрыта кавычка. '
        'Откройте его в таблице и сохраните заново как CSV',
  CsvEmptyFile() => 'Файл пустой',
  CsvMissingColumns(:final columns) =>
    '${columns.length == 1 ? 'Нет обязательной колонки' : 'Нет обязательных колонок:'} '
        '${columns.map((c) => '«$c»').join(', ')}. '
        'В первой строке файла должны быть названия колонок, как в экспорте Zuno',
  CsvDuplicateColumn(:final column) =>
    'Колонка «$column» встречается в первой строке дважды. Оставьте одну',
};

/// Ошибка строки: «Строка 15: сумма «12.3.4» — не число».
String csvRowErrorMessage(CsvRowError error) =>
    'Строка ${error.line}: ${_rowErrorText(error)}';

String _rowErrorText(CsvRowError error) {
  final value = _quoted(error.value);
  return switch (error) {
    CsvInvalidDate() =>
      value == null
          ? 'не указана дата'
          : 'дата $value — нужна настоящая дата в виде ДД.ММ.ГГГГ',
    CsvFutureDate() => 'дата $value ещё не наступила',
    CsvInvalidType() =>
      value == null
          ? 'не указан тип'
          : 'тип $value — нужен «$csvTypeExpense», «$csvTypeIncome», '
                '«$csvTypeRecurringExpense», «$csvTypeRecurringIncome», '
                '«$csvTypeOpeningBalance» или «$csvTypeTransfer»',
    final CsvInvalidAmount amountError =>
      value == null
          ? 'не указана сумма'
          : 'сумма $value — ${_amountReason(amountError)}',
    CsvNegativeIncome() =>
      'сумма $value — минус можно ставить только у расхода и начального '
          'остатка',
    CsvUnsupportedCurrency() =>
      'валюта $value — у расхода и дохода нужен код обычной валюты, '
          'например RUB или USD, или пусто',
    CsvInvalidCurrencyCode() =>
      'код валюты $value — нужно 3–10 латинских букв и цифр, первая — '
          'буква, например USD или USDT',
    CsvAccountTooLong() => 'счёт длиннее $accountNameMaxLength символов',
    CsvOpeningBalanceNoAccount() => 'у начального остатка не указан счёт',
    CsvOpeningBalanceWithCategory() =>
      'у начального остатка категория $value — ячейка должна быть пустой. '
          'Похоже, колонки съехали',
    CsvDuplicateOpeningBalance(:final firstLine) =>
      'второй начальный остаток счёта ${_quoted(error.value)} '
          '(первый — в строке $firstLine). Оставьте одну строку',
    CsvAccountCurrencyMismatch(:final accountName, :final accountCurrency) =>
      'валюта ${error.value} не совпадает с валютой счёта '
          '${_quoted(accountName)} '
          '— у него $accountCurrency',
    CsvTransferToAccountIdNotFound() =>
      'счёт с ID «${error.value}» не найден. '
          'Укажите имя счёта в колонке «$csvColumnTransferAccount»',
    CsvTransferCurrencyNoOpeningBalance() =>
      'перевод в валюте ${error.value}: в файле нет начального остатка '
          'счёта в этой валюте',
    CsvRecurringColumnOnOperation(:final column) =>
      'в колонке «$column» стоит $value — у обычной операции она должна быть '
          'пустой. Похоже, колонки съехали',
    CsvInvalidRepeat() =>
      value == null
          ? 'не указан повтор — нужно «$csvRepeatWeek», «$csvRepeatMonth» '
                'или «$csvRepeatYear»'
          : 'повтор $value — нужно «$csvRepeatWeek», «$csvRepeatMonth» '
                'или «$csvRepeatYear»',
    CsvEveryOutOfRange() =>
      'в колонке «$csvColumnEvery» ${value ?? 'пусто'} — нужно целое число '
          'от $recurringEveryMin до $recurringEveryMax или пусто',
    CsvInvalidUntil() =>
      'в колонке «$csvColumnUntil» $value — нужна настоящая дата в виде '
          'ДД.ММ.ГГГГ или пусто',
    CsvUntilBeforeStart() =>
      'в колонке «$csvColumnUntil» $value — это раньше даты первого платежа',
    CsvInvalidRemind() =>
      'в колонке «$csvColumnRemind» ${value ?? 'пусто'} — нужно '
          '«$csvRemindYes», «$csvRemindNo» или пусто',
    CsvRecurringZeroAmount() =>
      'сумма $value — у регулярного платежа нужна сумма больше нуля',
    CsvRecurringTitle() =>
      value == null
          ? 'у регулярного платежа не указано название '
                '(колонка «$csvColumnNote»)'
          : 'название регулярного платежа длиннее $recurringTitleMaxLength '
                'символов',
    CsvRecurringArchivedLink(:final link) => switch (link) {
      CsvArchivedLink.account =>
        'регулярный платёж привязан к архивному счёту ${value ?? ''}: '
            'верните его из архива или очистите ячейку с ID',
      CsvArchivedLink.category =>
        'регулярный платёж привязан к архивной категории ${value ?? ''}: '
            'верните её из архива или очистите ячейку с ID',
      CsvArchivedLink.subcategory =>
        'регулярный платёж привязан к архивной подкатегории ${value ?? ''}: '
            'верните её из архива или очистите ячейку с ID',
    },
    CsvTransferNoAccount() => 'у перевода не указан счёт',
    CsvTransferNoToAccount() => 'у перевода не указан счёт зачисления',
    CsvTransferSameAccount() => 'у перевода счёт и счёт зачисления совпадают',
    CsvTransferZeroAmount() =>
      'сумма $value — у перевода нужна сумма больше нуля',
    CsvTransferWithCategory() =>
      'у перевода категория $value — ячейка должна быть пустой. '
          'Похоже, колонки съехали',
    CsvAccountIdNotFound() =>
      'счёт с ID «${error.value}» не найден. '
          'Укажите имя счёта в колонке «$csvColumnAccount»',
    CsvEmptyCategory() => 'не указана категория',
    CsvCategoryTooLong() => 'категория длиннее $categoryNameMaxLength символов',
    CsvSubcategoryTooLong() =>
      'подкатегория длиннее $categoryNameMaxLength символов',
    CsvNoteTooLong() =>
      'комментарий длиннее $transactionNoteMaxLength символов',
    CsvInvalidId(:final column) =>
      'в колонке «${_idColumnName(column)}» не ID. Очистите эту ячейку',
    CsvDuplicateTransactionId() =>
      '«$csvColumnTransactionId» повторяется: такой уже есть выше в файле',
    CsvCategoryKindMismatch() =>
      '«$csvColumnCategoryId» указывает на категорию другого типа '
          '(доход вместо расхода или наоборот). Очистите эту ячейку',
    CsvCategoryIdIsSubcategory() =>
      '«$csvColumnCategoryId» указывает на подкатегорию. Очистите эту ячейку',
    CsvSubcategoryWrongParent() =>
      '«$csvColumnSubcategoryId» указывает на подкатегорию другой категории. '
          'Очистите эту ячейку',
    CsvExtraCells(:final value) =>
      value == ','
          ? 'ячеек больше, чем колонок. Похоже, сумма или текст с запятой '
                'без кавычек: нужно "350,50"'
          : 'ячеек больше, чем колонок. Похоже, в тексте есть «;» '
                'без кавычек вокруг ячейки',
  };
}

/// Короткая причина для суммы. Тексты ввода суммы (`amountFailureMessage`)
/// говорят о поле и кнопках экрана, здесь нужны короче и про файл.
String _amountReason(CsvInvalidAmount error) => switch (error.failure) {
  AmountParseFailure.empty => 'нет цифр',
  AmountParseFailure.notANumber => 'не число',
  AmountParseFailure.negative => 'лишний минус',
  AmountParseFailure.tooManyDecimals => _decimalsReason(error),
  AmountParseFailure.tooManySeparators => 'слишком много запятых или точек',
  AmountParseFailure.tooLarge =>
    'слишком большая (не больше ${_maxAmountText(error)})',
};

/// Лишние цифры после запятой: сколько можно — у валюты строки.
String _decimalsReason(CsvInvalidAmount error) {
  final digits = error.currencyDigits;
  if (error.digitsFromFile) return 'не больше $digits цифр после запятой';
  if (digits == 0) {
    return 'у ${error.currencyCode} не бывает цифр после запятой';
  }
  final noun = pluralRu(digits, 'цифры', 'цифр', 'цифр');
  return 'у ${error.currencyCode} не больше $digits $noun после запятой';
}

/// Предел суммы в валюте строки: «1 000 000 000 000,00 ₽», «1 000 000,00 BTC».
String _maxAmountText(CsvInvalidAmount error) {
  final info = currencyInfoFor(
    error.currencyCode,
    digits: error.currencyDigits,
  );
  return formatMoney(
    Money.fromMinor(maxInputMinorUnits, error.currencyCode),
    currency: info,
  );
}

String _idColumnName(CsvIdColumn column) => switch (column) {
  CsvIdColumn.transaction => csvColumnTransactionId,
  CsvIdColumn.category => csvColumnCategoryId,
  CsvIdColumn.subcategory => csvColumnSubcategoryId,
  CsvIdColumn.account => csvColumnAccountId,
  CsvIdColumn.transferAccount => csvColumnTransferAccountId,
};

/// Значение в кавычках-ёлочках; длинное обрезается с «…»; пустое — `null`.
String? _quoted(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  final runes = trimmed.runes.toList();
  final short = runes.length <= _quotedMaxLength
      ? trimmed
      : '${String.fromCharCodes(runes.take(_quotedMaxLength))}…';
  return '«$short»';
}
