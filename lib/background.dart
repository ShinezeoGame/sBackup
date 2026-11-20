import 'dart:async';

import 'package:flutter/widgets.dart';

import 'core/backup_job.dart';
import 'core/engine.dart';
import 'core/history.dart';
import 'core/progress.dart';
import 'data_files.dart';
import 'platform/android_platform.dart';
import 'platform/destinations.dart';

/// Point d'entrée de la sauvegarde en arrière-plan, lancé par `BackupWorker.kt` dans un
/// moteur Flutter sans interface (application fermée, écran éteint).
@pragma('vm:entry-point')
Future<void> sauvegardeArrierePlan() async {
  WidgetsFlutterBinding.ensureInitialized();
  const android = AndroidPlatform();
  final stop = StopSignal();
  // Android demande l'arrêt (bouton « Arrêter », contraintes perdues, délai dépassé) : le
  // passage s'arrête entre deux morceaux, l'index reste juste et l'envoi reprendra.
  systemChannel.setMethodCallHandler((call) async {
    if (call.method == 'arreter') stop.stop('Sauvegarde arrêtée.');
    return null;
  });

  RunRecord? record;
  try {
    final files = DataFiles(await android.dataDirectory());
    final trigger = await android.trigger();
    var lastSent = DateTime.fromMillisecondsSinceEpoch(0);
    var lastPhase = BackupPhase.idle;
    record = await BackupJob(
      system: android,
      settingsStore: files.settings,
      historyStore: files.history,
      index: files.index,
      createDestination: createDestination,
      stop: stop,
      onProgress: (progress) {
        // Au plus deux nouvelles par seconde, sauf changement d'étape.
        final now = DateTime.now();
        if (progress.phase == lastPhase && now.difference(lastSent) < const Duration(milliseconds: 500)) return;
        lastSent = now;
        lastPhase = progress.phase;
        unawaited(android.reportProgress(progress).catchError((Object _) {}));
      },
    ).run(trigger);
  } on Object catch (e) {
    final now = DateTime.now();
    record = RunRecord(
      start: now,
      end: now,
      outcome: RunOutcome.failed,
      trigger: RunTrigger.scheduled,
      message: 'La sauvegarde s\'est arrêtée sur une erreur inattendue.',
      errors: ['$e'],
    );
  } finally {
    await android.finished(record!);
  }
}
