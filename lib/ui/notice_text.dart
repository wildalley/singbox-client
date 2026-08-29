/// Turns an [AppNotice] from the state layer into localized text.
///
/// The state layer reports *what happened* as a [NoticeKind] and never builds
/// sentences, so this is the single place where notices become words.
library;

import '../l10n/app_localizations.dart';
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
    // Already-final text: an engine message or a redacted exception.
    NoticeKind.passthrough => detail,
  };
}
