/// What counts as a usable `sing-box`, shared by the two desktop runtimes.
///
/// Both of them find a binary on disk and have to decide whether the rendered
/// config will even parse on it. Android is exempt: it links libbox at build
/// time, so the engine there cannot be older than the app.
library;

import 'dart:io';

/// Lowest sing-box the rendered config parses on.
///
/// The config uses `route.default_domain_resolver`, `{"action": "sniff"}` rules
/// and `"type": "udp"` DNS servers, all 1.12 schema. An older binary rejects it
/// outright, and its complaint is a schema error several lines long — saying so
/// up front is more use than passing that through.
const singBoxMinimumVersion = (1, 12);

/// The leading `major.minor[.patch]` in `sing-box version` output, or null when
/// there is none to find.
///
/// The first line is `sing-box version 1.13.21`; a build from source can add a
/// suffix, so only the leading numbers are taken.
List<int>? parseCoreVersion(String output) {
  final match = RegExp(r'(\d+)\.(\d+)(?:\.(\d+))?').firstMatch(output);
  if (match == null) return null;
  return [
    for (var group = 1; group <= 3; group++)
      int.tryParse(match.group(group) ?? '0') ?? 0,
  ];
}

/// Runs `<binary> version` and reads the number out of it.
///
/// Null covers every way that can fail to produce an answer — the binary is not
/// executable, it is not sing-box, it printed something unexpected. Callers
/// treat null as "unknown", not as "too old": refusing to start over a version
/// we could not read would break on any build that prints differently.
Future<List<int>?> readCoreVersion(String binary) async {
  try {
    final result = await Process.run(binary, ['version']);
    if (result.exitCode != 0) return null;
    return parseCoreVersion('${result.stdout}');
  } on Object {
    return null;
  }
}

/// Whether [version] is at least [minimum], compared on major and minor only.
bool versionAtLeast(List<int> version, (int, int) minimum) {
  final major = version.isNotEmpty ? version[0] : 0;
  final minor = version.length > 1 ? version[1] : 0;
  if (major != minimum.$1) return major > minimum.$1;
  return minor >= minimum.$2;
}
