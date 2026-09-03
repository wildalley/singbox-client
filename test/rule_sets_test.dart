/// The rule-sets are the one part of the config that points at files rather
/// than describing itself, so a tag renamed on one side and not the other fails
/// only on a device, at start, as an unreadable rule-set. These check the
/// shipped assets, the unpacking, and that the config's paths are the paths
/// unpacking actually produces.
library;

import 'dart:io';
import 'dart:typed_data' show ByteData, Uint8List;

import 'package:flutter/services.dart' show AssetBundle, CachingAssetBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:singbox_client/data/config_builder.dart';
import 'package:singbox_client/data/rule_sets.dart';
import 'package:singbox_client/models/app_settings.dart';
import 'package:singbox_client/platform/app_paths.dart';

/// Serves the repository as the asset bundle. Asset keys are repo-relative
/// paths, which is exactly the mapping pubspec's `assets:` entry creates, so
/// this reads the same bytes the APK will carry.
class _RepoBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(await File(key).readAsBytes());
}

/// The same bundle with some keys replaced: an app update, from here.
class _PatchedBundle extends CachingAssetBundle {
  _PatchedBundle(this._inner, this._patches);

  final AssetBundle _inner;
  final Map<String, Uint8List> _patches;

  @override
  Future<ByteData> load(String key) async {
    final patch = _patches[key];
    return patch == null
        ? await _inner.load(key)
        : ByteData.sublistView(patch);
  }
}

Directory _tempDir() =>
    Directory.systemTemp.createTempSync('singbox-rule-sets-');

void main() {
  final AssetBundle bundle = _RepoBundle();

  group('bundled assets', () {
    test('every tag ships a compiled rule-set', () {
      for (final tag in BundledRuleSets.tags) {
        final file = File(BundledRuleSets.assetKey(tag));
        expect(file.existsSync(), isTrue,
            reason: '${file.path} is missing — run scripts/fetch-rule-sets.sh');
        final bytes = file.readAsBytesSync();
        // SRS magic. A captive portal or a 404 page would land here as HTML and
        // only fail on the device, where it reads as a corrupt rule-set.
        expect(String.fromCharCodes(bytes.take(3)), 'SRS',
            reason: '${file.path} is not a compiled rule-set');
        expect(bytes.length, greaterThan(1024),
            reason: '${file.path} is too small to be a real list');
      }
    });

    test('pubspec bundles the directory they live in', () {
      // Without this the files are in the repo and not in the APK, and the
      // engine falls back to downloading at start — the failure this replaces.
      expect(File('pubspec.yaml').readAsStringSync(),
          contains('- assets/rule-sets/'));
    });
  });

  group('unpacking', () {
    test('writes every rule-set, byte for byte', () async {
      final dir = _tempDir();
      addTearDown(() => dir.deleteSync(recursive: true));

      final path = await BundledRuleSets.extractTo(dir, bundle: bundle);
      expect(path, dir.path);
      for (final tag in BundledRuleSets.tags) {
        expect(
          File('${dir.path}/$tag.srs').readAsBytesSync(),
          File(BundledRuleSets.assetKey(tag)).readAsBytesSync(),
        );
      }
    });

    test('replaces a file of the wrong size and leaves a current one alone',
        () async {
      final dir = _tempDir();
      addTearDown(() => dir.deleteSync(recursive: true));
      await BundledRuleSets.extractTo(dir, bundle: bundle);

      final stale = File('${dir.path}/${BundledRuleSets.tags.first}.srs');
      final fresh = File('${dir.path}/${BundledRuleSets.tags.last}.srs');
      stale.writeAsBytesSync(const [0]);
      // Length is the whole test: mtime is what tells us the second file was
      // skipped rather than rewritten with identical bytes.
      final marker = DateTime(2020);
      fresh.setLastModifiedSync(marker);

      await BundledRuleSets.extractTo(dir, bundle: bundle);

      expect(
        stale.readAsBytesSync(),
        File(BundledRuleSets.assetKey(BundledRuleSets.tags.first))
            .readAsBytesSync(),
        reason: 'an app update ships new lists, so a changed size must rewrite',
      );
      expect(fresh.lastModifiedSync(), marker,
          reason: 'an unchanged rule-set should not be rewritten every launch');
    });

    test('creates the directory when it is not there yet', () async {
      final parent = _tempDir();
      addTearDown(() => parent.deleteSync(recursive: true));
      final dir = Directory('${parent.path}/nested/${BundledRuleSets.dirName}');

      await BundledRuleSets.extractTo(dir, bundle: bundle);

      expect(dir.existsSync(), isTrue);
    });
  });

  group('a download and a relaunch', () {
    /// A downloaded list, as the updater leaves it: different bytes from the
    /// asset, and the record saying a download is in place.
    Future<File> download(Directory dir, String tag) async {
      final file = File('${dir.path}/${BundledRuleSets.fileName(tag)}');
      // Longer than the asset, so a length comparison against the file alone
      // would decide the shipped copy has to be written back over it.
      file.writeAsBytesSync(
        [...file.readAsBytesSync(), ...List.filled(64, 7)],
      );
      await BundledRuleSets.markDownloaded(dir);
      return file;
    }

    test('a launch leaves the downloaded lists alone', () async {
      final dir = _tempDir();
      addTearDown(() => dir.deleteSync(recursive: true));
      await BundledRuleSets.extractTo(dir, bundle: bundle);
      final fresh = await download(dir, BundledRuleSets.tags.first);
      final bytes = fresh.readAsBytesSync();

      await BundledRuleSets.extractTo(dir, bundle: bundle);

      expect(fresh.readAsBytesSync(), bytes,
          reason: 'unpacking overwrote a newer list with the shipped one');
      final install = await BundledRuleSets.installed(dir);
      expect(install!.downloaded, isTrue,
          reason: 'the row would go back to claiming a bundled install');
    });

    test('a launch that changed nothing keeps the download timestamp', () async {
      final dir = _tempDir();
      addTearDown(() => dir.deleteSync(recursive: true));
      await BundledRuleSets.extractTo(dir, bundle: bundle);
      await download(dir, BundledRuleSets.tags.first);
      final at = (await BundledRuleSets.installed(dir))!.at;

      await BundledRuleSets.extractTo(dir, bundle: bundle);

      // Or the settings row would say the lists were refreshed at launch.
      expect((await BundledRuleSets.installed(dir))!.at, at);
    });

    test('a new app version still wins over a download', () async {
      final dir = _tempDir();
      addTearDown(() => dir.deleteSync(recursive: true));
      await BundledRuleSets.extractTo(dir, bundle: bundle);
      final tag = BundledRuleSets.tags.first;
      final file = await download(dir, tag);

      // What an app update looks like from here: the same key, other bytes.
      final shipped = File(BundledRuleSets.assetKey(tag)).readAsBytesSync();
      final newer = Uint8List.fromList([...shipped, ...List.filled(9, 3)]);
      await BundledRuleSets.extractTo(dir, bundle: _PatchedBundle(bundle, {
        BundledRuleSets.assetKey(tag): newer,
      }));

      expect(file.readAsBytesSync(), newer,
          reason: 'an app update ships new lists and has to replace the old');
      final install = await BundledRuleSets.installed(dir);
      expect(install!.downloaded, isFalse,
          reason: 'the files came from the bundle again, not from a download');
    });

    test('markDownloaded keeps the asset lengths the bundle installed',
        () async {
      // Which is the whole reason a new APK can still win: the record has to
      // keep saying what the *bundle* put here, not what the download did.
      final dir = _tempDir();
      addTearDown(() => dir.deleteSync(recursive: true));
      await BundledRuleSets.extractTo(dir, bundle: bundle);
      await BundledRuleSets.markDownloaded(dir);

      final record = File('${dir.path}/.installed.json').readAsStringSync();
      for (final tag in BundledRuleSets.tags) {
        expect(record, contains('"$tag"'));
      }
    });

    test('unreadable bookkeeping is not a failure', () async {
      final dir = _tempDir();
      addTearDown(() => dir.deleteSync(recursive: true));
      await BundledRuleSets.extractTo(dir, bundle: bundle);
      File('${dir.path}/.installed.json').writeAsStringSync('{oh no');

      expect(await BundledRuleSets.installed(dir), isNull);
      // And the next unpack simply rewrites both lists and record.
      expect(await BundledRuleSets.extractTo(dir, bundle: bundle), dir.path);
      expect((await BundledRuleSets.installed(dir))!.downloaded, isFalse);
    });
  });

  group('the host side', () {
    test('answers the channel method Dart asks for the directory on', () {
      // Dart and Kotlin agree on this name by convention only; a rename on one
      // side leaves prepare() returning null, which silently falls back to
      // downloading the rule-sets at start — the failure this replaces.
      final kotlin = File('android/app/src/main/kotlin/com/wildalley/'
              'singbox_client/MainActivity.kt')
          .readAsStringSync();
      expect(kotlin, contains('"$appControlChannel"'),
          reason: 'the host listens on a different channel name');
      expect(kotlin, contains('"$dataDirMethod" ->'),
          reason: 'MainActivity does not handle $dataDirMethod');
      expect(kotlin, contains('filesDir.absolutePath'),
          reason: 'the directory must be the one libbox is set up with');
    });

    test('derives an XDG path when no host answers', () async {
      // Which is what desktop gets: the channel throws, and the path is worked
      // out here instead. Pointed at a temp root so the test does not create a
      // directory in the real ~/.local/share.
      final root = _tempDir();
      addTearDown(() => root.deleteSync(recursive: true));

      expect(
        await appDataDirectory(environment: {'XDG_DATA_HOME': root.path}),
        '${root.path}/$desktopDataDirName',
      );
    });

    test('is null when there is nowhere to derive from', () async {
      // No XDG_DATA_HOME, no HOME. Callers treat this as "no local rule-sets"
      // and fall back to downloading them rather than failing to start.
      expect(await appDataDirectory(environment: const {}), isNull);
    });

    test('a relative XDG_DATA_HOME is ignored, as the spec says', () async {
      final home = _tempDir();
      addTearDown(() => home.deleteSync(recursive: true));

      expect(
        await appDataDirectory(
          environment: {'XDG_DATA_HOME': 'relative/share', 'HOME': home.path},
        ),
        '${home.path}/.local/share/$desktopDataDirName',
      );
    });
  });

  test('the config points at the files unpacking creates', () async {
    // The seam: ConfigBuilder names `$dir/$tag.srs` and BundledRuleSets writes
    // `$dir/$tag.srs`, from two lists of tags that must not drift apart.
    final dir = _tempDir();
    addTearDown(() => dir.deleteSync(recursive: true));
    await BundledRuleSets.extractTo(dir, bundle: bundle);

    final config = ConfigBuilder.build(
      nodes: const [],
      selectedNodeId: null,
      // blockAds pulls in the third set; without it one asset goes unreferenced.
      settings: const AppSettings(blockAds: true),
      clashSecret: 'test-secret',
      ruleSetDir: dir.path,
    );

    final paths = [
      for (final item in config['route']['rule_set'] as List)
        (item as Map)['path'] as String,
    ];
    expect(paths, hasLength(BundledRuleSets.tags.length));
    for (final path in paths) {
      expect(File(path).existsSync(), isTrue, reason: '$path was not unpacked');
    }
  });
}
