import 'package:flutter/material.dart';
import 'package:money_app/app/app_services.dart';
import 'package:money_app/core/database/app_database.dart';
import 'package:money_app/core/id/id_generator.dart';
import 'package:money_app/core/time/clock.dart';
import 'package:money_app/features/settings/presentation/app_settings_controller.dart';

/// Раздаёт [AppServices] всем виджетам ниже по дереву (ADR 0002).
///
/// Это `InheritedNotifier`: виджет, который вызвал [AppScope.of], запоминается
/// как «зависимый», и Flutter перестроит его, когда настройки
/// (`services.settings`) уведомят об изменении или когда подменят сами
/// [services]. Виджеты, которые [of] не вызывали, не перестраиваются.
///
/// Сам [AppScope] ничего не создаёт: сервисы готовит и хранит [AppScopeHost].
class AppScope extends InheritedNotifier<AppSettingsController> {
  AppScope({required this.services, required super.child, super.key})
    : super(notifier: services.settings);

  final AppServices services;

  /// Сервисы ближайшего [AppScope] выше [context]; виджет становится
  /// зависимым от него.
  ///
  /// Если [AppScope] в дереве нет, бросает [FlutterError] с подсказкой.
  static AppServices of(BuildContext context) {
    final services = maybeOf(context);
    if (services == null) {
      throw FlutterError.fromParts([
        ErrorSummary('AppScope не найден выше этого виджета в дереве.'),
        ErrorDescription(
          'Виджет вызвал AppScope.of(context), но над ним нет AppScope. '
          'Такой виджет должен находиться в дереве ниже AppScope '
          '(в приложении его ставит AppScopeHost внутри MoneyApp).',
        ),
        ErrorHint(
          'В тесте оберните проверяемый виджет: '
          'AppScope(services: AppServices(...), child: ...), '
          'подставив в AppServices фейковые репозитории.',
        ),
        context.describeElement('Контекст, в котором искали AppScope'),
      ]);
    }
    return services;
  }

  /// То же, что [of], но без ошибки: если [AppScope] нет, вернёт `null`.
  static AppServices? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<AppScope>()?.services;
  }

  // Базовый InheritedNotifier следит только за сменой уведомителя. Но
  // если подменили набор сервисов (например, открылась другая база), при том
  // же контроллере настроек зависимые тоже должны перестроиться.
  @override
  bool updateShouldNotify(covariant AppScope oldWidget) {
    return oldWidget.services != services ||
        super.updateShouldNotify(oldWidget);
  }
}

/// Хозяин [AppScope]: создаёт [AppServices] и хранит их между перерисовками.
///
/// Сервисы создаются один раз в [State.initState]. Пока приходит та же база
/// (и те же настройки, часы, генератор), они не пересоздаются: иначе каждая
/// перерисовка родителя (например, смена темы) создавала бы новые репозитории,
/// а потоки данных, подписанные на старые, «оторвались» бы. Пришла другая
/// база: сервисы создаются заново.
///
/// Базой владеет тот, кто её открыл (`DatabaseGate`): [AppScopeHost] её не
/// закрывает, а репозитории не требуют освобождения.
class AppScopeHost extends StatefulWidget {
  const AppScopeHost({
    required this.database,
    required this.settings,
    required this.child,
    this.clock = const SystemClock(),
    this.idGenerator,
    super.key,
  });

  final AppDatabase database;
  final AppSettingsController settings;
  final Widget child;

  /// «Сейчас» для репозиториев; в тестах подставляются фиксированные часы.
  final Clock clock;

  /// Источник id; `null` — обычный [UuidV7Generator].
  final IdGenerator? idGenerator;

  @override
  State<AppScopeHost> createState() => _AppScopeHostState();
}

class _AppScopeHostState extends State<AppScopeHost> {
  late AppServices _services;

  @override
  void initState() {
    super.initState();
    _services = _createServices();
  }

  @override
  void didUpdateWidget(AppScopeHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.database != oldWidget.database ||
        widget.settings != oldWidget.settings ||
        widget.clock != oldWidget.clock ||
        widget.idGenerator != oldWidget.idGenerator) {
      _services = _createServices();
    }
  }

  AppServices _createServices() {
    return AppServices.forDatabase(
      widget.database,
      settings: widget.settings,
      clock: widget.clock,
      idGenerator: widget.idGenerator,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(services: _services, child: widget.child);
  }
}
