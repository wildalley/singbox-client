/// Runtime state reported by the platform proxy controller.
library;

enum ProxyStage {
  disconnected,
  requestingPermission,
  starting,
  connected,
  stopping,
  error;

  bool get isBusy =>
      this == ProxyStage.starting ||
      this == ProxyStage.stopping ||
      this == ProxyStage.requestingPermission;

  bool get isActive => this == ProxyStage.connected || this == ProxyStage.starting;
}

class ProxyState {
  const ProxyState({
    this.stage = ProxyStage.disconnected,
    this.message,
    this.since,
  });

  final ProxyStage stage;

  /// Error detail when [stage] is [ProxyStage.error]; already redacted.
  final String? message;

  /// When the current connection was established.
  final DateTime? since;

  bool get isConnected => stage == ProxyStage.connected;

  static const disconnected = ProxyState();
}

/// Traffic counters. Rates are per-second deltas reported by sing-box.
class ProxyTraffic {
  const ProxyTraffic({
    this.uplink = 0,
    this.downlink = 0,
    this.uplinkTotal = 0,
    this.downlinkTotal = 0,
    this.connectionsIn = 0,
    this.connectionsOut = 0,
    this.memory = 0,
  });

  final int uplink;
  final int downlink;
  final int uplinkTotal;
  final int downlinkTotal;
  final int connectionsIn;
  final int connectionsOut;
  final int memory;

  static const zero = ProxyTraffic();

  static ProxyTraffic fromMap(Map<Object?, Object?> map) => ProxyTraffic(
        uplink: _int(map['uplink']),
        downlink: _int(map['downlink']),
        uplinkTotal: _int(map['uplinkTotal']),
        downlinkTotal: _int(map['downlinkTotal']),
        connectionsIn: _int(map['connectionsIn']),
        connectionsOut: _int(map['connectionsOut']),
        memory: _int(map['memory']),
      );

  static int _int(Object? value) => switch (value) {
        int v => v,
        num v => v.toInt(),
        _ => 0,
      };
}

class ProxyLogEntry {
  const ProxyLogEntry({required this.message, required this.at});

  final String message;
  final DateTime at;
}

/// Formats a byte count for display: `1.2 MB`.
String formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = value >= 100 || unit == 0 ? 0 : 1;
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}

/// Formats a per-second rate for display: `1.2 MB/s`.
String formatRate(int bytesPerSecond) =>
    bytesPerSecond <= 0 ? '—' : '${formatBytes(bytesPerSecond)}/s';

/// Formats an elapsed duration as `1h 04m` / `04:12`.
String formatUptime(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes % 60;
  final seconds = duration.inSeconds % 60;
  if (hours > 0) {
    return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
  }
  return '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}';
}
