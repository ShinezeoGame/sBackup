import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sbackup/core/conditions.dart';
import 'package:sbackup/core/progress.dart';
import 'package:sbackup/core/settings.dart';
import 'package:sbackup/platform/platform.dart';
import 'package:sbackup/state/app_controller.dart';
import 'package:sbackup/ui/format.dart';
import 'package:sbackup/ui/pages/albums_page.dart';
import 'package:sbackup/ui/pages/history_page.dart';
import 'package:sbackup/ui/pages/home_page.dart';
import 'package:sbackup/ui/pages/settings_page.dart';
import 'package:sbackup/ui/widgets/controls.dart';

import 'support/app_harness.dart';

void main() {
  setUpAll(loadFonts);

  // Petit téléphone, Galaxy S25 (360 × 780 dp), et S25 avec le texte agrandi.
  const sizes = {
    'petit téléphone 320×568': (Size(320, 568), 1.0),
    'Galaxy S25 360×780': (Size(360, 780), 1.0),
    'Galaxy S25, texte agrandi': (Size(360, 780), 1.3),
  };

  /// Fait défiler la page jusqu'en bas : tout le contenu est construit et mesuré.
  Future<void> scrollThrough(WidgetTester tester) async {
    final list = find.byType(Scrollable).first;
    for (var i = 0; i < 14; i++) {
      await tester.drag(list, const Offset(0, -400));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.takeException(), isNull);
  }

  Future<void> scrollToTop(WidgetTester tester) async {
    await tester.fling(find.byType(Scrollable).first, const Offset(0, 4000), 4000);
    await tester.pumpAndSettle();
  }

  /// Rend cliquable un élément, qu'il soit plus bas dans la page ou passé sous l'en-tête.
  Future<void> show(WidgetTester tester, Finder finder) async {
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(finder, 120, scrollable: find.byType(Scrollable).first);
    }
    // Au milieu de l'écran, loin de l'en-tête fixe.
    unawaited(Scrollable.ensureVisible(tester.element(finder), alignment: 0.5));
    await tester.pumpAndSettle();
  }

  for (final MapEntry(key: label, value: (size, scale)) in sizes.entries) {
    group(label, () {
      for (final dark in [false, true]) {
        final theme = dark ? 'sombre' : 'clair';

        testWidgets('accueil dans tous ses états ($theme)', (tester) async {
          final fake = FakePlatform()
            ..permissionState = const PermissionState()
            ..state = const DeviceState(onWifi: false, charging: false);
          final (controller, _) = await pumpApp(
            tester,
            size,
            textScale: scale,
            platform: fake,
            settings: Settings(theme: dark ? AppThemeMode.dark : AppThemeMode.light),
          );
          // Premier lancement : tout est à régler.
          expect(find.text('À configurer'), findsOneWidget);
          expect(find.text('Accès aux photos et vidéos'), findsOneWidget);
          await show(tester, find.text('Aucune sauvegarde pour l\'instant'));
          await scrollThrough(tester);

          // Configuré, en cours de sauvegarde, avec un historique.
          await controller.updateSettings(readySettings.copyWith(theme: controller.settings.theme));
          controller.debugSetState(
            permissions: FakePlatform().permissionState,
            device: const DeviceState(onWifi: true, ssid: 'Maison', charging: true),
            albums: FakePlatform().albumList,
            history: sampleHistory,
            savedCount: 12873,
            savedBytes: 44300000000,
            progress: const BackupProgress(
              phase: BackupPhase.sending,
              filesDone: 12,
              filesTotal: 340,
              bytesDone: 1200000000,
              bytesTotal: 3400000000,
              currentFile: 'VID_20261119_184502_un_nom_de_fichier_tres_long.mp4',
            ),
          );
          await tester.pumpAndSettle();
          await scrollToTop(tester);
          expect(find.text('Sauvegarde en cours'), findsOneWidget);
          expect(find.text('12 sur 340 fichiers'), findsOneWidget);
          expect(find.text('1,2 Go sur 3,4 Go'), findsOneWidget);
          expect(find.text('À régler'), findsNothing);
          expect(tester.takeException(), isNull);
          await scrollThrough(tester);

          // Au repos.
          controller.debugSetState(progress: BackupProgress.idle);
          await tester.pump();
          await scrollToTop(tester);
          expect(find.text('Prêt à sauvegarder'), findsOneWidget);
          expect(find.textContaining('Dernière sauvegarde'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tearDownApp(tester, controller);
        });
      }

      testWidgets('les réglages manquants se règlent d\'un bouton', (tester) async {
        final fake = FakePlatform()..permissionState = const PermissionState(location: true);
        final (controller, _) = await pumpApp(tester, size, textScale: scale, platform: fake);
        for (final (title, action, request) in [
          ('Accès aux photos et vidéos', 'Autoriser', PermissionRequest.media),
          ('Reconnaître le Wi-Fi appli fermée', 'Régler', PermissionRequest.backgroundLocation),
          ('Économie de batterie', 'Exempter', PermissionRequest.battery),
        ]) {
          await show(tester, find.text(title));
          final button = find.descendant(
            of: find.byKey(ValueKey('etape $title')),
            matching: find.widgetWithText(AppButton, action),
          );
          await show(tester, button);
          await tester.tap(button);
          await tester.pump();
          expect(fake.requests.last, request);
        }
        await tearDownApp(tester, controller);
      });

      testWidgets('sauvegarder maintenant, et arrêter', (tester) async {
        final (controller, fake) = await pumpApp(tester, size, textScale: scale);
        await tester.runAsync(controller.refresh);
        await tester.pump();
        await tester.tap(find.widgetWithText(AppButton, 'Sauvegarder maintenant'));
        await tester.pump();
        expect(fake.runs, 1);
        expect(find.text('Sauvegarde en cours'), findsOneWidget);
        await tester.tap(find.widgetWithText(AppButton, 'Arrêter'));
        await tester.pump();
        expect(fake.stops, 1);

        // Hors de la maison : la raison est donnée, rien n'est lancé.
        controller.debugSetState(
          progress: BackupProgress.idle,
          device: const DeviceState(onWifi: true, ssid: 'Café', charging: false),
        );
        await tester.pump();
        await tester.tap(find.widgetWithText(AppButton, 'Sauvegarder maintenant'));
        await tester.pump();
        expect(fake.runs, 1);
        expect(find.text(describeBlocker(Blocker.otherNetwork)), findsWidgets);
        await tearDownApp(tester, controller);
      });

      testWidgets('page Albums : les albums usuels sont cochés, un clic change le choix', (tester) async {
        final (controller, _) = await pumpApp(tester, size, textScale: scale);
        await tester.runAsync(controller.refresh);
        await tester.pump();
        await show(tester, find.text('Choisir'));
        await tester.tap(find.text('Choisir'));
        await tester.pumpAndSettle();
        expect(find.byType(AlbumsPage), findsOneWidget);
        expect(controller.selectedAlbumIds, {'cam', 'shots'});
        await tester.tap(find.text('Download'));
        await tester.pump();
        await tester.tap(find.text('Screenshots'));
        await tester.pump();
        expect(controller.settings.albums, {'cam', 'dl'});
        await scrollThrough(tester);
        await tearDownApp(tester, controller);
      });

      testWidgets('page Réglages : NAS, Wi-Fi, conditions, thème', (tester) async {
        final fake = FakePlatform()
          ..password = null
          ..state = const DeviceState(onWifi: true, ssid: 'Livebox-Salon', charging: false);
        final (controller, _) = await pumpApp(
          tester,
          size,
          textScale: scale,
          platform: fake,
          settings: const Settings(),
        );
        await tester.runAsync(controller.refresh);
        await tester.tap(find.byTooltip('Réglages'));
        await tester.pumpAndSettle();
        expect(find.byType(SettingsPage), findsOneWidget);
        expect(tester.takeException(), isNull);

        // Valeurs proposées pour un Synology : espace personnel, dossier Photos.
        expect(find.widgetWithText(TextField, 'home'), findsOneWidget);
        await tester.enterText(find.widgetWithText(TextField, 'Adresse IP du NAS'), '192.168.1.10');
        await tester.enterText(find.widgetWithText(TextField, 'Identifiant'), 'shine');
        await show(tester, find.widgetWithText(TextField, 'Mot de passe'));
        await tester.enterText(find.widgetWithText(TextField, 'Mot de passe'), 'motdepasse');
        await tester.pump();
        await show(tester, find.widgetWithText(AppButton, 'Enregistrer'));
        await tester.tap(find.widgetWithText(AppButton, 'Enregistrer'));
        await tester.pump();
        expect(controller.settings.destination.host, '192.168.1.10');
        expect(controller.settings.destination.share, 'home');
        expect(controller.settings.destination.folder, 'Photos/Téléphone');
        expect(fake.password, 'motdepasse');
        expect(fake.tested.single.user, 'shine');
        expect(find.textContaining('Connexion réussie'), findsOneWidget);

        // Le NAS refuse : l'explication s'affiche, en français.
        fake.connectionError = 'Le NAS a refusé l\'identifiant ou le mot de passe.';
        await show(tester, find.widgetWithText(AppButton, 'Tester'));
        await tester.tap(find.widgetWithText(AppButton, 'Tester'));
        await tester.pump();
        expect(find.text(fake.connectionError!), findsOneWidget);

        await show(tester, find.text('Ajouter « Livebox-Salon »'));
        await tester.tap(find.text('Ajouter « Livebox-Salon »'));
        await tester.pump();
        expect(controller.settings.homeNetworks, ['Livebox-Salon']);
        await show(tester, find.widgetWithText(TextField, 'Nom du Wi-Fi'));
        await tester.enterText(find.widgetWithText(TextField, 'Nom du Wi-Fi'), 'Livebox-Étage');
        await show(tester, find.widgetWithText(AppButton, 'Ajouter'));
        await tester.tap(find.widgetWithText(AppButton, 'Ajouter'));
        await tester.pump();
        expect(controller.settings.homeNetworks, ['Livebox-Salon', 'Livebox-Étage']);
        await show(tester, find.byTooltip('Retirer Livebox-Salon'));
        await tester.tap(find.byTooltip('Retirer Livebox-Salon'));
        await tester.pump();
        expect(controller.settings.homeNetworks, ['Livebox-Étage']);

        await show(tester, find.text('Seulement en charge'));
        await tester.tap(find.bySemanticsLabel('Seulement en charge'));
        await tester.pump();
        expect(controller.settings.requireCharging, isTrue);
        expect(fake.scheduled, (enabled: true, requireCharging: true));

        await show(tester, find.text('Sombre'));
        await tester.tap(find.text('Sombre'));
        await tester.pumpAndSettle();
        expect(controller.settings.theme, AppThemeMode.dark);
        expect(Theme.of(tester.element(find.byType(SettingsPage))).brightness, Brightness.dark);
        await scrollThrough(tester);
        await tearDownApp(tester, controller);
      });

      testWidgets('page Historique : les fichiers en échec sont expliqués', (tester) async {
        final (controller, _) = await pumpApp(tester, size, textScale: scale);
        controller.debugSetState(history: sampleHistory);
        await tester.pump();
        await show(tester, find.text('Tout voir'));
        await tester.tap(find.text('Tout voir'));
        await tester.pumpAndSettle();
        expect(find.byType(HistoryPage), findsOneWidget);
        expect(find.textContaining('fichier introuvable ou illisible'), findsOneWidget);
        expect(find.text('Incomplète'), findsOneWidget);
        await scrollThrough(tester);
        await tearDownApp(tester, controller);
      });
    });
  }

  test('dates en français', () {
    final now = DateTime(2026, 11, 19, 21);
    expect(formatWhen(DateTime(2026, 11, 19, 8, 5), now), 'aujourd\'hui à 8 h 05');
    expect(formatWhen(DateTime(2026, 11, 18, 22, 15), now), 'hier à 22 h 15');
    expect(formatDay(DateTime(2026, 11, 1), now), 'le 1er novembre');
    expect(formatDay(DateTime(2025, 3, 9), now), 'le 9 mars 2025');
  });

  test('le contrôleur réagit à la fin d\'une sauvegarde', () async {
    final fake = FakePlatform();
    final controller = AppController(platform: fake);
    await controller.start();
    fake.progressController.add(const BackupProgress(phase: BackupPhase.sending, filesTotal: 3));
    await Future<void>.delayed(Duration.zero);
    expect(controller.progress.running, isTrue);
    fake.progressController.add(BackupProgress.idle);
    await Future<void>.delayed(Duration.zero);
    expect(controller.progress.running, isFalse);
    controller.dispose();
  });

  test('une page de réglage s\'ouvre pour les réglages de l\'application', () {
    final controller = AppController(platform: FakePlatform());
    final steps = setupSteps(controller);
    expect(steps.map((s) => s.title), contains('Le NAS'));
    expect(steps.firstWhere((s) => s.title == 'Le NAS').page, isA<SettingsPage>());
  });
}
