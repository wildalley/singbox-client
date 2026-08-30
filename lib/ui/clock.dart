/// The single wall-clock read the UI is allowed to make.
///
/// Four places render text derived from "now" — the home greeting, the uptime
/// line, and the subscription's "updated N ago" / "N days left" — so a golden
/// PNG taken at 00:30 on the 29th does not match the same screen rendered at
/// 10:51 on the 30th. The greeting flipped from evening to morning and the
/// subscription aged a day, and six snapshots went red on a run that had
/// changed nothing about them.
///
/// Routing those reads through one hook lets the snapshot harness pin the clock
/// instead of re-recording the goldens every few hours.
library;

import 'package:flutter/foundation.dart';

import '../l10n/app_localizations.dart';

/// Returns the current time. Assign to pin it; call [reset] to restore.
DateTime Function() clockNow = DateTime.now;

/// "just now" / "5m ago" / "3h ago" / "2d ago" for [time].
///
/// Two rows render it — a subscription's last refresh and the rule-sets' last
/// download — so it lives beside the clock hook rather than in either page,
/// which is also what keeps both of them pinnable from the snapshot harness.
String relativeTime(L10n l10n, DateTime time) {
  final delta = clockNow().difference(time);
  if (delta.inMinutes < 1) return l10n.agoJustNow;
  if (delta.inHours < 1) return l10n.agoMinutes(delta.inMinutes);
  if (delta.inDays < 1) return l10n.agoHours(delta.inHours);
  return l10n.agoDays(delta.inDays);
}

/// Pins [clockNow] to [at] for the rest of the test.
@visibleForTesting
void pinClock(DateTime at) => clockNow = () => at;

/// Restores the real clock.
@visibleForTesting
void resetClock() => clockNow = DateTime.now;
