/// [CustomRule] validation and persistence.
///
/// Validation is the load-bearing part. sing-box rejects a malformed route rule
/// by refusing to start, so an unchecked rule turns into "the tunnel will not
/// come up" with nothing pointing at the line that did it. Everything here is a
/// mistake a user can actually make while typing one.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:singbox_client/models/custom_rule.dart';

/// A rule with the fields a test is not varying already filled in.
CustomRule rule({
  RuleMatcher matcher = RuleMatcher.domainSuffix,
  String value = 'example.com',
  RuleTarget target = RuleTarget.proxy,
  bool enabled = true,
}) =>
    CustomRule(
      id: 'r1',
      matcher: matcher,
      value: value,
      target: target,
      enabled: enabled,
    );

void main() {
  group('validation', () {
    test('a domain suffix rule is valid', () {
      expect(rule().problem, isNull);
      expect(rule().isValid, isTrue);
    });

    test('an empty value is rejected', () {
      // The state a row is in the moment it is added, so the UI needs to be able
      // to tell it apart from a mistake.
      expect(rule(value: '').problem, RuleProblem.empty);
    });

    test('a pasted URL is rejected, not silently accepted', () {
      // The most common way one of these goes wrong. sing-box takes it as a
      // domain, and it simply never matches — so without this the rule looks
      // right and does nothing.
      for (final value in [
        'https://example.com',
        'example.com/path',
        'http://example.com/',
        'example.com and more',
      ]) {
        expect(
          rule(value: value).problem,
          RuleProblem.url,
          reason: value,
        );
      }
    });

    test('a keyword may contain anything, because it is a substring', () {
      // A keyword rule has no shape to hold it to — `-tracker-` is the point.
      expect(
        rule(matcher: RuleMatcher.domainKeyword, value: '-tracker-').problem,
        isNull,
      );
      // Even something URL-shaped, which as a substring is a legitimate ask.
      expect(
        rule(matcher: RuleMatcher.domainKeyword, value: 'ads/banner').problem,
        isNull,
      );
    });

    group('port', () {
      test('accepts the usable range', () {
        for (final value in ['1', '80', '443', '65535']) {
          expect(rule(matcher: RuleMatcher.port, value: value).problem, isNull,
              reason: value);
        }
      });

      test('rejects zero, out of range, and anything not a number', () {
        for (final value in ['0', '65536', '-1', '80/tcp', 'http', '4 43']) {
          expect(
            rule(matcher: RuleMatcher.port, value: value).problem,
            RuleProblem.port,
            reason: value,
          );
        }
      });
    });

    group('ip_cidr', () {
      test('accepts an address with or without a prefix', () {
        // sing-box takes both, so both are allowed rather than forcing the user
        // to write /32 for one host.
        for (final value in [
          '10.0.0.0/8',
          '192.168.1.1',
          '0.0.0.0/0',
          '2001:db8::/32',
          'fe80::1',
        ]) {
          expect(rule(matcher: RuleMatcher.ipCidr, value: value).problem, isNull,
              reason: value);
        }
      });

      test('rejects a bad octet or a prefix out of range for the family', () {
        for (final value in [
          '10.0.0.256',
          '10.0.0',
          '10.0.0.0/33',
          '2001:db8::/129',
          '10.0.0.0/x',
          'example.com',
        ]) {
          expect(
            rule(matcher: RuleMatcher.ipCidr, value: value).problem,
            RuleProblem.cidr,
            reason: value,
          );
        }
      });
    });
  });

  group('persistence', () {
    test('every field round-trips', () {
      for (final matcher in RuleMatcher.values) {
        for (final target in RuleTarget.values) {
          final original = CustomRule(
            id: 'x',
            matcher: matcher,
            value: 'v',
            target: target,
            enabled: false,
          );

          expect(CustomRule.fromJson(original.toJson()), original,
              reason: '$matcher / $target');
        }
      }
    });

    test('a record written before the enabled flag reads as enabled', () {
      // It was one the user meant to be active; defaulting it off would silently
      // stop routing they had working.
      final restored = CustomRule.fromJson(const {
        'id': 'x',
        'matcher': 'domain_suffix',
        'value': 'example.com',
        'target': 'direct',
      });

      expect(restored.enabled, isTrue);
    });

    test('an unknown matcher or target falls back rather than throwing', () {
      // A record from a newer build. Refusing to load it would lose every other
      // rule in the list with it.
      final restored = CustomRule.fromJson(const {
        'id': 'x',
        'matcher': 'not_a_field',
        'value': 'example.com',
        'target': 'not_a_target',
      });

      expect(restored.matcher, RuleMatcher.domainSuffix);
      expect(restored.target, RuleTarget.proxy);
    });

    test('the stored value is trimmed', () {
      // Whitespace round a hostname is invisible in the UI and fatal to a match.
      final restored = CustomRule.fromJson(const {
        'id': 'x',
        'matcher': 'domain',
        'value': '  example.com  ',
        'target': 'proxy',
      });

      expect(restored.value, 'example.com');
    });
  });

  group('copyWith', () {
    test('keeps the id, and carries the fields not being changed', () {
      // The id is identity: a rule that changes id on edit is a different rule,
      // and the list would treat it as one.
      const original = CustomRule(
        id: 'keep-me',
        matcher: RuleMatcher.domain,
        value: 'a.example.com',
        target: RuleTarget.direct,
        enabled: false,
      );

      final edited = original.copyWith(value: 'b.example.com');

      expect(edited.id, 'keep-me');
      expect(edited.matcher, RuleMatcher.domain);
      expect(edited.target, RuleTarget.direct);
      expect(edited.enabled, isFalse);
      expect(edited.value, 'b.example.com');
    });
  });
}
