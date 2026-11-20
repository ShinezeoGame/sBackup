// Captures d'écran de la documentation (`docs/captures`). Elles ne sont produites que sur
// demande, pour ne pas réécrire des images à chaque exécution des tests :
//
//     SBACKUP_CAPTURES=1 flutter test test/captures_test.dart

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sbackup/core/conditions.dart';
import 'package:sbackup/core/progress.dart';
import 'package:sbackup/core/settings.dart';
import 'package:sbackup/platform/platform.dart';

import 'support/app_harness.dart';

/// Écran du Galaxy S25, en points.
const _screen = Size(360, 780);

Future<void> capture(WidgetTester tester, String name) async {
  // Le logo de l'en-tête se charge en différé : on l'attend avant de capturer.
  final element = tester.element(find.byKey(captureKey));
  await tester.runAsync(() => precacheImage(const AssetImage('assets/branding/logo.png'), element));
  await tester.pump();
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(captureKey));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('docs/captures/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void main() {
  final enabled = Platform.environment.containsKey('SBACKUP_CAPTURES');
  setUpAll(loadFonts);

  testWidgets('accueil : sauvegarde en cours', skip: !enabled, (tester) async {
    final (controller, _) = await pumpApp(tester, _screen);
    await tester.runAsync(controller.refresh);
    controller.debugSetState(
      history: sampleHistory,
      savedCount: 12873,
      savedBytes: 44300000000,
      progress: const BackupProgress(
        phase: BackupPhase.sending,
        filesDone: 12,
        filesTotal: 340,
        bytesDone: 1200000000,
        bytesTotal: 3400000000,
        currentFile: 'VID_20261119_184502.mp4',
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await capture(tester, 'accueil');
    await tearDownApp(tester, controller);
  });

  testWidgets('accueil sombre : premier lancement', skip: !enabled, (tester) async {
    final fake = FakePlatform()
      ..permissionState = const PermissionState(location: true, notifications: true)
      ..state = const DeviceState(onWifi: true, ssid: 'Maison', charging: false);
    final (controller, _) = await pumpApp(
      tester,
      _screen,
      platform: fake,
      settings: const Settings(theme: AppThemeMode.dark),
    );
    await tester.runAsync(controller.refresh);
    await tester.pump(const Duration(milliseconds: 300));
    await capture(tester, 'premier-lancement');
    await tearDownApp(tester, controller);
  });

  testWidgets('albums', skip: !enabled, (tester) async {
    final (controller, _) = await pumpApp(tester, _screen);
    await tester.runAsync(controller.refresh);
    await tester.pump();
    await tester.tap(find.text('Choisir'));
    await tester.pumpAndSettle();
    await capture(tester, 'albums');
    await tearDownApp(tester, controller);
  });

  testWidgets('réglages', skip: !enabled, (tester) async {
    final (controller, _) = await pumpApp(tester, _screen);
    await tester.runAsync(controller.refresh);
    await tester.tap(find.byTooltip('Réglages'));
    await tester.pumpAndSettle();
    await capture(tester, 'reglages');
    await tearDownApp(tester, controller);
  });

  testWidgets('historique', skip: !enabled, (tester) async {
    final (controller, _) = await pumpApp(tester, _screen, settings: readySettings.copyWith(theme: AppThemeMode.dark));
    controller.debugSetState(history: sampleHistory);
    await tester.pump();
    await tester.scrollUntilVisible(find.text('Tout voir'), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Tout voir'));
    await tester.pumpAndSettle();
    await capture(tester, 'historique');
    await tearDownApp(tester, controller);
  });
}
