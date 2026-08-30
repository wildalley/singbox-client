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

/// Why an import or a refresh did not produce nodes.
///
/// A kind rather than a message: this is persisted on the subscription and
/// rendered in two places, and the UI is localized while an exception's text is
/// not. The distinction that matters to the user is whether to try a different
/// path (unreachable, which connecting first may fix) or a different source.
enum SubscriptionFailure {
  /// Nothing answered: offline, blocked, TLS handshake dropped, timed out.
  unreachable,

  /// The server answered with an error status, carried alongside.
  httpStatus,

  /// It answered, and the body holds no node we can use.
  unusableContent,

  /// Not a subscription or config to begin with — a bad URL, a missing file.
  badSource,
}

class Subscription {
  const Subscription({
    required this.id,
    required this.name,
    required this.kind,
    this.url,
    this.nodeCount = 0,
    this.updatedAt,
    this.lastFailure,
    this.lastFailureStatus,
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

  /// How the last refresh failed, or null when it succeeded.
  final SubscriptionFailure? lastFailure;

  /// The status code behind [SubscriptionFailure.httpStatus].
  final int? lastFailureStatus;

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
    SubscriptionFailure? lastFailure,
    int? lastFailureStatus,
    bool clearFailure = false,
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
      lastFailure: clearFailure ? null : (lastFailure ?? this.lastFailure),
      lastFailureStatus:
          clearFailure ? null : (lastFailureStatus ?? this.lastFailureStatus),
      expiresAt: expiresAt ?? this.expiresAt,
      usedBytes: usedBytes ?? this.usedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
    );
  }

  /// Records why the last refresh failed.
  ///
  /// A method rather than a `copyWith` pair because the two fields move
  /// together: a status code means nothing except with
  /// [SubscriptionFailure.httpStatus], so it must be cleared when the reason
  /// changes.
  Subscription failed(SubscriptionFailure failure, {int? status}) =>
      Subscription(
        id: id,
        name: name,
        kind: kind,
        url: url,
        nodeCount: nodeCount,
        updatedAt: updatedAt,
        lastFailure: failure,
        lastFailureStatus: status,
        expiresAt: expiresAt,
        usedBytes: usedBytes,
        totalBytes: totalBytes,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind.name,
        if (url != null) 'url': url,
        'node_count': nodeCount,
        if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
        if (lastFailure != null) 'last_failure': lastFailure!.name,
        if (lastFailureStatus != null) 'last_failure_status': lastFailureStatus,
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
        // A record written by an older build holds an English sentence under
        // `last_error`; it is dropped rather than migrated, and the next refresh
        // writes a kind. Showing a stale failure is not worth a translation of
        // whatever that build happened to say.
        lastFailure: _failureNamed(json['last_failure']),
        lastFailureStatus: (json['last_failure_status'] as num?)?.toInt(),
        expiresAt: switch (json['expires_at']) {
          String value => DateTime.tryParse(value),
          _ => null,
        },
        usedBytes: (json['used_bytes'] as num?)?.toInt(),
        totalBytes: (json['total_bytes'] as num?)?.toInt(),
      );

  static SubscriptionFailure? _failureNamed(Object? name) {
    for (final failure in SubscriptionFailure.values) {
      if (failure.name == name) return failure;
    }
    return null;
  }

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
