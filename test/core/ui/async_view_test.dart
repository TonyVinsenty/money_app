import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/ui/async_view.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

AsyncView<List<int>> _view(
  Stream<List<int>> stream, {
  bool withLoading = false,
}) {
  return AsyncView<List<int>>(
    stream: stream,
    isEmpty: (data) => data.isEmpty,
    emptyBuilder: (_) => const Text('empty'),
    dataBuilder: (_, data) => Text('data ${data.join(',')}'),
    loadingBuilder: withLoading ? (_) => const Text('loading') : null,
  );
}

void main() {
  testWidgets('before the first value shows nothing at all', (tester) async {
    final controller = StreamController<List<int>>();
    addTearDown(controller.close);

    await tester.pumpWidget(_host(_view(controller.stream)));

    expect(find.textContaining('data'), findsNothing);
    expect(find.text('empty'), findsNothing);
    expect(find.text(AsyncView.defaultErrorText), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('loadingBuilder is shown until the first value', (tester) async {
    final controller = StreamController<List<int>>();
    addTearDown(controller.close);

    await tester.pumpWidget(_host(_view(controller.stream, withLoading: true)));
    expect(find.text('loading'), findsOneWidget);
    expect(find.text('empty'), findsNothing);

    controller.add([1]);
    await tester.pumpAndSettle();
    expect(find.text('loading'), findsNothing);
    expect(find.text('data 1'), findsOneWidget);
  });

  testWidgets('a value goes to dataBuilder', (tester) async {
    await tester.pumpWidget(_host(_view(Stream.value([1, 2]))));
    await tester.pumpAndSettle();

    expect(find.text('data 1,2'), findsOneWidget);
    expect(find.text('empty'), findsNothing);
  });

  testWidgets('an empty value shows the empty state', (tester) async {
    await tester.pumpWidget(_host(_view(Stream.value(const []))));
    await tester.pumpAndSettle();

    expect(find.text('empty'), findsOneWidget);
    expect(find.textContaining('data'), findsNothing);
  });

  testWidgets('without emptyBuilder an empty value goes to dataBuilder', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        AsyncView<List<int>>(
          stream: Stream.value(const []),
          isEmpty: (data) => data.isEmpty,
          dataBuilder: (_, data) => const Text('data'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('data'), findsOneWidget);
  });

  testWidgets('an error shows the default short text', (tester) async {
    await tester.pumpWidget(
      _host(_view(Stream<List<int>>.error(StateError('boom')))),
    );
    await tester.pumpAndSettle();

    expect(find.text(AsyncView.defaultErrorText), findsOneWidget);
    expect(find.textContaining('boom'), findsNothing);
    expect(find.text('empty'), findsNothing);
  });

  testWidgets('errorBuilder receives the error', (tester) async {
    await tester.pumpWidget(
      _host(
        AsyncView<int>(
          stream: Stream<int>.error('boom'),
          dataBuilder: (_, data) => const Text('data'),
          errorBuilder: (_, error) => Text('custom $error'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('custom boom'), findsOneWidget);
  });

  testWidgets('a new value updates the screen without empty state', (
    tester,
  ) async {
    final controller = StreamController<List<int>>();
    addTearDown(controller.close);

    await tester.pumpWidget(_host(_view(controller.stream)));
    controller.add([1]);
    await tester.pumpAndSettle();
    expect(find.text('data 1'), findsOneWidget);

    controller.add([1, 2]);
    await tester.pumpAndSettle();
    expect(find.text('data 1,2'), findsOneWidget);
    expect(find.text('empty'), findsNothing);

    // Свежая пустая выдача показывает пустое состояние.
    controller.add(const []);
    await tester.pumpAndSettle();
    expect(find.text('empty'), findsOneWidget);
  });

  testWidgets('a synchronous broadcast value shows on the first frame', (
    tester,
  ) async {
    final controller = StreamController<List<int>>.broadcast(sync: true);
    addTearDown(controller.close);

    await tester.pumpWidget(_host(_view(controller.stream)));
    controller.add([7]);
    await tester.pumpAndSettle();

    expect(find.text('data 7'), findsOneWidget);
    expect(find.text('empty'), findsNothing);
  });

  testWidgets('a changed stream resubscribes and keeps the old value', (
    tester,
  ) async {
    final first = StreamController<List<int>>();
    final second = StreamController<List<int>>();
    addTearDown(first.close);
    addTearDown(second.close);

    await tester.pumpWidget(_host(_view(first.stream)));
    first.add([1]);
    await tester.pumpAndSettle();
    expect(find.text('data 1'), findsOneWidget);
    expect(first.hasListener, isTrue);

    await tester.pumpWidget(_host(_view(second.stream)));
    // Старый поток отписан, прежнее значение остаётся без мигания.
    expect(first.hasListener, isFalse);
    expect(second.hasListener, isTrue);
    expect(find.text('data 1'), findsOneWidget);
    expect(find.text('empty'), findsNothing);

    second.add([2]);
    await tester.pumpAndSettle();
    expect(find.text('data 2'), findsOneWidget);

    // Старый поток больше не влияет на экран.
    first.add(const []);
    await tester.pumpAndSettle();
    expect(find.text('empty'), findsNothing);
    expect(find.text('data 2'), findsOneWidget);
  });
}
