import 'package:money_app/features/categories/domain/category_rules.dart';

/// Общий текст, когда сохранить категорию не удалось и человек ничем помочь не
/// может: ошибка программиста, сбой базы, любое неожиданное исключение.
const String categorySaveFailedText =
    'Не удалось сохранить. Попробуйте ещё раз';

/// Русский текст для пользователя по нарушенному правилу категории.
///
/// Исправимые пользователем правила (имя, иконка, дубль) имеют свой понятный
/// текст: он показывается рядом с полем. Правила «не должно случаться»
/// ([CategoryRule.negativeSortOrder], [CategoryRule.parentMustBeTopLevel],
/// [CategoryRule.kindMismatch]) получают запасной [categorySaveFailedText].
/// `switch` без ветки по умолчанию: при новом правиле компилятор потребует
/// добавить текст.
/// [subcategory]: тексты про имя говорят «подкатегория», а не «категория».
String categoryRuleMessage(CategoryRule rule, {bool subcategory = false}) {
  switch (rule) {
    case CategoryRule.emptyName:
      return subcategory
          ? 'Введите название подкатегории'
          : 'Введите название категории';
    case CategoryRule.nameTooLong:
      return 'Название слишком длинное: не больше $categoryNameMaxLength '
          'символов';
    case CategoryRule.emptyIconKey:
      return 'Выберите иконку';
    case CategoryRule.duplicateName:
      return subcategory
          ? 'Такая подкатегория уже есть. Выберите другое название'
          : 'Такая категория уже есть. Выберите другое название';
    case CategoryRule.negativeSortOrder:
    case CategoryRule.parentMustBeTopLevel:
    case CategoryRule.kindMismatch:
      return categorySaveFailedText;
  }
}

/// Отказ вернуть категорию из архива, когда её имя за это время занято другой
/// категорией (правило `duplicateName`). Текст под полем при создании и
/// переименовании остаётся прежним ([categoryRuleMessage]).
const String categoryRestoreDuplicateText =
    'В списке уже есть категория с таким названием. Переименуйте её или '
    'оставьте эту в архиве';

/// То же для подкатегории.
const String subcategoryRestoreDuplicateText =
    'В списке уже есть подкатегория с таким названием. Переименуйте её или '
    'оставьте эту в архиве';

/// Не удалось загрузить подкатегории: общий текст экрана «Подкатегории»,
/// сетки выбора и правки операции.
const String subcategoriesLoadErrorText = 'Не удалось загрузить подкатегории';
