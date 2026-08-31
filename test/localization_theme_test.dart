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
          'sky': p.sky,
          'amber': p.amber,
          'danger': p.danger,
        }.entries) {
          expect(ratio(accent.value, p.surface), greaterThanOrEqualTo(3.0),
              reason: '${entry.key} ${accent.key} on surface');
        }
      }
    });

    test('light mode is not a mechanical inversion of dark', () {
      // The foreground accents must get darker, not lighter, on white. Taken
      // straight across, dark mint is 1.70:1 there and dark sky 1.67:1 — both
      // unreadable — so light mode re-picks them rather than reusing them.
      expect(luminance(AppPalette.light.violetSoft),
          lessThan(luminance(AppPalette.dark.violetSoft)));
      expect(luminance(AppPalette.light.mint),
          lessThan(luminance(AppPalette.dark.mint)));
      expect(luminance(AppPalette.light.sky),
          lessThan(luminance(AppPalette.dark.sky)));
    });

    test('violet is a fill colour, and works as one', () {
      // violet is deliberately too dark to read on surface (~2.4:1), so it is
      // never a foreground — the pairing that has to hold is white-on-violet.
      for (final entry in {
        'dark': AppPalette.dark,
        'light': AppPalette.light,
      }.entries) {
        expect(
            ratio(Colors.white, entry.value.violet), greaterThanOrEqualTo(4.5),
            reason: '${entry.key} white on violet');
      }
    });

    test('faint is held to the text bar, not the decoration bar', () {
      // faint reads as decoration but draws content: log timestamps, node
      // addresses, the punctuation in the config preview. It has to clear 4.5:1
      // on both fills a page actually uses.
      for (final entry in {
        'dark': AppPalette.dark,
        'light': AppPalette.light,
      }.entries) {
        final p = entry.value;
        expect(ratio(p.faint, p.surface), greaterThanOrEqualTo(4.5),
            reason: '${entry.key} faint on surface');
        expect(ratio(p.faint, p.bg), greaterThanOrEqualTo(4.5),
            reason: '${entry.key} faint on bg');
      }
    });

    test('muted and faint stay tellable apart', () {
      // Lifting faint to meet the text bar walks it toward muted. If the two
      // converge the hierarchy they encode is gone, and every use of faint
      // becomes an arbitrary choice.
      for (final entry in {
        'dark': AppPalette.dark,
        'light': AppPalette.light,
      }.entries) {
        final p = entry.value;
        expect(
            ratio(p.muted, p.surface), greaterThan(ratio(p.faint, p.surface)),
            reason: '${entry.key} muted must out-contrast faint');
      }
    });

    test('badge text clears 4.5:1 on a fill tinted with its own colour', () {
      // Action badges, the node region tile and StatusPill all draw a colour on
      // tintFill() of that same colour. The tint moves contrast in opposite
      // directions per theme — away from the text over the dark surface, toward
      // it over white — so light mode is the binding case. This is the
      // assertion tintFill's doc comment points at: raising that alpha fails
      // here first.
      for (final entry in {
        'dark': AppPalette.dark,
        'light': AppPalette.light,
      }.entries) {
        final p = entry.value;
        for (final accent in {
          'muted': p.muted,
          'faint': p.faint,
          'violetSoft': p.violetSoft,
          'mint': p.mint,
          'sky': p.sky,
          'amber': p.amber,
          'danger': p.danger,
        }.entries) {
          final fill = Color.alphaBlend(tintFill(accent.value), p.surface);
          expect(ratio(accent.value, fill), greaterThanOrEqualTo(4.5),
              reason: '${entry.key} ${accent.key} on its own tint');
        }
      }
    });

    test('the connection dial is legible on its own tinted disc', () {
      // The dial fills a 118px disc with its stage accent at 9% and then draws
      // two lines on it: the stage label in the accent itself, and the detail
      // line in muted. Neither pairing is covered above — the badge test uses
      // tintFill's 7% and only ever puts a colour on a tint of itself, so the
      // cross-colour case (muted on an accent tint) and the stronger alpha both
      // went unmeasured. That is the hole a violet stage label went through:
      // violet is exempt from the foreground bar by design, and nothing here
      // was checking the surface the label actually lands on.
      //
      // The set is _stageAccent's range: mint connected, danger failed,
      // violetSoft otherwise. Keep it in step with that switch.
      //
      // This blend is only what the app paints because the disc's fill is
      // opaque — Color.alphaBlend of the same 9% against surface, baked in.
      // It used to be a translucent 9% over a two-layer glow, and a BoxShadow
      // paints behind its own fill, so the halo came through: the real disc was
      // the accent at ~46% and the detail line sat at 1.97:1 while this test
      // read 4.72 and passed. If the fill ever goes back to withValues(alpha:),
      // these numbers stop describing the screen — model the glow or, better,
      // keep the fill opaque.
      const discAlpha = .09;
      for (final entry in {
        'dark': AppPalette.dark,
        'light': AppPalette.light,
      }.entries) {
        final p = entry.value;
        for (final stage in {
          'connected': p.mint,
          'error': p.danger,
          'idle': p.violetSoft,
        }.entries) {
          final disc = Color.alphaBlend(
              stage.value.withValues(alpha: discAlpha), p.surface);
          // 14px w700 is under WCAG's large-text threshold, so it owes 4.5:1.
          expect(ratio(stage.value, disc), greaterThanOrEqualTo(4.5),
              reason: '${entry.key} ${stage.key} label on its disc');
          expect(ratio(p.muted, disc), greaterThanOrEqualTo(4.5),
              reason: '${entry.key} ${stage.key} detail line on its disc');
        }
      }
    });

    test('the rule row icon reads on its violet tile', () {
      // rules_page.dart fills each enabled row's icon tile with violet at 13%
      // and draws a violetSoft icon on it. Neither of the tests above can see
      // this: the badge test only ever puts a colour on a tint of itself, and
      // this is violetSoft on violet — two separate tokens plus an alpha, so a
      // change to either one moves it. Icons owe 3:1, not 4.5:1.
      //
      // Disabled rows swap to surface3/faint, which the faint test covers.
      const tileAlpha = .13;
      for (final entry in {
        'dark': AppPalette.dark,
        'light': AppPalette.light,
      }.entries) {
        final p = entry.value;
        final tile =
            Color.alphaBlend(p.violet.withValues(alpha: tileAlpha), p.surface);
        expect(ratio(p.violetSoft, tile), greaterThanOrEqualTo(3),
            reason: '${entry.key} rule icon on its tile');
      }
    });
  });

  group('render matrix', () {
    // The four dimensions of the restyle's visual regression pass: both
    // themes × both locales × both layouts. A palette or layout change that
    // only breaks one corner — light-mode Chinese on desktop, say — would slip
    // past tests that each hold three of the four fixed.
    for (final theme in [AppThemeMode.dark, AppThemeMode.light]) {
      for (final language in [AppLanguage.english, AppLanguage.chinese]) {
        for (final size in [const Size(420, 900), const Size(1280, 900)]) {
          final layout = size.width > 900 ? 'desktop' : 'mobile';
          final label = '${theme.name} ${language.name} $layout';

          testWidgets('$label renders every tab clean', (tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1.0;
            addTearDown(tester.view.reset);

            final harness = await buildState(
              nodes: [node('a', '东京 01'), node('b', 'US-Los Angeles')],
              settings: AppSettings(themeMode: theme, language: language),
            );
            addTearDown(harness.state.dispose);

            await tester.pumpWidget(SingBoxApp(state: harness.state));
            await tester.pumpAndSettle();

            // A log line so the log rows and the sparkline have something to
            // paint; empty charts hide layout faults.
            harness.controller.emitLog('inbound/tun: started');
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: '$label home');

            // Home last: it starts selected, so its inactive icon is only in
            // the tree once we have navigated away.
            for (final icon in [
              Icons.hub_outlined,
              Icons.alt_route_outlined,
              Icons.receipt_long_outlined,
              Icons.settings_outlined,
              Icons.home_outlined,
            ]) {
              await tester.tap(find.byIcon(icon).first);
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull, reason: '$label $icon');
            }
          });
        }
      }
    }
  });

  group('CJK fallback', () {
    // None of the three bundled faces ships CJK glyphs, so every style that
    // names one has to name the fallback chain too. Miss it on one style and
    // Chinese renders as tofu in exactly that spot — the failure the on-device
    // check is looking for, caught here instead.
    test('the fallback chain leads with faces that carry CJK', () {
      expect(AppFonts.cjkFallback, isNotEmpty);
      expect(AppFonts.cjkFallback.first, contains('CJK'));
      // Generic last, so a named face always wins when present.
      expect(AppFonts.cjkFallback.last, 'sans-serif');
    });

    test('every resolved text style carries the fallback chain', () {
      // Asserted on the *resolved* theme rather than on what buildAppTheme
      // passes in. ThemeData applies the base family to Material's default
      // text theme and then merges ours over it field by field, so a style
      // that names no family still ends up with Inter and the chain — and one
      // that does name a display face has to bring the chain itself. Only the
      // merged result tells us which actually happened.
      for (final brightness in [Brightness.dark, Brightness.light]) {
        final theme = buildAppTheme(brightness);
        final styles = <String, TextStyle?>{
          'headlineLarge': theme.textTheme.headlineLarge,
          'headlineMedium': theme.textTheme.headlineMedium,
          'titleMedium': theme.textTheme.titleMedium,
          'bodyMedium': theme.textTheme.bodyMedium,
          'bodySmall': theme.textTheme.bodySmall,
          'labelSmall': theme.textTheme.labelSmall,
        };
        for (final entry in styles.entries) {
          final style = entry.value;
          expect(style, isNotNull, reason: entry.key);
          expect(style!.fontFamily, isNotNull,
              reason: '$brightness ${entry.key} has no family at all');
          expect(
            style.fontFamily,
            anyOf(AppFonts.body, AppFonts.display, AppFonts.mono),
            reason: '$brightness ${entry.key} uses an unbundled family',
          );
          expect(style.fontFamilyFallback, AppFonts.cjkFallback,
              reason: '$brightness ${entry.key} would render CJK as tofu');
        }
      }
    });

    test('component themes carry the fallback too', () {
      // A textStyle on a component theme does not merge with textTheme — the
      // button installs it as a fresh DefaultTextStyle, replacing the ambient
      // one — so these styles drop both Inter and the chain unless they name
      // them. That is what left the Chinese Connect label without a fallback.
      for (final brightness in [Brightness.dark, Brightness.light]) {
        final theme = buildAppTheme(brightness);
        const states = <WidgetState>{};
        final styles = <String, TextStyle?>{
          'filledButton':
              theme.filledButtonTheme.style?.textStyle?.resolve(states),
          'outlinedButton':
              theme.outlinedButtonTheme.style?.textStyle?.resolve(states),
          'textButton': theme.textButtonTheme.style?.textStyle?.resolve(states),
          'snackBar': theme.snackBarTheme.contentTextStyle,
          'inputHint': theme.inputDecorationTheme.hintStyle,
          'navBarLabel':
              theme.navigationBarTheme.labelTextStyle?.resolve(states),
        };
        for (final entry in styles.entries) {
          final style = entry.value;
          expect(style, isNotNull, reason: entry.key);
          expect(style!.fontFamily, AppFonts.body,
              reason: '$brightness ${entry.key} lost the body family');
          expect(style.fontFamilyFallback, AppFonts.cjkFallback,
              reason: '$brightness ${entry.key} would render CJK as tofu');
        }
      }
    });

    test('monoStyle carries the fallback', () {
      // The config preview and node rows draw Chinese node names in the mono
      // face, which has no CJK coverage at all.
      final style = monoStyle(color: AppPalette.dark.text);
      expect(style.fontFamily, AppFonts.mono);
      expect(style.fontFamilyFallback, AppFonts.cjkFallback);
    });

    testWidgets('Chinese text on screen resolves through the fallback',
        (tester) async {
      final harness = await buildState(
        nodes: [node('a', '东京 01')],
        settings: const AppSettings(language: AppLanguage.chinese),
      );
      addTearDown(harness.state.dispose);

      await tester.pumpWidget(SingBoxApp(state: harness.state));
      await tester.pumpAndSettle();

      final text = tester.widget<Text>(find.text('连接'));
      final style = DefaultTextStyle.of(
        tester.element(find.text('连接')),
      ).style.merge(text.style);
      expect(style.fontFamilyFallback, AppFonts.cjkFallback);
    });
  });
}
