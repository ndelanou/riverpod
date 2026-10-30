import 'dart:async';

import 'package:riverpod/misc.dart';
import 'package:riverpod/riverpod.dart';
import 'package:test/test.dart';

const _timeout = Duration(milliseconds: 500);

Stream<int> _ticks() =>
    Stream.periodic(const Duration(milliseconds: 10), (i) => i);

class _Reader extends Notifier<int> {
  _Reader(this.target);

  final ProviderListenable<Future<int>> target;

  @override
  int build() => 0;

  Future<int> readTarget() => ref.read(target);
}

void main() {
  group('ProviderContainer.keepFutureReadsActive', () {
    test('defaults to false, and child containers inherit it', () {
      expect(ProviderContainer.test().keepFutureReadsActive, isFalse);

      final enabled = ProviderContainer.test(keepFutureReadsActive: true);
      expect(
        ProviderContainer.test(parent: enabled).keepFutureReadsActive,
        isTrue,
      );
      expect(
        ProviderContainer.test(
          parent: enabled,
          keepFutureReadsActive: false,
        ).keepFutureReadsActive,
        isFalse,
      );
    });

    test('when false, read(provider.future) of a stream provider never '
        'completes', () async {
      final provider = StreamProvider<int>((ref) => _ticks());
      final container = ProviderContainer.test();

      await expectLater(
        container.read(provider.future).timeout(_timeout),
        throwsA(isA<TimeoutException>()),
      );
    });

    group('when true', () {
      late ProviderContainer container;

      setUp(() {
        container = ProviderContainer.test(keepFutureReadsActive: true);
      });

      test('read(provider.future) of a stream provider completes', () async {
        final provider = StreamProvider<int>((ref) => _ticks());

        expect(await container.read(provider.future).timeout(_timeout), 0);
      });

      test(
        'read(provider.future) completes when the provider waits for a stream '
        'provider',
        () async {
          final stream = StreamProvider<int>((ref) => _ticks());
          final provider = FutureProvider<int>(
            (ref) async => await ref.watch(stream.future) + 1,
          );

          expect(await container.read(provider.future).timeout(_timeout), 1);
        },
      );

      test('read(provider.selectAsync(...)) completes', () async {
        final provider = StreamProvider<int>((ref) => _ticks());

        expect(
          await container
              .read(provider.selectAsync((value) => value + 10))
              .timeout(_timeout),
          10,
        );
      });

      test(
        'Ref.read completes, even when the reading provider is paused',
        () async {
          final stream = StreamProvider<int>((ref) => _ticks());
          final reader = NotifierProvider<_Reader, int>(
            () => _Reader(stream.future),
          );
          final subscription = container.listen(reader, (_, _) {});
          addTearDown(subscription.close);
          subscription.pause();

          final value = await container
              .read(reader.notifier)
              .readTarget()
              .timeout(_timeout);

          expect(value, 0);
        },
      );

      test('an auto-dispose provider stays alive until its future completes, '
          'then is disposed', () async {
        final provider = StreamProvider.autoDispose<int>((ref) => _ticks());

        final future = container.read(provider.future);
        await container.pump();
        expect(container.exists(provider), isTrue);

        expect(await future.timeout(_timeout), 0);
        await container.pump();
        expect(container.exists(provider), isFalse);
      });

      test('a failed future is rethrown and stops the listening', () async {
        final provider = FutureProvider.autoDispose<int>(
          (ref) async => throw StateError('boom'),
        );

        await expectLater(
          container.read(provider.future),
          throwsA(isA<StateError>()),
        );
        await container.pump();
        expect(container.exists(provider), isFalse);
      });

      test(
        'a read that does not return a future stops listening at once',
        () async {
          final provider = Provider.autoDispose<int>((ref) => 42);

          expect(container.read(provider), 42);
          await container.pump();
          expect(container.exists(provider), isFalse);
        },
      );

      test(
        'disposing the container while a read waits does not throw',
        () async {
          final controller = StreamController<int>();
          addTearDown(controller.close);
          final provider = StreamProvider<int>((ref) => controller.stream);

          final future = container.read(provider.future);
          container.dispose();

          await expectLater(future, throwsA(anything));
        },
      );
    });
  });
}
