/// The scaffolding both desktop runtimes are built on.
///
/// Linux and Windows each supervise a `sing-box` process and drive it over the
/// Clash API, and the parts of that which are *not* platform-specific had been
/// written twice: four broadcast streams, a session counter that invalidates
/// work from a superseded start, a queue that serialises lifecycle operations,
/// and the stdout/stderr line pump. Two copies of bookkeeping this fiddly is how
/// the two platforms drift apart — one side gains a guard, the other keeps the
/// race — so it lives here once.
///
/// What deliberately stays in the subclasses is everything the platforms really
/// do differently: how a core is found, how a tun is authorised, which signal
/// stops the process, and how the host's proxy settings are taken over. Forcing
/// those into one shape would be a rewrite pretending to be a refactor.
library;

import 'dart:async';
import 'dart:convert';

import '../models/proxy_state.dart';

/// Streams, session bookkeeping, and the lifecycle queue for a desktop runtime.
///
/// Subclasses own a process and an API client; this owns what surrounds them.
/// Members are protected by convention rather than by language: Dart has no
/// `protected`, so the contract is that only a subclass touches them.
abstract class DesktopRuntime {
  final _stateController = StreamController<ProxyState>.broadcast();
  final _trafficController = StreamController<ProxyTraffic>.broadcast();
  final _logController = StreamController<ProxyLogEntry>.broadcast();
  final _groupController = StreamController<ProxyGroup>.broadcast();

  var _state = ProxyState.disconnected;

  /// Generation counter for starts.
  ///
  /// Every asynchronous step of a start carries the session it belongs to and
  /// checks [isCurrentSession] before touching shared state. Without it a
  /// disconnect issued during a slow start gets overwritten by the start it was
  /// meant to cancel — the failure mode being a UI that says disconnected while
  /// an engine is running.
  var _sessionId = 0;

  /// The session whose failure has already been reported.
  ///
  /// A failing start can unwind through several layers, each with something to
  /// say. The first message is the specific one, so later ones are dropped
  /// rather than allowed to overwrite it with something vaguer.
  int? _reportedErrorSession;

  /// True from the moment a stop begins until the process is gone, so its exit
  /// reads as intentional rather than as a crash.
  var isStopping = false;

  var _disposed = false;

  Future<void> _lifecycleTail = Future<void>.value();

  Stream<ProxyState> get states => _stateController.stream;
  Stream<ProxyTraffic> get traffic => _trafficController.stream;
  Stream<ProxyLogEntry> get logs => _logController.stream;
  Stream<ProxyGroup> get groups => _groupController.stream;

  ProxyState get currentState => _state;

  /// The session a start is currently in, for the paths that report against
  /// "whatever is running now" rather than against a session they were handed.
  int get sessionId => _sessionId;

  bool get isDisposed => _disposed;

  /// Opens a new session, clearing the previous one's reported-error latch.
  int beginSession() {
    _reportedErrorSession = null;
    return ++_sessionId;
  }

  /// Whether [session] is still the one worth reporting against.
  bool isCurrentSession(int session) => !_disposed && _sessionId == session;

  /// Runs [operation] after every lifecycle operation queued before it.
  ///
  /// start, stop and reload all mutate the same process handle and the same
  /// host proxy settings, so overlapping them is how a stop ends up restoring
  /// settings a start has just applied. The queue is FIFO and a failure does not
  /// poison it: the tail swallows errors so the *next* operation still runs,
  /// while the caller still sees the original future's error.
  Future<void> enqueueLifecycle(Future<void> Function() operation) {
    final previous = _lifecycleTail;
    final result = previous.then((_) => operation());
    _lifecycleTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return result;
  }

  void emitState(ProxyState state) {
    _state = state;
    if (!_stateController.isClosed) _stateController.add(state);
  }

  /// Reports a failure once per session. See [_reportedErrorSession].
  void emitError(String message, {required int session}) {
    if (_reportedErrorSession == session) return;
    _reportedErrorSession = session;
    emitState(ProxyState(
      stage: ProxyStage.error,
      message: message,
      sessionId: session,
    ));
  }

  /// A classified failure against the current session.
  ///
  /// [EngineProblem.encode] rather than a sentence: the UI localises these, and
  /// a message built here would reach the user untranslated.
  void fail(EngineProblem problem, [String? detail]) => emitError(
        problem.encode(detail),
        session: _sessionId,
      );

  /// One line for the log page. Blank lines and a closed stream are no-ops.
  void log(String line) {
    if (_disposed || _logController.isClosed || line.trim().isEmpty) return;
    _logController.add(ProxyLogEntry(message: line, at: DateTime.now()));
  }

  void emitTraffic(ProxyTraffic value) {
    if (_disposed || _trafficController.isClosed) return;
    _trafficController.add(value);
  }

  void emitGroup(ProxyGroup group) {
    if (_disposed || _groupController.isClosed) return;
    _groupController.add(group);
  }

  /// Pumps a child process's stdout or stderr into [log], one line at a time.
  ///
  /// Returns the subscription so a stop can cancel it: a process being killed
  /// closes its pipes, and a listener left on them outlives the session it
  /// belonged to.
  StreamSubscription<String> pipeLines(
    Stream<List<int>> output, {
    void Function(String line)? onLine,
  }) =>
      output
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(onLine ?? log, onError: (Object _) {});

  /// Marks this runtime disposed and invalidates any session in flight.
  ///
  /// Separate from [closeStreams] because the order matters: a subclass sets
  /// this first so nothing it tears down afterwards tries to emit, then closes
  /// the streams last.
  ///
  /// Returns false when already disposed, so a subclass can `if (!markDisposed())
  /// return;` at the top of its own dispose.
  bool markDisposed() {
    if (_disposed) return false;
    _disposed = true;
    _sessionId++;
    return true;
  }

  void closeStreams() {
    _stateController.close();
    _trafficController.close();
    _logController.close();
    _groupController.close();
  }
}
