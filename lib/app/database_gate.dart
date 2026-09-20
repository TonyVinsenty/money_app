import 'dart:async';

import 'package:flutter/material.dart';
import 'package:money_app/core/database/app_database.dart';

/// Подпись индикатора загрузки для программ экранного чтения.
const databaseLoadingLabel = 'Загрузка';

/// Заголовок экрана ошибки открытия базы.
const databaseErrorTitle = 'Не удалось открыть базу данных';

/// Пояснение на экране ошибки: без имён исключений и технических слов.
const databaseErrorMessage =
    'Приложению не удалось открыть файл с вашими данными. '
    'Нажмите «Повторить». Если ошибка повторяется, перезапустите приложение.';

/// Подпись кнопки повторной попытки.
const databaseRetryLabel = 'Повторить';

/// Заголовок раскрывающегося пункта с техническим текстом ошибки.
const databaseDetailsLabel = 'Подробности';

/// «Шлюз» над содержимым приложения: открывает базу данных и пускает дальше
/// только когда она открыта.
///
/// Пока база открывается, показывает индикатор загрузки. Если открыть не
/// удалось (файл повреждён, нет места) — экран ошибки с кнопкой «Повторить»,
/// вместо того чтобы приложение молча закрылось. Когда база открыта, строит
/// [builder].
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

  @override
  void initState() {
    super.initState();
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
      setState(() {
        _database = database;
        _error = null;
      });
    } catch (error) {
      if (!mounted || attempt != _attempt) {
        return;
      }
      setState(() => _error = error);
    }
  }

  void _retry() {
    setState(() => _error = null);
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
      return _DatabaseErrorView(error: error, onRetry: _retry);
    }
    return const _DatabaseLoadingView();
  }
}

class _DatabaseLoadingView extends StatelessWidget {
  const _DatabaseLoadingView();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(semanticsLabel: databaseLoadingLabel),
      ),
    );
  }
}

class _DatabaseErrorView extends StatelessWidget {
  const _DatabaseErrorView({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
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
                  Text(
                    databaseErrorTitle,
                    style: textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    databaseErrorMessage,
                    style: textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                    ),
                    onPressed: onRetry,
                    child: const Text(databaseRetryLabel),
                  ),
                  const SizedBox(height: 16),
                  ExpansionTile(
                    title: const Text(databaseDetailsLabel),
                    // Технический текст нужен для отчёта об ошибке, поэтому
                    // его можно выделить и скопировать.
                    childrenPadding: const EdgeInsets.all(16),
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    children: [SelectableText(error.toString())],
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
