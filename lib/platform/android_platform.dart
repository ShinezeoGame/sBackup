import 'package:flutter/services.dart';

import '../core/backup_job.dart';
import '../core/conditions.dart';
import '../core/destination.dart';
import '../core/settings.dart';
import '../core/history.dart';
import '../core/media.dart';
import '../core/progress.dart';
import 'platform.dart';
import 'smb_destination.dart';

/// Canal vers `android/…/SystemChannel.kt`, partagé par l'interface et par la sauvegarde
/// en arrière-plan (`BackupWorker.kt`, qui démarre son propre moteur Flutter).
const systemChannel = MethodChannel('sbackup/systeme');
const _progressChannel = EventChannel('sbackup/progression');

class AndroidPlatform implements PhonePlatform {
  const AndroidPlatform();

  Future<T?> _call<T>(String method, [Object? arguments]) => systemChannel.invokeMethod<T>(method, arguments);

  @override
  Future<String> dataDirectory() async => (await _call<String>('dossierDonnees'))!;

  @override
  Future<PermissionState> permissions() async =>
      PermissionState.fromMap(await _call<Map<Object?, Object?>>('autorisations') ?? const {});

  @override
  Future<void> request(PermissionRequest what) => _call<void>('demander', switch (what) {
    PermissionRequest.media => 'medias',
    PermissionRequest.notifications => 'notifications',
    PermissionRequest.location => 'localisation',
    PermissionRequest.backgroundLocation => 'localisationArrierePlan',
    PermissionRequest.battery => 'batterie',
    PermissionRequest.appSettings => 'reglagesAppli',
    PermissionRequest.locationSettings => 'reglagesLocalisation',
  });

  @override
  Future<DeviceState> deviceState() async =>
      DeviceState.fromMap(await _call<Map<Object?, Object?>>('etatAppareil') ?? const {});

  @override
  Future<List<Album>> albums() async => [
    for (final map in await _call<List<Object?>>('albums') ?? const []) Album.fromMap(map! as Map<Object?, Object?>),
  ];

  @override
  Future<List<MediaItem>> media(Set<String> albumIds) async => [
    for (final map in await _call<List<Object?>>('medias', albumIds.toList()) ?? const [])
      MediaItem.fromMap(map! as Map<Object?, Object?>),
  ];

  @override
  Future<void> schedule({required bool enabled, required bool requireCharging}) =>
      _call<void>('planifier', {'actif': enabled, 'charge': requireCharging});

  @override
  Future<void> runNow() => _call<void>('sauvegarderMaintenant');

  @override
  Future<void> stop() => _call<void>('arreter');

  @override
  Stream<BackupProgress> progress() => _progressChannel.receiveBroadcastStream().map(
    (event) => event is Map ? BackupProgress.fromMap(event) : BackupProgress.idle,
  );

  @override
  Future<void> savePassword(String password) => const NasPassword().save(password);

  @override
  Future<bool> hasPassword() => const NasPassword().isSaved();

  @override
  Future<String?> testDestination(DestinationConfig config) async {
    final nas = SmbDestination(config);
    try {
      await nas.open();
      return null;
    } on DestinationException catch (e) {
      return describeFailure(e.failure);
    } finally {
      try {
        await nas.close();
      } on DestinationException {
        // Déjà déconnecté.
      }
    }
  }

  // ── Côté sauvegarde en arrière-plan ──

  /// Ce qui a lancé ce passage (choisi par `BackupWorker.kt`).
  Future<RunTrigger> trigger() async {
    final name = await _call<String>('declencheur');
    return RunTrigger.values.firstWhere((t) => t.name == name, orElse: () => RunTrigger.scheduled);
  }

  /// Transmet l'avancement : interface ouverte, notification pendant les gros transferts.
  Future<void> reportProgress(BackupProgress progress) => _call<void>('avancement', progress.toMap());

  /// Signale la fin du passage au `BackupWorker`, qui peut alors arrêter le moteur.
  Future<void> finished(RunRecord record) =>
      _call<void>('termine', {'issue': record.outcome.name, 'message': record.message});
}
