import 'dart:async';

import 'backup_index.dart';
import 'conditions.dart';
import 'destination.dart';
import 'engine.dart';
import 'history.dart';
import 'media.dart';
import 'progress.dart';
import 'settings.dart';

/// Ce que la sauvegarde demande au téléphone. Sur Android : `AndroidSystem`
/// (`lib/platform/android_system.dart`) ; dans les tests, un faux téléphone.
abstract class SystemPort {
  Future<DeviceState> deviceState();

  Future<List<Album>> albums();

  /// Photos et vidéos des albums donnés.
  Future<List<MediaItem>> media(Set<String> albumIds);
}

/// Crée la destination décrite par les réglages, ou `null` si ce n'est pas possible.
typedef DestinationFactory = Future<Destination?> Function(DestinationConfig config);

/// Explication d'une erreur du NAS, en français.
String describeFailure(DestinationFailure failure) => switch (failure) {
  DestinationFailure.unreachable => 'Le NAS ne répond pas. Vérifiez qu\'il est allumé et que son adresse est la bonne.',
  DestinationFailure.authentication => 'Le NAS a refusé l\'identifiant ou le mot de passe.',
  DestinationFailure.permission =>
    'Le dossier de destination est introuvable sur le NAS, ou sBackup n\'a pas le droit d\'y écrire.',
  DestinationFailure.full => 'Le NAS est plein : libérez de la place pour continuer.',
  DestinationFailure.interrupted => 'La liaison avec le NAS a été coupée. La sauvegarde reprendra au prochain passage.',
  DestinationFailure.other => 'Le NAS a renvoyé une erreur inattendue.',
};

/// Albums retenus : ceux choisis, sinon les albums usuels.
Set<String> selectedAlbums(Settings settings, List<Album> albums) =>
    settings.albums ??
    {
      for (final album in albums)
        if (isDefaultAlbum(album)) album.id,
    };

/// Un passage complet : conditions, liste des fichiers, envoi, historique.
/// Le même code tourne dans l'interface (tests) et en arrière-plan (Android, WorkManager).
class BackupJob {
  BackupJob({
    required this.system,
    required this.settingsStore,
    required this.historyStore,
    required this.index,
    required this.createDestination,
    this.onProgress,
    StopSignal? stop,
    this.checkEvery = const Duration(seconds: 20),
    DateTime Function()? clock,
  }) : stop = stop ?? StopSignal(),
       _clock = clock ?? DateTime.now;

  final SystemPort system;
  final SettingsStore settingsStore;
  final HistoryStore historyStore;
  final BackupIndex index;
  final DestinationFactory createDestination;
  final void Function(BackupProgress progress)? onProgress;
  final StopSignal stop;

  /// Fréquence de contrôle des conditions pendant l'envoi (Wi-Fi, charge).
  final Duration checkEvery;
  final DateTime Function() _clock;

  Future<RunRecord> run(RunTrigger trigger) async {
    final start = _clock();
    final settings = await settingsStore.load();

    Future<RunRecord> finish(
      RunOutcome outcome,
      String message, {
      EngineResult? result,
      List<String> errors = const [],
    }) async {
      onProgress?.call(BackupProgress.idle);
      final record = RunRecord(
        start: start,
        end: _clock(),
        outcome: outcome,
        trigger: trigger,
        sent: result?.sent ?? 0,
        alreadySaved: result?.alreadySaved ?? 0,
        bytes: result?.bytes ?? 0,
        message: message,
        errors: [...errors, for (final f in result?.failures ?? const <FileFailure>[]) '$f'].take(50).toList(),
      );
      await historyStore.add(record);
      return record;
    }

    final blocker = blockerFor(settings, await system.deviceState());
    if (blocker != null) return finish(RunOutcome.skipped, describeBlocker(blocker));

    onProgress?.call(const BackupProgress(phase: BackupPhase.preparing));
    final destination = await createDestination(settings.destination);
    if (destination == null) {
      return finish(
        RunOutcome.failed,
        'Le NAS n\'est pas complètement configuré : adresse, dossier partagé et identifiant.',
      );
    }

    final List<MediaItem> items;
    try {
      final albums = await system.albums();
      items = await system.media(selectedAlbums(settings, albums));
      await index.load();
    } on Object catch (e) {
      return finish(
        RunOutcome.failed,
        'Impossible de lire les photos du téléphone. Autorisez l\'accès aux photos et vidéos.',
        errors: ['$e'],
      );
    }

    // Les conditions sont surveillées pendant l'envoi : sorti de la maison ou débranché,
    // le passage s'arrête proprement et reprendra plus tard.
    final watch = Timer.periodic(checkEvery, (_) async {
      try {
        final blocker = blockerFor(settings, await system.deviceState());
        if (blocker != null) stop.stop(describeBlocker(blocker));
      } on Object {
        // Un contrôle manqué n'arrête rien : le suivant décidera.
      }
    });
    final EngineResult result;
    try {
      await destination.open();
      result = await BackupEngine(
        destination: destination,
        index: index,
        deepVerify: settings.deepVerify,
        clock: _clock,
      ).run(items, onProgress: (p) => onProgress?.call(p), stop: stop);
    } on DestinationException catch (e) {
      return finish(RunOutcome.failed, describeFailure(e.failure), errors: [if (e.detail.isNotEmpty) e.detail]);
    } finally {
      watch.cancel();
      try {
        await destination.close();
      } on Object {
        // La connexion est perdue de toute façon.
      }
    }

    final fatal = result.fatal;
    if (fatal != null) {
      return finish(
        result.sent > 0 ? RunOutcome.interrupted : RunOutcome.failed,
        describeFailure(fatal.failure),
        result: result,
        errors: [if (fatal.detail.isNotEmpty) fatal.detail],
      );
    }
    final summary = _summary(result);
    if (result.stopReason != null) {
      return finish(RunOutcome.interrupted, '${result.stopReason} $summary'.trim(), result: result);
    }
    if (result.failures.isNotEmpty) {
      final failed = plural(result.failures.length, 'fichier');
      return finish(RunOutcome.partial, '$summary $failed en échec.'.trim(), result: result);
    }
    return finish(RunOutcome.success, summary.isEmpty ? 'Tout était déjà sauvegardé.' : summary, result: result);
  }

  static String _summary(EngineResult r) {
    final parts = <String>[
      if (r.sent > 0) '${plural(r.sent, 'fichier envoyé', 'fichiers envoyés')} (${formatBytes(r.bytes)})',
      if (r.alreadySaved > 0) '${plural(r.alreadySaved, 'fichier', 'fichiers')} déjà sur le NAS',
    ];
    return parts.isEmpty ? '' : '${parts.join(', ')}.';
  }
}
