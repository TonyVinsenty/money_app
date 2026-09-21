import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:money_app/core/id/id_generator.dart';
import 'package:money_app/core/ui/category_icons.dart';
import 'package:money_app/core/ui/category_rule_text.dart';
import 'package:money_app/core/ui/runes_length_formatter.dart';
import 'package:money_app/features/categories/domain/categories_repository.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/categories/domain/category_rules.dart';

/// Заголовки экрана формы.
const categoryFormCreateTitle = 'Новая категория';
const categoryFormRenameTitle = 'Переименовать категорию';

/// Подписи полей и кнопок формы.
const categoryFormNameLabel = 'Название';
const categoryFormKindTitle = 'Вид';
const categoryFormKindExpense = 'Расход';
const categoryFormKindIncome = 'Доход';
const categoryFormIconTitle = 'Иконка';
const categoryFormSaveLabel = 'Сохранить';

/// Подпись иконки в сетке для скринридера: «Иконка: Кофе, выбрана».
String categoryFormIconLabel(String iconName, {required bool selected}) =>
    selected ? 'Иконка: $iconName, выбрана' : 'Иконка: $iconName';

/// Форма категории: создание новой или переименование существующей.
///
/// При создании человек вводит имя, выбирает вид («Расход» / «Доход»; сначала
/// стоит вид открытой вкладки [initialKind]) и иконку из фиксированного набора.
/// При переименовании ([renaming] задана) есть только имя: вид и иконку
/// репозиторий не меняет.
///
/// Правила проверяет `domain` и репозиторий (пустое или длинное имя, дубль);
/// форма только показывает их текстом под полем. Успех закрывает экран, ошибка
/// оставляет его открытым.
class CategoryFormScreen extends StatefulWidget {
  const CategoryFormScreen({
    required this.categories,
    required this.idGenerator,
    required this.initialKind,
    this.renaming,
    super.key,
  });

  final CategoriesRepository categories;

  /// Откуда берётся id новой категории.
  final IdGenerator idGenerator;

  /// Предвыбранный вид при создании (при переименовании не используется).
  final CategoryKind initialKind;

  /// Категория, которую переименовываем; `null` — создаём новую.
  final Category? renaming;

  @override
  State<CategoryFormScreen> createState() => _CategoryFormScreenState();
}

class _CategoryFormScreenState extends State<CategoryFormScreen> {
  late final TextEditingController _name;
  late CategoryKind _kind;

  /// Иконка по умолчанию — первая в наборе.
  String _iconKey = categoryIconKeys.first;

  /// Идёт сохранение (или оно уже удалось): повторный тап по «Сохранить»
  /// игнорируется. После успеха флаг не сбрасывается: экран закрывается.
  bool _saving = false;

  /// Ошибка правила про имя: показывается под полем.
  String? _nameError;

  /// Общая ошибка сохранения: показывается над кнопкой.
  String? _saveError;

  bool get _isRename => widget.renaming != null;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.renaming?.name ?? '');
    _kind = widget.renaming?.kind ?? widget.initialKind;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// Порядок новой категории: в конец своего вида, после всех, включая
  /// архивные (номера не должны повторяться).
  Future<int> _nextSortOrder() async {
    final all = await widget.categories.watchAll().first;
    var next = 0;
    for (final c in all) {
      if (c.isTopLevel && c.kind == _kind) {
        next = math.max(next, c.sortOrder + 1);
      }
    }
    return next;
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _nameError = null;
      _saveError = null;
    });
    // Navigator берём до первого await: после закрытия экрана его context
    // использовать нельзя.
    final navigator = Navigator.of(context);
    try {
      final renaming = widget.renaming;
      if (renaming != null) {
        await widget.categories.rename(renaming.id, _name.text);
      } else {
        final sortOrder = await _nextSortOrder();
        await widget.categories.create(
          Category.topLevel(
            id: widget.idGenerator.newId(),
            kind: _kind,
            name: _name.text,
            iconKey: _iconKey,
            sortOrder: sortOrder,
          ),
        );
      }
      // Экран могли закрыть кнопкой «Назад», пока шла запись: закрывать нечего
      // (иначе закрылся бы чужой экран).
      if (!mounted) return;
      navigator.pop();
      return;
    } on CategoryRuleException catch (error) {
      if (!mounted) return;
      final text = categoryRuleMessage(error.rule);
      setState(() {
        _saving = false;
        switch (error.rule) {
          case CategoryRule.emptyName:
          case CategoryRule.nameTooLong:
          case CategoryRule.duplicateName:
            _nameError = text;
          case CategoryRule.emptyIconKey:
          case CategoryRule.negativeSortOrder:
          case CategoryRule.parentMustBeTopLevel:
          case CategoryRule.kindMismatch:
            _saveError = text;
        }
      });
    } on Object {
      // Сбой базы и всё прочее: человек исправить не может.
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = categorySaveFailedText;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isRename ? categoryFormRenameTitle : categoryFormCreateTitle,
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _name,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.done,
                      inputFormatters: const [
                        RunesLengthFormatter(categoryNameMaxLength),
                      ],
                      decoration: InputDecoration(
                        labelText: categoryFormNameLabel,
                        errorText: _nameError,
                        errorMaxLines: 3,
                        // Свой счётчик: встроенный считает не так, как domain.
                        counterText:
                            '${runesLength(_name.text)}/$categoryNameMaxLength',
                      ),
                      onChanged: (_) => setState(() => _nameError = null),
                      onSubmitted: (_) => unawaited(_save()),
                    ),
                    if (!_isRename) ...[
                      const SizedBox(height: 16),
                      Text(
                        categoryFormKindTitle,
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<CategoryKind>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(
                            value: CategoryKind.expense,
                            label: Text(categoryFormKindExpense),
                          ),
                          ButtonSegment(
                            value: CategoryKind.income,
                            label: Text(categoryFormKindIncome),
                          ),
                        ],
                        selected: {_kind},
                        onSelectionChanged: (selection) =>
                            setState(() => _kind = selection.first),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        categoryFormIconTitle,
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          for (final key in categoryIconKeys)
                            _IconChoice(
                              key: ValueKey<String>('icon-$key'),
                              iconKey: key,
                              selected: key == _iconKey,
                              onTap: () => setState(() => _iconKey = key),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_saveError != null)
                    Semantics(
                      liveRegion: true,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          _saveError!,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ),
                    ),
                  FilledButton(
                    onPressed: _saving ? null : () => unawaited(_save()),
                    child: const Text(categoryFormSaveLabel),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Одна иконка в сетке выбора: круглая зона 48 x 48 dp, выбранная выделена
/// цветом и рамкой (не только цветом).
class _IconChoice extends StatelessWidget {
  const _IconChoice({
    required this.iconKey,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String iconKey;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      label: categoryFormIconLabel(
        categoryIconName(iconKey),
        selected: selected,
      ),
      button: true,
      selected: selected,
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected ? colors.primaryContainer : null,
            border: Border.all(
              color: selected ? colors.primary : Colors.transparent,
              width: 2,
            ),
          ),
          child: Icon(
            categoryIconFor(iconKey),
            color: selected
                ? colors.onPrimaryContainer
                : colors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
