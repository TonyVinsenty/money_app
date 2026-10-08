import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:money_app/core/id/id_generator.dart';
import 'package:money_app/core/ui/category_icon_view.dart';
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
String subcategoryFormCreateTitle(String parentName) =>
    'Новая подкатегория · $parentName';
const subcategoryFormRenameTitle = 'Переименовать подкатегорию';

/// Подписи полей и кнопок формы.
const categoryFormNameLabel = 'Название';
const categoryFormKindTitle = 'Тип';
const categoryFormKindExpense = 'Расход';
const categoryFormKindIncome = 'Доход';
const categoryFormIconTitle = 'Иконка';
const categoryFormSaveLabel = 'Сохранить';

/// Строка только для чтения при переименовании: «Тип: Расход».
String categoryFormKindReadOnly(CategoryKind kind) =>
    '$categoryFormKindTitle: ${kind == CategoryKind.income ? categoryFormKindIncome : categoryFormKindExpense}';

/// Подпись иконки в сетке для скринридера: «Иконка: Кофе». Выбранность
/// говорит признак `selected`, в подпись её не кладём.
String categoryFormIconLabel(String iconName) => 'Иконка: $iconName';

/// Форма категории: создание новой или переименование существующей.
///
/// При создании человек вводит имя, выбирает вид («Расход» / «Доход»; сначала
/// стоит вид открытой вкладки [initialKind]) и иконку из фиксированного набора.
/// При переименовании ([renaming] задана) есть только имя: тип показан строкой
/// «Тип: Расход» без выбора, вид и иконку репозиторий не меняет.
///
/// Если задан [parent], форма работает с подкатегорией этой категории: есть
/// только поле имени (вид и иконка наследуются от родителя, порядок — в конец
/// списка подкатегорий родителя).
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
    this.parent,
    super.key,
  });

  final CategoriesRepository categories;

  /// Откуда берётся id новой категории.
  final IdGenerator idGenerator;

  /// Предвыбранный вид при создании (при переименовании не используется).
  final CategoryKind initialKind;

  /// Категория, которую переименовываем; `null` — создаём новую.
  final Category? renaming;

  /// Родитель, если это форма подкатегории; `null` — форма категории.
  final Category? parent;

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
  bool get _isSubcategory => widget.parent != null;

  /// Форма подкатегории: создание (есть parent) или переименование строки с
  /// родителем.
  bool get _isSubcategoryForm =>
      _isSubcategory || widget.renaming?.parentId != null;

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
      final parent = widget.parent;
      if (renaming != null) {
        await widget.categories.rename(renaming.id, _name.text);
      } else if (parent != null) {
        final sortOrder = await widget.categories.nextSortOrder(
          parent.kind,
          parentId: parent.id,
        );
        await widget.categories.create(
          Category.subcategoryOf(
            id: widget.idGenerator.newId(),
            parent: parent,
            name: _name.text,
            iconKey: parent.iconKey,
            sortOrder: sortOrder,
          ),
        );
      } else {
        final sortOrder = await widget.categories.nextSortOrder(_kind);
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
      final text = categoryRuleMessage(
        error.rule,
        subcategory: _isSubcategoryForm,
      );
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
          _isSubcategory
              ? (_isRename
                    ? subcategoryFormRenameTitle
                    : subcategoryFormCreateTitle(widget.parent!.name))
              : (_isRename ? categoryFormRenameTitle : categoryFormCreateTitle),
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
                      autofocus: true,
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
                    // У подкатегории только имя: вид и иконка от родителя.
                    if (_isRename && !_isSubcategory) ...[
                      const SizedBox(height: 16),
                      Text(
                        categoryFormKindReadOnly(_kind),
                        style: theme.textTheme.bodyLarge,
                      ),
                    ] else if (!_isRename && !_isSubcategory) ...[
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
                      // Ровная сетка: столбцов сколько влезает по 56 dp (не меньше
                      // 4), ширина ячейки считается из доступной ширины.
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final columns = math.max(
                            4,
                            (constraints.maxWidth / 56).floor(),
                          );
                          final cellWidth = (constraints.maxWidth / columns)
                              .floorToDouble();
                          return Wrap(
                            children: [
                              for (final key in categoryIconKeys)
                                SizedBox(
                                  width: cellWidth,
                                  child: Center(
                                    child: _IconChoice(
                                      key: ValueKey<String>('icon-$key'),
                                      iconKey: key,
                                      selected: key == _iconKey,
                                      onTap: () =>
                                          setState(() => _iconKey = key),
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
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
    final name = categoryIconName(iconKey);
    return Semantics(
      label: categoryFormIconLabel(name),
      button: true,
      selected: selected,
      onTap: onTap,
      excludeSemantics: true,
      child: Tooltip(
        message: name,
        excludeFromSemantics: true,
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
            child: CategoryIconView(
              iconKey,
              color: selected
                  ? colors.onPrimaryContainer
                  : colors.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
