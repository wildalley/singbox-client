/// The rule-set update as the app drives it: by hand from Settings, and once by
/// itself after a connect.
///
/// The invariant these exist to hold is that the download never sits on the
/// start path. sing-box reads the lists off disk when it starts, so a fetch that
/// hangs, fails, or is offline may cost nothing but a stale list.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data' show ByteData, Uint8List;

import 'package:flutter/services.dart' show CachingAssetBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:singbox_client/data/rule_set_updater.dart';
import 'package:singbox_client/data/rule_sets.dart';
import 'package:singbox_client/data/storage.dart';
import 'package:singbox_client/state/app_state.dart';

import 'widget_test.dart' show FakeProxyController, node;

/// Stands in for the download. Records the calls and never touches the network.
///
/// It extends the real updater so the state layer keeps its concrete type: the
/// superclass constructor makes an idle `HttpClient`, which [dispose] closes.
class _FakeUpdater extends RuleSetUpdater {
  _FakeUpdater();

  final calls = <({String dir, bool viaLocalProxy})>[];

  /// Completes each [update]. Left pending to model a download in flight.
  var pending = <Completer<RuleSetInstall>>[];

  /// When set, every call fails with it — offline, blocked, or a bad body.
  Object? error;

  /// Held open so a test can assert nothing awaits the download.
  var hang = false;

  @override
  Future<RuleSetInstall> update(Directory dir, {bool viaLocalProxy = false}) {
    calls.add((dir: dir.path, viaLocalProxy: viaLocalProxy));
    if (hang) {
      final completer = Completer<RuleSetInstall>();
      pending.add(completer);
      return completer.future;
    }
    if (error != null) return Future.error(error!);
    return Future.value(
      RuleSetInstall(at: DateTime.now(), downloaded: true),
    );
  }
}

/// Three assets of fixed bytes, so [BundledRuleSets.extractTo] can lay down a
/// bundled install without reading the repository.
class _StubBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => ByteData.sublistView(
        Uint8List.fromList([...'SRS'.codeUnits, 1, ...List.filled(2048, 9)]),
      );
}

void main() {
  late _FakeUpdater updater;

  setUp(() => updater = _FakeUpdater());

  Directory tempDir() {
    final dir = Directory.systemTemp.createTempSync('singbox-state-');
    addTearDown(() => dir.deleteSync(recursive: true));
    return dir;
  }

  /// A directory holding a bundled install: files plus the record that says the
  /// shipped copies are what is there.
  Future<Directory> bundled() async {
    final dir = tempDir();
    await BundledRuleSets.extractTo(dir, bundle: _StubBundle());
    return dir;
  }

  Future<({AppState state, FakeProxyController controller})> build({
    String? ruleSetDir,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final storage = await Storage.open();
    await storage.writeNodes([node('a', 'Tokyo')]);
    final controller = FakeProxyController();
    final state = AppState(
      storage: storage,
      controller: controller,
      ruleSetUpdater: updater,
      ruleSetDir: ruleSetDir,
    );
    addTearDown(state.dispose);
    // The constructor reads the install record off disk.
    await pumpEventQueue();
    return (state: state, controller: controller);
  }

  group('by hand', () {
    test('downloads over the direct path and says it applies next connect',
        () async {
      final dir = await bundled();
      final harness = await build(ruleSetDir: dir.path);
      expect(harness.state.ruleSetInstall?.downloaded, isFalse,
          reason: 'a bundled install should not claim to be a download');

      await harness.state.updateRuleSets();

      expect(updater.calls, [(dir: dir.path, viaLocalProxy: false)],
          reason: 'nothing is listening on the loopback proxy while down');
      expect(harness.state.ruleSetInstall?.downloaded, isTrue);
      expect(harness.state.isUpdatingRuleSets, isFalse);
      expect(harness.state.takeNotice()?.kind, NoticeKind.ruleSetsUpdated);
    });

    test('sends the download through the tunnel while connected', () async {
      final dir = await bundled();
      final harness = await build(ruleSetDir: dir.path);
      await harness.state.connect();
      await pumpEventQueue();
      updater.calls.clear();

      await harness.state.updateRuleSets();

      // The app's own package is excluded from the VPN, so the loopback `mixed`
      // inbound is the only way this request can leave through the node.
      expect(updater.calls.single.viaLocalProxy, isTrue);
    });

    test('a failure keeps the lists that are there and reports it once',
        () async {
      final dir = await bundled();
      final harness = await build(ruleSetDir: dir.path);
      updater.error = RuleSetUpdateException('Could not update geoip-cn');

      await harness.state.updateRuleSets();

      expect(harness.state.ruleSetInstall?.downloaded, isFalse,
          reason: 'the old install record must survive a failed download');
      expect(
        harness.state.takeNotice()?.kind,
        NoticeKind.ruleSetsUpdateFailed,
        reason: 'the updater message is English and names tags, so it is a kind',
      );
      expect(harness.state.takeNotice(), isNull);
    });

    test('says so on a platform with nothing unpacked', () async {
      final harness = await build();

      await harness.state.updateRuleSets();

      expect(harness.state.hasLocalRuleSets, isFalse);
      expect(updater.calls, isEmpty);
      expect(harness.state.takeNotice()?.kind, NoticeKind.ruleSetsUnavailable);
    });

    test('a second tap while one is in flight is ignored', () async {
      final harness = await build(ruleSetDir: (await bundled()).path);
      updater.hang = true;

      final first = harness.state.updateRuleSets();
      await pumpEventQueue();
      expect(harness.state.isUpdatingRuleSets, isTrue);
      await harness.state.updateRuleSets();

      expect(updater.calls, hasLength(1));
      updater.pending.single
          .complete(RuleSetInstall(at: DateTime.now(), downloaded: true));
      await first;
    });
  });

  group('by itself', () {
    test('refreshes a bundled install on the first connect, silently',
        () async {
      final harness = await build(ruleSetDir: (await bundled()).path);

      await harness.state.connect();
      await pumpEventQueue();

      // Bundled always counts as stale: the record's date is when the app first
      // ran, which says nothing about how old the shipped list is.
      expect(updater.calls.single.viaLocalProxy, isTrue);
      expect(harness.state.takeNotice(), isNull,
          reason: 'the user did not ask, and a stale list is not their problem');
    });

    test('does not try again on a later connect', () async {
      final harness = await build(ruleSetDir: (await bundled()).path);

      await harness.state.connect();
      await pumpEventQueue();
      await harness.state.disconnect();
      await harness.state.connect();
      await pumpEventQueue();

      // A silent retry per connect would hammer an upstream that simply cannot
      // be reached from here.
      expect(updater.calls, hasLength(1));
    });

    test('leaves a recent download alone', () async {
      final dir = await bundled();
      await BundledRuleSets.markDownloaded(dir);
      final harness = await build(ruleSetDir: dir.path);

      await harness.state.connect();
      await pumpEventQueue();

      expect(updater.calls, isEmpty);
    });

    test('reports nothing when the silent attempt fails', () async {
      final harness = await build(ruleSetDir: (await bundled()).path);
      updater.error = RuleSetUpdateException('offline');

      await harness.state.connect();
      await pumpEventQueue();

      expect(updater.calls, hasLength(1));
      expect(harness.state.takeNotice(), isNull);
    });

    test('a download in flight does not hold up the connect', () async {
      // The whole point of moving the fetch off the start path: the engine is
      // already running on the lists it read, so nothing here may block a start.
      final harness = await build(ruleSetDir: (await bundled()).path);
      updater.hang = true;

      await harness.state.connect().timeout(const Duration(seconds: 5));

      expect(harness.controller.startedConfigs, hasLength(1));
      expect(harness.state.isConnected, isTrue);
      await pumpEventQueue();
      expect(updater.pending, hasLength(1),
          reason: 'the download should still be open, and nobody waiting on it');
    });
  });
}
