import 'dart:convert';
import 'dart:io';

/// Un fichier sauvegardé : où il est sur le NAS, et son empreinte.
class IndexEntry {
  const IndexEntry({
    required this.key,
    required this.sha256,
    required this.remotePath,
    required this.size,
    required this.savedAt,
  });

  /// Clé du fichier sur le téléphone (voir `MediaItem.key`).
  final String key;
  final String sha256;
  final String remotePath;
  final int size;
  final DateTime savedAt;

  Map<String, Object> toJson() => {
    'cle': key,
    'sha256': sha256,
    'nas': remotePath,
    'taille': size,
    'le': savedAt.millisecondsSinceEpoch,
  };

  static IndexEntry? tryParse(String line) {
    try {
      final map = jsonDecode(line) as Map<String, dynamic>;
      return IndexEntry(
        key: map['cle'] as String,
        sha256: map['sha256'] as String,
        remotePath: map['nas'] as String,
        size: (map['taille'] as num).toInt(),
        savedAt: DateTime.fromMillisecondsSinceEpoch((map['le'] as num).toInt()),
      );
    } on Object {
      return null;
    }
  }
}

/// Index des fichiers déjà sauvegardés, sur le téléphone.
///
/// C'est un journal : une ligne JSON par fichier, ajoutée **après** que le fichier est
/// arrivé, vérifié et rangé sur le NAS. Une ligne coupée par une extinction brutale est
/// ignorée à la lecture ; le fichier correspondant sera reconnu sur le NAS au passage
/// suivant (même nom, même empreinte) sans être renvoyé.
class BackupIndex {
  BackupIndex(this.file);

  final File file;

  final _byKey = <String, IndexEntry>{};
  final _byHash = <String, IndexEntry>{};
  int _bytes = 0;

  int get count => _byHash.length;

  /// Volume total sauvegardé (chaque contenu compté une fois).
  int get bytes => _bytes;

  Future<void> load() async {
    _byKey.clear();
    _byHash.clear();
    _bytes = 0;
    if (!await file.exists()) return;
    final lines = await file.openRead().transform(utf8.decoder).transform(const LineSplitter()).toList();
    for (final line in lines) {
      final entry = IndexEntry.tryParse(line);
      if (entry != null) _remember(entry);
    }
  }

  bool containsKey(String key) => _byKey.containsKey(key);

  IndexEntry? byKey(String key) => _byKey[key];

  /// Un contenu identique déjà sauvegardé (la même photo dans deux albums, par exemple).
  IndexEntry? byHash(String sha256) => _byHash[sha256];

  Future<void> add(IndexEntry entry) async {
    await file.parent.create(recursive: true);
    // Le saut de ligne en tête referme une éventuelle ligne coupée lors d'un arrêt brutal.
    await file.writeAsString('\n${jsonEncode(entry.toJson())}', mode: FileMode.append, flush: true);
    _remember(entry);
  }

  void _remember(IndexEntry entry) {
    _byKey[entry.key] = entry;
    if (!_byHash.containsKey(entry.sha256)) _bytes += entry.size;
    _byHash[entry.sha256] = entry;
  }
}
