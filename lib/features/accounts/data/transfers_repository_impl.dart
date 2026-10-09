import 'dart:async';

import 'package:drift/drift.dart';
import 'package:money_app/core/database/app_database.dart';
import 'package:money_app/core/errors/data_corrupted_exception.dart';
import 'package:money_app/core/time/clock.dart';
import 'package:money_app/features/accounts/data/transfer_mapper.dart';
import 'package:money_app/features/accounts/domain/transfer.dart';
import 'package:money_app/features/accounts/domain/transfer_rules.dart';
import 'package:money_app/features/accounts/domain/transfers_repository.dart';

/// Реализация [TransfersRepository] на drift. Условие `deleted_at IS NULL`
/// стоит в каждом запросе к «живым» строкам (частичные индексы схемы).
class DriftTransfersRepository implements TransfersRepository {
  DriftTransfersRepository(this._db, {this._clock = const SystemClock()});

  final AppDatabase _db;
  final Clock _clock;

  @override
  Future<void> add(Transfer transfer) {
    return _db.transaction(() async {
      await _checkAccounts(transfer, checkFrom: true, checkTo: true);
      final now = _nowMs();
      await _db
          .into(_db.transfers)
          .insert(
            TransfersCompanion.insert(
              id: transfer.id,
              fromAccountId: transfer.fromAccountId,
              toAccountId: transfer.toAccountId,
              amountMinor: transfer.amount.minorUnits,
              currency: transfer.amount.currency,
              occurredOn: transfer.occurredOn,
              occurredAt: transfer.occurredAt.millisecondsSinceEpoch,
              note: Value(transfer.note),
              createdAt: now,
              updatedAt: now,
            ),
          );
    });
  }

  /// Архивность проверяется только у ИЗМЕНЁННОГО счёта: если счёт остался
  /// прежним (пусть и архивным), сумму, дату и комментарий править можно.
  @override
  Future<void> update(Transfer transfer) {
    return _db.transaction(() async {
      final state = await _requireState(transfer.id);
      if (state.isDeleted) {
        throw ArgumentError.value(
          transfer.id,
          'transfer',
          'transfer is deleted',
        );
      }
      await _checkAccounts(
        transfer,
        checkFrom: transfer.fromAccountId != state.fromAccountId,
        checkTo: transfer.toAccountId != state.toAccountId,
      );
      await _write(
        transfer.id,
        TransfersCompanion(
          fromAccountId: Value(transfer.fromAccountId),
          toAccountId: Value(transfer.toAccountId),
          amountMinor: Value(transfer.amount.minorUnits),
          currency: Value(transfer.amount.currency),
          occurredOn: Value(transfer.occurredOn),
          occurredAt: Value(transfer.occurredAt.millisecondsSinceEpoch),
          note: Value(transfer.note),
          updatedAt: Value(_nowMs()),
        ),
      );
    });
  }

  @override
  Future<void> softDelete(String id) {
    return _db.transaction(() async {
      final state = await _requireState(id);
      if (state.isDeleted) return; // Время удаления остаётся прежним.
      final now = _nowMs();
      await _write(
        id,
        TransfersCompanion(deletedAt: Value(now), updatedAt: Value(now)),
      );
    });
  }

  @override
  Future<void> restore(String id) {
    return _db.transaction(() async {
      final state = await _requireState(id);
      if (!state.isDeleted) return;
      await _write(
        id,
        TransfersCompanion(
          deletedAt: const Value(null),
          updatedAt: Value(_nowMs()),
        ),
      );
    });
  }

  @override
  Stream<List<Transfer>> watchForAccount(String accountId) {
    final query = _db.select(_db.transfers)
      ..where(
        (t) =>
            t.deletedAt.isNull() &
            (t.fromAccountId.equals(accountId) |
                t.toAccountId.equals(accountId)),
      )
      ..orderBy([
        (t) => OrderingTerm.desc(t.occurredOn),
        (t) => OrderingTerm.desc(t.occurredAt),
        (t) => OrderingTerm.desc(t.id),
      ]);
    return query
        .watch()
        .map((rows) => rows.map(transferFromRow).toList())
        .transform(
          StreamTransformer<List<Transfer>, List<Transfer>>.fromHandlers(
            handleError: (error, stackTrace, sink) {
              // Конвертер дня срабатывает внутри drift, до transferFromRow.
              sink.addError(
                error is FormatException
                    ? DataCorruptedException(
                        'Stored transfers are corrupted: ${error.message}',
                        cause: error,
                      )
                    : error,
                stackTrace,
              );
            },
          ),
        );
  }

  /// Оба счёта есть (иначе [ArgumentError]) и в валюте суммы (иначе
  /// `currencyMismatch`); архивность — только у помеченных флагами.
  Future<void> _checkAccounts(
    Transfer transfer, {
    required bool checkFrom,
    required bool checkTo,
  }) async {
    final from = await _requireAccount(transfer.fromAccountId, 'fromAccountId');
    final to = await _requireAccount(transfer.toAccountId, 'toAccountId');
    final currency = transfer.amount.currency;
    if (from.currency != currency || to.currency != currency) {
      throw TransferRuleException(TransferRule.currencyMismatch);
    }
    if ((checkFrom && from.isArchived) || (checkTo && to.isArchived)) {
      throw TransferRuleException(TransferRule.accountArchived);
    }
  }

  Future<({String currency, bool isArchived})> _requireAccount(
    String id,
    String argName,
  ) async {
    final table = _db.accounts;
    final row =
        await (_db.selectOnly(table)
              ..addColumns([table.currency, table.archivedAt])
              ..where(table.deletedAt.isNull() & table.id.equals(id)))
            .getSingleOrNull();
    if (row == null) {
      throw ArgumentError.value(id, argName, 'account not found');
    }
    return (
      currency: row.read(table.currency)!,
      isArchived: row.read(table.archivedAt) != null,
    );
  }

  /// Данные строки без чтения преобразуемых колонок: удалять и править можно
  /// и испорченную строку.
  Future<_TransferState> _requireState(String id) async {
    final table = _db.transfers;
    final row =
        await (_db.selectOnly(table)
              ..addColumns([
                table.deletedAt,
                table.fromAccountId,
                table.toAccountId,
              ])
              ..where(table.id.equals(id)))
            .getSingleOrNull();
    if (row == null) {
      throw ArgumentError.value(id, 'id', 'transfer not found');
    }
    return _TransferState(
      isDeleted: row.read(table.deletedAt) != null,
      fromAccountId: row.read(table.fromAccountId)!,
      toAccountId: row.read(table.toAccountId)!,
    );
  }

  Future<void> _write(String id, TransfersCompanion changes) {
    return (_db.update(
      _db.transfers,
    )..where((t) => t.id.equals(id))).write(changes);
  }

  int _nowMs() => _clock.now().toUtc().millisecondsSinceEpoch;
}

final class _TransferState {
  const _TransferState({
    required this.isDeleted,
    required this.fromAccountId,
    required this.toAccountId,
  });

  final bool isDeleted;
  final String fromAccountId;
  final String toAccountId;
}
