/// The launchable Android apps that can be excluded from the VPN tunnel.
library;

import 'dart:io';

import 'package:flutter/services.dart';

import 'app_paths.dart';

class InstalledApp {
  const InstalledApp({required this.packageName, required this.label});

  final String packageName;
  final String label;
}

const installedAppsMethod = 'installedApps';
const _channel = MethodChannel(appControlChannel);

/// Reads the launchable apps exposed by the Android host.
Future<List<InstalledApp>> installedApps() async {
  if (!Platform.isAndroid) return const [];
  final raw = await _channel.invokeMethod<List<Object?>>(installedAppsMethod);
  return parseInstalledApps(raw);
}

/// Converts the platform channel payload into stable, display-ready rows.
///
/// Kept separate from [installedApps] so malformed host entries are ignored
/// without making the picker unusable, and so the sorting/deduplication rules
/// are testable without an Android device.
List<InstalledApp> parseInstalledApps(Object? raw) {
  if (raw is! List) return const [];
  final seen = <String>{};
  final result = <InstalledApp>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final packageName = item['packageName']?.toString().trim() ?? '';
    if (packageName.isEmpty || !seen.add(packageName)) continue;
    final label = item['label']?.toString().trim() ?? '';
    result.add(InstalledApp(
      packageName: packageName,
      label: label.isEmpty ? packageName : label,
    ));
  }
  result.sort((a, b) {
    final byLabel = a.label.toLowerCase().compareTo(b.label.toLowerCase());
    return byLabel == 0 ? a.packageName.compareTo(b.packageName) : byLabel;
  });
  return result;
}
