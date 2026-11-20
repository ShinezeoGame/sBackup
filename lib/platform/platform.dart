import '../core/backup_job.dart';
import '../core/progress.dart';

/// Accès aux photos et vidéos accordé par Android 14+ : tout, une sélection, ou rien.
enum MediaAccess { all, partial, none }

/// Autorisations dont sBackup a besoin, et leur état.
class PermissionState {
  const PermissionState({
    this.media = MediaAccess.none,
    this.notifications = false,
    this.location = false,
    this.backgroundLocation = false,
    this.batteryUnrestricted = false,
    this.locationEnabled = true,
  });

  /// Photos et vidéos (avec leur position GPS d'origine).
  final MediaAccess media;

  /// Notification pendant les gros transferts.
  final bool notifications;

  /// Localisation : Android en a besoin pour donner le nom du Wi-Fi.
  final bool location;

  /// Localisation « toujours » : nom du Wi-Fi lisible quand l'appli est fermée.
  final bool backgroundLocation;

  /// Localisation activée sur le téléphone.
  final bool locationEnabled;

  /// Exempté de l'optimisation de batterie : les sauvegardes ne sont pas endormies.
  final bool batteryUnrestricted;

  bool get complete =>
      media == MediaAccess.all && notifications && backgroundLocation && locationEnabled && batteryUnrestricted;

  factory PermissionState.fromMap(Map<Object?, Object?> map) => PermissionState(
    media: MediaAccess.values.firstWhere((m) => m.name == map['medias'], orElse: () => MediaAccess.none),
    notifications: map['notifications'] == true,
    location: map['localisation'] == true,
    backgroundLocation: map['localisationArrierePlan'] == true,
    locationEnabled: map['localisationActive'] != false,
    batteryUnrestricted: map['batterieLibre'] == true,
  );
}

/// Ce qu'on peut demander à Android.
enum PermissionRequest { media, notifications, location, backgroundLocation, battery, appSettings, locationSettings }

/// Le téléphone vu par l'interface : tout `SystemPort`, plus les autorisations, la
/// planification en arrière-plan et le suivi des sauvegardes en cours.
abstract class PhonePlatform implements SystemPort {
  /// Dossier privé de l'application (réglages, index, historique).
  Future<String> dataDirectory();

  Future<PermissionState> permissions();

  /// Demande une autorisation (ou ouvre la page de réglages correspondante).
  Future<void> request(PermissionRequest what);

  /// Programme (ou retire) les sauvegardes automatiques.
  Future<void> schedule({required bool enabled, required bool requireCharging});

  /// Lance une sauvegarde tout de suite, en arrière-plan.
  Future<void> runNow();

  /// Arrête la sauvegarde en cours ; elle reprendra au prochain passage.
  Future<void> stop();

  /// Avancement des sauvegardes, qu'elles soient lancées par l'interface ou par Android.
  Stream<BackupProgress> progress();
}
