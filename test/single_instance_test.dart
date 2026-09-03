/// Single-instance guard, which exists because of how tray failures trap users.
///
/// Once the close button hides the window, the only way back in is the tray — and
/// if that icon is unresponsive, a user's natural next move is to launch the app
/// again from their menu. Unguarded that starts a second process which cannot
/// bind the engine's ports, while the window they wanted stays hidden in the
/// first. So a second launch is not an error to refuse: it is a request for the
/// window.
///
/// Every test here points the guard at its own temp directory. The default is the
/// real `~/.local/share/singbox-client`, which holds the rendered config and its
/// node credentials — a test suite has no business binding, planting or deleting
/// files in there, and two test files doing it at once is also how they end up
/// failing only when run together.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:singbox_client/platform/single_instance.dart';

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('singbox_instance_test');
  });

  tearDown(() async {
    await SingleInstance.release();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  /// Claims against this test's own directory.
  Future<bool> claim({void Function()? onActivate}) => SingleInstance.claim(
        onActivate: onActivate ?? () {},
        directory: dir.path,
      );

  test('the first instance claims and listens', () async {
    var activated = false;

    expect(await claim(onActivate: () => activated = true), isTrue);
    // Nothing has asked for the window yet.
    expect(activated, isFalse);
  });

  test('a second claim asks the first to activate, then stands down', () async {
    // This is the whole point of the guard. The user could not reach the tray,
    // so they launched the app again — and what they wanted was the window, not
    // a second copy of the app.
    var firstActivated = false;
    expect(await claim(onActivate: () => firstActivated = true), isTrue);

    var secondActivated = false;
    final second = await claim(onActivate: () => secondActivated = true);

    expect(second, isFalse, reason: 'the socket is already held');
    expect(secondActivated, isFalse,
        reason: "the second process exits; it is not the one showing a window");

    // The message has to cross the socket and be drained, which takes a turn or
    // two of the event loop.
    await Future.delayed(const Duration(milliseconds: 300));
    expect(firstActivated, isTrue, reason: 'the first was never asked to show');
  });

  test('release frees the socket, so a restart claims it', () async {
    expect(await claim(), isTrue);
    await SingleInstance.release();

    // Launching again after a clean quit.
    expect(await claim(), isTrue);
  });

  test('a stale socket is recognised and cleared', () async {
    // What a crash leaves behind: the file is there, nothing is listening. This
    // is the case a lock file cannot distinguish from a live instance, and the
    // reason the guard connects before it decides — a refused connection is the
    // proof that the file is dead.
    final path = await SingleInstance.socketPathForTests(dir.path);
    expect(path, isNotNull);
    File(path!).writeAsStringSync('');

    var activated = false;
    final claimed = await claim(onActivate: () => activated = true);

    expect(claimed, isTrue, reason: 'a dead socket must not block a launch');
    expect(activated, isFalse, reason: 'there was nothing there to ask');
  });

  test('a live socket is not mistaken for a stale one', () async {
    // The inverse, and the more dangerous direction: deleting a socket someone
    // is listening on would leave the running instance unreachable and let a
    // second one start.
    expect(await claim(), isTrue);

    expect(await claim(), isFalse, reason: 'a live holder must be detected');
  });

  test('no data directory means unguarded rather than refusing to start',
      () async {
    // A single instance is a convenience. The failure that matters is a user
    // with no window at all, not a user with two — so when the socket cannot be
    // placed, the launch continues.
    final missing = '${dir.path}/does/not/exist';

    expect(
      await SingleInstance.claim(onActivate: () {}, directory: missing),
      isTrue,
    );
  });
}
