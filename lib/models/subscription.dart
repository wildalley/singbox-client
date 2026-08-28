/// Subscription source metadata.
library;

enum SubscriptionKind {
  /// Remote URL returning base64 links, plain links, or a sing-box config.
  remote,

  /// Links pasted by hand.
  manual,

  /// Imported sing-box JSON config (file or pasted text).
  config,
}

class Subscription {
  const Subscription({
    required this.id,
    required this.name,
    required this.kind,
    this.url,
    this.nodeCount = 0,
    this.updatedAt,
    this.lastError,
    this.expiresAt,
    this.usedBytes,
    this.totalBytes,
  });

  final String id;
  final String name;
  final SubscriptionKind kind;

  /// Only set for [SubscriptionKind.remote].
  final String? url;
  final int nodeCount;
  final DateTime? updatedAt;
  final String? lastError;

  /// Quota metadata from the panel's `subscription-userinfo` header.
  final DateTime? expiresAt;
  final int? usedBytes;
  final int? totalBytes;

  bool get isRemote => kind == SubscriptionKind.remote;

  /// True when the panel reported a quota we can show as a progress bar.
  bool get hasQuota => totalBytes != null && totalBytes! > 0;

  /// Fraction of the quota used, clamped to 0..1.
  double get quotaFraction {
    if (!hasQuota) return 0;
    return ((usedBytes ?? 0) / totalBytes!).clamp(0.0, 1.0);
  }

  /// Whole days until expiry; negative once expired, null when unknown.
  int? get daysRemaining {
    final expiry = expiresAt;
    if (expiry == null) return null;
    return expiry.difference(DateTime.now()).inDays;
  }

  Subscription copyWith({
    String? name,
    String? url,
    int? nodeCount,
    DateTime? updatedAt,
    String? lastError,
    bool clearError = false,
    DateTime? expiresAt,
    int? usedBytes,
    int? totalBytes,
  }) {
    return Subscription(
      id: id,
      name: name ?? this.name,
      kind: kind,
      url: url ?? this.url,
      nodeCount: nodeCount ?? this.nodeCount,
      updatedAt: updatedAt ?? this.updatedAt,
      lastError: clearError ? null : (lastError ?? this.lastError),
      expiresAt: expiresAt ?? this.expiresAt,
      usedBytes: usedBytes ?? this.usedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind.name,
        if (url != null) 'url': url,
        'node_count': nodeCount,
        if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
        if (lastError != null) 'last_error': lastError,
        if (expiresAt != null) 'expires_at': expiresAt!.toIso8601String(),
        if (usedBytes != null) 'used_bytes': usedBytes,
        if (totalBytes != null) 'total_bytes': totalBytes,
      };

  static Subscription fromJson(Map<String, dynamic> json) => Subscription(
        id: json['id'] as String,
        name: json['name'] as String,
        kind: SubscriptionKind.values.firstWhere(
          (item) => item.name == json['kind'],
          orElse: () => SubscriptionKind.manual,
        ),
        url: json['url'] as String?,
        nodeCount: (json['node_count'] as num?)?.toInt() ?? 0,
        updatedAt: switch (json['updated_at']) {
          String value => DateTime.tryParse(value),
          _ => null,
        },
        lastError: json['last_error'] as String?,
        expiresAt: switch (json['expires_at']) {
          String value => DateTime.tryParse(value),
          _ => null,
        },
        usedBytes: (json['used_bytes'] as num?)?.toInt(),
        totalBytes: (json['total_bytes'] as num?)?.toInt(),
      );

  /// URL with credentials removed, safe to show in the UI.
  String get redactedUrl {
    final value = url;
    if (value == null || value.isEmpty) return '';
    final uri = Uri.tryParse(value);
    if (uri == null) return 'invalid url';
    final buffer = StringBuffer()
      ..write(uri.scheme)
      ..write('://')
      ..write(uri.host);
    if (uri.hasPort) buffer.write(':${uri.port}');
    if (uri.path.isNotEmpty && uri.path != '/') buffer.write(uri.path);
    if (uri.hasQuery) buffer.write('?…');
    return buffer.toString();
  }
}
