import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProviderScope.keepFutureReadsActive', () {
    Future<WidgetRef> pumpScope(
      WidgetTester tester, {
      bool? keepFutureReadsActive,
    }) async {
      late WidgetRef ref;
      await tester.pumpWidget(
        ProviderScope(
          keepFutureReadsActive: keepFutureReadsActive,
          child: Consumer(
            builder: (context, widgetRef, _) {
              ref = widgetRef;
              return const SizedBox();
            },
          ),
        ),
      );
      return ref;
    }

    testWidgets('is passed to the container', (tester) async {
      final ref = await pumpScope(tester, keepFutureReadsActive: true);

      expect(ref.container.keepFutureReadsActive, isTrue);
    });

    testWidgets('when true, WidgetRef.read(provider.future) completes', (
      tester,
    ) async {
      final provider = StreamProvider<int>((ref) => Stream.value(42));
      final ref = await pumpScope(tester, keepFutureReadsActive: true);

      int? value;
      unawaited(ref.read(provider.future).then((v) => value = v));
      await tester.pump();

      expect(value, 42);
    });

    testWidgets('when not set, WidgetRef.read(provider.future) stays pending', (
      tester,
    ) async {
      final provider = StreamProvider<int>((ref) => Stream.value(42));
      final ref = await pumpScope(tester);

      int? value;
      // The pending future fails when the scope is disposed at the end of the test.
      unawaited(
        ref
            .read(provider.future)
            .then((v) => value = v, onError: (Object _) {}),
      );
      await tester.pump();

      expect(value, isNull);
    });
  });
}
