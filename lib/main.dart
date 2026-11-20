import 'package:flutter/material.dart';

import 'app.dart';
import 'background.dart' as background;
import 'platform/android_platform.dart';
import 'state/app_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = AppController(platform: const AndroidPlatform());
  // Les réglages sont lus avant le premier affichage : le thème choisi s'applique d'emblée.
  await controller.load();
  runApp(SBackupApp(controller: controller));
  await controller.start();
}

/// Sauvegarde en arrière-plan : point d'entrée appelé par `BackupWorker.kt`. Il doit se
/// trouver dans ce fichier, la bibliothèque principale, pour qu'Android le trouve.
@pragma('vm:entry-point')
Future<void> sauvegardeArrierePlan() => background.sauvegardeArrierePlan();
