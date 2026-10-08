import 'package:flutter/material.dart';

/// Индикатор загрузки по центру: для `loadingBuilder`, когда пустое место
/// выглядело бы как зависший экран.
class AsyncLoading extends StatelessWidget {
  const AsyncLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: CircularProgressIndicator(),
      ),
    );
  }
}

/// Показывает данные из потока и берёт на себя три «служебных» состояния
/// (ADR 0002, «`AsyncView`»).
///
/// - Пока поток не отдал первое значение, показывается [loadingBuilder] (по
///   умолчанию — пустое место). Пустое состояние тут не показываем никогда:
///   оно значит «спросили, и там пусто», а не «ответ ещё не пришёл».
/// - Пришло значение: если [isEmpty] говорит «пусто» и задан [emptyBuilder],
///   показываем его, иначе — [dataBuilder].
/// - Поток вернул ошибку: [errorBuilder] (по умолчанию короткий текст).
///
/// Поток должен быть один и тот же между перерисовками (его создаёт
/// вызывающий): при смене потока виджет переподписывается, а прежнее значение
/// остаётся на экране, пока не придёт новое, поэтому ничего не мигает.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({
    required this.stream,
    required this.dataBuilder,
    this.isEmpty,
    this.emptyBuilder,
    this.errorBuilder,
    this.loadingBuilder,
    super.key,
  });

  final Stream<T> stream;
  final Widget Function(BuildContext context, T data) dataBuilder;

  /// Признак «данных нет» для пришедшего значения. Без него и без
  /// [emptyBuilder] пустого состояния нет.
  final bool Function(T data)? isEmpty;
  final WidgetBuilder? emptyBuilder;

  /// Строитель ошибки. Получает саму ошибку, но по умолчанию её не показывает.
  final Widget Function(BuildContext context, Object error)? errorBuilder;
  final WidgetBuilder? loadingBuilder;

  static const defaultErrorText = 'Не удалось загрузить данные';

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<T>(
      stream: stream,
      builder: (context, snapshot) {
        final error = snapshot.error;
        if (error != null) {
          return errorBuilder?.call(context, error) ??
              const Center(
                child: Text(defaultErrorText, textAlign: TextAlign.center),
              );
        }
        // Значение может быть `null`, если T допускает null, поэтому смотрим
        // на признак «значение пришло», а не на сам `data`.
        if (!snapshot.hasData) {
          return loadingBuilder?.call(context) ?? const SizedBox.shrink();
        }
        final data = snapshot.requireData;
        final empty = emptyBuilder;
        if (empty != null && (isEmpty?.call(data) ?? false)) {
          return empty(context);
        }
        return dataBuilder(context, data);
      },
    );
  }
}
