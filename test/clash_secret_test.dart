/// The Clash API token: generated once, persisted, and required by the config
/// the engine is actually started with.
///
/// Why it exists: `experimental.clash_api` listens on 127.0.0.1, and on Android
/// loopback is shared by every app on the device. Without a token, any of them
/// can switch the user's outbound, read their connection list, and watch their
/// traffic. So the assertions here are about the token being present in the
/// started config, stable across runs, and unique per install — and about it not
/// leaking back out through the one screen that renders the config.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:singbox_client/data/storage.dart';
import 'package:singbox_client/state/app_state.dart';

import 'widget_test.dart' show FakeProxyController, node;

/// The token in the config [state] hands to the runtime.
///
/// Read from the started config rather than from [AppState.previewConfig],
/// because the preview deliberately masks it — this is the value that reaches
/// the engine.
Future<String> _startedSecret(
  AppState state,
  FakeProxyController controller,
) async {
  await state.connect();
  expect(controller.startedConfigs, hasLength(1));
  final config = jsonDecode(controller.startedConfigs.single) as Map;
  final api = (config['experimental'] as Map)['clash_api'] as Map;
  return api['secret'] as String;
}

Future<({AppState state, FakeProxyController controller})> _build(
  Storage storage,
) async {
  await storage.writeNodes([node('a', 'Tokyo')]);
  final controller = FakeProxyController();
  final state = AppState(storage: storage, controller: controller);
  addTearDown(state.dispose);
  return (state: state, controller: controller);
}

void main() {
  test('the started config carries a secret with real entropy', () async {
    SharedPreferences.setMockInitialValues({});
    final harness = await _build(await Storage.open());

    final secret = await _startedSecret(harness.state, harness.controller);

    // 128 bits, hex. Asserted as a shape rather than a value: the point is that
    // a co-resident app cannot guess it, and a short or non-random token would
    // satisfy "is not empty" while failing at that.
    expect(secret, matches(RegExp(r'^[0-9a-f]{32}$')));
  });

  test('the same install keeps the same secret', () async {
    // A token that changed per run would break anything the user had pointed at
    // the API, and would rewrite the config on every launch for no reason.
    SharedPreferences.setMockInitialValues({});
    final first = await _build(await Storage.open());
    final before = await _startedSecret(first.state, first.controller);

    // A second AppState over the same store: the app restarting.
    final second = await _build(await Storage.open());
    final after = await _startedSecret(second.state, second.controller);

    expect(after, before);
  });

  test('a fresh install gets its own secret', () async {
    SharedPreferences.setMockInitialValues({});
    final first = await _build(await Storage.open());
    final one = await _startedSecret(first.state, first.controller);

    SharedPreferences.setMockInitialValues({});
    final second = await _build(await Storage.open());
    final two = await _startedSecret(second.state, second.controller);

    expect(two, isNot(one));
  });

  test('the config preview masks the secret', () async {
    // The preview sheet has a copy button, and copied configs end up in bug
    // reports. Presence is the only thing worth seeing there.
    SharedPreferences.setMockInitialValues({});
    final harness = await _build(await Storage.open());
    final live = await _startedSecret(harness.state, harness.controller);

    final preview = harness.state.previewConfig();

    expect(preview, isNot(contains(live)));
    final api = (jsonDecode(preview) as Map)['experimental']['clash_api'] as Map;
    expect(api['secret'], isNotEmpty);
  });
}
