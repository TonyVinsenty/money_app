import 'package:drift/drift.dart';
import 'package:money_app/core/database/converters/date_only_converter.dart';
import 'package:money_app/core/database/converters/transaction_type_converter.dart';
import 'package:money_app/core/database/tables/categories.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

/// Операции: доходы и расходы (SQL-имя `transactions`, ADR 0001 и 0004).
///
/// Сумма хранится целым числом в минорных единицах (копейки) и положительной
/// или нулевой; направление денег задаёт колонка `type`, а не знак суммы.
///
/// Чего база НЕ проверяет (это делает слой репозиториев):
/// - что `subcategory_id` указывает на подкатегорию именно той категории,
///   которая записана в `category_id` (`parent_id` подкатегории = `category_id`);
/// - что `category_id` — категория верхнего уровня;
/// - что вид категории (доход/расход) совпадает с `type` операции;
/// - обрезку пробелов в `note` и превращение пустой строки в NULL.
///
/// Индексы частичные: в них попадают только «живые» строки
/// (`deleted_at IS NULL`). `(occurred_on, occurred_at)` покрывает и отбор
/// по дню/периоду, и сортировку «Истории»
/// `ORDER BY occurred_on DESC, occurred_at DESC`; итоги по категориям
/// читают `(category_id, occurred_on)`.
@DataClassName('TransactionRow')
@TableIndex.sql(
  'CREATE INDEX transactions_occurred_on_at ON transactions '
  '(occurred_on, occurred_at) WHERE deleted_at IS NULL',
)
@TableIndex.sql(
  'CREATE INDEX transactions_category_occurred_on ON transactions '
  '(category_id, occurred_on) WHERE deleted_at IS NULL',
)
class Transactions extends Table {
  /// UUID v7, создаётся вне базы (ADR 0001).
  TextColumn get id => text()();

  /// Доход или расход. В базе — текст `income`/`expense`, в коде —
  /// [TransactionType]; превращением занимается конвертер.
  TextColumn get type => text().map(const TransactionTypeConverter())();

  /// Сумма в копейках: целое число, не отрицательное (ноль допустим).
  IntColumn get amountMinor => integer()();

  /// Трёхбуквенный код валюты: три заглавные латинские буквы, например `RUB`.
  TextColumn get currency => text()();

  /// Локальный календарный день операции (ГГГГММДД). Фиксируется при записи и
  /// потом не пересчитывается; по нему считаются «сегодня», неделя и месяц.
  IntColumn get occurredOn => integer().map(const DateOnlyConverter())();

  /// Точный момент операции: миллисекунды эпохи UTC. Нужен для порядка
  /// внутри дня и для будущей синхронизации.
  IntColumn get occurredAt => integer()();

  /// Категория верхнего уровня (внешний ключ на `categories.id`).
  // Два внешних ключа ведут в одну таблицу, поэтому у каждого своё имя
  // обратной ссылки: без него drift предупреждает о совпадении имён.
  @ReferenceName('transactionsInCategory')
  TextColumn get categoryId => text().references(Categories, #id)();

  /// Подкатегория или NULL (внешний ключ на `categories.id`).
  @ReferenceName('transactionsInSubcategory')
  TextColumn get subcategoryId =>
      text().nullable().references(Categories, #id)();

  /// Комментарий от 1 до 200 символов; NULL — комментария нет (пустая строка
  /// запрещена, обрезку пробелов делает репозиторий).
  TextColumn get note => text().nullable()();

  IntColumn get createdAt => integer()();

  IntColumn get updatedAt => integer()();

  /// Мягкое удаление (миллисекунды эпохи UTC); NULL — строка «живая».
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  // Ограничения уровня таблицы, а не колонки: `check` на собственный геттер
  // ссылается сам на себя, и анализатор ругается на рекурсию.
  @override
  List<String> get customConstraints => [
    "CHECK (type IN ('income', 'expense'))",
    'CHECK (amount_minor >= 0)',
    // GLOB чувствителен к регистру: 'rub', 'РУБ', '123' и 4 символа не пройдут.
    "CHECK (currency GLOB '[A-Z][A-Z][A-Z]')",
    // Только границы разумного диапазона DateOnly (1.01.1 .. 31.12.9999).
    // Мусор внутри диапазона, например 20261332, база не поймает: это
    // делает DateOnlyConverter.
    'CHECK (occurred_on BETWEEN 10101 AND 99991231)',
    // Пустая строка запрещена: «нет комментария» — это NULL.
    'CHECK (note IS NULL OR length(note) BETWEEN 1 AND 200)',
  ];
}
