/// Root application widget and presentation lifecycle.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'l10n/app_localizations.dart';
import 'models/app_settings.dart';
import 'state/app_state.dart';
import 'ui/app_shell.dart';
import 'ui/theme.dart';

export 'ui/app_shell.dart';

/// Hosts the Material/localization layer above the navigation shell.
class SingBoxApp extends StatefulWidget {
  const SingBoxApp({super.key, required this.state});

  final AppState state;

  @override
  State<SingBoxApp> createState() => _SingBoxAppState();
}

class _SingBoxAppState extends State<SingBoxApp> with WidgetsBindingObserver {
  /// The two settings [MaterialApp] actually reads, as a notifier that only
  /// fires when one of them changes.
  late final _presentation =
      ValueNotifier<({AppThemeMode theme, AppLanguage language})>(_read());

  ({AppThemeMode theme, AppLanguage language}) _read() => (
        theme: widget.state.settings.themeMode,
        language: widget.state.settings.language,
      );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.state.addListener(_onStateChanged);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Android's VPN is a foreground service whose lifetime is intentionally
    // independent from the Flutter engine. Desktop has no such owner, so a
    // real engine detach still uses the awaited shutdown path.
    if (state == AppLifecycleState.detached && !Platform.isAndroid) {
      unawaited(_stopForLifecycle());
    }
  }

  Future<void> _stopForLifecycle() async {
    try {
      await widget.state.shutdown();
    } on Object {
      // Already shut down, most likely because the quit path got here first.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.state.removeListener(_onStateChanged);
    _presentation.dispose();
    super.dispose();
  }

  void _onStateChanged() => _presentation.value = _read();

  static final _light = buildAppTheme(Brightness.light);
  static final _dark = buildAppTheme(Brightness.dark);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<({AppThemeMode theme, AppLanguage language})>(
      valueListenable: _presentation,
      builder: (context, settings, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          onGenerateTitle: (context) => L10n.of(context).appTitle,
          theme: _light,
          darkTheme: _dark,
          themeMode: switch (settings.theme) {
            AppThemeMode.system => ThemeMode.system,
            AppThemeMode.light => ThemeMode.light,
            AppThemeMode.dark => ThemeMode.dark,
          },
          localizationsDelegates: const [
            L10n.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: L10n.supportedLocales,
          locale: settings.language.code == null
              ? null
              : Locale(settings.language.code!),
          home: AppShell(state: widget.state),
        );
      },
    );
  }
}
