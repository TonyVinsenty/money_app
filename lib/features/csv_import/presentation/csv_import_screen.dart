import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:money_app/core/time/clock.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/csv_import/domain/csv_import_failures.dart';
import 'package:money_app/features/csv_import/domain/csv_import_result.dart';
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
/// Закрывается с [CsvImportResult] (сколько операций и счетов добавлено) или с
/// `null`, если ничего не загружено. Копию файла удаляет тот, кто открыл экран.
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
  const _Preview(this.plan, this.categoryGroups, {required this.noRows});

  final CsvImportPlan plan;
  final List<CsvImportCategoryGroup> categoryGroups;

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
        case CsvImportParsed(
          :final rows,
          :final errors,
          :final openingBalances,
          :final transfers,
          :final recurring,
        ):
          final plan = await widget.store.prepare(
            rows,
            openingBalances: openingBalances,
            transfers: transfers,
            recurring: recurring,
          );
          final all = _byLine([...errors, ...plan.errors]);
          if (all.isNotEmpty) {
            view = _RowErrors(all);
          } else {
            final existing = await widget.categories.first;
            view = _Preview(
              plan,
              csvImportNewCategoryGroups(plan.categoriesToCreate, existing),
              noRows:
                  rows.isEmpty &&
                  openingBalances.isEmpty &&
                  transfers.isEmpty &&
                  recurring.isEmpty,
            );
          }
      }
    } catch (_) {
      view = const _Failed(csvImportReadFailedMessage);
    }
    if (!mounted) return;
    setState(() => _view = view);
    _announce(_summary(view));
  }

  /// Главная фраза нового состояния экрана для скринридера.
  static String _summary(_View view) => switch (view) {
    _Checking() => csvImportCheckingLabel,
    _Failed(:final message) => message,
    _RowErrors() => csvImportErrorsIntro,
    _Preview(:final plan, :final noRows) when _nothingToWrite(plan) =>
      noRows ? csvImportNoRowsMessage : csvImportNothingToAddMessage,
    _Preview(:final plan) => csvImportPreviewAnnouncement(
      transactions: plan.transactions.length,
      accounts: plan.accountsToCreate,
      transfers: plan.transfers.length,
      recurring: plan.recurring.length,
    ),
  };

  /// Ни операций, ни счетов к созданию: кнопки «Загрузить» нет.
  static bool _nothingToWrite(CsvImportPlan plan) =>
      plan.transactions.isEmpty &&
      plan.transfers.isEmpty &&
      plan.recurring.isEmpty &&
      plan.accountsToCreate.isEmpty;

  /// Содержимое экрана сменилось целиком, а фокус VoiceOver и TalkBack
  /// остался на прежнем месте: говорим, что теперь на экране.
  void _announce(String message) {
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        message,
        Directionality.of(context),
      ),
    );
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
    _announce(csvImportWritingLabel);
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
        _announce(csvImportWriteFailedMessage);
      }
      return;
    }
    if (mounted) {
      Navigator.of(context).pop(
        CsvImportResult(
          transactions: plan.transactions.length,
          transfers: plan.transfers.length,
          recurring: plan.recurring.length,
          accounts: plan.accountsToCreate.length,
        ),
      );
    }
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
          _Preview(:final plan) when !_nothingToWrite(plan) => _buttons(
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
    if (_nothingToWrite(plan)) {
      return _Message([
        view.noRows ? csvImportNoRowsMessage : csvImportNothingToAddMessage,
        ...skipped,
      ]);
    }
    final accounts = csvImportSortedAccounts(plan.accountsToCreate);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final (index, line) in [
          if (plan.transactions.isNotEmpty)
            csvImportWillAdd(plan.transactions.length),
          if (plan.transfers.isNotEmpty)
            csvImportWillAddTransfers(plan.transfers.length),
          if (plan.recurring.isNotEmpty)
            csvImportWillAddRecurring(plan.recurring.length),
          if (plan.transactions.isEmpty && accounts.isNotEmpty)
            csvImportWillCreateAccounts(accounts.length),
        ].indexed)
          Padding(
            padding: EdgeInsets.only(top: index == 0 ? 0 : 6),
            child: Text(line, style: textTheme.titleMedium),
          ),
        for (final line in skipped)
          Padding(padding: const EdgeInsets.only(top: 8), child: Text(line)),
        if (accounts.isNotEmpty) ...[
          const SizedBox(height: 24),
          Semantics(
            header: true,
            child: Text(csvImportNewAccountsTitle, style: textTheme.titleSmall),
          ),
          for (final account in accounts)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: 8, start: 16),
              child: Semantics(
                label: csvImportAccountSpoken(account),
                excludeSemantics: true,
                child: Text(csvImportAccountLine(account)),
              ),
            ),
        ],
        if (view.categoryGroups.isNotEmpty) ...[
          const SizedBox(height: 24),
          Semantics(
            header: true,
            child: Text(
              csvImportNewCategoriesTitle,
              style: textTheme.titleSmall,
            ),
          ),
          for (final group in view.categoryGroups) ...[
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Semantics(
                header: true,
                child: Text(group.title, style: textTheme.labelLarge),
              ),
            ),
            for (final line in group.lines)
              Padding(
                padding: const EdgeInsetsDirectional.only(top: 8, start: 16),
                child: Text(line),
              ),
          ],
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
        FilledButton(
          onPressed: _writing ? null : () => _write(plan),
          // Кружок без подписи скринридер называет просто «индикатор»:
          // прячем его, кнопка читается текстом «Загружаем…».
          child: _writing
              ? const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ExcludeSemantics(
                      child: SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
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

/// Кнопки внизу экрана, прижатые вправо. Если в строку не помещаются
/// (крупный текст), встают друг под другом, главная — сверху.
class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: OverflowBar(
          alignment: MainAxisAlignment.end,
          spacing: 8,
          overflowAlignment: OverflowBarAlignment.end,
          overflowDirection: VerticalDirection.up,
          overflowSpacing: 8,
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
          // Подпись — текст ниже; кружок скринридеру не нужен.
          const ExcludeSemantics(child: CircularProgressIndicator()),
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
