import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:money_app/app/app_scope.dart';
import 'package:money_app/app/app_services.dart';
import 'package:money_app/core/time/clock.dart';
import 'package:money_app/features/recurring/data/reminders_channel.dart';
import 'package:money_app/features/recurring/domain/recurring_payment.dart';
import 'package:money_app/features/recurring/domain/recurring_repository.dart';
import 'package:money_app/features/recurring/domain/reminder_plan.dart';
import 'package:money_app/features/settings/presentation/app_settings_controller.dart';

/// Канал напоминаний приложения (в тестах вместо него подставляют фейк).
const appRemindersChannel = RemindersChannel();

/// Пересчитывает план уведомлений и отдаёт его системе (ADR 0011, п. 11).
///
/// Данные ([payments], [dues], [categoryNames]) приходят из потоков базы и
/// записываются сюда по мере поступления; пока не пришли все три, пересчёта
/// нет. Лишних вызовов канала нет двумя способами: одновременные запросы
/// склеиваются (пока идёт вызов канала, новые лишь ставят отметку «ещё раз»),
/// а план, равный последнему принятому системой, в канал не отправляется.
class ReminderSyncer {
  ReminderSyncer({
    required this.channel,
    required this.settings,
    required this.clock,
  });

  final RemindersChannel channel;
  final AppSettingsController settings;
  final Clock clock;

  /// Живые платежи.
  List<RecurringPayment>? payments;

  /// Ожидающие записи «К оплате».
  List<RecurringDue>? dues;

  /// Названия категорий по id.
  Map<String, String>? categoryNames;

  List<ReminderItem>? _last;
  bool _running = false;
  bool _again = false;

  /// Пересчитывает и при изменении плана вызывает `replaceAll`. Ошибки
  /// (нет реализации канала, сбой платформы) только пишутся в лог; тогда
  /// следующий пересчёт попробует снова.
  Future<void> sync() async {
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    try {
      do {
        _again = false;
        await _syncOnce();
      } while (_again);
    } finally {
      _running = false;
    }
  }

  Future<void> _syncOnce() async {
    final payments = this.payments;
    final dues = this.dues;
    final names = categoryNames;
    if (payments == null || dues == null || names == null) return;
    try {
      final today = clock.today();
      // Платёж на сегодня, которого нет среди ожидающих записей, уже оплачен
      // или пропущен: напоминать о нём не нужно.
      final pendingToday = {
        for (final due in dues)
          if (due.dueOn == today) due.payment.id,
      };
      final plan = planReminders(
        payments: payments,
        paidTodayIds: {
          for (final p in payments)
            if (!pendingToday.contains(p.id)) p.id,
        },
        categoryNames: names,
        now: clock.now(),
        time: settings.reminderTime,
      );
      if (listEquals(plan, _last)) return;
      await channel.replaceAll(plan);
      _last = plan;
    } catch (error) {
      debugPrint('Не удалось обновить напоминания: $error');
    }
  }
}

/// Держит [ReminderSyncer] и запускает его при каждом изменении платежей,
/// записей «К оплате», категорий, времени напоминаний и при возврате в
/// приложение. Ставится под `AppScope`.
class ReminderSyncHost extends StatefulWidget {
  const ReminderSyncHost({
    required this.child,
    this.channel = appRemindersChannel,
    super.key,
  });

  final Widget child;
  final RemindersChannel channel;

  @override
  State<ReminderSyncHost> createState() => _ReminderSyncHostState();
}

class _ReminderSyncHostState extends State<ReminderSyncHost> {
  final _subscriptions = <StreamSubscription<Object?>>[];
  late final AppLifecycleListener _lifecycle;
  AppServices? _services;
  ReminderSyncer? _syncer;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _sync);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = AppScope.of(context);
    if (identical(services.recurring, _services?.recurring)) return;
    _unsubscribe();
    _services = services;
    final syncer = ReminderSyncer(
      channel: widget.channel,
      settings: services.settings,
      clock: services.clock,
    );
    _syncer = syncer;
    void listen<T>(Stream<T> stream, void Function(T value) store) {
      _subscriptions.add(
        stream.listen((value) {
          store(value);
          _sync();
        }, onError: (Object error) => debugPrint('Напоминания: $error')),
      );
    }

    listen<List<RecurringListItem>>(
      services.recurring.watchAll(),
      (items) => syncer.payments = [for (final i in items) i.payment],
    );
    listen<List<RecurringDue>>(
      services.recurring.watchDue(),
      (list) => syncer.dues = list,
    );
    listen(
      services.categories.watchAll(),
      (all) => syncer.categoryNames = {for (final c in all) c.id: c.name},
    );
    // Меняется и тема: пересчёт без изменений плана канал не вызывает.
    services.settings.addListener(_sync);
  }

  void _sync() => unawaited(_syncer?.sync());

  void _unsubscribe() {
    _services?.settings.removeListener(_sync);
    for (final s in _subscriptions) {
      unawaited(s.cancel());
    }
    _subscriptions.clear();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
