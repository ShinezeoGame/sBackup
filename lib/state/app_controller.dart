import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/backup_job.dart';
import '../core/conditions.dart';
import '../core/history.dart';
import '../core/media.dart';
import '../core/progress.dart';
import '../core/settings.dart';
import '../data_files.dart';
import '../platform/platform.dart';

/// Message affiché en haut de la page d'accueil, en réponse à une action.
class Notice {
  const Notice(this.message, {this.error = false});

  final String message;
  final bool error;
}

/// Tout l'état de l'interface. La sauvegarde elle-même tourne ailleurs (en arrière-plan,
/// dans un autre moteur Flutter) : l'interface la lance, la suit et lit ses résultats dans
/// les fichiers partagés (`DataFiles`).
class AppController extends ChangeNotifier {
  AppController({required this.platform, DataFiles? files}) : _files = files; // ignore: prefer_initializing_formals

  final PhonePlatform platform;
  DataFiles? _files;

  Settings settings = const Settings();
  PermissionState permissions = const PermissionState();
  DeviceState? device;

  /// Albums de la galerie ; `null` tant qu'ils n'ont pas pu être lus.
  List<Album>? albums;
  List<RunRecord> history = const [];

  /// Fichiers et volume déjà sauvegardés (d'après l'index du téléphone).
  int savedCount = 0;
  int savedBytes = 0;
  BackupProgress progress = BackupProgress.idle;
  Notice? notice;

  StreamSubscription<BackupProgress>? _progressSub;
  bool _disposed = false;

  /// Pourquoi la sauvegarde attend, d'après le dernier état connu du téléphone.
  Blocker? get blocker => device == null ? null : blockerFor(settings, device!);

  Set<String> get selectedAlbumIds => selectedAlbums(settings, albums ?? const []);

  RunRecord? get lastRun => history.isEmpty ? null : history.first;

  /// Dernier passage qui a envoyé ou vérifié quelque chose.
  RunRecord? get lastBackup {
    for (final run in history) {
      if (run.outcome == RunOutcome.success || run.outcome == RunOutcome.partial) return run;
    }
    return null;
  }

  /// Lit les réglages et l'état du téléphone. Appelé une fois, avant le premier affichage.
  Future<void> load() async {
    _files ??= DataFiles(await platform.dataDirectory());
    settings = await _files!.settings.load();
    await refresh();
  }

  /// Suit les sauvegardes et remet la planification en accord avec les réglages.
  Future<void> start() async {
    _progressSub = platform.progress().listen(_onProgress, onError: (Object _) {});
    await _schedule();
  }

  /// Relit tout ce qui a pu changer hors de l'interface (retour au premier plan, fin d'une
  /// sauvegarde) : autorisations, Wi-Fi, albums, historique.
  Future<void> refresh() async {
    try {
      permissions = await platform.permissions();
      device = await platform.deviceState();
    } on Object {
      // L'état précédent reste affiché.
    }
    if (permissions.media != MediaAccess.none) {
      try {
        albums = await platform.albums();
      } on Object {
        albums = null;
      }
    } else {
      albums = null;
    }
    await _reloadResults();
    _notify();
  }

  Future<void> _reloadResults() async {
    final files = _files;
    if (files == null) return;
    history = await files.history.load();
    await files.index.load();
    savedCount = files.index.count;
    savedBytes = files.index.bytes;
  }

  void _onProgress(BackupProgress next) {
    final finished = progress.running && !next.running;
    progress = next;
    _notify();
    if (finished) {
      unawaited(_reloadResults().then((_) => _notify()));
    }
  }

  Future<void> updateSettings(Settings next) async {
    final scheduleChanged = next.autoBackup != settings.autoBackup || next.requireCharging != settings.requireCharging;
    settings = next;
    _notify();
    await _files?.settings.save(next);
    if (scheduleChanged) await _schedule();
  }

  Future<void> _schedule() async {
    try {
      await platform.schedule(enabled: settings.autoBackup, requireCharging: settings.requireCharging);
    } on Object {
      // Sans Android (tests), rien à programmer.
    }
  }

  Future<void> setAlbum(String id, bool selected) {
    final ids = {...selectedAlbumIds};
    selected ? ids.add(id) : ids.remove(id);
    return updateSettings(settings.copyWith(albums: ids));
  }

  Future<void> addHomeNetwork(String ssid) {
    final name = ssid.trim();
    if (name.isEmpty || settings.homeNetworks.contains(name)) return Future.value();
    return updateSettings(settings.copyWith(homeNetworks: [...settings.homeNetworks, name]));
  }

  Future<void> removeHomeNetwork(String ssid) =>
      updateSettings(settings.copyWith(homeNetworks: [...settings.homeNetworks.where((s) => s != ssid)]));

  Future<void> runNow() async {
    final reason = blocker;
    if (reason != null) {
      notice = Notice(describeBlocker(reason), error: true);
      _notify();
      return;
    }
    progress = const BackupProgress(phase: BackupPhase.preparing);
    notice = null;
    _notify();
    try {
      await platform.runNow();
    } on Object {
      progress = BackupProgress.idle;
      notice = const Notice('La sauvegarde n\'a pas pu être lancée.', error: true);
      _notify();
    }
  }

  Future<void> stop() => platform.stop();

  Future<void> request(PermissionRequest what) async {
    await platform.request(what);
    await refresh();
  }

  void clearNotice() {
    notice = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _progressSub?.cancel();
    super.dispose();
  }

  /// Impose un état, pour les tests de l'interface et les captures de la documentation.
  @visibleForTesting
  void debugSetState({
    List<Album>? albums,
    List<RunRecord>? history,
    BackupProgress? progress,
    PermissionState? permissions,
    DeviceState? device,
    int? savedCount,
    int? savedBytes,
    Notice? notice,
  }) {
    if (albums != null) this.albums = albums;
    if (history != null) this.history = history;
    if (progress != null) this.progress = progress;
    if (permissions != null) this.permissions = permissions;
    if (device != null) this.device = device;
    if (savedCount != null) this.savedCount = savedCount;
    if (savedBytes != null) this.savedBytes = savedBytes;
    if (notice != null) this.notice = notice;
    _notify();
  }
}
