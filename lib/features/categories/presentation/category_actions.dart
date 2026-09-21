import 'dart:async';

import 'package:flutter/material.dart';
import 'package:money_app/core/ui/category_rule_text.dart';
import 'package:money_app/features/categories/domain/categories_repository.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_rules.dart';
import 'package:money_app/features/categories/presentation/category_list.dart';

/// Действия «В архив», «Вернуть» и перестановка, общие для экранов
/// «Категории» и «Подкатегории»: запись в репозиторий, защита от двойных тапов,
/// сообщения об ошибках и об архиве с кнопкой «Вернуть».
mixin CategoryActions<T extends StatefulWidget> on State<T> {
  CategoriesRepository get categoriesRepository;

  /// Текст сообщения после отправки [name] в архив.
  String archivedMessage(String name);

  /// Строки, по которым сейчас идёт запись: второй тап игнорируется.
  final _pending = <String>{};

  /// Другой экран (форма, список подкатегорий) уже открыт и ещё не закрыт.
  bool _routeOpen = false;

  /// Открывает другой экран через [open] (Future завершается, когда его
  /// закрыли). Пока он открыт, повторный тап (двойной) второго не открывает.
  Future<void> openOnce(Future<void> Function() open) async {
    if (_routeOpen) return;
    _routeOpen = true;
    try {
      await open();
    } finally {
      _routeOpen = false;
    }
  }

  /// True, если запись удалась; иначе показано сообщение об ошибке.
  /// [messenger] берётся заранее, пока экран смонтирован: кнопка «Вернуть» в
  /// сообщении живёт и после ухода с экрана, а к уничтоженному контексту
  /// обращаться нельзя.
  /// [restoring]: отказ из-за дубля имени при возврате из архива объясняется
  /// отдельным текстом.
  Future<bool> _change(
    Category category,
    Future<void> Function(String id) action,
    ScaffoldMessengerState messenger, {
    bool restoring = false,
  }) async {
    if (!_pending.add(category.id)) return false;
    try {
      await action(category.id);
      return true;
    } on CategoryRuleException catch (error) {
      final subcategory = category.parentId != null;
      _showError(
        messenger,
        restoring && error.rule == CategoryRule.duplicateName
            ? (subcategory
                  ? subcategoryRestoreDuplicateText
                  : categoryRestoreDuplicateText)
            : categoryRuleMessage(error.rule, subcategory: subcategory),
      );
    } on Object {
      // Сбой базы и всё прочее: человек исправить не может.
      _showError(messenger, categorySaveFailedText);
    } finally {
      _pending.remove(category.id);
    }
    return false;
  }

  /// [messenger] передаёт «Вернуть» из сообщения (экрана к тому времени может
  /// уже не быть); из строки списка его берём из контекста.
  Future<void> restoreCategory(
    Category category, [
    ScaffoldMessengerState? messenger,
  ]) => _change(
    category,
    categoriesRepository.restore,
    messenger ?? ScaffoldMessenger.of(context),
    restoring: true,
  );

  Future<void> archiveCategory(Category category) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await _change(category, categoriesRepository.archive, messenger);
    if (!ok || !mounted) return;
    // Прежнее сообщение скрываем: при быстрых нажатиях они не копятся.
    // `persist: false`: у сообщения с кнопкой иначе время не отсчитывается.
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(archivedMessage(category.name)),
          duration: categoriesArchivedDuration,
          persist: false,
          action: SnackBarAction(
            label: categoriesUndoAction,
            onPressed: () => unawaited(restoreCategory(category, messenger)),
          ),
        ),
      );
  }

  /// Записывает новый порядок живых строк. `false` при любой ошибке
  /// (сообщение показано).
  Future<bool> reorderCategories(List<String> orderedIds) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await categoriesRepository.reorder(orderedIds);
      return true;
    } on Object {
      _showError(messenger, categorySaveFailedText);
      return false;
    }
  }

  /// Без проверки `mounted`: [messenger] корневой и живёт после ухода с экрана,
  /// а ошибка «Вернуть» должна быть видна и тогда.
  void _showError(ScaffoldMessengerState messenger, String text) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }
}
