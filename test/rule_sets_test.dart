/// The rule-sets are the one part of the config that points at files rather
/// than describing itself, so a tag renamed on one side and not the other fails
/// only on a device, at start, as an unreadable rule-set. These check the
/// shipped assets, the unpacking, and that the config's paths are the paths
/// unpacking actually produces.
library;

import 'dart:io';
import 'dart:typed_data' show ByteData;

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

    test('falls back to null with no host listening', () async {
      // Which is what desktop gets, and what makes the remote rule-sets the
      // fallback rather than a hard failure.
      expect(await appDataDirectory(), isNull);
      expect(await BundledRuleSets.prepare(), isNull);
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
