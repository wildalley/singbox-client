import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:singbox_client/main.dart';
import 'package:singbox_client/models/app_settings.dart';
import 'package:singbox_client/models/proxy_state.dart';
import 'package:singbox_client/ui/widgets.dart';

import 'widget_test.dart' show buildState, node;

void main() {
  for (final theme in [AppThemeMode.dark, AppThemeMode.light]) {
    testWidgets('disconnect stays flat and clickable on ${theme.name} hover',
        (tester) async {
      final harness = await buildState(nodes: [node('a', 'Tokyo')]);
      addTearDown(harness.state.dispose);
      await harness.state.applySettings(AppSettings(themeMode: theme));
      harness.controller.emit(const ProxyState(stage: ProxyStage.connected));
      await tester.pumpWidget(SingBoxApp(state: harness.state));
      await tester.pumpAndSettle();

      final button = find.widgetWithText(FilledButton, 'Disconnect');
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(button));
      await tester.pumpAndSettle();
      final material = tester.widget<Material>(
        find.descendant(of: button, matching: find.byType(Material)).first,
      );
      expect(material.elevation, 0,
          reason: 'a shadow behind a translucent face muddies light mode');
      expect(material.shadowColor, Colors.transparent);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(harness.controller.stopCount, 1);
    });
  }

  testWidgets('hero rate changes number and unit together across KB/MB',
      (tester) async {
    tester.view
      ..physicalSize = const Size(1280, 720)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final harness = await buildState(nodes: [node('a', 'Tokyo')]);
    addTearDown(harness.state.dispose);
    harness.controller.emit(const ProxyState(stage: ProxyStage.connected));
    harness.controller.emitTraffic(const ProxyTraffic(downlink: 1024));
    await tester.pumpWidget(SingBoxApp(state: harness.state));
    await tester.pumpAndSettle();

    final heroCount = find.byWidgetPredicate(
      (widget) => widget is AnimatedCount && widget.style.fontSize == 54,
    );
    expect(
        find.descendant(of: heroCount, matching: find.text('1.0')), findsOne);
    expect(find.text('KB/s'), findsOne);
    harness.controller.emitTraffic(
      const ProxyTraffic(downlink: 2 * 1024 * 1024),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    // No intermediate KB number may be painted beside the new MB label.
    expect(
        find.descendant(of: heroCount, matching: find.text('2.0')), findsOne);
    expect(find.text('MB/s'), findsOne);
    expect(tester.takeException(), isNull);
  });
}
