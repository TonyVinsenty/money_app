import 'dart:io';

import 'package:flutter/material.dart';
import 'package:money_app/core/time/clock.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/csv_import/domain/csv_import_failures.dart';
import 'package:money_app/features/csv_import/domain/csv_import_store.dart';
import 'package:money_app/features/csv_import/domain/parse_csv_import.dart';
import 'package:money_app/features/csv_import/domain/plan_csv_import.dart';
import 'package:money_app/features/csv_import/presentation/csv_import_texts.dart';

/// Чтение файла по пути. В тестах подменяется.
typedef ReadFileBytes = Future<List<int>> Function(String path);

// Синхронное чтение: файл небольшой и уже лежит в каталоге приложения, а
// асинхронный ввод-вывод в widget-тестах не завершается.
Future<List<int>> _readFile(String path) async => File(path).readAsBytesSync();

/// Экран «Загрузка из CSV» (ADR 0009, п. 6): проверяет копию выбранного файла,
/// показывает предпросмотр или ошибки и по кнопке «Загрузить» пишет всё сразу.
///
/// Закрывается с числом добавленных операций или с `null`, если ничего не
/// загружено. Копию файла удаляет тот, кто открыл экран.
class CsvImportScreen extends StatefulWidget {
  const CsvImportScreen({
    required this.path,
    required this.clock,
    required this.store,
    required this.categories,
    this.readBytes = _readFile,
    super.key,
  });

  /// Путь к копии выбранного файла.
  final String path;
  final Clock clock;
  final CsvImportStore store;

  /// Все категории приложения: по ним подписываются родители новых
  /// подкатегорий («Еда → Кафе»).
  final Stream<List<Category>> categories;
  final ReadFileBytes readBytes;

  @override
  State<CsvImportScreen> createState() => _CsvImportScreenState();
}

/// Что показывает экран.
sealed class _View {
  const _View();
}

final class _Checking extends _View {
  const _Checking();
}

/// Файл не прочитан или не разобран целиком: только сообщение.
final class _Failed extends _View {
  const _Failed(this.message);

  final String message;
}

/// Ошибки строк, по возрастанию номера строки.
final class _RowErrors extends _View {
  const _RowErrors(this.errors);

  final List<CsvRowError> errors;
}

final class _Preview extends _View {
  const _Preview(this.plan, this.categoryLines, {required this.noRows});

  final CsvImportPlan plan;
  final List<String> categoryLines;

  /// В файле только строка заголовков.
  final bool noRows;
}

class _CsvImportScreenState extends State<CsvImportScreen> {
  _View _view = const _Checking();
  bool _writing = false;
  bool _writeFailed = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    _View view;
    try {
      final bytes = await widget.readBytes(widget.path);
      switch (parseCsvImport(bytes, clock: widget.clock)) {
        case CsvImportFileFailed(:final failure):
          view = _Failed(csvFileFailureMessage(failure));
        case CsvImportParsed(:final rows, :final errors):
          final plan = await widget.store.prepare(rows);
          final all = _byLine([...errors, ...plan.errors]);
          if (all.isNotEmpty) {
            view = _RowErrors(all);
          } else {
            final existing = await widget.categories.first;
            view = _Preview(
              plan,
              csvImportNewCategoryLines(plan.categoriesToCreate, existing),
              noRows: rows.isEmpty,
            );
          }
      }
    } catch (_) {
      view = const _Failed(csvImportReadFailedMessage);
    }
    if (mounted) setState(() => _view = view);
  }

  /// Сортировка по номеру строки; ошибки одной строки — в прежнем порядке.
  static List<CsvRowError> _byLine(List<CsvRowError> errors) {
    final indexed = errors.indexed.toList()
      ..sort((a, b) {
        final byLine = a.$2.line.compareTo(b.$2.line);
        return byLine != 0 ? byLine : a.$1.compareTo(b.$1);
      });
    return [for (final (_, error) in indexed) error];
  }

  Future<void> _write(CsvImportPlan plan) async {
    setState(() {
      _writing = true;
      _writeFailed = false;
    });
    try {
      await widget.store.write(plan);
      // Любая ошибка, не только Exception: иначе `_writing` останется true,
      // а с ним и запрет «назад» — экран не закрыть до перезапуска.
      // База при сбое не меняется (одна транзакция).
    } catch (_) {
      if (mounted) {
        setState(() {
          _writing = false;
          _writeFailed = true;
        });
      }
      return;
    }
    if (mounted) Navigator.of(context).pop(plan.transactions.length);
  }

  @override
  Widget build(BuildContext context) {
    final view = _view;
    return PopScope(
      // Пока идёт запись, уйти с экрана нельзя: результат должен дойти.
      canPop: !_writing,
      child: Scaffold(
        appBar: AppBar(title: const Text(csvImportTitle)),
        body: switch (view) {
          _Checking() => const _Progress(csvImportCheckingLabel),
          _Failed(:final message) => _Message([message]),
          _RowErrors(:final errors) => _ErrorList(errors),
          _Preview() => _previewBody(context, view),
        },
        bottomNavigationBar: switch (view) {
          _Checking() => null,
          _Preview(:final plan) when plan.transactions.isNotEmpty => _buttons(
            context,
            plan,
          ),
          _ => _closeButton(context),
        },
      ),
    );
  }

  Widget _previewBody(BuildContext context, _Preview view) {
    final plan = view.plan;
    final textTheme = Theme.of(context).textTheme;
    final skipped = [
      if (plan.skippedExisting > 0)
        csvImportSkippedExisting(plan.skippedExisting),
      if (plan.skippedDeleted > 0) csvImportSkippedDeleted(plan.skippedDeleted),
    ];
    if (plan.transactions.isEmpty) {
      return _Message([
        view.noRows ? csvImportNoRowsMessage : csvImportNothingToAddMessage,
        ...skipped,
      ]);
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          csvImportWillAdd(plan.transactions.length),
          style: textTheme.titleMedium,
        ),
        for (final line in skipped)
          Padding(padding: const EdgeInsets.only(top: 8), child: Text(line)),
        if (view.categoryLines.isNotEmpty) ...[
          const SizedBox(height: 24),
          Semantics(
            header: true,
            child: Text(
              csvImportNewCategoriesTitle,
              style: textTheme.titleSmall,
            ),
          ),
          for (final line in view.categoryLines)
            Padding(padding: const EdgeInsets.only(top: 8), child: Text(line)),
        ],
        if (_writeFailed) ...[
          const SizedBox(height: 24),
          Text(
            csvImportWriteFailedMessage,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );
  }

  Widget _buttons(BuildContext context, CsvImportPlan plan) {
    return _BottomBar(
      children: [
        TextButton(
          onPressed: _writing ? null : () => Navigator.of(context).pop(),
          child: const Text(csvImportCancelButton),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: _writing ? null : () => _write(plan),
          child: _writing
              ? const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    Text(csvImportWritingLabel),
                  ],
                )
              : const Text(csvImportLoadButton),
        ),
      ],
    );
  }

  Widget _closeButton(BuildContext context) {
    return _BottomBar(
      children: [
        FilledButton.tonal(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(csvImportCloseButton),
        ),
      ],
    );
  }
}

/// Кнопки внизу экрана, прижатые вправо.
class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: children,
        ),
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(label),
        ],
      ),
    );
  }
}

/// Один или несколько абзацев текста с прокруткой.
class _Message extends StatelessWidget {
  const _Message(this.lines);

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final (i, line) in lines.indexed)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
            child: Text(
              line,
              style: i == 0 ? Theme.of(context).textTheme.bodyLarge : null,
            ),
          ),
      ],
    );
  }
}

/// Пояснение и первые [csvImportShownErrorsLimit] ошибок строк.
class _ErrorList extends StatelessWidget {
  const _ErrorList(this.errors);

  final List<CsvRowError> errors;

  @override
  Widget build(BuildContext context) {
    final shown = errors.take(csvImportShownErrorsLimit);
    final rest = errors.length - shown.length;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          csvImportErrorsIntro,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 8),
        for (final error in shown)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(csvRowErrorMessage(error)),
          ),
        if (rest > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(csvImportMoreErrors(rest)),
          ),
      ],
    );
  }
}
