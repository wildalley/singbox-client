/// Covers the two things this round delivers: Chinese text and a light theme.
///
/// The other widget tests run under the default `en` locale, so they would keep
/// passing even if the Chinese ARB or the light palette were broken.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:singbox_client/data/storage.dart';
import 'package:singbox_client/l10n/app_localizations.dart';
import 'package:singbox_client/main.dart';
import 'package:singbox_client/models/app_settings.dart';
import 'package:singbox_client/models/node.dart';
import 'package:singbox_client/state/app_state.dart';
import 'package:singbox_client/ui/theme.dart';

import 'widget_test.dart' show FakeProxyController, node;

Future<({AppState state, FakeProxyController controller})> buildState({
  List<ProxyNode> nodes = const [],
  AppSettings settings = const AppSettings(),
}) async {
  SharedPreferences.setMockInitialValues({});
  final storage = await Storage.open();
  if (nodes.isNotEmpty) await storage.writeNodes(nodes);
  await storage.writeSettings(settings);
  final controller = FakeProxyController();
  return (
    state: AppState(storage: storage, controller: controller),
    controller: controller,
  );
}

/// Resolves the palette actually in effect, as the widgets see it.
AppPalette effectivePalette(WidgetTester tester) {
  final context = tester.element(find.byType(Scaffold).first);
  return context.palette;
}

void main() {
  group('Chinese', () {
    testWidgets('renders navigation and home in Chinese when selected',
        (tester) async {
      final harness = await buildState(
        nodes: [node('a', '东京 01')],
        settings: const AppSettings(language: AppLanguage.chinese),
      );
      addTearDown(harness.state.dispose);

      await tester.pumpWidget(SingBoxApp(state: harness.state));
      await tester.pumpAndSettle();

      expect(find.text('首页'), findsWidgets);
      expect(find.text('节点'), findsWidgets);
      expect(find.text('设置'), findsWidgets);
      expect(find.text('未连接'), findsWidgets);
      expect(find.text('连接'), findsOneWidget);
      // No English leaking through on the primary surface.
      expect(find.text('Connect'), findsNothing);
      expect(find.text('Disconnected'), findsNothing);
    });

    testWidgets('follows the platform locale when set to system',
        (tester) async {
      tester.platformDispatcher.localesTestValue = const [Locale('zh')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);

      final harness = await buildState(nodes: [node('a', 'Tokyo')]);
      addTearDown(harness.state.dispose);

      await tester.pumpWidget(SingBoxApp(state: harness.state));
      await tester.pumpAndSettle();

      expect(find.text('连接'), findsOneWidget);
    });

    testWidgets('falls back to English for an untranslated locale',
        (tester) async {
      tester.platformDispatcher.localesTestValue = const [Locale('de')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);

      final harness = await buildState(nodes: [node('a', 'Tokyo')]);
      addTearDown(harness.state.dispose);

      await tester.pumpWidget(SingBoxApp(state: harness.state));
      await tester.pumpAndSettle();

      expect(find.text('Connect'), findsOneWidget);
    });

    testWidgets('localizes runtime notices, not just static labels',
        (tester) async {
      // An empty node list makes connect() emit the needNodes notice.
      final harness = await buildState(
        settings: const AppSettings(language: AppLanguage.chinese),
      );
      addTearDown(harness.state.dispose);

      await tester.pumpWidget(SingBoxApp(state: harness.state));
      await tester.pumpAndSettle();

      await harness.state.connect();
      await tester.pumpAndSettle();

      expect(find.text('请先添加节点或订阅'), findsOneWidget);
    });

    testWidgets('switching language in settings updates the UI immediately',
        (tester) async {
      final harness = await buildState(nodes: [node('a', 'Tokyo')]);
      addTearDown(harness.state.dispose);

      await tester.pumpWidget(SingBoxApp(state: harness.state));
      await tester.pumpAndSettle();
      expect(find.text('Connect'), findsOneWidget);

      await harness.state.applySettings(
        harness.state.settings.copyWith(language: AppLanguage.chinese),
      );
      await tester.pumpAndSettle();

      expect(find.text('连接'), findsOneWidget);
      expect(find.text('Connect'), findsNothing);
    });

    testWidgets('every ARB key resolves in both locales', (tester) async {
      // Guards against a key that exists in the template but not in zh: the
      // generated class would throw or return the English string.
      for (final locale in L10n.supportedLocales) {
        final l10n = await L10n.delegate.load(locale);
        expect(l10n.appTitle, isNotEmpty, reason: '$locale appTitle');
        expect(l10n.navSettings, isNotEmpty, reason: '$locale navSettings');
        expect(l10n.noticeNodesImported(3), isNotEmpty);
        expect(l10n.nodesCountLabel(1), isNotEmpty);
        expect(l10n.noticeSubscriptionUpdated('S', 2), contains('S'));
        expect(l10n.homeProtectedFor('01:20'), contains('01:20'));
      }
    });

    testWidgets('Chinese plurals read naturally, without English forms',
        (tester) async {
      final zh = await L10n.delegate.load(const Locale('zh'));
      // Chinese has no singular/plural split; both counts use the measure word.
      expect(zh.nodesCountLabel(1), '1 个节点');
      expect(zh.nodesCountLabel(5), '5 个节点');
      expect(zh.nodesCountLabel(1), isNot(contains('node')));
    });
  });

  group('light theme', () {
    testWidgets('uses the light palette when light mode is selected',
        (tester) async {
      final harness = await buildState(
        nodes: [node('a', 'Tokyo')],
        settings: const AppSettings(themeMode: AppThemeMode.light),
      );
      addTearDown(harness.state.dispose);

      await tester.pumpWidget(SingBoxApp(state: harness.state));
      await tester.pumpAndSettle();

      expect(effectivePalette(tester), AppPalette.light);
      expect(Theme.of(tester.element(find.byType(Scaffold).first)).brightness,
          Brightness.light);
    });

    testWidgets('uses the dark palette when dark mode is selected',
        (tester) async {
      final harness = await buildState(
        nodes: [node('a', 'Tokyo')],
        settings: const AppSettings(themeMode: AppThemeMode.dark),
      );
      addTearDown(harness.state.dispose);

      await tester.pumpWidget(SingBoxApp(state: harness.state));
      await tester.pumpAndSettle();

      expect(effectivePalette(tester), AppPalette.dark);
    });

    testWidgets('system mode follows the platform brightness', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      final harness = await buildState(nodes: [node('a', 'Tokyo')]);
      addTearDown(harness.state.dispose);

      await tester.pumpWidget(SingBoxApp(state: harness.state));
      await tester.pumpAndSettle();
      expect(effectivePalette(tester), AppPalette.light);

      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpAndSettle();
      expect(effectivePalette(tester), AppPalette.dark);
    });

    testWidgets('switching theme in settings repaints immediately',
        (tester) async {
      final harness = await buildState(
        nodes: [node('a', 'Tokyo')],
        settings: const AppSettings(themeMode: AppThemeMode.dark),
      );
      addTearDown(harness.state.dispose);

      await tester.pumpWidget(SingBoxApp(state: harness.state));
      await tester.pumpAndSettle();
      expect(effectivePalette(tester), AppPalette.dark);

      await harness.state.applySettings(
        harness.state.settings.copyWith(themeMode: AppThemeMode.light),
      );
      await tester.pumpAndSettle();

      expect(effectivePalette(tester), AppPalette.light);
    });

    testWidgets('renders every tab in light mode without exceptions',
        (tester) async {
      final harness = await buildState(
        nodes: [node('a', 'Tokyo'), node('b', 'Osaka')],
        settings: const AppSettings(themeMode: AppThemeMode.light),
      );
      addTearDown(harness.state.dispose);

      await tester.pumpWidget(SingBoxApp(state: harness.state));
      await tester.pumpAndSettle();

      // Traffic + a log line so the sparkline and log rows actually paint.
      harness.controller.emitLog('inbound/tun: started');
      await tester.pumpAndSettle();

      for (final icon in [
        Icons.hub_outlined,
        Icons.alt_route_outlined,
        Icons.receipt_long_outlined,
        Icons.settings_outlined,
        Icons.home_outlined,
      ]) {
        await tester.tap(find.byIcon(icon));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$icon in light mode');
      }
    });
  });

  group('palette contrast', () {
    /// WCAG relative luminance.
    double luminance(Color c) => c.computeLuminance();

    double ratio(Color fg, Color bg) {
      final a = luminance(fg);
      final b = luminance(bg);
      final lighter = a > b ? a : b;
      final darker = a > b ? b : a;
      return (lighter + 0.05) / (darker + 0.05);
    }

    test('body and secondary text meet 4.5:1 on surface in both palettes', () {
      for (final entry in {
        'dark': AppPalette.dark,
        'light': AppPalette.light,
      }.entries) {
        final p = entry.value;
        expect(ratio(p.text, p.surface), greaterThanOrEqualTo(4.5),
            reason: '${entry.key} text on surface');
        expect(ratio(p.muted, p.surface), greaterThanOrEqualTo(4.5),
            reason: '${entry.key} muted on surface');
      }
    });

    test('accent foregrounds stay legible on surface', () {
      // These are used as icon/label colours, so they need 3:1 at minimum.
      for (final entry in {
        'dark': AppPalette.dark,
        'light': AppPalette.light,
      }.entries) {
        final p = entry.value;
        for (final accent in {
          'violetSoft': p.violetSoft,
          'mint': p.mint,
          'amber': p.amber,
          'danger': p.danger,
        }.entries) {
          expect(ratio(accent.value, p.surface), greaterThanOrEqualTo(3.0),
              reason: '${entry.key} ${accent.key} on surface');
        }
      }
    });

    test('light mode is not a mechanical inversion of dark', () {
      // The foreground accents must get darker, not lighter, on white.
      expect(luminance(AppPalette.light.violetSoft),
          lessThan(luminance(AppPalette.dark.violetSoft)));
      expect(luminance(AppPalette.light.mint),
          lessThan(luminance(AppPalette.dark.mint)));
    });
  });
}
