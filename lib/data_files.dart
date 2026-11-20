import 'dart:io';

import 'core/backup_index.dart';
import 'core/history.dart';
import 'core/settings.dart';

/// Fichiers de sBackup dans le dossier privé de l'application, partagés par l'interface et
/// par la sauvegarde en arrière-plan.
class DataFiles {
  DataFiles(String directory)
    : settings = SettingsStore(File('$directory/reglages.json')),
      history = HistoryStore(File('$directory/historique.json')),
      index = BackupIndex(File('$directory/index.jsonl'));

  /// Fichiers fournis un à un (tests).
  DataFiles.custom({required this.settings, required this.history, required this.index});

  final SettingsStore settings;
  final HistoryStore history;
  final BackupIndex index;
}
