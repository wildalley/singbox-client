part of 'app_state.dart';

/// What a notice is about. The UI turns this into localized text; this layer
/// never builds user-facing sentences, so it needs no [BuildContext].
enum NoticeKind {
  needNodes,
  permissionDenied,
  switchFailed,
  reloadFailed,
  noUrlToRefresh,
  subscriptionUpdated,
  nodesImported,

  /// An import or refresh that produced no nodes. The reason travels as
  /// [AppNotice.failure] rather than as a sentence.
  importFailed,
  ruleSetsUpdated,
  ruleSetsUpdateFailed,
  ruleSetsUnavailable,

  /// The start failures the app works out for itself rather than reading off
  /// the engine. Each names a fix, so each gets a sentence in the user's
  /// language where engine text would be passed through untranslated.
  engineMissing,

  /// [AppNotice.detail] carries the version that was found.
  engineTooOld,

  /// [AppNotice.detail] carries the binary to grant the capability to, on the
  /// platform where a path is the fix. Empty where the fix is a prompt.
  tunUnprivileged,

  /// The elevated instance never took over, so nothing is running.
  elevationFailed,

  /// The engine refused the rendered config. [AppNotice.detail] carries its
  /// exit code, deliberately not its output.
  configRejected,

  /// The app refused its own rendered config, before any runtime saw it.
  ///
  /// Distinct from [configRejected]: that one is the engine's verdict, reported
  /// after a process ran. This one means the config never left the app, so the
  /// tunnel is untouched and nothing needs stopping. [AppNotice.detail] carries
  /// the field at fault, never its value — the config holds node credentials and
  /// the Clash API token.
  configInvalid,

  /// The core came up but never answered its control API.
  engineApiTimeout,

  /// The host's proxy settings could not be taken over.
  systemProxyUnavailable,

  /// Text that is already final: an engine error or a redacted exception.
  /// Not translatable, so it is passed through as-is.
  passthrough,
}

/// A transient message for the UI to surface in a snackbar.
class AppNotice {
  const AppNotice(
    this.kind, {
    this.isError = false,
    this.detail,
    this.name,
    this.count,
    this.skipped,
    this.failure,
  });

  const AppNotice.error(NoticeKind kind, {String? detail})
      : this(kind, isError: true, detail: detail);

  /// Already-final text, e.g. a redacted exception message.
  const AppNotice.passthrough(String text, {bool isError = true})
      : this(NoticeKind.passthrough, isError: isError, detail: text);

  final NoticeKind kind;
  final bool isError;

  /// Error detail or passthrough text.
  final String? detail;

  /// Subscription name, for the kinds that mention one.
  final String? name;

  /// A count of nodes, or the HTTP status for [NoticeKind.importFailed].
  final int? count;
  final int? skipped;

  /// Why an import failed, for [NoticeKind.importFailed].
  final SubscriptionFailure? failure;
}
