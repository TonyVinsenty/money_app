import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';

/// Хранилище категорий: что можно попросить, но не как это устроено.
///
/// Интерфейс живёт в `domain`, а реализация (на drift) — в `data`. Экраны
/// и правила знают только этот интерфейс, поэтому хранилище можно заменить
/// или подменить в тестах фейком.
///
/// Общие ошибки методов:
/// - `CategoryRuleException` — нарушено правило категории;
/// - `DataCorruptedException` — данные в хранилище испорчены и не
///   превращаются в корректную `Category`.
abstract interface class CategoriesRepository {
  /// Поток «живых» категорий верхнего уровня вида [kind], по `sortOrder`.
  ///
  /// В потоке нет архивных и удалённых категорий. Поток сам выдаёт новый
  /// список после каждой записи.
  Stream<List<Category>> watchTopLevel(CategoryKind kind);

  /// Поток «живых» подкатегорий родителя [parentId], по `sortOrder`.
  ///
  /// В потоке нет архивных и удалённых подкатегорий.
  Stream<List<Category>> watchSubcategories(String parentId);

  /// Находит категорию по [id] или возвращает `null`.
  ///
  /// Архивные категории возвращаются (они нужны, чтобы показать имя в
  /// старых операциях). Мягко удалённые не возвращаются.
  Future<Category?> findById(String id);

  /// Есть ли в хранилище хоть одна строка категорий.
  ///
  /// Учитываются и архивные, и удалённые. Нужна для засева категорий по
  /// умолчанию: пользователь мог всё архивировать, и заново засевать нельзя.
  Future<bool> hasAny();

  /// Сохраняет новую [category].
  ///
  /// Для подкатегории проверяет связь с родителем (`Category.checkParent`):
  /// `CategoryRuleException`, если родитель не верхнего уровня или вид
  /// не совпадает.
  Future<void> create(Category category);

  /// Переименовывает категорию [id] в [newName].
  ///
  /// Имя проходит те же проверки, что и при создании
  /// (`CategoryRuleException`).
  Future<void> rename(String id, String newName);

  /// Переставляет «братьев» — категории одного уровня и одного вида.
  ///
  /// Порядок задаёт список [orderedIds]; после вызова `sortOrder` равен
  /// `0..n-1` в этом порядке.
  Future<void> reorder(List<String> orderedIds);

  /// Отправляет категорию [id] в архив.
  ///
  /// Она пропадает из «живых» потоков, но операции по ней остаются целыми.
  Future<void> archive(String id);

  /// Возвращает категорию [id] из архива.
  Future<void> restore(String id);
}
