import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sbackup/app.dart';
import 'package:sbackup/core/backup_index.dart';
import 'package:sbackup/core/conditions.dart';
import 'package:sbackup/core/history.dart';
import 'package:sbackup/core/media.dart';
import 'package:sbackup/core/progress.dart';
import 'package:sbackup/core/settings.dart';
import 'package:sbackup/data_files.dart';
import 'package:sbackup/platform/platform.dart';
import 'package:sbackup/state/app_controller.dart';

/// Charge les vraies polices pour que les mesures de texte correspondent à l'application.
Future<void> loadFonts() async {
  final outfit = FontLoader('Outfit');
  for (final weight in ['300Light', '400Regular', '500Medium', '600SemiBold']) {
    final bytes = File('assets/fonts/Outfit_$weight.ttf').readAsBytesSync();
    outfit.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await outfit.load();

  // Les icônes Material viennent du SDK Flutter ; sans elles, des carrés les remplacent.
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot == null) return;
  final icons = File('$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (!icons.existsSync()) return;
  final material = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.view(icons.readAsBytesSync().buffer)));
  await material.load();
}

/// Clé de la zone capturée pour la documentation.
const captureKey = ValueKey('capture');

/// Heure de référence des dates affichées.
final testNow = DateTime(2026, 11, 19, 21, 30);

/// Un téléphone simulé pour l'interface : il note ce qu'on lui demande.
class FakePlatform implements PhonePlatform {
  PermissionState permissionState = const PermissionState(
    media: MediaAccess.all,
    notifications: true,
    location: true,
    backgroundLocation: true,
    batteryUnrestricted: true,
  );
  DeviceState state = const DeviceState(onWifi: true, ssid: 'Maison', charging: false);
  List<Album> albumList = const [
    Album(id: 'cam', name: 'Camera', count: 8412, bytes: 41200000000, path: 'DCIM/Camera/'),
    Album(id: 'shots', name: 'Screenshots', count: 1290, bytes: 980000000, path: 'Pictures/Screenshots/'),
    Album(
      id: 'wa',
      name: 'WhatsApp Images',
      count: 3021,
      bytes: 2100000000,
      path: 'Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Images/',
    ),
    Album(id: 'dl', name: 'Download', count: 57, bytes: 310000000, path: 'Download/'),
    Album(
      id: 'long',
      name: 'Un album au nom vraiment très long pour vérifier que rien ne déborde',
      count: 1,
      bytes: 1200,
      path: 'Pictures/Autre/',
    ),
  ];
  final requests = <PermissionRequest>[];
  final progressController = StreamController<BackupProgress>.broadcast();
  int runs = 0;
  int stops = 0;
  ({bool enabled, bool requireCharging})? scheduled;

  @override
  Future<String> dataDirectory() async => throw UnimplementedError();

  @override
  Future<PermissionState> permissions() async => permissionState;

  @override
  Future<void> request(PermissionRequest what) async => requests.add(what);

  @override
  Future<DeviceState> deviceState() async => state;

  @override
  Future<List<Album>> albums() async => albumList;

  @override
  Future<List<MediaItem>> media(Set<String> albumIds) async => const [];

  @override
  Future<void> schedule({required bool enabled, required bool requireCharging}) async =>
      scheduled = (enabled: enabled, requireCharging: requireCharging);

  @override
  Future<void> runNow() async => runs++;

  @override
  Future<void> stop() async => stops++;

  @override
  Stream<BackupProgress> progress() => progressController.stream;
}

/// Réglages prêts à sauvegarder.
const readySettings = Settings(
  homeNetworks: ['Maison'],
  destination: DestinationConfig(host: '192.168.1.10', folder: 'Photos/Téléphone', user: 'shine'),
);

final sampleHistory = [
  RunRecord(
    start: DateTime(2026, 11, 19, 18, 40),
    end: DateTime(2026, 11, 19, 18, 47),
    outcome: RunOutcome.success,
    trigger: RunTrigger.newMedia,
    sent: 23,
    bytes: 412000000,
    message: '23 fichiers envoyés (412 Mo).',
  ),
  RunRecord(
    start: DateTime(2026, 11, 18, 22, 3),
    end: DateTime(2026, 11, 18, 22, 15),
    outcome: RunOutcome.partial,
    trigger: RunTrigger.scheduled,
    sent: 140,
    message: '140 fichiers envoyés (1,8 Go). 2 fichiers en échec.',
    errors: [
      'IMG_20261118_101010.jpg : fichier introuvable ou illisible sur le téléphone',
      'VID_20261118_120000_un_nom_de_video_particulierement_long.mp4 : le fichier arrivé sur le NAS ne correspond pas à l\'original (vérification échouée)',
    ],
  ),
  RunRecord(
    start: DateTime(2026, 11, 2, 9),
    end: DateTime(2026, 11, 2, 9),
    outcome: RunOutcome.failed,
    trigger: RunTrigger.manual,
    message: 'Le NAS ne répond pas. Vérifiez qu\'il est allumé et que son adresse est la bonne.',
  ),
];

/// Affiche l'application sur un écran de la taille donnée, sans Android : l'état est
/// imposé par le faux téléphone et par `debugSetState`.
Future<(AppController, FakePlatform)> pumpApp(
  WidgetTester tester,
  Size size, {
  Settings settings = readySettings,
  FakePlatform? platform,
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final fake = platform ?? FakePlatform();
  final store = MemorySettingsStore(settings);
  final controller = AppController(
    platform: fake,
    files: DataFiles.custom(settings: store, history: HistoryStore(null), index: BackupIndex(File('/nulle-part'))),
  );
  await tester.runAsync(controller.load);
  await tester.runAsync(controller.start);
  await tester.pumpWidget(
    RepaintBoundary(
      key: captureKey,
      child: SBackupApp(controller: controller),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
  return (controller, fake);
}

Future<void> tearDownApp(WidgetTester tester, AppController controller) async {
  await tester.pumpWidget(const SizedBox());
  controller.dispose();
  await tester.pump(const Duration(seconds: 1));
}

/// Réglages gardés en mémoire.
class MemorySettingsStore extends SettingsStore {
  MemorySettingsStore(this.value) : super(null);

  Settings value;

  @override
  Future<Settings> load() async => value;

  @override
  Future<void> save(Settings settings) async => value = settings;
}
