import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/settings.dart';
import 'state/app_controller.dart';
import 'state/app_scope.dart';
import 'ui/pages/home_page.dart';
import 'ui/theme.dart';

class SBackupApp extends StatefulWidget {
  const SBackupApp({super.key, required this.controller});

  final AppController controller;

  @override
  State<SBackupApp> createState() => _SBackupAppState();
}

class _SBackupAppState extends State<SBackupApp> with WidgetsBindingObserver {
  static final _light = buildTheme(Brightness.light);
  static final _dark = buildTheme(Brightness.dark);

  late AppThemeMode _mode = widget.controller.settings.theme;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  /// De retour d'une page de réglages d'Android, ou après une sauvegarde faite en
  /// arrière-plan : tout est relu.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) widget.controller.refresh();
  }

  /// L'application entière n'est reconstruite que si le thème choisi change.
  void _onControllerChanged() {
    final mode = widget.controller.settings.theme;
    if (mode != _mode) setState(() => _mode = mode);
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      controller: widget.controller,
      child: MaterialApp(
        title: 'sBackup',
        debugShowCheckedModeBanner: false,
        theme: _light,
        darkTheme: _dark,
        themeMode: switch (_mode) {
          AppThemeMode.auto => ThemeMode.system,
          AppThemeMode.light => ThemeMode.light,
          AppThemeMode.dark => ThemeMode.dark,
        },
        locale: const Locale('fr', 'FR'),
        supportedLocales: const [Locale('fr', 'FR')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const HomePage(),
      ),
    );
  }
}
