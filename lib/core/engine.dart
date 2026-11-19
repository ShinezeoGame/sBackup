import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'backup_index.dart';
import 'destination.dart';
import 'media.dart';
import 'progress.dart';

/// Dossier des envois en cours sur le NAS : un fichier n'en sort, renommé à sa place
/// définitive, qu'une fois arrivé en entier et vérifié.
const partialFolder = '.sbackup-partiel';

/// Dossier de rangement d'un fichier : année et mois de la prise de vue (`2026/11`).
String folderFor(MediaItem item) =>
    '${item.taken.year.toString().padLeft(4, '0')}/${item.taken.month.toString().padLeft(2, '0')}';

/// Nom d'origine, débarrassé des caractères refusés par les partages réseau (Windows, SMB).
String safeName(String name) {
  var s = name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_').trim();
  s = s.replaceAll(RegExp(r'[. ]+$'), '');
  return s.isEmpty ? 'sans-nom' : s;
}

/// Noms possibles, dans l'ordre : `IMG.jpg`, `IMG (2).jpg`, `IMG (3).jpg`…
Iterable<String> candidateNames(String name) sync* {
  yield name;
  final dot = name.lastIndexOf('.');
  final base = dot > 0 ? name.substring(0, dot) : name;
  final ext = dot > 0 ? name.substring(dot) : '';
  for (var i = 2; ; i++) {
    yield '$base ($i)$ext';
  }
}

/// Demande d'arrêt, posée de l'extérieur (Wi-Fi perdu, débranché, bouton « Arrêter ») et
/// lue par le moteur entre deux morceaux de fichier.
class StopSignal {
  String? reason;

  void stop(String why) => reason ??= why;
}

/// Un fichier qui n'a pas pu être sauvegardé.
class FileFailure {
  const FileFailure(this.name, this.message);

  final String name;
  final String message;

  @override
  String toString() => '$name : $message';
}

/// Bilan d'un passage du moteur.
class EngineResult {
  EngineResult({
    this.sent = 0,
    this.alreadySaved = 0,
    this.bytes = 0,
    this.failures = const [],
    this.stopReason,
    this.fatal,
  });

  final int sent;

  /// Fichiers reconnus sur le NAS ou dans l'index sous une autre clé, sans renvoi.
  final int alreadySaved;
  final int bytes;
  final List<FileFailure> failures;

  /// Raison de l'arrêt en route, le cas échéant (la suite reprendra plus tard).
  final String? stopReason;

  /// Erreur de destination qui a empêché de continuer (NAS injoignable, plein…).
  final DestinationException? fatal;
}

/// Le moteur de sauvegarde : envoie les fichiers absents de l'index, avec reprise,
/// vérification et rangement sans écrasement.
class BackupEngine {
  BackupEngine({
    required this.destination,
    required this.index,
    this.deepVerify = true,
    Stream<List<int>> Function(String path, int start)? openFile,
    DateTime Function()? clock,
  }) : _open = openFile ?? ((path, start) => File(path).openRead(start)),
       _clock = clock ?? DateTime.now;

  final Destination destination;
  final BackupIndex index;
  final bool deepVerify;
  final Stream<List<int>> Function(String path, int start) _open;
  final DateTime Function() _clock;

  /// Fichiers que l'index ne connaît pas encore, du plus ancien au plus récent.
  List<MediaItem> pending(Iterable<MediaItem> items) =>
      items.where((item) => !index.containsKey(item.key)).toList()..sort((a, b) => a.taken.compareTo(b.taken));

  Future<EngineResult> run(
    List<MediaItem> items, {
    required void Function(BackupProgress progress) onProgress,
    StopSignal? stop,
  }) async {
    final todo = pending(items);
    final signal = stop ?? StopSignal();
    final totalBytes = todo.fold<int>(0, (sum, item) => sum + item.size);
    var sent = 0, already = 0, bytes = 0, doneBytes = 0;
    final failures = <FileFailure>[];

    void report(BackupPhase phase, int filesDone, String current, [int extra = 0]) => onProgress(
      BackupProgress(
        phase: phase,
        filesDone: filesDone,
        filesTotal: todo.length,
        bytesDone: doneBytes + extra,
        bytesTotal: totalBytes,
        currentFile: current,
      ),
    );

    EngineResult result({String? stopReason, DestinationException? fatal}) => EngineResult(
      sent: sent,
      alreadySaved: already,
      bytes: bytes,
      failures: failures,
      stopReason: stopReason,
      fatal: fatal,
    );

    if (todo.isNotEmpty) await destination.makeDirs(partialFolder);
    for (final (i, item) in todo.indexed) {
      if (signal.reason != null) return result(stopReason: signal.reason);
      report(BackupPhase.sending, i, item.name);
      try {
        final outcome = await _saveOne(item, signal, (n) => report(BackupPhase.sending, i, item.name, n));
        switch (outcome) {
          case _Outcome.sent:
            sent++;
            bytes += item.size;
          case _Outcome.alreadyThere:
            already++;
        }
      } on _Stopped {
        return result(stopReason: signal.reason);
      } on DestinationException catch (e) {
        if (e.failure == DestinationFailure.interrupted && signal.reason != null) {
          return result(stopReason: signal.reason);
        }
        // Toute erreur du NAS arrête le passage : la suivante aurait la même cause. Les
        // fichiers partiels restent en place pour la reprise.
        return result(fatal: e);
      } on _FileError catch (e) {
        failures.add(FileFailure(item.name, e.message));
      } on SocketException catch (e) {
        if (signal.reason != null) return result(stopReason: signal.reason);
        return result(fatal: DestinationException(DestinationFailure.unreachable, e.message));
      } on IOException catch (e) {
        if (signal.reason != null) return result(stopReason: signal.reason);
        return result(fatal: DestinationException(DestinationFailure.interrupted, '$e'));
      }
      doneBytes += item.size;
    }
    report(BackupPhase.finishing, todo.length, '');
    return result();
  }

  Future<_Outcome> _saveOne(MediaItem item, StopSignal signal, void Function(int bytes) onBytes) async {
    final hash = await _localHash(item, signal);

    // Même contenu déjà sauvegardé (copie dans un autre album, fichier déplacé) : rien à envoyer.
    final twin = index.byHash(hash);
    if (twin != null) {
      await _remember(item, hash, twin.remotePath);
      return _Outcome.alreadyThere;
    }

    // Place définitive : le premier nom libre, sauf si le fichier y est déjà (envoi
    // précédent dont l'index n'a pas gardé trace : réinstallation, extinction brutale).
    final folder = folderFor(item);
    final name = safeName(item.name);
    final existing = await _findExisting(folder, name, item.size, hash);
    if (existing != null) {
      await _remember(item, hash, existing);
      return _Outcome.alreadyThere;
    }

    // Envoi dans le dossier des partiels, en reprenant là où un envoi précédent s'est arrêté.
    final partial = '$partialFolder/$hash.part';
    for (var attempt = 0; attempt < 2; attempt++) {
      var offset = attempt == 0 ? (await destination.sizeOf(partial) ?? 0) : 0;
      if (offset > item.size) offset = 0;
      if (offset < item.size || attempt > 0) {
        await destination.write(
          partial,
          _readLocal(item, offset, signal, (n) => onBytes(offset + n)),
          append: offset > 0,
        );
      }
      onBytes(item.size);
      if (await _verify(partial, item.size, hash, signal)) {
        await destination.makeDirs(folder);
        for (final candidate in candidateNames(name)) {
          final target = '$folder/$candidate';
          if (await destination.renameNoReplace(partial, target)) {
            await _remember(item, hash, target);
            return _Outcome.sent;
          }
        }
      }
      // Arrivé abîmé : on repart de zéro une seconde fois avant d'abandonner ce fichier.
    }
    throw const _FileError('le fichier arrivé sur le NAS ne correspond pas à l\'original (vérification échouée)');
  }

  Future<String?> _findExisting(String folder, String name, int size, String hash) async {
    for (final candidate in candidateNames(name)) {
      final path = '$folder/$candidate';
      final remoteSize = await destination.sizeOf(path);
      if (remoteSize == null) return null; // premier nom libre : rien au-delà
      if (remoteSize == size && await _remoteHash(path) == hash) return path;
    }
    return null;
  }

  Future<bool> _verify(String path, int size, String hash, StopSignal signal) async {
    if (await destination.sizeOf(path) != size) return false;
    if (!deepVerify) return true;
    if (signal.reason != null) throw const _Stopped();
    return await _remoteHash(path) == hash;
  }

  Future<String> _remoteHash(String path) async => (await sha256.bind(destination.read(path)).first).toString();

  Future<String> _localHash(MediaItem item, StopSignal signal) async {
    return (await sha256.bind(_readLocal(item, 0, signal, null)).first).toString();
  }

  Stream<List<int>> _readLocal(MediaItem item, int start, StopSignal signal, void Function(int)? onBytes) async* {
    var read = 0;
    try {
      await for (final chunk in _open(item.path, start)) {
        if (signal.reason != null) throw const _Stopped();
        read += chunk.length;
        onBytes?.call(read);
        yield chunk;
      }
    } on FileSystemException {
      throw const _FileError('fichier introuvable ou illisible sur le téléphone');
    }
  }

  Future<void> _remember(MediaItem item, String hash, String remotePath) =>
      index.add(IndexEntry(key: item.key, sha256: hash, remotePath: remotePath, size: item.size, savedAt: _clock()));
}

enum _Outcome { sent, alreadyThere }

class _Stopped implements Exception {
  const _Stopped();
}

class _FileError implements Exception {
  const _FileError(this.message);

  final String message;
}
