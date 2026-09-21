import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/app/app_services.dart';
import 'package:money_app/features/categories/domain/categories_repository.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/settings/presentation/app_settings_controller.dart';
import 'package:money_app/features/transactions/domain/transactions_repository.dart';

import 'fake_id_generator.dart';
import 'fixed_clock.dart';

/// Пустой фейк репозитория категорий: методы не реализованы, любой вызов
/// бросит ошибку. Годится, когда тесту нужен лишь сам объект («тот же ли он»).
class FakeCategoriesRepository extends Fake implements CategoriesRepository {}

/// Фейк репозитория категорий, у которого работает только `watchTopLevel`:
/// отдаёт то, что тест кладёт в [source], оставляя, как и настоящий репозиторий,
/// только живые категории верхнего уровня нужного вида. Остальные методы
/// бросают ошибку.
class StreamCategoriesRepository extends FakeCategoriesRepository {
  StreamCategoriesRepository(this.source);

  /// Всё, что «лежит в базе»: тест сам решает, когда и что отдать.
  final Stream<List<Category>> source;

  @override
  Stream<List<Category>> watchTopLevel(CategoryKind kind) {
    return source.map(
      (all) => [
        for (final c in all)
          if (c.kind == kind && c.isTopLevel && !c.isArchived) c,
      ],
    );
  }
}

/// Фейк репозитория категорий «в памяти» для экранов «Категории» и формы
/// категории: работают `watchAll`, `create`, `rename`, `archive` и `restore` (с
/// проверкой дубля имени, как у настоящего). Остальные методы бросают ошибку.
class InMemoryCategoriesRepository extends FakeCategoriesRepository {
  InMemoryCategoriesRepository(List<Category> initial)
    : _state = ValueNotifier<List<Category>>(List.of(initial));

  final ValueNotifier<List<Category>> _state;

  /// Сколько раз вызвали `create`, `rename`, `archive` и `restore` (для проверки
  /// «один тап — одна запись»).
  int writes = 0;

  /// Если задан, все записи бросают его (сбой базы).
  Exception? failWith;

  /// Текущее содержимое «базы».
  List<Category> get all => List.unmodifiable(_state.value);

  @override
  Future<void> create(Category category) async {
    writes++;
    final error = failWith;
    if (error != null) throw error;
    Category.checkUniqueName(
      name: category.name,
      kind: category.kind,
      parentId: category.parentId,
      existing: _state.value,
    );
    _state.value = [..._state.value, category];
  }

  @override
  Future<void> rename(String id, String newName) async {
    writes++;
    final error = failWith;
    if (error != null) throw error;
    final name = Category.checkedName(newName);
    final target = _state.value.firstWhere((c) => c.id == id);
    Category.checkUniqueName(
      name: name,
      kind: target.kind,
      parentId: target.parentId,
      existing: _state.value,
      selfId: id,
    );
    _state.value = [
      for (final c in _state.value)
        if (c.id == id) c.copyWith(name: name) else c,
    ];
  }

  /// Аргументы всех вызовов `reorder` (в том числе неудачных).
  final reorderCalls = <List<String>>[];

  /// Если задан, `reorder` ждёт его, прежде чем записать (запись «в пути»).
  Future<void>? reorderGate;

  /// Как настоящий: переданные категории получают номера `0..n-1`, остальные
  /// «братья» (архивные) следуют за ними в прежнем порядке. `sortOrder` не
  /// хранится отдельно от порядка списка, поэтому переписываем сам список.
  @override
  Future<void> reorder(List<String> orderedIds) async {
    reorderCalls.add(List.of(orderedIds));
    await reorderGate;
    final error = failWith;
    if (error != null) throw error;
    final byId = {for (final c in _state.value) c.id: c};
    final first = byId[orderedIds.first]!;
    bool sibling(Category c) =>
        c.kind == first.kind && c.parentId == first.parentId;
    final ordered = [for (final id in orderedIds) byId[id]!];
    final rest = [
      for (final c in _state.value)
        if (sibling(c) && !orderedIds.contains(c.id)) c,
    ];
    final others = [
      for (final c in _state.value)
        if (!sibling(c)) c,
    ];
    _state.value = [...ordered, ...rest, ...others];
  }

  void dispose() => _state.dispose();

  @override
  Stream<List<Category>> watchAll() => Stream.multi((controller) {
    void push() => controller.add(List.of(_state.value));
    push();
    _state.addListener(push);
    controller.onCancel = () => _state.removeListener(push);
  });

  Future<void> _replace(String id, Category Function(Category) change) async {
    writes++;
    final error = failWith;
    if (error != null) throw error;
    _state.value = [
      for (final c in _state.value)
        if (c.id == id) change(c) else c,
    ];
  }

  @override
  Future<void> archive(String id) =>
      _replace(id, (c) => c.archived(DateTime.utc(2026, 9, 20)));

  @override
  Future<void> restore(String id) async {
    final target = _state.value.firstWhere((c) => c.id == id);
    Category.checkUniqueName(
      name: target.name,
      kind: target.kind,
      parentId: target.parentId,
      existing: _state.value,
      selfId: id,
    );
    await _replace(id, (c) => c.restored());
  }
}

/// Пустой фейк репозитория операций (см. [FakeCategoriesRepository]).
class FakeTransactionsRepository extends Fake
    implements TransactionsRepository {}

/// Набор сервисов из фейков: то, что тест кладёт в `AppScope`.
///
/// [settings] передаёт сам тест: кто создал контроллер, тот и вызывает
/// `dispose`. Репозитории можно заменить своими, иначе подставляются пустые
/// фейки.
AppServices fakeAppServices({
  required AppSettingsController settings,
  CategoriesRepository? categories,
  TransactionsRepository? transactions,
}) {
  return AppServices(
    categories: categories ?? FakeCategoriesRepository(),
    transactions: transactions ?? FakeTransactionsRepository(),
    settings: settings,
    clock: FixedClock(DateTime.utc(2026, 9, 20, 12)),
    idGenerator: FakeIdGenerator(),
  );
}
