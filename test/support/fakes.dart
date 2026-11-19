import 'dart:io';
import 'dart:math';

import 'package:sbackup/core/backup_job.dart';
import 'package:sbackup/core/conditions.dart';
import 'package:sbackup/core/media.dart';

/// Un faux téléphone : des photos dans un dossier temporaire, un Wi-Fi, une batterie.
class FakePhone implements SystemPort {
  FakePhone(this.folder);

  final Directory folder;
  final items = <MediaItem>[];
  final albumList = <Album>[
    const Album(id: 'cam', name: 'Camera', count: 0, bytes: 0, path: 'DCIM/Camera/'),
    const Album(id: 'shots', name: 'Screenshots', count: 0, bytes: 0, path: 'Pictures/Screenshots/'),
    const Album(id: 'dl', name: 'Download', count: 0, bytes: 0, path: 'Download/'),
  ];

  DeviceState state = const DeviceState(onWifi: true, ssid: 'Maison', charging: true);
  int _next = 0;

  /// Ajoute une photo de [size] octets aléatoires, ou du [content] donné.
  MediaItem add(
    String name, {
    int size = 50000,
    List<int>? content,
    String album = 'cam',
    DateTime? taken,
    bool video = false,
  }) {
    final id = '${++_next}';
    final file = File('${folder.path}/$id-$name');
    final random = Random(_next);
    file.writeAsBytesSync(content ?? List<int>.generate(size, (_) => random.nextInt(256)));
    final item = MediaItem(
      id: id,
      name: name,
      path: file.path,
      size: file.lengthSync(),
      taken: taken ?? DateTime(2026, 11, 19, 18, 45),
      modified: DateTime(2026, 11, 19, 18, 45, _next),
      albumId: album,
      isVideo: video,
    );
    items.add(item);
    return item;
  }

  @override
  Future<DeviceState> deviceState() async => state;

  @override
  Future<List<Album>> albums() async => albumList;

  @override
  Future<List<MediaItem>> media(Set<String> albumIds) async =>
      items.where((item) => albumIds.contains(item.albumId)).toList();
}
