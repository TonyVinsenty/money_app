import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/accounts/domain/transfer.dart';

/// Строка журнала счетов (ADR 0010, п. 18). Журнал вычисляется, а не хранится.
///
/// Набор видов закрыт (`sealed`): новый вид придётся обработать во всех
/// `switch`.
sealed class BalanceJournalEntry {
  const BalanceJournalEntry();

  /// Локальный день события.
  DateOnly get day;

  /// Момент события в UTC.
  DateTime get moment;

  /// Идентификатор источника (счёта или перевода), для стабильного порядка.
  String get id;

  /// Место среди строк с одним днём и моментом: меньше - выше в ленте.
  int get _kindRank;
}

/// «Создан счёт»: момент - `createdAt` счёта.
final class AccountCreatedEntry extends BalanceJournalEntry {
  const AccountCreatedEntry(this.account, this.day, this.moment);

  final Account account;

  @override
  final DateOnly day;

  @override
  final DateTime moment;

  @override
  String get id => account.id;

  @override
  int get _kindRank => 2;
}

/// «Счёт отправлен в архив»: момент - `archivedAt` счёта.
final class AccountArchivedEntry extends BalanceJournalEntry {
  const AccountArchivedEntry(this.account, this.day, this.moment);

  final Account account;

  @override
  final DateOnly day;

  @override
  final DateTime moment;

  @override
  String get id => account.id;

  @override
  int get _kindRank => 0;
}

/// Перевод: день - его `occurredOn`, момент - `occurredAt`.
final class TransferEntry extends BalanceJournalEntry {
  TransferEntry(this.transfer);

  final Transfer transfer;

  @override
  DateOnly get day => transfer.occurredOn;

  @override
  DateTime get moment => transfer.occurredAt;

  @override
  String get id => transfer.id;

  @override
  int get _kindRank => 1;
}

/// Собирает журнал из [accounts] (с архивными) и живых [transfers].
///
/// Порядок: день и момент от новых к старым, затем вид строки (в архив, перевод,
/// создан) и `id`. [dayOf] переводит момент в местный день; по умолчанию
/// берётся день часового пояса устройства. Счёт без `createdAt` строки
/// «Создан» не даёт.
List<BalanceJournalEntry> buildBalanceJournal(
  Iterable<Account> accounts,
  Iterable<Transfer> transfers, {
  DateOnly Function(DateTime moment)? dayOf,
}) {
  final toDay = dayOf ?? DateOnly.fromDateTime;
  final entries = <BalanceJournalEntry>[
    for (final account in accounts) ...[
      if (account.createdAt case final at?)
        AccountCreatedEntry(account, toDay(at), at),
      if (account.archivedAt case final at?)
        AccountArchivedEntry(account, toDay(at), at),
    ],
    for (final transfer in transfers) TransferEntry(transfer),
  ];
  entries.sort((a, b) {
    final byDay = b.day.compareTo(a.day);
    if (byDay != 0) return byDay;
    final byMoment = b.moment.compareTo(a.moment);
    if (byMoment != 0) return byMoment;
    final byKind = a._kindRank.compareTo(b._kindRank);
    if (byKind != 0) return byKind;
    return a.id.compareTo(b.id);
  });
  return entries;
}
