/// SingBox Client entry point.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'app.dart';
import 'data/rule_sets.dart';
import 'data/storage.dart';
import 'platform/desktop_shell.dart';
import 'platform/single_instance.dart';
import 'platform/proxy_controller.dart';
import 'state/app_state.dart';

export 'app.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // The shell does not exist yet — it needs AppState, which needs storage — so
  // the guard is handed a callback that defers to it once it does. An activation
  // arriving in that window is dropped, which is the right answer: the first
  // instance is still starting, and its window is about to appear anyway.
  DesktopShell? shell;
  final elevatedRestart =
      Platform.isWindows && args.contains(elevatedRestartArgument);
  if (elevatedRestart) {
    // The parent UAC request waits for this acknowledgement before it exits.
    // It has to precede SingleInstance.claim because the child intentionally
    // waits there for the parent's mutex release.
    await SingleInstance.signalElevationReady();
  }
  if (isSupported &&
      !await SingleInstance.claim(
        onActivate: () => shell?.activate(),
        waitForExisting: elevatedRestart,
      )) {
    // Another instance holds the socket and has been asked to show its window.
    // Nothing has been initialised yet, so there is nothing to unwind.
    exit(0);
  }

  // Before runApp, and before the user can reach the close button: the window
  // has to be told not to quit on its own first. No-op off the desktop.
  await DesktopShell.ensureWindowReady();
  final storage = await Storage.open();
  // Before the first config is rendered: with the rule-sets on disk the engine
  // starts without reaching the network, which is the difference between
  // connecting and not on a filtered or offline link.
  final ruleSetDir = await BundledRuleSets.prepare();
  final state = AppState(
    storage: storage,
    controller: createProxyController(),
    ruleSetDir: ruleSetDir,
  );
  runApp(SingBoxApp(state: state));
  // After runApp so the icon does not delay the first frame. Unawaited for the
  // same reason: a panel that is slow to accept an indicator must not hold up
  // the window.
  shell = DesktopShell(state);
  unawaited(shell.start());
  // The unelevated process launched the UAC child on behalf of a connection
  // request, then exited. The child has the same persisted nodes/settings, so
  // resume that request instead of requiring a second manual click.
  if (elevatedRestart) unawaited(state.connect());
}
