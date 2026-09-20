import 'package:flutter/material.dart';
import 'package:money_app/core/format/day_label.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/format/money_spoken.dart';
import 'package:money_app/core/money/currency.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/ui/async_view.dart';
import 'package:money_app/core/ui/category_icons.dart';
import 'package:money_app/core/ui/category_labels.dart';
import 'package:money_app/core/ui/theme/app_colors.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

/// Настоящий минус (U+2212), а не дефис (как в `AmountField`).
final String _minusSign = String.fromCharCode(0x2212);

/// Ключ заглушки-скелетона: по нему тесты отличают «ещё грузится» от «пусто».
const Key historySkeletonKey = ValueKey('history-skeleton');

/// Вкладка «История»: живые операции по дням, новые сверху.
///
/// Экран не знает, откуда берутся данные и куда ведёт нажатие: потоки и
/// [onTransactionTap] передаёт приложение (`lib/app`), поэтому фича не зависит
/// от маршрутов и хранилища (ADR 0002). Потоки должны быть одними и теми же
/// между перерисовками (их создаёт вызывающий), иначе подписка начнётся заново.
///
/// - [transactions] — операции уже в нужном порядке (новые сверху): экран лишь
///   группирует подряд идущие операции одного дня под заголовком;
/// - [categories] — справочник с архивными категориями и подкатегориями:
///   из него берутся имя и иконка. Операция по архивной категории показывает
///   её имя; если категории нет вовсе — «Без категории».
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({
    required this.transactions,
    required this.categories,
    required this.today,
    required this.onTransactionTap,
    super.key,
  });

  final Stream<List<Transaction>> transactions;
  final Stream<List<Category>> categories;

  /// Сегодняшний день: от него считаются «Сегодня» и «Вчера» в заголовках.
  final DateOnly today;

  /// Тап по строке. Правку по нему подключает шаг 2.28.
  final ValueChanged<Transaction> onTransactionTap;

  @override
  Widget build(BuildContext context) {
    // Справочник снаружи, операции внутри: справочник живёт, пока открыта
    // вкладка, а пустое состояние показывается только после ответа базы (до
    // него — скелетон, а не «Операций пока нет»).
    return AsyncView<List<Category>>(
      stream: categories,
      loadingBuilder: (_) => const _HistorySkeleton(),
      dataBuilder: (context, all) {
        final byId = {for (final c in all) c.id: c};
        return AsyncView<List<Transaction>>(
          stream: transactions,
          loadingBuilder: (_) => const _HistorySkeleton(),
          isEmpty: (list) => list.isEmpty,
          emptyBuilder: (_) => const _EmptyState(),
          dataBuilder: (context, list) => _HistoryList(
            transactions: list,
            categoriesById: byId,
            today: today,
            onTransactionTap: onTransactionTap,
          ),
        );
      },
    );
  }
}

class _HistoryList extends StatelessWidget {
  const _HistoryList({
    required this.transactions,
    required this.categoriesById,
    required this.today,
    required this.onTransactionTap,
  });

  final List<Transaction> transactions;
  final Map<String, Category> categoriesById;
  final DateOnly today;
  final ValueChanged<Transaction> onTransactionTap;

  @override
  Widget build(BuildContext context) {
    // Плоский список: заголовок дня (DateOnly) и строки операций (Transaction).
    final items = <Object>[];
    DateOnly? currentDay;
    for (final t in transactions) {
      if (t.occurredOn != currentDay) {
        currentDay = t.occurredOn;
        items.add(t.occurredOn);
      }
      items.add(t);
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        if (item is DateOnly) {
          return _DayHeader(label: historyDayLabel(item, today: today));
        }
        final t = item as Transaction;
        final category = categoriesById[t.categoryId];
        final subcategory = t.subcategoryId == null
            ? null
            : categoriesById[t.subcategoryId];
        return _TransactionTile(
          transaction: t,
          title: _title(category, subcategory),
          iconKey: category?.iconKey,
          dayText: historyDayLabel(t.occurredOn, today: today),
          onTap: () => onTransactionTap(t),
        );
      },
    );
  }

  /// «Категория» или «Категория · Подкатегория»; без категории — запасной текст.
  static String _title(Category? category, Category? subcategory) {
    if (category == null) return noCategoryLabel;
    if (subcategory == null) return category.name;
    return '${category.name} · ${subcategory.name}';
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(
          label,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({
    required this.transaction,
    required this.title,
    required this.iconKey,
    required this.dayText,
    required this.onTap,
  });

  final Transaction transaction;
  final String title;

  /// Ключ иконки категории; `null` — категории нет, берётся запасная иконка.
  final String? iconKey;
  final String dayText;
  final VoidCallback onTap;

  static String _spoken(Money money) => money.currency == rubCurrencyCode
      ? spokenMoney(money)
      : formatMoney(money);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isIncome = transaction.type == TransactionType.income;
    final accent = isIncome
        ? context.appColors.income
        : context.appColors.expense;
    final amountText =
        '${isIncome ? '+' : _minusSign}${formatMoney(transaction.amount)}';
    final note = transaction.note;

    // Сводная подпись для скринридера: тип, сумма словами, категория, день и
    // комментарий одной фразой; содержимое строки из озвучки исключено.
    final label = StringBuffer(isIncome ? 'Доход ' : 'Расход ')
      ..write(_spoken(transaction.amount))
      ..write(', $title, $dayText');
    if (note != null) label.write(', комментарий: $note');

    return Semantics(
      button: true,
      label: label.toString(),
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          // Зона нажатия не ниже 48 dp; при крупном шрифте строка растёт сама.
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    iconKey == null
                        ? fallbackCategoryIcon
                        : categoryIconFor(iconKey!),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge,
                      ),
                      if (note != null)
                        Text(
                          note,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Сумма не занимает больше 45% ширины: очень длинная сумма при
                // крупном шрифте уменьшается, а не выталкивает название.
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.sizeOf(context).width * 0.45,
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      amountText,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Пустое состояние: спросили базу, и операций в ней нет.
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Прокрутка на случай крупного шрифта на маленьком экране.
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Операций пока нет',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Добавьте расход или доход на вкладке «Главная»',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Серые строки-заглушки на месте будущего списка (без анимации: никаких
/// таймеров). Для скринридера — одна подпись «Загрузка».
class _HistorySkeleton extends StatelessWidget {
  const _HistorySkeleton();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;

    Widget bar(double width, double height) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
    );

    Widget row() => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [bar(120, 14), const SizedBox(height: 6), bar(80, 10)],
            ),
          ),
          const SizedBox(width: 12),
          bar(64, 14),
        ],
      ),
    );

    // ListView без прокрутки: лишние строки просто обрезаются по краю экрана,
    // переполнения не бывает.
    return Semantics(
      label: 'Загрузка операций',
      child: ExcludeSemantics(
        child: ListView(
          key: historySkeletonKey,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.only(top: 16),
          children: [for (var i = 0; i < 8; i++) row()],
        ),
      ),
    );
  }
}
