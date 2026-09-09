/// The marker a runtime encodes into [ProxyState.message], and the notice the
/// state layer decodes back out of it.
///
/// This is the whole path a classified start failure travels: a desktop
/// controller has no access to the localizations, so it names the condition and
/// the UI turns it into a sentence. If the encoding and the decoding disagree
/// the user gets the raw marker in a snackbar, which is why the round trip is
/// asserted for every value rather than for a representative one.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:singbox_client/models/proxy_state.dart';
// NoticeKind and AppNotice are parts of this library, not imports of their own.
import 'package:singbox_client/state/app_state.dart';

void main() {
  test('every problem survives the trip through a message', () {
    for (final problem in EngineProblem.values) {
      expect(EngineProblem.of(problem.encode()), problem,
          reason: '${problem.name} without a detail');
      expect(EngineProblem.detailOf(problem.encode()), isNull);

      expect(EngineProblem.of(problem.encode('detail')), problem,
          reason: '${problem.name} with a detail');
      expect(EngineProblem.detailOf(problem.encode('detail')), 'detail');
    }
  });

  test('an empty detail encodes as no detail', () {
    // The callers that have nothing to add pass null, but `_fail`'s optional
    // parameter makes '' reachable, and a trailing space would then be read
    // back as a detail of ''.
    expect(EngineProblem.missing.encode(''), EngineProblem.missing.encode());
    expect(EngineProblem.detailOf(EngineProblem.missing.encode('')), isNull);
  });

  test('a detail keeps its own spaces', () {
    // Linux puts the binary to run setcap on in the detail. A path can contain
    // spaces, so only the first one separates the name from the detail.
    const path = '/home/a b/sing-box';
    final message = EngineProblem.unprivileged.encode(path);

    expect(EngineProblem.of(message), EngineProblem.unprivileged);
    expect(EngineProblem.detailOf(message), path);
  });

  test('engine output is not mistaken for a marker', () {
    for (final message in const [
      '',
      'sing-box exited with code 1',
      'engine-problem',
      'FATAL[0000] decode config at 1+1: json: unknown field "foo"',
      // The prefix has to lead: an engine line that quotes one is still output.
      'error: engine-problem:missing',
    ]) {
      expect(EngineProblem.of(message), isNull, reason: message);
      expect(EngineProblem.detailOf(message), isNull, reason: message);
    }
  });

  test('an unknown name is output, not a problem', () {
    // A marker written by a newer runtime than this build knows about. Passing
    // it through shows something rather than swallowing the failure.
    expect(EngineProblem.of('engine-problem:someFutureCode'), isNull);
  });

  test('each problem becomes a translatable notice', () {
    const expected = {
      EngineProblem.missing: NoticeKind.engineMissing,
      EngineProblem.tooOld: NoticeKind.engineTooOld,
      EngineProblem.unprivileged: NoticeKind.tunUnprivileged,
      EngineProblem.elevationFailed: NoticeKind.elevationFailed,
      EngineProblem.configRejected: NoticeKind.configRejected,
      EngineProblem.apiTimeout: NoticeKind.engineApiTimeout,
      EngineProblem.systemProxyUnavailable: NoticeKind.systemProxyUnavailable,
    };

    // Not a lookup over `expected` alone: this fails when a value is added to
    // the enum without being given a notice, which would otherwise reach the
    // user as the raw marker.
    expect(expected.keys, containsAll(EngineProblem.values));

    for (final entry in expected.entries) {
      final notice = AppState.noticeFor(entry.key.encode());
      expect(notice.kind, entry.value, reason: entry.key.name);
      expect(notice.isError, isTrue);
    }
  });

  test('the notice carries the detail for the kinds that show one', () {
    expect(AppState.noticeFor(EngineProblem.tooOld.encode('1.9.3')).detail,
        '1.9.3');
    expect(
        AppState.noticeFor(EngineProblem.configRejected.encode('1')).detail,
        '1');
    expect(
        AppState.noticeFor(
                EngineProblem.unprivileged.encode('/usr/bin/sing-box'))
            .detail,
        '/usr/bin/sing-box');
  });

  test('an unprivileged failure with no detail is the prompt, not a path', () {
    // Windows and Linux share the code; the missing detail is what tells the
    // UI to name the UAC prompt instead of a setcap line.
    final notice = AppState.noticeFor(EngineProblem.unprivileged.encode());

    expect(notice.kind, NoticeKind.tunUnprivileged);
    expect(notice.detail, isNull);
  });

  test('unclassified text passes through as itself', () {
    const message = 'sing-box exited with code 2';
    final notice = AppState.noticeFor(message);

    expect(notice.kind, NoticeKind.passthrough);
    expect(notice.detail, message);
    expect(notice.isError, isTrue);
  });
}
