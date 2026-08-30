/// The routing rule-sets, shipped inside the app instead of fetched at start.
///
/// sing-box initializes a `remote` rule-set *during* start and treats the fetch
/// failing as fatal — there is no per-rule-set `optional` flag, so one
/// unreachable URL aborts the whole tunnel. That makes downloading them at
/// start structurally wrong for this app twice over:
///
///  * The CN lists are wanted by precisely the users who cannot reach
///    raw.githubusercontent.com directly.
///  * `download_detour: proxy` does not rescue it. The rule-sets are needed
///    while the route is being built, before the outbound they name can carry
///    traffic, so the fetch goes out on whatever path exists at that moment.
///
/// Bundling them makes start need no network at all, which is also the only way
/// the app can connect offline-first (airplane mode, captive portal, a dead
/// upstream). The cost is freshness: a shipped list is as old as the APK, which
/// is why `RuleSetUpdater` can replace the files on disk afterwards — off the
/// start path, where a failed download costs nothing.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import '../platform/app_paths.dart';

/// Where the rule-sets on disk came from and when they were put there.
class RuleSetInstall {
  const RuleSetInstall({required this.at, required this.downloaded});

  /// When these files were written — unpacked, or downloaded.
  final DateTime at;

  /// True once a download has replaced the shipped copies.
  ///
  /// A bundled install carries no useful date: [at] is when the app first ran,
  /// not when the list was compiled, and an APK can sit in a store for months.
  /// So the UI shows "bundled" rather than an age, and an update is due as soon
  /// as there is a tunnel to fetch through.
  final bool downloaded;
}

class BundledRuleSets {
  const BundledRuleSets._();

  /// Rule-set tag -> asset. The tags are what `route.rule_set` refers to, so
  /// these names are the contract with `ConfigBuilder`, not just file names.
  static const tags = ['geosite-cn', 'geoip-cn', 'geosite-ads'];

  static String assetKey(String tag) => 'assets/rule-sets/$tag.srs';

  /// Name on disk. Both the config's `path` and the updater go through this, so
  /// the two cannot drift.
  static String fileName(String tag) => '$tag.srs';

  /// Directory name under the app's data directory.
  static const dirName = 'rule-sets';

  /// Upstream root for the compiled lists.
  static const upstreamBase = 'https://raw.githubusercontent.com/SagerNet';

  /// Where [tag] is published.
  ///
  /// [base] exists so tests can serve the same paths from a local server.
  /// geoip and geosite are separate repositories — pointing a geoip set at
  /// sing-geosite 404s, which then reads as a network failure.
  static Uri upstreamUrl(String tag, {String base = upstreamBase}) {
    final repo = tag.startsWith('geoip') ? 'sing-geoip' : 'sing-geosite';
    return Uri.parse('$base/$repo/rule-set/${_upstreamFile[tag]}');
  }

  /// Upstream file name per tag. The tags are ours; these are not.
  static const _upstreamFile = {
    'geosite-cn': 'geosite-geolocation-cn.srs',
    'geoip-cn': 'geoip-cn.srs',
    'geosite-ads': 'geosite-category-ads-all.srs',
  };

  /// First bytes of a compiled rule-set. A 404 body or a captive-portal login
  /// page is still an HTTP 200 with content, and only fails on the device.
  static const magic = 'SRS';

  /// Bookkeeping beside the lists: which asset lengths were installed here, and
  /// when the files were last written. Hidden so a directory listing of the
  /// rule-sets stays just the rule-sets.
  static const _recordName = '.installed.json';

  /// Unpacks every rule-set into [dir], returning its path for the config.
  ///
  /// Three things decide whether a file is written, and the order matters:
  ///
  ///  * missing file — always written;
  ///  * the *asset* differs from the one this directory last recorded — written,
  ///    which is what makes a new APK's lists take effect even over a download;
  ///  * otherwise, only when no download is in place and the file on disk no
  ///    longer matches the asset, which repairs a truncated or replaced copy.
  ///
  /// That last condition is why the record exists at all: a downloaded list has
  /// a different length from the shipped one by definition, so comparing with
  /// the file alone would make every launch overwrite the fresh list with the
  /// bundled one.
  ///
  /// `.srs` files are compressed, so a changed list is a changed length in every
  /// practical case, and the check costs one stat instead of reading ~100KB off
  /// disk at every launch.
  static Future<String> extractTo(
    Directory dir, {
    AssetBundle? bundle,
  }) async {
    final assets = bundle ?? rootBundle;
    await dir.create(recursive: true);

    final record = await _readRecord(dir);
    final installed = record?.assetLengths ?? const <String, int>{};
    final downloaded = record?.downloaded ?? false;
    final lengths = <String, int>{};
    var wrote = false;

    for (final tag in tags) {
      final data = await assets.load(assetKey(tag));
      final size = data.lengthInBytes;
      lengths[tag] = size;
      final file = File('${dir.path}/${fileName(tag)}');
      if (file.existsSync() &&
          installed[tag] == size &&
          (downloaded || file.lengthSync() == size)) {
        continue;
      }
      await file.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, size),
        flush: true,
      );
      wrote = true;
    }

    // No write and a record already there means a download is in place: leave
    // its timestamp alone, or the row would claim it was refreshed at launch.
    if (wrote || record == null) {
      await _writeRecord(
        dir,
        _Record(assetLengths: lengths, at: DateTime.now(), downloaded: false),
      );
    }
    return dir.path;
  }

  /// Records that a download replaced the files in [dir].
  ///
  /// Leaves the asset lengths untouched: they say what the *bundle* installed,
  /// so a later app update still recognises its own new assets and replaces the
  /// downloaded lists with them.
  static Future<RuleSetInstall> markDownloaded(Directory dir) async {
    final record = await _readRecord(dir);
    final written = _Record(
      assetLengths: record?.assetLengths ?? const {},
      at: DateTime.now(),
      downloaded: true,
    );
    await _writeRecord(dir, written);
    return RuleSetInstall(at: written.at, downloaded: true);
  }

  /// What is on disk in [dir], or null when the bookkeeping is missing.
  static Future<RuleSetInstall?> installed(Directory dir) async {
    final record = await _readRecord(dir);
    if (record == null) return null;
    return RuleSetInstall(at: record.at, downloaded: record.downloaded);
  }

  /// Unpacks into the app's own data directory.
  ///
  /// Returns null rather than throwing — on a host that cannot name a directory
  /// as much as on a write failure. The engine can still run on remote
  /// rule-sets, and losing the local ones is not a reason to refuse to launch.
  static Future<String?> prepare() async {
    try {
      final data = await appDataDirectory();
      if (data == null) return null;
      return await extractTo(Directory('$data/$dirName'));
    } on Object {
      return null;
    }
  }

  static Future<_Record?> _readRecord(Directory dir) async {
    final file = File('${dir.path}/$_recordName');
    if (!file.existsSync()) return null;
    try {
      return _Record.fromJson(
          Map<String, dynamic>.from(jsonDecode(await file.readAsString())));
    } on Object {
      // Unreadable bookkeeping reads as "nothing installed": the next unpack
      // rewrites the lists and the record, which is cheap and always safe.
      return null;
    }
  }

  static Future<void> _writeRecord(Directory dir, _Record record) =>
      File('${dir.path}/$_recordName')
          .writeAsString(jsonEncode(record.toJson()), flush: true);
}

/// The on-disk bookkeeping. Private: callers see [RuleSetInstall].
class _Record {
  const _Record({
    required this.assetLengths,
    required this.at,
    required this.downloaded,
  });

  final Map<String, int> assetLengths;
  final DateTime at;
  final bool downloaded;

  static _Record fromJson(Map<String, dynamic> json) => _Record(
        assetLengths: switch (json['assets']) {
          Map map => {
              for (final entry in map.entries)
                if (entry.value is num)
                  entry.key.toString(): (entry.value as num).toInt(),
            },
          _ => const {},
        },
        at: DateTime.tryParse(json['at']?.toString() ?? '') ?? DateTime(2000),
        downloaded: json['downloaded'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'assets': assetLengths,
        'at': at.toIso8601String(),
        'downloaded': downloaded,
      };
}
