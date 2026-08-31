/// Turns an [AppNotice] from the state layer into localized text.
///
/// The state layer reports *what happened* as a [NoticeKind] and never builds
/// sentences, so this is the single place where notices become words.
library;

import '../l10n/app_localizations.dart';
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
    };
