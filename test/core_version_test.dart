/// The version gate both desktop runtimes put in front of a start.
///
/// The rendered config uses 1.12 schema, so an older core rejects it with a
/// schema dump. Reading the number wrong in either direction is a real failure:
/// too strict refuses a core that would have worked, too lax hands the user the
/// dump instead of a sentence naming the version. The parse is separate from the
/// process so the shapes `sing-box version` actually prints can be asserted.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:singbox_client/platform/core_version.dart';

void main() {
  test('reads the number a release prints', () {
    expect(parseCoreVersion('sing-box version 1.13.21'), [1, 13, 21]);
  });

  test('reads a build from source, suffix and all', () {
    // `go build` output carries the commit and the toolchain after the version,
    // and a dev build's version is itself suffixed.
    expect(
      parseCoreVersion('sing-box version 1.12.0-beta.7\n\n'
          'Environment: go1.24.2 linux/amd64\n'
          'Tags: with_gvisor,with_quic\n'
          'Revision: 9a1c0f2\n'),
      [1, 12, 0],
    );
  });

  test('a two-part version leaves the patch at zero', () {
    expect(parseCoreVersion('sing-box version 2.0'), [2, 0, 0]);
  });

  test('nothing numeric is no answer at all', () {
    for (final output in const [
      '',
      'command not found',
      'sing-box version unknown',
    ]) {
      expect(parseCoreVersion(output), isNull, reason: output);
    }
  });

  test('the minimum is met by itself and by anything newer', () {
    expect(versionAtLeast([1, 12, 0], singBoxMinimumVersion), isTrue);
    expect(versionAtLeast([1, 13, 21], singBoxMinimumVersion), isTrue);
    // A major bump is newer even though its minor is lower than the minimum's.
    expect(versionAtLeast([2, 0, 0], singBoxMinimumVersion), isTrue);
  });

  test('an older minor or major is not', () {
    expect(versionAtLeast([1, 11, 15], singBoxMinimumVersion), isFalse);
    expect(versionAtLeast([0, 99, 0], singBoxMinimumVersion), isFalse);
  });

  test('a short or empty list reads as 0.0, not as newer', () {
    // Nothing produces these today, but treating a missing component as absent
    // rather than as zero would let an empty list pass the gate.
    expect(versionAtLeast([], singBoxMinimumVersion), isFalse);
    expect(versionAtLeast([1], singBoxMinimumVersion), isFalse);
    expect(versionAtLeast([2], singBoxMinimumVersion), isTrue);
  });

  test('a version that cannot be read is not treated as too old', () async {
    // The callers only refuse a start on a version they read and rejected, so
    // an unreadable one has to be distinguishable from an old one.
    expect(await readCoreVersion('/nonexistent/sing-box'), isNull);
  });
}
