import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/app/browse_controller.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/features/transactions/domain/history_view.dart';

DateRange _month(int year, int month) => monthRange(DateOnly(year, month, 1));

void main() {
  late BrowseController c;
  late int notifications;

  BrowseController make(DateOnly today, {DateOnly? firstDay}) {
    final controller = BrowseController(today: today);
    if (firstDay != null) controller.updateFirstDay(firstDay);
    notifications = 0;
    controller.addListener(() => notifications++);
    addTearDown(controller.dispose);
    return controller;
  }

  setUp(() {
    c = make(DateOnly(2026, 10, 4), firstDay: DateOnly(2026, 7, 15));
  });

  test('по умолчанию: текущий месяц, фильтр выключен, сначала новые', () {
    expect(c.today, DateOnly(2026, 10, 4));
    expect(c.month, _month(2026, 10));
    expect(c.historyFilter, HistoryFilter.off);
    expect(c.historySort, HistorySort.newestFirst);
  });

  group('firstDayKnown', () {
    test('false до ответа; null-ответ делает true с уведомлением', () {
      final fresh = make(DateOnly(2026, 10, 4));
      expect(fresh.firstDayKnown, isFalse);
      fresh.updateFirstDay(null);
      expect(fresh.firstDayKnown, isTrue);
      expect(fresh.firstDay, isNull);
      expect(notifications, 1);
      fresh.updateFirstDay(null);
      expect(notifications, 1);
    });

    test('markFirstDayKnown снимает «неизвестно» один раз', () {
      final fresh = make(DateOnly(2026, 10, 4));
      fresh.markFirstDayKnown();
      fresh.markFirstDayKnown();
      expect(fresh.firstDayKnown, isTrue);
      expect(notifications, 1);
    });
  });

  group('updateToday', () {
    test('тот же день: без уведомления', () {
      c.updateToday(DateOnly(2026, 10, 4));
      expect(notifications, 0);
    });

    test('выбран текущий месяц: переходим на новый, одно уведомление', () {
      c.updateToday(DateOnly(2026, 11, 1));
      expect(c.today, DateOnly(2026, 11, 1));
      expect(c.month, _month(2026, 11));
      expect(notifications, 1);
    });

    test('выбран прошлый месяц: месяц тот же, вперёд пересчитан', () {
      c.previousMonth();
      expect(c.month, _month(2026, 9));
      notifications = 0;
      c.updateToday(DateOnly(2026, 11, 1));
      expect(c.month, _month(2026, 9));
      expect(notifications, 1);
      c.nextMonth();
      c.nextMonth();
      expect(c.month, _month(2026, 11));
      expect(c.canGoForward, isFalse);
    });

    test('новый день в том же месяце: месяц тот же', () {
      c.updateToday(DateOnly(2026, 10, 5));
      expect(c.month, _month(2026, 10));
      expect(notifications, 1);
    });
  });

  group('листание', () {
    test('вперёд с текущего месяца нельзя, из прошлого можно', () {
      expect(c.canGoForward, isFalse);
      c.nextMonth();
      expect(c.month, _month(2026, 10));
      expect(notifications, 0);

      c.previousMonth();
      expect(c.month, _month(2026, 9));
      expect(c.canGoForward, isTrue);
      c.nextMonth();
      expect(c.month, _month(2026, 10));
      expect(notifications, 2);
    });

    test('январь -> декабрь прошлого года и обратно', () {
      final jan = make(DateOnly(2026, 1, 10), firstDay: DateOnly(2025, 11, 1));
      jan.previousMonth();
      expect(jan.month, _month(2025, 12));
      jan.nextMonth();
      expect(jan.month, _month(2026, 1));
    });

    test('назад нельзя без firstDay', () {
      final empty = make(DateOnly(2026, 10, 4));
      expect(empty.canGoBack, isFalse);
      empty.previousMonth();
      expect(empty.month, _month(2026, 10));
      expect(notifications, 0);
    });

    test('назад нельзя на месяце первой операции', () {
      c.previousMonth();
      c.previousMonth();
      expect(c.month, _month(2026, 8));
      expect(c.canGoBack, isTrue);
      c.previousMonth();
      expect(c.month, _month(2026, 7));
      expect(c.canGoBack, isFalse);

      notifications = 0;
      c.previousMonth();
      expect(c.month, _month(2026, 7));
      expect(notifications, 0);
    });
  });

  group('showMonthOf', () {
    test('показывает месяц дня, повтор не уведомляет', () {
      c.showMonthOf(DateOnly(2026, 9, 30));
      expect(c.month, _month(2026, 9));
      expect(notifications, 1);

      c.showMonthOf(DateOnly(2026, 9, 1));
      expect(notifications, 1);
    });

    test('день в будущем — не дальше текущего месяца', () {
      c.showMonthOf(DateOnly(2027, 3, 1));
      expect(c.month, _month(2026, 10));
      expect(notifications, 0);

      c.showMonthOf(DateOnly(2026, 8, 1));
      c.showMonthOf(DateOnly(2026, 10, 31));
      expect(c.month, _month(2026, 10));
    });

    test('день раньше firstDay допустим', () {
      c.showMonthOf(DateOnly(2026, 3, 5));
      expect(c.month, _month(2026, 3));
      expect(c.canGoBack, isFalse);
    });
  });

  group('updateFirstDay', () {
    test('тот же день не уведомляет, новый — один раз', () {
      c.updateFirstDay(DateOnly(2026, 7, 15));
      expect(notifications, 0);

      c.updateFirstDay(DateOnly(2026, 5, 1));
      expect(notifications, 1);
      expect(c.firstDay, DateOnly(2026, 5, 1));
    });

    test('самую раннюю удалили: месяц остаётся, назад нельзя', () {
      c.showMonthOf(DateOnly(2026, 7, 1));
      notifications = 0;

      c.updateFirstDay(DateOnly(2026, 9, 2));
      expect(c.month, _month(2026, 7));
      expect(c.canGoBack, isFalse);
      expect(notifications, 1);
    });

    test('null: операций нет, назад нельзя', () {
      c.updateFirstDay(null);
      expect(c.canGoBack, isFalse);
      expect(notifications, 1);
    });

    test('операция появилась раньше: назад снова можно', () {
      c.showMonthOf(DateOnly(2026, 7, 1));
      expect(c.canGoBack, isFalse);
      c.updateFirstDay(DateOnly(2026, 6, 1));
      expect(c.canGoBack, isTrue);
    });
  });

  group('фильтр и сортировка', () {
    test('сохраняются при смене месяца', () {
      c.showCategoryExpenses({'cat-food'});
      c.setHistorySort(HistorySort.largestFirst);
      c.previousMonth();

      expect(c.historyFilter, HistoryFilter.expenseCategories({'cat-food'}));
      expect(c.historySort, HistorySort.largestFirst);
    });

    test('showCategoryExpenses не меняет месяц и копирует набор', () {
      final ids = {'a'};
      c.showCategoryExpenses(ids);
      ids.add('b');

      expect(c.month, _month(2026, 10));
      expect(c.historyFilter.type, HistoryTypeFilter.expense);
      expect(c.historyFilter.expenseCategoryIds, {'a'});
      expect(notifications, 1);
    });

    test('тот же фильтр и та же сортировка не уведомляют', () {
      c.setHistoryFilter(HistoryFilter.off);
      c.setHistorySort(HistorySort.newestFirst);
      c.resetHistoryFilter();
      expect(notifications, 0);

      c.showCategoryExpenses({'a'});
      c.showCategoryExpenses({'a'});
      c.setHistorySort(HistorySort.oldestFirst);
      c.setHistorySort(HistorySort.oldestFirst);
      expect(notifications, 2);
    });

    test('resetHistoryFilter сбрасывает фильтр, но не сортировку', () {
      c.showCategoryExpenses({'a'});
      c.setHistorySort(HistorySort.smallestFirst);
      notifications = 0;

      c.resetHistoryFilter();

      expect(c.historyFilter, HistoryFilter.off);
      expect(c.historySort, HistorySort.smallestFirst);
      expect(notifications, 1);
    });
  });
}
