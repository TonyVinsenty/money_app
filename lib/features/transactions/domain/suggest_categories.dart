import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/transactions/domain/category_kind_mapping.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

/// Сколько подсказок показываем самое большее.
const int suggestionsMaxCount = 3;

/// Сколько операций должно быть у пары, чтобы она попала в подсказки.
const int suggestionMinOperations = 3;

/// Окно истории: старше операции не учитываются.
const int suggestionHistoryDays = 90;

/// «Свежее» окно: операции из него весят вдвое больше.
const int suggestionRecentDays = 30;

/// Полуширина окна «то же время суток», в минутах (±2 часа).
const int suggestionTimeWindowMinutes = 120;

/// Подсказка: категория и, возможно, подкатегория (`null` — «без неё»).
final class CategorySuggestion {
  const CategorySuggestion({required this.category, this.subcategory});

  /// Категория верхнего уровня (не в архиве).
  final Category category;

  /// Подкатегория (не в архиве) или `null`, если операции были без неё.
  final Category? subcategory;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CategorySuggestion &&
            other.category == category &&
            other.subcategory == subcategory;
  }

  @override
  int get hashCode => Object.hash(category, subcategory);

  @override
  String toString() =>
      'CategorySuggestion(${category.name} / ${subcategory?.name})';
}

/// Подбирает до [suggestionsMaxCount] пар «категория · подкатегория» для
/// быстрого ввода операций типа [type].
///
/// [recent] — операции (любого типа; чужой тип и всё старше
/// [suggestionHistoryDays] дней, а также «из будущего» отбрасывается),
/// [now] — текущий момент, [categories] — категории и подкатегории
/// (архивные игнорируются).
///
/// Вес операции — целое число: ×3, если её время суток (по местным часам) не
/// дальше [suggestionTimeWindowMinutes] минут от времени суток [now] (по кругу
/// через полночь), иначе ×1; и ещё ×2, если она из последних
/// [suggestionRecentDays] дней. Пара берётся, если в ней не меньше
/// [suggestionMinOperations] операций. Пара, у которой категория или
/// подкатегория в архиве (или неизвестна), исключается целиком и не заменяется
/// парой без подкатегории. Порядок: больший вес, при равенстве — более свежая
/// последняя операция, затем по идентификаторам (детерминированно).
List<CategorySuggestion> suggestCategories({
  required Iterable<Transaction> recent,
  required DateTime now,
  required Iterable<Category> categories,
  required TransactionType type,
}) {
  final byId = {
    for (final c in categories)
      if (!c.isArchived && c.kind.transactionType == type) c.id: c,
  };
  final nowUtc = now.toUtc();
  final historyStart = nowUtc.subtract(
    const Duration(days: suggestionHistoryDays),
  );
  final recentStart = nowUtc.subtract(
    const Duration(days: suggestionRecentDays),
  );
  final nowMinute = _minuteOfDay(nowUtc);

  final stats = <(String, String?), _PairStats>{};
  for (final t in recent) {
    if (t.type != type ||
        t.occurredAt.isBefore(historyStart) ||
        t.occurredAt.isAfter(nowUtc)) {
      continue;
    }
    var weight = _isNearTimeOfDay(_minuteOfDay(t.occurredAt), nowMinute)
        ? 3
        : 1;
    if (!t.occurredAt.isBefore(recentStart)) {
      weight *= 2;
    }
    final stat = stats.putIfAbsent((
      t.categoryId,
      t.subcategoryId,
    ), _PairStats.new);
    stat.count++;
    stat.score += weight;
    if (stat.latest == null || t.occurredAt.isAfter(stat.latest!)) {
      stat.latest = t.occurredAt;
    }
  }

  final candidates = <_Candidate>[];
  for (final entry in stats.entries) {
    final (categoryId, subcategoryId) = entry.key;
    if (entry.value.count < suggestionMinOperations) continue;
    final category = byId[categoryId];
    if (category == null || !category.isTopLevel) continue;
    Category? subcategory;
    if (subcategoryId != null) {
      subcategory = byId[subcategoryId];
      if (subcategory == null || subcategory.parentId != categoryId) continue;
    }
    candidates.add(
      _Candidate(
        CategorySuggestion(category: category, subcategory: subcategory),
        entry.value,
      ),
    );
  }

  candidates.sort((a, b) {
    final byScore = b.stats.score.compareTo(a.stats.score);
    if (byScore != 0) return byScore;
    final byLatest = b.stats.latest!.compareTo(a.stats.latest!);
    if (byLatest != 0) return byLatest;
    final byCategory = a.suggestion.category.id.compareTo(
      b.suggestion.category.id,
    );
    if (byCategory != 0) return byCategory;
    return (a.suggestion.subcategory?.id ?? '').compareTo(
      b.suggestion.subcategory?.id ?? '',
    );
  });
  return [for (final c in candidates.take(suggestionsMaxCount)) c.suggestion];
}

int _minuteOfDay(DateTime utc) {
  final local = utc.toLocal();
  return local.hour * 60 + local.minute;
}

bool _isNearTimeOfDay(int minute, int nowMinute) {
  final diff = (minute - nowMinute).abs();
  final circular = diff > 720 ? 1440 - diff : diff;
  return circular <= suggestionTimeWindowMinutes;
}

final class _PairStats {
  int count = 0;
  int score = 0;
  DateTime? latest;
}

final class _Candidate {
  _Candidate(this.suggestion, this.stats);

  final CategorySuggestion suggestion;
  final _PairStats stats;
}
