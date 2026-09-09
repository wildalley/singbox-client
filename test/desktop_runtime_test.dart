/// The bookkeeping both desktop runtimes now share.
///
/// This logic was written twice — once in the Linux controller, once in the
/// Windows one — and it is exactly the kind that drifts: a session counter that
/// decides whether a slow start may still touch shared state, a latch that keeps
/// the first error message from being overwritten by a vaguer one, and a queue
/// that stops a stop from restoring host proxy settings a start just applied.
/// Two copies meant one side could gain a guard while the other kept the race.
///
/// Asserted against the base class directly rather than through a controller,
/// because the platform-specific halves need a real `sing-box` process to reach
/// most of this.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:singbox_client/models/proxy_state.dart';
import 'package:singbox_client/platform/desktop_runtime.dart';

/// The base class with nothing added: what a subclass inherits, alone.
class _Runtime extends DesktopRuntime {}

void main() {
  group('sessions', () {
    test('a new session invalidates the one before it', () async {
      // The failure this prevents: a disconnect issued during a slow start gets
      // overwritten by the start it was meant to cancel, leaving the UI saying
      // disconnected while an engine is running.
      final runtime = _Runtime();
      addTearDown(runtime.closeStreams);

      final first = runtime.beginSession();
      final second = runtime.beginSession();

      expect(runtime.isCurrentSession(first), isFalse);
      expect(runtime.isCurrentSession(second), isTrue);
      expect(second, greaterThan(first));
    });

    test('disposal invalidates every session, including the current one',
        () async {
      final runtime = _Runtime();
      final session = runtime.beginSession();
      expect(runtime.isCurrentSession(session), isTrue);

      runtime.markDisposed();

      expect(runtime.isCurrentSession(session), isFalse,
          reason: 'work in flight must not touch a disposed runtime');
      runtime.closeStreams();
    });

    test('markDisposed reports whether it was the one that disposed', () {
      // What lets a subclass write `if (!markDisposed()) return;` and know its
      // own teardown runs exactly once.
      final runtime = _Runtime();
      addTearDown(runtime.closeStreams);

      expect(runtime.markDisposed(), isTrue);
      expect(runtime.markDisposed(), isFalse);
      expect(runtime.isDisposed, isTrue);
    });
  });

  group('errors', () {
    test('the first message of a session wins', () async {
      // A failing start unwinds through several layers, each with something to
      // say. The first is the specific one — "core not found" beats the generic
      // "failed to start" that follows it out.
      final runtime = _Runtime();
      addTearDown(runtime.closeStreams);
      final seen = <String>[];
      runtime.states
          .where((state) => state.stage == ProxyStage.error)
          .listen((state) => seen.add(state.message ?? ''));

      final session = runtime.beginSession();
      runtime.emitError('specific', session: session);
      runtime.emitError('vague', session: session);
      await pumpEventQueue();

      expect(seen, ['specific']);
    });

    test('a later session may report again', () async {
      // The latch is per session, not for the life of the runtime: a second
      // connect attempt that fails must still be able to say so.
      final runtime = _Runtime();
      addTearDown(runtime.closeStreams);
      final seen = <String>[];
      runtime.states
          .where((state) => state.stage == ProxyStage.error)
          .listen((state) => seen.add(state.message ?? ''));

      runtime.emitError('first attempt', session: runtime.beginSession());
      runtime.emitError('second attempt', session: runtime.beginSession());
      await pumpEventQueue();

      expect(seen, ['first attempt', 'second attempt']);
    });

    test('fail encodes a problem rather than a sentence', () async {
      // The state layer turns these markers into localized text. A sentence
      // built here would reach the user untranslated.
      final runtime = _Runtime();
      addTearDown(runtime.closeStreams);
      runtime.beginSession();

      runtime.fail(EngineProblem.tooOld, '1.11.0');

      final message = runtime.currentState.message ?? '';
      expect(EngineProblem.of(message), EngineProblem.tooOld);
      expect(EngineProblem.detailOf(message), '1.11.0');
    });
  });

  group('the lifecycle queue', () {
    test('runs operations in order, never overlapping', () async {
      // start, stop and reload all mutate the same process handle and the same
      // host proxy settings. Overlapping them is how a stop ends up restoring
      // settings a start has just applied.
      final runtime = _Runtime();
      addTearDown(runtime.closeStreams);
      final order = <String>[];

      Future<void> slow(String name, Duration delay) async {
        order.add('$name:start');
        await Future<void>.delayed(delay);
        order.add('$name:end');
      }

      final first = runtime.enqueueLifecycle(
        () => slow('a', const Duration(milliseconds: 30)),
      );
      final second = runtime.enqueueLifecycle(
        () => slow('b', const Duration(milliseconds: 1)),
      );
      await Future.wait([first, second]);

      // 'b' is quicker but queued second, so it cannot start until 'a' is done.
      expect(order, ['a:start', 'a:end', 'b:start', 'b:end']);
    });

    test('a failed operation does not poison the queue', () async {
      // A start that throws must not stop the disconnect queued behind it —
      // that disconnect is what puts the host's proxy settings back.
      final runtime = _Runtime();
      addTearDown(runtime.closeStreams);
      var ranAfter = false;

      final failing = runtime.enqueueLifecycle(
        () async => throw StateError('start failed'),
      );

      await expectLater(failing, throwsStateError,
          reason: 'the caller still has to see its own failure');
      await runtime.enqueueLifecycle(() async => ranAfter = true);

      expect(ranAfter, isTrue);
    });
  });

  group('emission guards', () {
    test('a disposed runtime emits nothing', () async {
      // Teardown order in both controllers is: mark disposed, release
      // everything, close the streams last. The parts released in between must
      // not be able to emit on their way out.
      final runtime = _Runtime();
      final traffic = <ProxyTraffic>[];
      final groups = <ProxyGroup>[];
      final logs = <ProxyLogEntry>[];
      runtime.traffic.listen(traffic.add);
      runtime.groups.listen(groups.add);
      runtime.logs.listen(logs.add);

      runtime.markDisposed();
      runtime.emitTraffic(const ProxyTraffic(downlink: 1));
      runtime.emitGroup(const ProxyGroup(tag: 'proxy', selected: '', delays: {}));
      runtime.log('a line');
      await pumpEventQueue();

      expect(traffic, isEmpty);
      expect(groups, isEmpty);
      expect(logs, isEmpty);
      runtime.closeStreams();
    });

    test('blank log lines are dropped', () async {
      // The engine emits them around its startup banner, and a log page full of
      // empty rows is worse than one that is merely long.
      final runtime = _Runtime();
      addTearDown(runtime.closeStreams);
      final logs = <String>[];
      runtime.logs.listen((entry) => logs.add(entry.message));

      runtime.log('');
      runtime.log('   ');
      runtime.log('real line');
      await pumpEventQueue();

      expect(logs, ['real line']);
    });

    test('currentState is the last state emitted', () async {
      // AppState reads this when it attaches, so a runtime that already moved
      // has to be able to say where it got to.
      final runtime = _Runtime();
      addTearDown(runtime.closeStreams);
      expect(runtime.currentState.stage, ProxyStage.disconnected);

      runtime.emitState(const ProxyState(stage: ProxyStage.connected));

      expect(runtime.currentState.stage, ProxyStage.connected);
    });
  });

  group('the line pump', () {
    test('splits a byte stream into log lines', () async {
      // Engine output arrives in whatever chunks the pipe hands over, which is
      // not lines: a single read can carry three of them and half of a fourth.
      final runtime = _Runtime();
      addTearDown(runtime.closeStreams);
      final logs = <String>[];
      runtime.logs.listen((entry) => logs.add(entry.message));

      final output = Stream<List<int>>.fromIterable([
        'first\nsec'.codeUnits,
        'ond\nthird\n'.codeUnits,
      ]);
      final sub = runtime.pipeLines(output);
      await pumpEventQueue();
      await sub.cancel();

      expect(logs, ['first', 'second', 'third']);
    });

    test('onLine diverts the lines a subclass wants to keep', () async {
      // Linux keeps a tail of the engine's own output to quote in a failure
      // message, which the plain path must not collect.
      final runtime = _Runtime();
      addTearDown(runtime.closeStreams);
      final diverted = <String>[];

      final sub = runtime.pipeLines(
        Stream<List<int>>.fromIterable(['one\ntwo\n'.codeUnits]),
        onLine: diverted.add,
      );
      await pumpEventQueue();
      await sub.cancel();

      expect(diverted, ['one', 'two']);
    });
  });
}
