/// Photos, vidéos et albums du téléphone, tels que la galerie d'Android les décrit.
library;

/// Un album de la galerie (un dossier du téléphone : « Camera », « Screenshots »…).
class Album {
  const Album({required this.id, required this.name, required this.count, required this.bytes, this.path = ''});

  /// Identifiant stable donné par Android (`BUCKET_ID`).
  final String id;
  final String name;
  final int count;
  final int bytes;

  /// Dossier relatif sur le téléphone (`DCIM/Camera/`), pour reconnaître les albums connus.
  final String path;

  factory Album.fromMap(Map<Object?, Object?> map) => Album(
    id: '${map['id']}',
    name: map['nom'] as String? ?? 'Sans nom',
    count: (map['nombre'] as num?)?.toInt() ?? 0,
    bytes: (map['octets'] as num?)?.toInt() ?? 0,
    path: map['chemin'] as String? ?? '',
  );
}

/// Une photo ou une vidéo à sauvegarder.
class MediaItem {
  const MediaItem({
    required this.id,
    required this.name,
    required this.path,
    required this.size,
    required this.taken,
    required this.modified,
    required this.albumId,
    this.isVideo = false,
  });

  /// Identifiant de la galerie d'Android : il ne change pas si le fichier est renommé.
  final String id;

  /// Nom d'origine (`IMG_20261119_184502.jpg`).
  final String name;

  /// Chemin du fichier sur le téléphone, lisible avec l'autorisation d'accès aux médias.
  final String path;
  final int size;

  /// Date de prise de vue, à défaut date d'ajout : elle décide du rangement `AAAA/MM`.
  final DateTime taken;

  /// Dernière modification : une photo retouchée est une nouvelle version à sauvegarder.
  final DateTime modified;
  final String albumId;
  final bool isVideo;

  /// Clé de l'index : le même fichier, dans le même état, a toujours la même clé.
  String get key => '$id:$size:${modified.millisecondsSinceEpoch}';

  factory MediaItem.fromMap(Map<Object?, Object?> map) {
    DateTime date(Object? value) => DateTime.fromMillisecondsSinceEpoch((value as num?)?.toInt() ?? 0);
    final modified = date(map['modifie']);
    final taken = (map['prise'] as num?) == null || (map['prise'] as num) <= 0 ? modified : date(map['prise']);
    return MediaItem(
      id: '${map['id']}',
      name: map['nom'] as String? ?? 'sans-nom',
      path: map['chemin'] as String? ?? '',
      size: (map['taille'] as num?)?.toInt() ?? 0,
      taken: taken,
      modified: modified,
      albumId: '${map['album']}',
      isVideo: map['video'] == true,
    );
  }
}

/// Albums cochés par défaut, reconnus par leur dossier sur le téléphone : appareil photo,
/// captures d'écran et photos reçues par WhatsApp.
bool isDefaultAlbum(Album album) {
  final path = album.path.toLowerCase();
  final name = album.name.toLowerCase();
  return path.startsWith('dcim/camera') ||
      name == 'camera' ||
      name == 'appareil photo' ||
      path.contains('screenshots') ||
      name == 'screenshots' ||
      name == 'captures d\'écran' ||
      path.contains('whatsapp images') ||
      path.contains('whatsapp video') ||
      name == 'whatsapp images' ||
      name == 'whatsapp video';
}
