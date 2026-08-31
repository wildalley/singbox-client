/// The rule-set download, against a real HTTP server on loopback.
///
/// What matters here is what a *bad* response does: the files the engine reads
/// at start live in this directory, so a 404 page or a truncated body must leave
/// the old list exactly where it was rather than becoming an unreadable
/// rule-set that only fails on a device.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:singbox_client/data/config_builder.dart';
import 'package:singbox_client/data/local_proxy.dart';
import 'package:singbox_client/data/rule_set_updater.dart';
import 'package:singbox_client/data/rule_sets.dart';

/// A body that passes the magic and length checks, distinct per [tag].
Uint8List _compiled(String tag) => Uint8List.fromList([
      ...'SRS'.codeUnits,
      1,
      ...List.filled(2048, tag.hashCode & 0xff),
    ]);

void main() {
  late HttpServer server;
  late String base;

  /// Per-path handler, keyed by the request path. Anything unhandled is a 404,
  /// which is also what a wrong upstream file name looks like.
  late Map<String, void Function(HttpResponse)> routes;

  setUp(() async {
    routes = {};
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://${server.address.address}:${server.port}';
    server.listen((request) async {
      final handler = routes[request.uri.path];
      if (handler == null) {
        request.response.statusCode = HttpStatus.notFound;
        request.response.write('404: Not Found');
      } else {
        handler(request.response);
      }
      await request.response.close();
    });
  });

  tearDown(() => server.close(force: true));

  /// Serves every tag from [base], with [bodies] overriding individual tags.
  void serveAll({Map<String, Uint8List>? bodies}) {
    for (final tag in BundledRuleSets.tags) {
      final path = BundledRuleSets.upstreamUrl(tag, base: base).path;
      final body = bodies?[tag] ?? _compiled(tag);
      routes[path] = (response) => response.add(body);
    }
  }

  Directory tempDir() {
    final dir = Directory.systemTemp.createTempSync('singbox-updater-');
    addTearDown(() => dir.deleteSync(recursive: true));
    return dir;
  }

  RuleSetUpdater updater() {
    final it = RuleSetUpdater(base: base);
    addTearDown(it.dispose);
    return it;
  }

  test('writes every tag and records the download', () async {
    serveAll();
    final dir = tempDir();

    final install = await updater().update(dir);

    for (final tag in BundledRuleSets.tags) {
      expect(
        File('${dir.path}/${BundledRuleSets.fileName(tag)}').readAsBytesSync(),
        _compiled(tag),
        reason: 'the file the config points at must hold the fetched bytes',
      );
    }
    expect(install.downloaded, isTrue);
    // Which is what tells the next launch not to unpack the shipped lists over
    // these, and the settings row to show an age instead of "bundled".
    expect((await BundledRuleSets.installed(dir))!.downloaded, isTrue);
  });

  test('a 404 leaves the previous list in place and reports the failure',
      () async {
    final dir = tempDir();
    final tag = BundledRuleSets.tags.first;
    final old = File('${dir.path}/${BundledRuleSets.fileName(tag)}')
      ..writeAsBytesSync(_compiled('old'));

    // Every tag but the first, so the run is a partial success.
    serveAll();
    routes.remove(BundledRuleSets.upstreamUrl(tag, base: base).path);

    await expectLater(
      updater().update(dir),
      throwsA(isA<RuleSetUpdateException>()),
    );

    expect(old.readAsBytesSync(), _compiled('old'),
        reason: 'a failed fetch must not disturb the list the engine reads');
    expect(await BundledRuleSets.installed(dir), isNull,
        reason: 'a partial run must be retried, not remembered as current');
  });

  test('an HTML error page is rejected rather than written', () async {
    // A captive portal and a proxy error page both arrive as an HTTP 200 with a
    // body; on disk they would only fail on the device, at start.
    final dir = tempDir();
    final tag = BundledRuleSets.tags.first;
    serveAll(bodies: {
      tag: Uint8List.fromList(
        '<html><body>${'sign in ' * 200}</body></html>'.codeUnits,
      ),
    });

    await expectLater(
      updater().update(dir),
      throwsA(isA<RuleSetUpdateException>()),
    );

    expect(File('${dir.path}/${BundledRuleSets.fileName(tag)}').existsSync(),
        isFalse);
  });

  test('a body too short to be a list is rejected', () async {
    final dir = tempDir();
    final tag = BundledRuleSets.tags.first;
    serveAll(bodies: {tag: Uint8List.fromList('SRS\x01 short'.codeUnits)});

    await expectLater(
      updater().update(dir),
      throwsA(isA<RuleSetUpdateException>()),
    );

    expect(File('${dir.path}/${BundledRuleSets.fileName(tag)}').existsSync(),
        isFalse);
  });

  test('leaves no staging files behind, on success or on failure', () async {
    final dir = tempDir();
    serveAll(bodies: {
      BundledRuleSets.tags.first: Uint8List.fromList('nope'.codeUnits),
    });

    await expectLater(
      updater().update(dir),
      throwsA(isA<RuleSetUpdateException>()),
    );
    serveAll();
    await updater().update(dir);

    final leftovers = dir
        .listSync()
        .map((entity) => entity.path)
        .where((path) => path.endsWith('.new'));
    expect(leftovers, isEmpty);
  });

  test('creates the directory when nothing was ever unpacked', () async {
    serveAll();
    final parent = tempDir();
    final dir = Directory('${parent.path}/${BundledRuleSets.dirName}');

    await updater().update(dir);

    expect(dir.existsSync(), isTrue);
  });

  test('the tunnel path names the port the config listens on', () {
    // findProxy cannot be read back off an HttpClient, so this is the seam: a
    // request goes to the loopback `mixed` inbound the config declares, which is
    // the only way in-app HTTP can leave through the selected node.
    expect(
      localProxyDirective(viaLocalProxy: true),
      'PROXY 127.0.0.1:${ConfigBuilder.localProxyPort}',
    );
    expect(localProxyDirective(viaLocalProxy: false), 'DIRECT');
  });
}
