import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/categories/domain/category_rules.dart';

/// Категория доходов или расходов, либо подкатегория внутри категории.
///
/// Вложенность ровно в один уровень: у категории верхнего уровня
/// [parentId] равен `null`, у подкатегории он указывает на родителя, а
/// своих подкатегорий у неё быть не может.
///
/// Объект неизменяемый: «изменить» его можно только получив копию
/// ([copyWith], [archived], [restored]). Собственные правила (имя, ключ
/// иконки, порядок) проверяются при создании и при каждой копии, поэтому
/// испорченная [Category] в программе существовать не может.
///
/// Есть три способа создания:
/// - [Category.topLevel] для новой категории верхнего уровня;
/// - [Category.subcategoryOf] для новой подкатегории (родитель известен);
/// - [Category.new] для восстановления из хранилища. Родителя он не знает и
///   проверяет только собственные правила; связь с родителем проверяет
///   [Category.checkParent].
final class Category {
  /// Восстанавливает категорию из хранилища (или создаёт по готовым полям).
  ///
  /// Проверяет только собственные правила и не знает родителя. Бросает
  /// [CategoryRuleException] (пустое или слишком длинное имя, пустой
  /// [iconKey], отрицательный [sortOrder]) и [ArgumentError], если
  /// [archivedAt] не в UTC. Имя сохраняется уже без пробелов по краям.
  Category({
    required this.id,
    required this.kind,
    required String name,
    required String iconKey,
    required this.parentId,
    required int sortOrder,
    DateTime? archivedAt,
  }) : name = checkedName(name),
       iconKey = _checkedIconKey(iconKey),
       sortOrder = _checkedSortOrder(sortOrder),
       archivedAt = _checkedArchivedAt(archivedAt);

  /// Новая категория верхнего уровня ([parentId] равен `null`).
  Category.topLevel({
    required String id,
    required CategoryKind kind,
    required String name,
    required String iconKey,
    required int sortOrder,
  }) : this(
         id: id,
         kind: kind,
         name: name,
         iconKey: iconKey,
         parentId: null,
         sortOrder: sortOrder,
       );

  /// Новая подкатегория внутри [parent].
  ///
  /// Вид берётся от родителя. Если [parent] сам подкатегория, бросает
  /// [CategoryRuleException] с правилом
  /// [CategoryRule.parentMustBeTopLevel]: вложенность только в один уровень.
  factory Category.subcategoryOf({
    required String id,
    required Category parent,
    required String name,
    required String iconKey,
    required int sortOrder,
  }) {
    if (!parent.isTopLevel) {
      throw CategoryRuleException(CategoryRule.parentMustBeTopLevel);
    }
    return Category(
      id: id,
      kind: parent.kind,
      name: name,
      iconKey: iconKey,
      parentId: parent.id,
      sortOrder: sortOrder,
    );
  }

  /// Проверяет связь [child] с [parent]; её вызывает репозиторий на данных
  /// из хранилища (там родитель и ребёнок читаются отдельно).
  ///
  /// Бросает [CategoryRuleException]: [CategoryRule.parentMustBeTopLevel],
  /// если родитель сам подкатегория, и [CategoryRule.kindMismatch], если
  /// виды разные. Бросает [ArgumentError], если [parent] вообще не родитель
  /// [child] (`child.parentId != parent.id`): это ошибка вызывающего кода.
  static void checkParent(Category child, Category parent) {
    if (child.parentId != parent.id) {
      throw ArgumentError.value(
        parent.id,
        'parent',
        'is not the parent of the category ${child.id}',
      );
    }
    if (!parent.isTopLevel) {
      throw CategoryRuleException(CategoryRule.parentMustBeTopLevel);
    }
    if (parent.kind != child.kind) {
      throw CategoryRuleException(CategoryRule.kindMismatch);
    }
  }

  /// Неизменяемый идентификатор (UUID v7, создаётся вне базы).
  final String id;

  /// Доход или расход.
  final CategoryKind kind;

  /// Имя без пробелов по краям, не пустое, не длиннее
  /// [categoryNameMaxLength] символов.
  final String name;

  /// Строковый ключ иконки (не пустой).
  final String iconKey;

  /// Идентификатор родителя; `null` у категории верхнего уровня.
  final String? parentId;

  /// Порядок среди «братьев» (не отрицательный).
  final int sortOrder;

  /// Момент архивации в UTC; `null`, если категория не в архиве.
  final DateTime? archivedAt;

  /// Категория верхнего уровня (не подкатегория).
  bool get isTopLevel => parentId == null;

  /// Категория в архиве.
  bool get isArchived => archivedAt != null;

  /// Копия с новым именем, иконкой или порядком; остальное сохраняется.
  ///
  /// Проверки те же, что при создании. Вид, родитель и id менять нельзя:
  /// это могло бы нарушить связь с родителем.
  Category copyWith({String? name, String? iconKey, int? sortOrder}) {
    return Category(
      id: id,
      kind: kind,
      name: name ?? this.name,
      iconKey: iconKey ?? this.iconKey,
      parentId: parentId,
      sortOrder: sortOrder ?? this.sortOrder,
      archivedAt: archivedAt,
    );
  }

  /// Копия, отправленная в архив в момент [at] (обязательно UTC, иначе
  /// [ArgumentError]).
  Category archived(DateTime at) {
    return Category(
      id: id,
      kind: kind,
      name: name,
      iconKey: iconKey,
      parentId: parentId,
      sortOrder: sortOrder,
      archivedAt: at,
    );
  }

  /// Копия, возвращённая из архива (`archivedAt` сброшен в `null`).
  Category restored() {
    return Category(
      id: id,
      kind: kind,
      name: name,
      iconKey: iconKey,
      parentId: parentId,
      sortOrder: sortOrder,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is Category &&
            other.id == id &&
            other.kind == kind &&
            other.name == name &&
            other.iconKey == iconKey &&
            other.parentId == parentId &&
            other.sortOrder == sortOrder &&
            other.archivedAt == archivedAt;
  }

  @override
  int get hashCode =>
      Object.hash(id, kind, name, iconKey, parentId, sortOrder, archivedAt);

  @override
  String toString() {
    return 'Category(id: $id, kind: ${kind.name}, name: $name, '
        'iconKey: $iconKey, parentId: $parentId, sortOrder: $sortOrder, '
        'archivedAt: $archivedAt)';
  }

  /// Проверяет имя и возвращает его без пробелов по краям.
  ///
  /// Бросает [CategoryRuleException]: [CategoryRule.emptyName] (пустое имя или
  /// одни пробелы) и [CategoryRule.nameTooLong] (длиннее
  /// [categoryNameMaxLength] символов). Конструктор и [copyWith] используют
  /// именно её; репозиторий вызывает её сам, чтобы переименовать категорию, не
  /// собирая [Category] из (возможно, испорченной) строки хранилища.
  static String checkedName(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      throw CategoryRuleException(CategoryRule.emptyName);
    }
    if (trimmed.runes.length > categoryNameMaxLength) {
      throw CategoryRuleException(CategoryRule.nameTooLong);
    }
    return trimmed;
  }

  static String _checkedIconKey(String iconKey) {
    if (iconKey.trim().isEmpty) {
      throw CategoryRuleException(CategoryRule.emptyIconKey);
    }
    return iconKey;
  }

  static int _checkedSortOrder(int sortOrder) {
    if (sortOrder < 0) {
      throw CategoryRuleException(CategoryRule.negativeSortOrder);
    }
    return sortOrder;
  }

  static DateTime? _checkedArchivedAt(DateTime? archivedAt) {
    if (archivedAt != null && !archivedAt.isUtc) {
      throw ArgumentError.value(archivedAt, 'archivedAt', 'must be in UTC');
    }
    return archivedAt;
  }
}
