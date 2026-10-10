import 'dart:async';

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/app/app_services.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/accounts/domain/accounts_repository.dart';
import 'package:money_app/features/accounts/domain/transfer.dart';
import 'package:money_app/features/accounts/domain/transfers_repository.dart';
import 'package:money_app/features/categories/domain/categories_repository.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/categories/domain/category_rules.dart';
import 'package:money_app/features/csv_import/domain/csv_import_store.dart';
import 'package:money_app/features/csv_import/domain/parse_csv_import.dart';
import 'package:money_app/features/csv_import/domain/plan_csv_import.dart';
import 'package:money_app/features/recurring/domain/recurring_repository.dart';
import 'package:money_app/features/settings/domain/data_eraser.dart';
import 'package:money_app/features/settings/presentation/app_settings_controller.dart';
import 'package:money_app/features/transactions/domain/transactions_repository.dart';

import 'fake_id_generator.dart';
import 'fixed_clock.dart';

/// Фейк репозитория счетов: отдаёт заданные [accounts] и [balances] (по
/// умолчанию пусто), остальные вызовы бросают ошибку.
/// Пустой фейк переводов: любой вызов падает, если тест его не ждал.
class FakeTransfersRepository extends Fake implements TransfersRepository {
  /// Список переводов счёта показывает экран счёта: по умолчанию он пуст.
  @override
  Stream<List<Transfer>> watchForAccount(String accountId) =>
      Stream.value(const []);

  @override
  Stream<List<Transfer>> watchAll() => Stream.value(const []);
}

/// Фейк переводов «в памяти»: `add`, `update`, `softDelete`, `restore`
/// работают над списком [all] (живые переводы). Если задан [failWith], `add`
/// и `update` бросают его.
class InMemoryTransfersRepository extends Fake implements TransfersRepository {
  InMemoryTransfersRepository([List<Transfer> initial = const []])
    : all = List.of(initial);

  final List<Transfer> all;
  final List<Transfer> _deleted = [];
  final _changes = StreamController<void>.broadcast();
  Exception? failWith;

  /// Если задан, `softDelete` и `restore` бросают его.
  Exception? failDeleteWith;

  @override
  Stream<List<Transfer>> watchForAccount(String accountId) =>
      _watch((t) => t.fromAccountId == accountId || t.toAccountId == accountId);

  @override
  Stream<List<Transfer>> watchAll() => _watch((_) => true);

  Stream<List<Transfer>> _watch(bool Function(Transfer) test) =>
      Stream.multi((c) {
        List<Transfer> read() =>
            [
              for (final t in all)
                if (test(t)) t,
            ]..sort((a, b) {
              final byDay = b.occurredOn.compareTo(a.occurredOn);
              if (byDay != 0) return byDay;
              final byMoment = b.occurredAt.compareTo(a.occurredAt);
              return byMoment != 0 ? byMoment : b.id.compareTo(a.id);
            });
        c.add(read());
        final sub = _changes.stream.listen((_) => c.add(read()));
        c.onCancel = sub.cancel;
      });

  @override
  Future<List<Transfer>> findAllLive() async => List.of(all);

  @override
  Future<void> add(Transfer transfer) async {
    if (failWith != null) throw failWith!;
    all.add(transfer);
    _changes.add(null);
  }

  @override
  Future<void> addImported(Transfer transfer) => add(transfer);

  @override
  Future<void> update(Transfer transfer) async {
    if (failWith != null) throw failWith!;
    final i = all.indexWhere((t) => t.id == transfer.id);
    if (i < 0) throw ArgumentError.value(transfer.id, 'id');
    all[i] = transfer;
    _changes.add(null);
  }

  @override
  Future<void> softDelete(String id) async {
    if (failDeleteWith != null) throw failDeleteWith!;
    final i = all.indexWhere((t) => t.id == id);
    if (i >= 0) _deleted.add(all.removeAt(i));
    _changes.add(null);
  }

  @override
  Future<void> restore(String id) async {
    if (failDeleteWith != null) throw failDeleteWith!;
    final i = _deleted.indexWhere((t) => t.id == id);
    if (i >= 0) all.add(_deleted.removeAt(i));
    _changes.add(null);
  }
}

class FakeAccountsRepository extends Fake implements AccountsRepository {
  FakeAccountsRepository({
    this.accounts = const [],
    this.balances = const {},
    this.watchError,
  });

  final List<Account> accounts;
  final Map<String, Money> balances;

  /// Если задан, потоки отдают эту ошибку.
  final Object? watchError;

  @override
  Stream<List<Account>> watchAll() =>
      watchError != null ? Stream.error(watchError!) : Stream.value(accounts);

  @override
  Stream<Map<String, Money>> watchBalances() =>
      watchError != null ? Stream.error(watchError!) : Stream.value(balances);
}

/// Фейк счетов «в памяти»: работают `watchAll`, `watchBalances` (только
/// стартовые остатки плюс [net]), `nextSortOrder`, `create` (с проверкой
/// дубля), `update`, `adjustCurrentBalance`, `archive` и `restore`. Остальное
/// бросает ошибку.
class InMemoryAccountsRepository extends Fake implements AccountsRepository {
  InMemoryAccountsRepository([List<Account> initial = const []])
    : _all = List.of(initial);

  List<Account> _all;
  final _changes = StreamController<void>.broadcast();

  /// Если задан, `create` и `update` бросают его (сбой базы).
  Exception? failWith;

  /// Текущее содержимое «базы».
  List<Account> get all => List.unmodifiable(_all);

  Stream<T> _live<T>(T Function() read) => Stream.multi((c) {
    c.add(read());
    final sub = _changes.stream.listen((_) => c.add(read()));
    c.onCancel = sub.cancel;
  });

  @override
  Stream<List<Account>> watchAll() => _live(() => all);

  /// «Движения» по счетам (чистое изменение остатка): так тест имитирует
  /// операции, которых в фейке нет.
  final Map<String, Money> net = {};

  @override
  Stream<Map<String, Money>> watchBalances() => _live(
    () => {
      for (final a in _all)
        a.id: net[a.id] == null
            ? a.openingBalance
            : a.openingBalance + net[a.id]!,
    },
  );

  Account _require(String id) {
    final found = _all.where((a) => a.id == id);
    if (found.isEmpty) {
      throw ArgumentError.value(id, 'id', 'account not found');
    }
    return found.first;
  }

  /// Если задан, `archive` ждёт его завершения перед записью (имитация
  /// долгой записи).
  Completer<void>? archiveGate;

  void _replace(String id, Account Function(Account) change) {
    final error = failWith;
    if (error != null) throw error;
    _require(id);
    _all = [
      for (final a in _all)
        if (a.id == id) change(a) else a,
    ];
    _changes.add(null);
  }

  @override
  Future<void> adjustCurrentBalance(String id, Money entered) async {
    final move = net[id] ?? Money.zero(entered.currency);
    _replace(id, (a) => a.withOpeningBalance(entered - move));
  }

  @override
  Future<void> archive(String id) async {
    await archiveGate?.future;
    if (_require(id).isArchived) return;
    _replace(id, (a) => a.archived(DateTime.utc(2026, 10, 8)));
  }

  @override
  Future<void> restore(String id) async {
    final account = _require(id);
    if (!account.isArchived) return;
    Account.checkUniqueName(name: account.name, existing: _all, selfId: id);
    _replace(id, (a) => a.restored());
  }

  @override
  Future<int> nextSortOrder() async =>
      _all.fold<int>(-1, (m, a) => a.sortOrder > m ? a.sortOrder : m) + 1;

  @override
  Future<void> create(Account account) async {
    final error = failWith;
    if (error != null) throw error;
    Account.checkUniqueName(name: account.name, existing: _all);
    _all = [..._all, account];
    _changes.add(null);
  }

  @override
  Future<void> update(
    String id, {
    required String name,
    required String iconKey,
  }) async {
    final error = failWith;
    if (error != null) throw error;
    _require(id);
    final checked = Account.checkedName(name);
    Account.checkUniqueName(name: checked, existing: _all, selfId: id);
    _all = [
      for (final a in _all)
        if (a.id == id) a.withName(checked).withIcon(iconKey) else a,
    ];
    _changes.add(null);
  }

  /// Аргументы всех вызовов `reorder`.
  final reorderCalls = <List<String>>[];

  /// Как у настоящего: названные идут первыми по `sortOrder` 0..n-1, остальные
  /// следом; список отдаётся в порядке `sortOrder`.
  @override
  Future<void> reorder(List<String> orderedIds) async {
    reorderCalls.add(List.of(orderedIds));
    final error = failWith;
    if (error != null) throw error;
    final rest = [
      for (final a in _all)
        if (!orderedIds.contains(a.id)) a,
    ];
    final ordered = [for (final id in orderedIds) _require(id), ...rest];
    _all = [
      for (var i = 0; i < ordered.length; i++) ordered[i].withSortOrder(i),
    ];
    _changes.add(null);
  }
}

/// Пустой фейк репозитория категорий: методы не реализованы, любой вызов
/// бросит ошибку. Годится, когда тесту нужен лишь сам объект («тот же ли он»).
///
/// Исключение — `watchSubcategories`: быстрый ввод спрашивает подкатегории
/// после каждого тапа по категории, и по умолчанию их нет. Тесты, которым нужны
/// подкатегории, переопределяют метод.
class FakeCategoriesRepository extends Fake implements CategoriesRepository {
  @override
  Stream<List<Category>> watchAll() => Stream.value(const []);

  @override
  Stream<List<Category>> watchSubcategories(String parentId) =>
      Stream.value(const []);
}

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

  /// Как настоящий: на единицу больше максимума среди категорий верхнего
  /// уровня вида (или подкатегорий [parentId]); архивные считаются, для
  /// пустого списка 0.
  @override
  Future<int> nextSortOrder(CategoryKind kind, {String? parentId}) async {
    var next = 0;
    for (final c in _state.value) {
      final sibling = parentId == null
          ? c.isTopLevel && c.kind == kind
          : c.parentId == parentId;
      if (sibling && c.sortOrder >= next) {
        next = c.sortOrder + 1;
      }
    }
    return next;
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

  @override
  Future<void> update(
    String id, {
    required String newName,
    required String iconKey,
  }) async {
    writes++;
    final error = failWith;
    if (error != null) throw error;
    // Порядок проверок как у drift: id, имя, значок, дубль имени.
    final found = _state.value.where((c) => c.id == id);
    if (found.isEmpty) {
      throw ArgumentError.value(id, 'id', 'category not found');
    }
    final target = found.first;
    final name = Category.checkedName(newName);
    if (iconKey.trim().isEmpty) {
      throw CategoryRuleException(CategoryRule.emptyIconKey);
    }
    Category.checkUniqueName(
      name: name,
      kind: target.kind,
      parentId: target.parentId,
      existing: _state.value,
      selfId: id,
    );
    final oldIcon = target.iconKey;
    _state.value = [
      for (final c in _state.value)
        if (c.id == id)
          c.copyWith(name: name, iconKey: iconKey)
        else if (target.isTopLevel && c.parentId == id && c.iconKey == oldIcon)
          c.copyWith(iconKey: iconKey)
        else
          c,
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
///
/// Исключение — `watchFirstDay`: `BrowseHost` подписывается на него в каждом
/// приложении. Фейк отдаёт [firstDay] (по умолчанию `null`), повторяет каждое
/// изменение через [setFirstDay] и считает живые подписки в [firstDayListeners].
class FakeTransactionsRepository extends Fake
    implements TransactionsRepository {
  DateOnly? firstDay;

  /// `false` — подписка молчит, пока тест не вызовет [setFirstDay] или
  /// [failFirstDay] (имитация «база ещё не ответила»).
  bool answerFirstDayOnListen = true;

  /// Сколько подписок на `watchFirstDay` сейчас активно.
  int firstDayListeners = 0;

  final _firstDayControllers = <StreamController<DateOnly?>>[];

  /// Меняет день первой операции и сообщает всем подписчикам.
  void setFirstDay(DateOnly? day) {
    firstDay = day;
    for (final controller in _firstDayControllers) {
      controller.add(day);
    }
  }

  /// Шлёт подписчикам ошибку (поток при этом остаётся живым).
  void failFirstDay(Object error) {
    for (final controller in _firstDayControllers) {
      controller.addError(error);
    }
  }

  /// Операций в других валютах у фейка нет.
  @override
  Stream<bool> watchHasOtherCurrency(String currency) =>
      Stream<bool>.multi((controller) => controller.add(false));

  @override
  Stream<DateOnly?> watchFirstDay() {
    late StreamController<DateOnly?> controller;
    controller = StreamController<DateOnly?>(
      onListen: () {
        firstDayListeners++;
        _firstDayControllers.add(controller);
        if (answerFirstDayOnListen) controller.add(firstDay);
      },
      onCancel: () {
        firstDayListeners--;
        _firstDayControllers.remove(controller);
      },
    );
    return controller.stream;
  }
}

/// Набор сервисов из фейков: то, что тест кладёт в `AppScope`.
///
/// [settings] передаёт сам тест: кто создал контроллер, тот и вызывает
/// `dispose`. Репозитории можно заменить своими, иначе подставляются пустые
/// фейки.
AppServices fakeAppServices({
  required AppSettingsController settings,
  CategoriesRepository? categories,
  TransactionsRepository? transactions,
  AccountsRepository? accounts,
  TransfersRepository? transfers,
  RecurringRepository? recurring,
  FixedClock? clock,
  CsvImportStore? csvImport,
  DataEraser? dataEraser,
}) {
  return AppServices(
    categories: categories ?? FakeCategoriesRepository(),
    transactions: transactions ?? FakeTransactionsRepository(),
    accounts: accounts ?? FakeAccountsRepository(),
    transfers: transfers ?? FakeTransfersRepository(),
    recurring: recurring ?? FakeRecurringRepository(),
    settings: settings,
    clock: clock ?? FixedClock(DateTime.utc(2026, 9, 20, 12)),
    idGenerator: FakeIdGenerator(),
    csvImport: csvImport ?? FakeCsvImportStore(),
    dataEraser: dataEraser ?? FakeDataEraser(),
  );
}

/// Фейк стирания данных: считает вызовы; [error] — что бросить.
class FakeDataEraser implements DataEraser {
  int calls = 0;
  Exception? error;

  @override
  Future<void> eraseAll() async {
    calls++;
    final failure = error;
    if (failure != null) throw failure;
  }
}

/// Пустой фейк импорта CSV: любой вызов падает, если тест его не ждал.
class FakeCsvImportStore extends Fake implements CsvImportStore {}

/// Фейк импорта CSV с заданным планом. Записанные планы — в [written];
/// [writeError] — что бросить при записи (имитация сбоя базы).
class PlannedCsvImportStore implements CsvImportStore {
  PlannedCsvImportStore(this.plan);

  CsvImportPlan plan;
  Exception? writeError;
  List<ParsedCsvRow>? preparedRows;
  final List<CsvImportPlan> written = [];

  @override
  Future<CsvImportPlan> prepare(
    List<ParsedCsvRow> rows, {
    List<ParsedOpeningBalance> openingBalances = const [],
    List<ParsedTransfer> transfers = const [],
  }) async {
    preparedRows = rows;
    return plan;
  }

  @override
  Future<void> write(CsvImportPlan plan) async {
    final error = writeError;
    if (error != null) throw error;
    written.add(plan);
  }
}

/// Пустой фейк репозитория регулярных платежей: любой вызов падает, если тест
/// его не ждал.
class FakeRecurringRepository extends Fake implements RecurringRepository {
  /// Дни, за которые просили `materializeDue`.
  final materializedDays = <DateOnly>[];

  /// Что бросить из `materializeDue` (если не `null`).
  Error? materializeError;

  /// Что отдаст `watchAll` (список читается в момент вызова).
  List<RecurringListItem> items = const [];

  @override
  Stream<List<RecurringListItem>> watchAll() => Stream.value(items);

  @override
  Future<int> materializeDue(DateOnly today) async {
    materializedDays.add(today);
    final error = materializeError;
    if (error != null) throw error;
    return 0;
  }
}
