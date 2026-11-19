import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

/// Nature d'un échec côté destination : elle décide du message montré et de la suite.
enum DestinationFailure {
  /// Le NAS ne répond pas (éteint, autre réseau, adresse erronée).
  unreachable,

  /// Identifiant ou mot de passe refusé.
  authentication,

  /// Le dossier de destination n'existe pas ou n'est pas accessible en écriture.
  permission,

  /// Le NAS est plein.
  full,

  /// Liaison coupée en cours de route.
  interrupted,

  /// Autre erreur.
  other,
}

class DestinationException implements Exception {
  const DestinationException(this.failure, [this.detail = '']);

  final DestinationFailure failure;
  final String detail;

  @override
  String toString() => 'DestinationException(${failure.name}${detail.isEmpty ? '' : ', $detail'})';
}

/// L'endroit où les fichiers sont sauvegardés : le NAS, ou un substitut dans les tests.
///
/// Tous les chemins sont relatifs au dossier de destination et utilisent « / ».
///
/// Le contrat est volontairement petit, pour se brancher sur n'importe quel protocole
/// (SMB, WebDAV, SFTP…) : **aucune opération ne supprime ni n'écrase un fichier**, à une
/// exception près, [write] sans `append`, réservé aux fichiers temporaires de sBackup
/// (dossier `.sbackup-partiel`), jamais aux fichiers sauvegardés.
abstract class Destination {
  /// Description lisible (« NAS 192.168.1.10, dossier Photos »).
  String get label;

  /// Se connecte et vérifie que le dossier de destination est accessible en écriture.
  Future<void> open();

  Future<void> close();

  /// Taille du fichier, ou `null` s'il n'existe pas.
  Future<int?> sizeOf(String path);

  /// Crée le dossier et ses parents s'ils n'existent pas.
  Future<void> makeDirs(String path);

  /// Écrit [data] dans [path] : à la suite du contenu existant si [append] (reprise d'un
  /// envoi interrompu), sinon en repartant de zéro. Les dossiers parents existent déjà.
  /// Une erreur levée par [data] (fichier illisible, arrêt demandé) doit remonter telle
  /// quelle, sans être enveloppée.
  Future<void> write(String path, Stream<List<int>> data, {required bool append});

  /// Relit un fichier, pour vérifier ce qui est arrivé.
  Stream<List<int>> read(String path);

  /// Renomme [from] en [to] **seulement si [to] n'existe pas** ; renvoie `false` sinon.
  Future<bool> renameNoReplace(String from, String to);
}

/// Destination en mémoire, pour les tests : elle peut simuler une coupure en cours d'envoi.
class MemoryDestination implements Destination {
  MemoryDestination({this.label = 'Destination en mémoire'});

  @override
  final String label;

  final files = <String, BytesBuilder>{};
  final dirs = <String>{''};

  /// Si défini, l'écriture s'interrompt (exception) après ce nombre d'octets reçus.
  int? failAfterBytes;

  /// Si défini, ce fichier est corrompu (un octet modifié) à chaque écriture.
  bool Function(String path)? corrupt;

  /// Si défini, [open] échoue avec cette erreur.
  DestinationFailure? openFailure;

  bool opened = false;
  int writtenBytes = 0;

  Uint8List? bytesOf(String path) => files[path]?.toBytes();

  @override
  Future<void> open() async {
    if (openFailure != null) throw DestinationException(openFailure!);
    opened = true;
  }

  @override
  Future<void> close() async => opened = false;

  @override
  Future<int?> sizeOf(String path) async => files[path]?.length;

  @override
  Future<void> makeDirs(String path) async {
    var current = '';
    for (final part in path.split('/').where((s) => s.isNotEmpty)) {
      current = current.isEmpty ? part : '$current/$part';
      dirs.add(current);
    }
  }

  @override
  Future<void> write(String path, Stream<List<int>> data, {required bool append}) async {
    final parent = p.posix.dirname(path);
    if (!dirs.contains(parent == '.' ? '' : parent)) {
      throw DestinationException(DestinationFailure.permission, 'Dossier absent : $parent');
    }
    final builder = append ? (files[path] ?? BytesBuilder()) : BytesBuilder();
    files[path] = builder;
    await for (final chunk in data) {
      final limit = failAfterBytes;
      if (limit != null && writtenBytes + chunk.length > limit) {
        final keep = limit - writtenBytes;
        if (keep > 0) builder.add(chunk.sublist(0, keep));
        writtenBytes = limit;
        throw const DestinationException(DestinationFailure.interrupted, 'Coupure simulée');
      }
      builder.add(chunk);
      writtenBytes += chunk.length;
    }
    if (corrupt?.call(path) ?? false) {
      final bytes = builder.takeBytes();
      if (bytes.isNotEmpty) bytes[bytes.length ~/ 2] ^= 0xFF;
      builder.add(bytes);
    }
  }

  @override
  Stream<List<int>> read(String path) {
    final bytes = files[path]?.toBytes();
    if (bytes == null) return Stream.error(DestinationException(DestinationFailure.other, 'Absent : $path'));
    return Stream.value(bytes);
  }

  @override
  Future<bool> renameNoReplace(String from, String to) async {
    if (files.containsKey(to)) return false;
    final builder = files.remove(from);
    if (builder == null) throw DestinationException(DestinationFailure.other, 'Absent : $from');
    files[to] = builder;
    return true;
  }
}

/// Destination dans un dossier local. Elle sert aux tests, et à tout dossier que le
/// système présente comme local.
class LocalFolderDestination implements Destination {
  LocalFolderDestination(this.root);

  final Directory root;

  @override
  String get label => 'Dossier ${root.path}';

  File _file(String path) => File(p.joinAll([root.path, ...path.split('/')]));

  @override
  Future<void> open() async {
    try {
      await root.create(recursive: true);
      final probe = File(p.join(root.path, '.sbackup-essai'));
      await probe.writeAsString('ok');
      // Seul fichier que sBackup supprime : le sien, créé à l'instant pour l'essai.
      await probe.delete();
    } on FileSystemException catch (e) {
      throw DestinationException(DestinationFailure.permission, e.message);
    }
  }

  @override
  Future<void> close() async {}

  @override
  Future<int?> sizeOf(String path) async {
    final file = _file(path);
    return await file.exists() ? file.length() : null;
  }

  @override
  Future<void> makeDirs(String path) => Directory(p.joinAll([root.path, ...path.split('/')])).create(recursive: true);

  @override
  Future<void> write(String path, Stream<List<int>> data, {required bool append}) async {
    final sink = _file(path).openWrite(mode: append ? FileMode.append : FileMode.write);
    try {
      await sink.addStream(data);
      await sink.flush();
    } finally {
      await sink.close();
    }
  }

  @override
  Stream<List<int>> read(String path) => _file(path).openRead();

  @override
  Future<bool> renameNoReplace(String from, String to) async {
    final target = _file(to);
    // Vérification puis renommage : suffisant, une seule sauvegarde écrit à la fois.
    if (await target.exists()) return false;
    await _file(from).rename(target.path);
    return true;
  }
}
