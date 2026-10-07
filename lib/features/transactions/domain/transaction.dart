import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/transactions/domain/category_kind_mapping.dart';
import 'package:money_app/features/transactions/domain/transaction_rules.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

/// Операция: один доход или один расход.
///
/// Объект неизменяемый: «изменить» его можно только получив копию
/// ([copyWith], [withNote], [withCategory]). Собственные правила (сумма,
/// момент в UTC, идентификаторы, комментарий) проверяются при создании и при
/// каждой копии, поэтому испорченная [Transaction] в программе существовать
/// не может.
///
/// Есть два способа создания:
/// - [Transaction.new] для восстановления из хранилища. Категорий под рукой
///   там нет, поэтому он проверяет только собственные правила операции;
/// - [Transaction.create] для новой операции из формы. Категории уже
///   загружены, поэтому он дополнительно проверяет связи с ними.
final class Transaction {
  /// Восстанавливает операцию из хранилища (или создаёт по готовым полям).
  ///
  /// Проверяет только собственные правила и не знает категорий. Бросает
  /// [TransactionRuleException]: [TransactionRule.negativeAmount] (ноль
  /// допустим), [TransactionRule.occurredAtNotUtc],
  /// [TransactionRule.emptyCategoryId] (для [categoryId] и для заданной
  /// [subcategoryId]) и [TransactionRule.noteTooLong]. Комментарий
  /// сохраняется без пробелов по краям, пустой становится `null`.
  Transaction({
    required this.id,
    required this.type,
    required Money amount,
    required this.occurredOn,
    required DateTime occurredAt,
    required String categoryId,
    String? subcategoryId,
    String? note,
    this.accountId,
  }) : amount = _checkedAmount(amount),
       occurredAt = _checkedOccurredAt(occurredAt),
       categoryId = _checkedId(categoryId),
       subcategoryId = subcategoryId == null ? null : _checkedId(subcategoryId),
       note = _checkedNote(note);

  /// Новая операция по загруженным категориям.
  ///
  /// [Transaction.categoryId] и [Transaction.subcategoryId] берутся из
  /// [category] и [subcategory]. Кроме собственных правил проверяет связи
  /// (см. [withCategory]).
  factory Transaction.create({
    required String id,
    required TransactionType type,
    required Money amount,
    required DateOnly occurredOn,
    required DateTime occurredAt,
    required Category category,
    Category? subcategory,
    String? note,
    String? accountId,
  }) {
    _checkLinks(type, category, subcategory);
    return Transaction(
      id: id,
      type: type,
      amount: amount,
      occurredOn: occurredOn,
      occurredAt: occurredAt,
      categoryId: category.id,
      subcategoryId: subcategory?.id,
      note: note,
      accountId: accountId,
    );
  }

  /// Неизменяемый идентификатор (UUID v7, создаётся вне базы).
  final String id;

  /// Доход или расход. Направление денег задаёт именно он, а не знак суммы.
  final TransactionType type;

  /// Сумма: не отрицательная (ноль допустим), с кодом валюты.
  final Money amount;

  /// Локальный календарный день операции, каким его видел пользователь.
  final DateOnly occurredOn;

  /// Момент операции в UTC.
  final DateTime occurredAt;

  /// Идентификатор категории (не пустой).
  final String categoryId;

  /// Идентификатор подкатегории; `null`, если она не выбрана.
  final String? subcategoryId;

  /// Комментарий без пробелов по краям, не длиннее
  /// [transactionNoteMaxLength] символов; `null` — «нет комментария».
  final String? note;

  /// Идентификатор счёта (ADR 0010); `null` — «без счёта». Существование,
  /// архивность и валюту счёта проверяет репозиторий.
  final String? accountId;

  /// Копия с другим счётом (или без счёта, если [accountId] равен `null`).
  Transaction withAccount(String? accountId) {
    return Transaction(
      id: id,
      type: type,
      amount: amount,
      occurredOn: occurredOn,
      occurredAt: occurredAt,
      categoryId: categoryId,
      subcategoryId: subcategoryId,
      note: note,
      accountId: accountId,
    );
  }

  /// Копия с новой суммой, днём или моментом; остальное сохраняется.
  ///
  /// Проверки те же, что при создании.
  Transaction copyWith({
    Money? amount,
    DateOnly? occurredOn,
    DateTime? occurredAt,
  }) {
    return Transaction(
      id: id,
      type: type,
      amount: amount ?? this.amount,
      occurredOn: occurredOn ?? this.occurredOn,
      occurredAt: occurredAt ?? this.occurredAt,
      categoryId: categoryId,
      subcategoryId: subcategoryId,
      note: note,
      accountId: accountId,
    );
  }

  /// Копия с новым комментарием. `null`, пустая строка и одни пробелы
  /// означают «нет комментария».
  Transaction withNote(String? note) {
    return Transaction(
      id: id,
      type: type,
      amount: amount,
      occurredOn: occurredOn,
      occurredAt: occurredAt,
      categoryId: categoryId,
      subcategoryId: subcategoryId,
      note: note,
      accountId: accountId,
    );
  }

  /// Копия с другой подкатегорией (или без неё, если [subcategory] равна
  /// `null`); категория и тип остаются.
  ///
  /// Проверяет связь [subcategory] с операцией: родитель равен
  /// [categoryId] ([TransactionRule.subcategoryNotOfCategory]), вид
  /// соответствует [type] ([TransactionRule.typeKindMismatch]). Архивность
  /// здесь не проверяется (это делает репозиторий).
  Transaction withSubcategory(Category? subcategory) {
    if (subcategory != null) {
      if (subcategory.parentId != categoryId) {
        throw TransactionRuleException(
          TransactionRule.subcategoryNotOfCategory,
        );
      }
      if (subcategory.kind.transactionType != type) {
        throw TransactionRuleException(TransactionRule.typeKindMismatch);
      }
    }
    return Transaction(
      id: id,
      type: type,
      amount: amount,
      occurredOn: occurredOn,
      occurredAt: occurredAt,
      categoryId: categoryId,
      subcategoryId: subcategory?.id,
      note: note,
      accountId: accountId,
    );
  }

  /// Копия с новым типом и/или категорией.
  ///
  /// Так реализована «смена типа в правке со сбросом категории»: вызывающий
  /// код обязан передать новую категорию нового вида (и новую подкатегорию
  /// или `null`), старая подкатегория не переносится. Проверяет связи:
  /// - [category] верхнего уровня, иначе
  ///   [TransactionRule.categoryMustBeTopLevel];
  /// - вид [category] соответствует [type], иначе
  ///   [TransactionRule.typeKindMismatch];
  /// - [subcategory], если есть, — дочерняя для [category]
  ///   ([TransactionRule.subcategoryNotOfCategory]) и того же вида
  ///   ([TransactionRule.typeKindMismatch]).
  Transaction withCategory({
    required TransactionType type,
    required Category category,
    Category? subcategory,
  }) {
    _checkLinks(type, category, subcategory);
    return Transaction(
      id: id,
      type: type,
      amount: amount,
      occurredOn: occurredOn,
      occurredAt: occurredAt,
      categoryId: category.id,
      subcategoryId: subcategory?.id,
      note: note,
      accountId: accountId,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is Transaction &&
            other.id == id &&
            other.type == type &&
            other.amount == amount &&
            other.occurredOn == occurredOn &&
            other.occurredAt == occurredAt &&
            other.categoryId == categoryId &&
            other.subcategoryId == subcategoryId &&
            other.note == note &&
            other.accountId == accountId;
  }

  @override
  int get hashCode => Object.hash(
    id,
    type,
    amount,
    occurredOn,
    occurredAt,
    categoryId,
    subcategoryId,
    note,
    accountId,
  );

  @override
  String toString() {
    return 'Transaction(id: $id, type: ${type.name}, amount: $amount, '
        'occurredOn: $occurredOn, occurredAt: $occurredAt, '
        'categoryId: $categoryId, subcategoryId: $subcategoryId, '
        'note: $note, accountId: $accountId)';
  }

  static void _checkLinks(
    TransactionType type,
    Category category,
    Category? subcategory,
  ) {
    if (!category.isTopLevel) {
      throw TransactionRuleException(TransactionRule.categoryMustBeTopLevel);
    }
    if (category.kind.transactionType != type) {
      throw TransactionRuleException(TransactionRule.typeKindMismatch);
    }
    if (subcategory != null) {
      if (subcategory.parentId != category.id) {
        throw TransactionRuleException(
          TransactionRule.subcategoryNotOfCategory,
        );
      }
      if (subcategory.kind != category.kind) {
        throw TransactionRuleException(TransactionRule.typeKindMismatch);
      }
    }
  }

  static Money _checkedAmount(Money amount) {
    if (amount.isNegative) {
      throw TransactionRuleException(TransactionRule.negativeAmount);
    }
    return amount;
  }

  static DateTime _checkedOccurredAt(DateTime occurredAt) {
    if (!occurredAt.isUtc) {
      throw TransactionRuleException(TransactionRule.occurredAtNotUtc);
    }
    return occurredAt;
  }

  static String _checkedId(String categoryId) {
    if (categoryId.trim().isEmpty) {
      throw TransactionRuleException(TransactionRule.emptyCategoryId);
    }
    return categoryId;
  }

  static String? _checkedNote(String? note) {
    final normalized = normalizeTransactionNote(note);
    if (normalized != null &&
        normalized.runes.length > transactionNoteMaxLength) {
      throw TransactionRuleException(TransactionRule.noteTooLong);
    }
    return normalized;
  }
}
