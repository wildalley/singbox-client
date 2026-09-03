/// User-defined routing rules.
///
/// The bundled rule-sets answer "China direct, ads blocked, everything else
/// proxied", which is the right default and the wrong answer for any specific
/// thing a user cares about — one work domain that must not be proxied, one
/// service that must be, one tracker to drop. Those are single lines, not lists,
/// and shipping a rule-set for them is not possible.
///
/// Kept deliberately small. Each rule is one matcher and one destination, which
/// covers what a user can reason about; anything more expressive is a config
/// file, and this app already renders one.
library;

/// What a rule matches on.
enum RuleMatcher {
  /// Exact hostname. `example.com` matches only that name.
  domain('domain'),

  /// A name and everything under it. `example.com` also matches
  /// `api.example.com`, which is what people usually mean by a domain rule.
  domainSuffix('domain_suffix'),

  /// Substring anywhere in the name. The escape hatch for `*-tracker-*` shapes.
  domainKeyword('domain_keyword'),

  /// A CIDR block, or a bare address.
  ipCidr('ip_cidr'),

  /// A single port, matched on the destination.
  port('port'),

  /// The process making the request, by executable name. Desktop only — Android
  /// has per-app proxy for this, and sing-box needs the process name from a
  /// platform that will give it.
  processName('process_name');

  const RuleMatcher(this.field);

  /// The sing-box route-rule key this becomes.
  final String field;

  static RuleMatcher fromField(String? value) => values.firstWhere(
        (matcher) => matcher.field == value,
        orElse: () => domainSuffix,
      );
}

/// Why a rule cannot be rendered.
///
/// A kind rather than a message: the UI says it in the user's language, and the
/// model has no business holding English.
enum RuleProblem {
  /// Nothing typed yet.
  empty,

  /// Not a port number in 1–65535.
  port,

  /// Not an address or CIDR block.
  cidr,

  /// A URL where a hostname belongs — the most common mistake, and one sing-box
  /// accepts as a domain that will never match.
  url,
}

/// Where a matched connection goes.
enum RuleTarget {
  /// Through the selected node.
  proxy('proxy'),

  /// Straight out, bypassing the tunnel.
  direct('direct'),

  /// Dropped.
  block('block');

  const RuleTarget(this.key);

  final String key;

  static RuleTarget fromKey(String? value) => values.firstWhere(
        (target) => target.key == value,
        orElse: () => proxy,
      );
}

/// One user-defined rule.
class CustomRule {
  const CustomRule({
    required this.id,
    required this.matcher,
    required this.value,
    required this.target,
    this.enabled = true,
  });

  final String id;
  final RuleMatcher matcher;

  /// The pattern, already trimmed. Its meaning depends on [matcher].
  final String value;

  final RuleTarget target;

  /// Disabled rules are kept but not rendered, so a user can park one without
  /// retyping it. This is the reason a rule is a record rather than a line of
  /// text.
  final bool enabled;

  CustomRule copyWith({
    RuleMatcher? matcher,
    String? value,
    RuleTarget? target,
    bool? enabled,
  }) =>
      CustomRule(
        id: id,
        matcher: matcher ?? this.matcher,
        value: value ?? this.value,
        target: target ?? this.target,
        enabled: enabled ?? this.enabled,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'matcher': matcher.field,
        'value': value,
        'target': target.key,
        'enabled': enabled,
      };

  static CustomRule fromJson(Map<String, dynamic> json) => CustomRule(
        id: json['id'] as String? ?? '',
        matcher: RuleMatcher.fromField(json['matcher'] as String?),
        value: (json['value'] as String? ?? '').trim(),
        target: RuleTarget.fromKey(json['target'] as String?),
        // Absent means enabled: a record written before the flag existed was
        // one the user meant to be active.
        enabled: json['enabled'] as bool? ?? true,
      );

  /// Why this rule cannot be rendered, or null when it can.
  ///
  /// Checked before the config is built, not after: sing-box rejects a malformed
  /// route rule by refusing to start, and a user who mistyped a port would get
  /// "the tunnel will not come up" with no hint as to which line did it. The
  /// returned value is a [RuleProblem] rather than a sentence so the UI can say
  /// it in the user's language.
  RuleProblem? get problem {
    if (value.isEmpty) return RuleProblem.empty;
    switch (matcher) {
      case RuleMatcher.port:
        final port = int.tryParse(value);
        if (port == null || port < 1 || port > 65535) {
          return RuleProblem.port;
        }
      case RuleMatcher.ipCidr:
        if (!_looksLikeCidr(value)) return RuleProblem.cidr;
      case RuleMatcher.domain:
      case RuleMatcher.domainSuffix:
      case RuleMatcher.domainKeyword:
        // A keyword is a substring, so it has no shape to check beyond being
        // non-empty. The two domain forms only have to be free of the things
        // that mean the user typed a URL instead of a host.
        if (matcher != RuleMatcher.domainKeyword && _looksLikeUrl(value)) {
          return RuleProblem.url;
        }
      case RuleMatcher.processName:
        break;
    }
    return null;
  }

  bool get isValid => problem == null;

  /// Whether [value] parses as an address, with or without a prefix length.
  ///
  /// sing-box takes both `10.0.0.0/8` and a bare `10.0.0.1`, so both are allowed
  /// here; what is rejected is a prefix that is not a number or is out of range
  /// for the family, which sing-box would refuse at start.
  static bool _looksLikeCidr(String value) {
    final slash = value.indexOf('/');
    final host = slash < 0 ? value : value.substring(0, slash);
    final address = _parseAddress(host);
    if (address == null) return false;
    if (slash < 0) return true;
    final prefix = int.tryParse(value.substring(slash + 1));
    if (prefix == null || prefix < 0) return false;
    return prefix <= (address ? 32 : 128);
  }

  /// True for IPv4, false for IPv6, null when it is neither.
  ///
  /// Hand-rolled rather than `InternetAddress`, which lives in `dart:io` — this
  /// file is a model and is reached from tests that do not want that dependency.
  static bool? _parseAddress(String value) {
    if (value.contains(':')) {
      // Loose on purpose: a full IPv6 grammar is not worth carrying here, and
      // sing-box is the authority. This catches a typo, not every malformed
      // address.
      final valid = RegExp(r'^[0-9a-fA-F:]+$').hasMatch(value) &&
          !value.contains(':::');
      return valid ? false : null;
    }
    final parts = value.split('.');
    if (parts.length != 4) return null;
    for (final part in parts) {
      final octet = int.tryParse(part);
      if (octet == null || octet < 0 || octet > 255) return null;
    }
    return true;
  }

  /// Whether the user pasted a URL where a hostname belongs.
  ///
  /// The most common way one of these goes wrong: `https://example.com/path`
  /// never matches anything, and sing-box accepts it happily as a domain that
  /// simply does not exist.
  static bool _looksLikeUrl(String value) =>
      value.contains('://') || value.contains('/') || value.contains(' ');

  @override
  bool operator ==(Object other) =>
      other is CustomRule &&
      other.id == id &&
      other.matcher == matcher &&
      other.value == value &&
      other.target == target &&
      other.enabled == enabled;

  @override
  int get hashCode => Object.hash(id, matcher, value, target, enabled);
}
