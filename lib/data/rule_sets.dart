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
/// upstream). The cost is freshness: the lists are as old as the APK. Re-run
/// `scripts/fetch-rule-sets.sh` and ship again — these are country and
/// ad-domain lists, which move slowly.
library;

import 'dart:io';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import '../platform/app_paths.dart';

class BundledRuleSets {
  const BundledRuleSets._();

  /// Rule-set tag -> asset. The tags are what `route.rule_set` refers to, so
  /// these names are the contract with [ConfigBuilder], not just file names.
  static const tags = ['geosite-cn', 'geoip-cn', 'geosite-ads'];

  static String assetKey(String tag) => 'assets/rule-sets/$tag.srs';

  /// Directory name under the app's data directory.
  static const dirName = 'rule-sets';

  /// Unpacks every rule-set into [dir], returning its path for the config.
  ///
  /// Rewrites a file whose size differs from the asset, which is what makes an
  /// app update take effect; `.srs` files are compressed, so a changed list is
  /// a changed length in every practical case, and the check costs one stat
  /// instead of reading ~100KB off disk at every launch.
  static Future<String> extractTo(
    Directory dir, {
    AssetBundle? bundle,
  }) async {
    final assets = bundle ?? rootBundle;
    await dir.create(recursive: true);
    for (final tag in tags) {
      final data = await assets.load(assetKey(tag));
      final file = File('${dir.path}/$tag.srs');
      if (file.existsSync() && file.lengthSync() == data.lengthInBytes) {
        continue;
      }
      await file.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
    }
    return dir.path;
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
}
