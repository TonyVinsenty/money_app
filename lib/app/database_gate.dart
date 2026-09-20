import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:money_app/core/database/app_database.dart';

/// Подпись индикатора загрузки для программ экранного чтения.
const databaseLoadingLabel = 'Загрузка';

/// Заголовок экрана ошибки открытия базы (вынесен в константу, чтобы при
/// смене формулировки правка была в одном месте).
const databaseErrorTitle = 'Не удалось открыть базу данных';

/// Первый абзац пояснения: что случилось и что можно сделать. Без имён
/// исключений и технических слов, без обещаний про целостность данных.
const databaseErrorMessage =
    'Zuno не смог открыть свои данные на этом телефоне. Попробуйте ещё раз. '
    'Если не получается: освободите место на телефоне, перезагрузите его '
    'и обновите Zuno.';

/// Второй абзац: что делать нельзя и куда смотреть за подробностями.
const databaseErrorDataWarning =
    'Не удаляйте приложение и не очищайте его данные: вместе с ними пропадут '
    'все записи. Откройте «Подробности» и передайте этот текст разработчику.';

/// Подпись кнопки повторной попытки.
const databaseRetryLabel = 'Повторить';

/// Заголовок раскрывающегося пункта с техническим текстом ошибки.
const databaseDetailsLabel = 'Подробности (для разработчика)';

/// Подпись кнопки копирования технического текста в буфер обмена.
const databaseCopyDetailsLabel = 'Скопировать подробности';

/// Текст уведомления после копирования.
const databaseCopiedMessage = 'Скопировано';

/// Строка после неудачной повторной попытки; [attempt] — её номер (от 2).
String databaseRetryFailedMessage(int attempt) =>
    'Не получилось. Попытка $attempt.';

/// Добавляется, когда неудачными были уже две повторные попытки подряд.
const databaseRetryUnlikelyMessage =
    'Повторные попытки, скорее всего, не помогут.';

/// Через сколько показывать индикатор загрузки: при быстром открытии базы он
/// не успевает мигнуть.
const databaseSpinnerDelay = Duration(milliseconds: 300);

/// «Шлюз» над содержимым приложения: открывает базу данных и пускает дальше
/// только когда она открыта.
///
/// Пока база открывается, сначала показывает пустой экран, а если открытие
/// затянулось (дольше [databaseSpinnerDelay]) — индикатор загрузки. Если
/// открыть не удалось (файл повреждён, нет места) — экран ошибки с кнопкой
/// «Повторить», вместо того чтобы приложение молча закрылось. Во время
/// повторной попытки экран ошибки остаётся на месте, а кнопка показывает
/// индикатор. Когда база открыта, строит [builder].
///
/// Шлюз владеет открытой им базой и закрывает её, когда сам удаляется из
/// дерева виджетов.
class DatabaseGate extends StatefulWidget {
  const DatabaseGate({required this.open, required this.builder, super.key});

  /// Открывает базу. Вызывается при старте и при каждом нажатии «Повторить»,
  /// но не при простых перерисовках.
  final Future<AppDatabase> Function() open;

  /// Строит приложение, когда база открыта.
  final Widget Function(BuildContext context, AppDatabase database) builder;

  @override
  State<DatabaseGate> createState() => _DatabaseGateState();
}

class _DatabaseGateState extends State<DatabaseGate> {
  AppDatabase? _database;
  Object? _error;

  /// Номер последней начатой попытки: результат более старой игнорируется.
  int _attempt = 0;

  /// Номер попытки, которая закончилась текущей ошибкой [_error].
  int _failedAttempt = 0;

  /// Идёт повторная попытка (экран ошибки при этом остаётся).
  bool _retrying = false;

  /// Пора показывать индикатор первичной загрузки.
  bool _showSpinner = false;

  Timer? _spinnerTimer;

  @override
  void initState() {
    super.initState();
    _spinnerTimer = Timer(databaseSpinnerDelay, () {
      if (mounted) {
        setState(() => _showSpinner = true);
      }
    });
    unawaited(_open());
  }

  Future<void> _open() async {
    final attempt = ++_attempt;
    try {
      // Если open() бросит синхронно, это тоже попадёт в catch ниже.
      final database = await widget.open();
      if (!mounted || attempt != _attempt) {
        // Результат уже никому не нужен: не оставляем базу открытой.
        await _closeQuietly(database);
        return;
      }
      _spinnerTimer?.cancel();
      setState(() {
        _database = database;
        _error = null;
        _retrying = false;
      });
    } catch (error) {
      if (!mounted || attempt != _attempt) {
        return;
      }
      _spinnerTimer?.cancel();
      setState(() {
        _error = error;
        _failedAttempt = attempt;
        _retrying = false;
      });
    }
  }

  void _retry() {
    if (_retrying) return;
    // Экран ошибки не убираем: пользователь видит, что попытка идёт.
    setState(() => _retrying = true);
    unawaited(_open());
  }

  /// Ошибку закрытия игнорируем осознанно: закрываем при выходе, показать её
  /// пользователю уже некому, а сообщать о ней нечем.
  static Future<void> _closeQuietly(AppDatabase database) async {
    try {
      await database.close();
    } catch (_) {}
  }

  @override
  void dispose() {
    _spinnerTimer?.cancel();
    final database = _database;
    if (database != null) {
      unawaited(_closeQuietly(database));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final database = _database;
    if (database != null) {
      return widget.builder(context, database);
    }
    final error = _error;
    if (error != null) {
      return _DatabaseErrorView(
        error: error,
        failedAttempt: _failedAttempt,
        retrying: _retrying,
        onRetry: _retry,
      );
    }
    return _DatabaseLoadingView(showSpinner: _showSpinner);
  }
}

class _DatabaseLoadingView extends StatelessWidget {
  const _DatabaseLoadingView({required this.showSpinner});

  final bool showSpinner;

  @override
  Widget build(BuildContext context) {
    // До задержки — пустой экран цвета темы, чтобы быстрая загрузка не мигала.
    return Scaffold(
      body: showSpinner
          ? const Center(
              child: CircularProgressIndicator(
                semanticsLabel: databaseLoadingLabel,
              ),
            )
          : null,
    );
  }
}

class _DatabaseErrorView extends StatelessWidget {
  const _DatabaseErrorView({
    required this.error,
    required this.failedAttempt,
    required this.retrying,
    required this.onRetry,
  });

  final Object error;

  /// Номер попытки, которая закончилась этой ошибкой (1 — первая, при старте).
  final int failedAttempt;

  /// Идёт повторная попытка: кнопка отключена и показывает индикатор.
  final bool retrying;

  final VoidCallback onRetry;

  Future<void> _copyDetails(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: error.toString()));
    messenger.showSnackBar(
      const SnackBar(content: Text(databaseCopiedMessage)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    // Строки о неудачной повторной попытке: пока идёт новая попытка, их нет.
    final showRetryStatus = !retrying && failedAttempt >= 2;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // liveRegion: программа экранного чтения сама озвучивает
                  // заголовок, когда экран ошибки появляется.
                  Semantics(
                    header: true,
                    liveRegion: true,
                    child: Text(
                      databaseErrorTitle,
                      style: textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    databaseErrorMessage,
                    style: textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    databaseErrorDataWarning,
                    style: textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                    ),
                    onPressed: retrying ? null : onRetry,
                    child: retrying
                        ? const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  semanticsLabel: databaseLoadingLabel,
                                ),
                              ),
                              SizedBox(width: 12),
                              Text(databaseRetryLabel),
                            ],
                          )
                        : const Text(databaseRetryLabel),
                  ),
                  if (showRetryStatus) ...[
                    const SizedBox(height: 12),
                    Semantics(
                      liveRegion: true,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            databaseRetryFailedMessage(failedAttempt),
                            style: textTheme.bodyMedium,
                            textAlign: TextAlign.center,
                          ),
                          if (failedAttempt >= 3)
                            Text(
                              databaseRetryUnlikelyMessage,
                              style: textTheme.bodyMedium,
                              textAlign: TextAlign.center,
                            ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  ExpansionTile(
                    title: const Text(databaseDetailsLabel),
                    // Технический текст нужен для отчёта об ошибке, поэтому
                    // его можно выделить и скопировать.
                    childrenPadding: const EdgeInsets.all(16),
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText(error.toString()),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => unawaited(_copyDetails(context)),
                        child: const Text(databaseCopyDetailsLabel),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
