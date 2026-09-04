/// Turns an [AppNotice] from the state layer into localized text.
///
/// The state layer reports *what happened* as a [NoticeKind] and never builds
/// sentences, so this is the single place where notices become words.
library;

import '../l10n/app_localizations.dart';
import '../models/custom_rule.dart';
import '../models/subscription.dart';
import '../state/app_state.dart';

String noticeText(L10n l10n, AppNotice notice) {
  final detail = notice.detail ?? '';
  return switch (notice.kind) {
    NoticeKind.needNodes => l10n.noticeNeedNodes,
    NoticeKind.permissionDenied => l10n.noticePermissionDenied,
    NoticeKind.switchFailed => l10n.noticeSwitchFailed(detail),
    NoticeKind.reloadFailed => l10n.noticeReloadFailed(detail),
    NoticeKind.noUrlToRefresh => l10n.noticeNoUrlToRefresh(notice.name ?? ''),
    NoticeKind.subscriptionUpdated => l10n.noticeSubscriptionUpdated(
        notice.name ?? '',
        notice.count ?? 0,
      ),
    NoticeKind.nodesImported => (notice.skipped ?? 0) > 0
        ? l10n.noticeNodesImportedSkipped(
            notice.count ?? 0, notice.skipped ?? 0)
        : l10n.noticeNodesImported(notice.count ?? 0),
    NoticeKind.importFailed => subscriptionFailureText(
        l10n,
        notice.failure ?? SubscriptionFailure.unusableContent,
        status: notice.count,
      ),
    NoticeKind.ruleSetsUpdated => l10n.noticeRuleSetsUpdated,
    NoticeKind.ruleSetsUpdateFailed => l10n.noticeRuleSetsUpdateFailed,
    NoticeKind.ruleSetsUnavailable => l10n.noticeRuleSetsUnavailable,
    NoticeKind.engineMissing => l10n.noticeEngineMissing,
    NoticeKind.engineTooOld => l10n.noticeEngineTooOld(detail),
    NoticeKind.tunUnprivileged => l10n.noticeTunUnprivileged(
        detail.isEmpty ? 'sing-box' : detail,
      ),
    // Already-final text: an engine message or a redacted exception.
    NoticeKind.passthrough => detail,
  };
}

/// Why an import or refresh failed.
///
/// Shared by the snackbar and by the two rows that show a source's last
/// failure, so a source cannot describe itself differently from the message that
/// put it in that state.
String subscriptionFailureText(
  L10n l10n,
  SubscriptionFailure failure, {
  int? status,
}) =>
    switch (failure) {
      SubscriptionFailure.unreachable => l10n.noticeImportUnreachable,
      SubscriptionFailure.httpStatus =>
        l10n.noticeImportHttpStatus(status ?? 0),
      SubscriptionFailure.unusableContent => l10n.noticeImportUnusable,
      SubscriptionFailure.badSource => l10n.noticeImportBadSource,
      SubscriptionFailure.timeout => l10n.noticeImportTimeout,
      SubscriptionFailure.responseTooLarge => l10n.noticeImportTooLarge,
    };

/// What is wrong with a rule, in the user's language.
///
/// [CustomRule.problem] reports a kind rather than a sentence, for the same
/// reason the state layer does: the model has no business holding English.
String ruleProblemText(L10n l10n, RuleProblem problem) => switch (problem) {
      RuleProblem.empty => l10n.rulesProblemEmpty,
      RuleProblem.port => l10n.rulesProblemPort,
      RuleProblem.cidr => l10n.rulesProblemCidr,
      RuleProblem.url => l10n.rulesProblemUrl,
    };

/// The name of a matcher, as the picker shows it.
String ruleMatcherText(L10n l10n, RuleMatcher matcher) => switch (matcher) {
      RuleMatcher.domain => l10n.rulesMatcherDomain,
      RuleMatcher.domainSuffix => l10n.rulesMatcherDomainSuffix,
      RuleMatcher.domainKeyword => l10n.rulesMatcherDomainKeyword,
      RuleMatcher.ipCidr => l10n.rulesMatcherIpCidr,
      RuleMatcher.port => l10n.rulesMatcherPort,
      RuleMatcher.processName => l10n.rulesMatcherProcessName,
    };

/// An example of what [matcher] expects, shown as the field's hint.
///
/// Worth having per matcher: "example.com" in a port field is the kind of thing
/// that makes a user type `example.com:443` and get a rule that never matches.
String ruleValueHint(L10n l10n, RuleMatcher matcher) => switch (matcher) {
      RuleMatcher.domain => l10n.rulesValueHintDomain,
      RuleMatcher.domainSuffix => l10n.rulesValueHintDomain,
      RuleMatcher.domainKeyword => l10n.rulesValueHintKeyword,
      RuleMatcher.ipCidr => l10n.rulesValueHintIpCidr,
      RuleMatcher.port => l10n.rulesValueHintPort,
      RuleMatcher.processName => l10n.rulesValueHintProcess,
    };

/// The name of a rule's destination.
String ruleTargetText(L10n l10n, RuleTarget target) => switch (target) {
      RuleTarget.proxy => l10n.rulesTargetProxy,
      RuleTarget.direct => l10n.rulesTargetDirect,
      RuleTarget.block => l10n.rulesTargetBlock,
    };
