import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sbackup/core/backup_index.dart';
import 'package:sbackup/core/backup_job.dart';
import 'package:sbackup/core/conditions.dart';
import 'package:sbackup/core/destination.dart';
import 'package:sbackup/core/engine.dart';
import 'package:sbackup/core/history.dart';
import 'package:sbackup/core/media.dart';
import 'package:sbackup/core/progress.dart';
import 'package:sbackup/core/settings.dart';

import 'support/fakes.dart';

void main() {
  late Directory temp;
  late FakePhone phone;
  late BackupIndex index;
  late MemoryDestination nas;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('sbackup');
    Directory('${temp.path}/tel').createSync();
    phone = FakePhone(Directory('${temp.path}/tel'));
    index = BackupIndex(File('${temp.path}/index.jsonl'));
    nas = MemoryDestination();
  });
  tearDown(() => temp.deleteSync(recursive: true));

  BackupEngine engine({bool deepVerify = true, Destination? destination}) =>
      BackupEngine(destination: destination ?? nas, index: index, deepVerify: deepVerify);

  Future<EngineResult> run([BackupEngine? e, StopSignal? stop, List<BackupProgress>? progress]) async {
    await index.load();
    return (e ?? engine()).run(phone.items, onProgress: (p) => progress?.add(p), stop: stop);
  }

  List<int> bytesOf(MediaItem item) => File(item.path).readAsBytesSync();

  group('moteur', () {
    test('range par année et mois, avec le nom d\'origine, et vérifie le contenu', () async {
      final a = phone.add('IMG_20261119_184502.jpg');
      final b = phone.add('VID_20250102_101010.mp4', size: 300000, taken: DateTime(2025, 1, 2), video: true);
      final progress = <BackupProgress>[];
      final result = await run(null, null, progress);

      expect(result.sent, 2);
      expect(result.fatal, isNull);
      expect(nas.bytesOf('2026/11/IMG_20261119_184502.jpg'), bytesOf(a));
      expect(nas.bytesOf('2025/01/VID_20250102_101010.mp4'), bytesOf(b));
      // Plus rien dans le dossier des envois en cours.
      expect(nas.files.keys.where((k) => k.startsWith(partialFolder)), isEmpty);
      expect(index.count, 2);
      expect(progress.last.phase, BackupPhase.finishing);
      expect(progress.map((p) => p.bytesDone), everyElement(lessThanOrEqualTo(350000)));
    });

    test('un fichier déjà sauvegardé n\'est jamais renvoyé', () async {
      phone.add('a.jpg');
      phone.add('b.jpg');
      await run();
      final written = nas.writtenBytes;

      final again = await run();
      expect(again.sent, 0);
      expect(nas.writtenBytes, written);

      // L'index est relu depuis le disque : même constat après un redémarrage.
      index = BackupIndex(File('${temp.path}/index.jsonl'));
      expect((await run()).sent, 0);
      expect(nas.writtenBytes, written);
    });

    test('n\'écrase jamais un fichier existant : le nouveau prend le nom suivant', () async {
      nas.makeDirs('2026/11');
      nas.files['2026/11/IMG.jpg'] = BytesBuilder()..add([1, 2, 3]);
      nas.files['2026/11/IMG (2).jpg'] = BytesBuilder()..add([4, 5, 6]);
      final item = phone.add('IMG.jpg');

      expect((await run()).sent, 1);
      expect(nas.bytesOf('2026/11/IMG.jpg'), [1, 2, 3]);
      expect(nas.bytesOf('2026/11/IMG (2).jpg'), [4, 5, 6]);
      expect(nas.bytesOf('2026/11/IMG (3).jpg'), bytesOf(item));
      expect(index.byKey(item.key)!.remotePath, '2026/11/IMG (3).jpg');
    });

    test('un fichier déjà présent sur le NAS (index perdu) est reconnu sans être renvoyé', () async {
      final item = phone.add('IMG.jpg');
      await run();
      final written = nas.writtenBytes;

      // Réinstallation : l'index du téléphone est vide, le NAS a tout.
      File('${temp.path}/index.jsonl').deleteSync();
      final result = await run();
      expect(result.sent, 0);
      expect(result.alreadySaved, 1);
      expect(nas.writtenBytes, written);
      expect(index.byKey(item.key)!.remotePath, '2026/11/IMG.jpg');
    });

    test('reprise après une coupure : seul le reste du fichier est envoyé', () async {
      final item = phone.add('VID.mp4', size: 1000000, video: true);
      nas.failAfterBytes = 400000;
      final cut = await run();
      expect(cut.fatal?.failure, DestinationFailure.interrupted);
      expect(cut.sent, 0);
      expect(index.count, 0);
      expect(nas.files.keys.single, startsWith('$partialFolder/'));
      expect(nas.files.values.single.length, 400000);

      nas.failAfterBytes = null;
      nas.writtenBytes = 0;
      final resumed = await run();
      expect(resumed.sent, 1);
      expect(nas.writtenBytes, 600000);
      expect(nas.bytesOf('2026/11/VID.mp4'), bytesOf(item));
    });

    test('un fichier arrivé abîmé n\'est jamais rangé, et l\'erreur est expliquée', () async {
      phone.add('a.jpg');
      final b = phone.add('b.jpg');
      nas.corrupt = (path) => path.endsWith('.part') && nas.files[path]!.length == 50000;
      final result = await run();
      expect(result.sent, 0);
      expect(result.failures.map((f) => f.name), ['a.jpg', 'b.jpg']);
      expect(result.failures.first.message, contains('vérification échouée'));
      expect(nas.files.keys.where((k) => k.startsWith('2026')), isEmpty);
      expect(index.containsKey(b.key), isFalse);

      // Sans le défaut, le passage suivant les envoie.
      nas.corrupt = null;
      expect((await run()).sent, 2);
    });

    test('vérification par la taille seulement, si la vérification complète est coupée', () async {
      phone.add('a.jpg');
      nas.corrupt = (path) => path.endsWith('.part');
      // Le contenu est altéré mais la taille est juste : seule la vérification complète le voit.
      expect((await run(engine(deepVerify: false))).sent, 1);
    });

    test('la même photo dans deux albums n\'est envoyée qu\'une fois', () async {
      final content = List<int>.generate(20000, (i) => i % 251);
      phone.add('IMG.jpg', content: content);
      phone.add('IMG-copie.jpg', content: content, album: 'dl');
      final result = await run();
      expect(result.sent, 1);
      expect(result.alreadySaved, 1);
      expect(nas.files.keys.where((k) => k.startsWith('2026')), hasLength(1));
    });

    test('un fichier disparu du téléphone n\'empêche pas les autres', () async {
      final gone = phone.add('parti.jpg');
      phone.add('la.jpg');
      File(gone.path).deleteSync();
      final result = await run();
      expect(result.sent, 1);
      expect(result.failures.single.toString(), 'parti.jpg : fichier introuvable ou illisible sur le téléphone');
    });

    test('un arrêt demandé laisse le passage reprendre plus tard', () async {
      phone.add('a.jpg');
      phone.add('b.jpg');
      final stop = StopSignal();
      final progress = <BackupProgress>[];
      final result = await engine().run(
        phone.items,
        stop: stop,
        onProgress: (p) {
          progress.add(p);
          if (p.filesDone == 1) stop.stop('Wi-Fi perdu.');
        },
      );
      expect(result.stopReason, 'Wi-Fi perdu.');
      expect(result.sent, 1);
      expect((await run()).sent, 1);
    });

    test('fonctionne aussi avec un vrai dossier', () async {
      final item = phone.add('IMG.jpg');
      final folder = Directory('${temp.path}/nas');
      final local = LocalFolderDestination(folder);
      await local.open();
      expect((await run(engine(destination: local))).sent, 1);
      expect(File('${folder.path}/2026/11/IMG.jpg').readAsBytesSync(), bytesOf(item));
      expect(Directory('${folder.path}/$partialFolder').listSync(), isEmpty);
      expect(await local.renameNoReplace('2026/11/IMG.jpg', '2026/11/IMG.jpg'), isFalse);
    });
  });

  group('index', () {
    test('une ligne coupée par une extinction brutale est ignorée', () async {
      final entry = IndexEntry(key: 'k1', sha256: 'h1', remotePath: '2026/11/a.jpg', size: 10, savedAt: DateTime(2026));
      await index.add(entry);
      index.file.writeAsStringSync('\n{"cle":"k2","sha2', mode: FileMode.append);
      await index.add(
        IndexEntry(key: 'k3', sha256: 'h3', remotePath: '2026/11/c.jpg', size: 5, savedAt: DateTime(2026)),
      );
      final reloaded = BackupIndex(index.file);
      await reloaded.load();
      expect(reloaded.count, 2);
      expect(reloaded.containsKey('k1'), isTrue);
      expect(reloaded.containsKey('k3'), isTrue);
      expect(reloaded.byHash('h3')!.remotePath, '2026/11/c.jpg');
      expect(reloaded.bytes, 15);
    });
  });

  group('noms et rangement', () {
    test('noms sûrs pour un partage réseau', () {
      expect(safeName('IMG_1.jpg'), 'IMG_1.jpg');
      expect(safeName('a/b\\c:d*e?.jpg'), 'a_b_c_d_e_.jpg');
      expect(safeName('fin. '), 'fin');
      expect(safeName('   '), 'sans-nom');
    });

    test('noms suivants sans écrasement', () {
      expect(candidateNames('IMG.jpg').take(3), ['IMG.jpg', 'IMG (2).jpg', 'IMG (3).jpg']);
      expect(candidateNames('LISEZMOI').take(2), ['LISEZMOI', 'LISEZMOI (2)']);
      expect(candidateNames('.cache').take(2), ['.cache', '.cache (2)']);
    });

    test('dossier année / mois', () {
      final item = MediaItem.fromMap({
        'id': 7,
        'nom': 'x.jpg',
        'chemin': '/x.jpg',
        'taille': 3,
        'prise': DateTime(2024, 3, 9).millisecondsSinceEpoch,
        'modifie': DateTime(2026, 1, 1).millisecondsSinceEpoch,
        'album': 12,
      });
      expect(folderFor(item), '2024/03');
      // Sans date de prise de vue, la date du fichier sert.
      final undated = MediaItem.fromMap({
        'id': 8,
        'nom': 'y.png',
        'modifie': DateTime(2026, 12, 31).millisecondsSinceEpoch,
      });
      expect(folderFor(undated), '2026/12');
    });

    test('tailles et nombres lisibles', () {
      expect(formatBytes(0), '0 octet');
      expect(formatBytes(4200000), '4,2 Mo');
      expect(formatBytes(1300000000), '1,3 Go');
      expect(plural(1, 'photo'), '1 photo');
      expect(plural(12345, 'photo'), '12 345 photos');
    });

    test('albums cochés par défaut', () {
      bool d(String name, String path) => isDefaultAlbum(Album(id: '', name: name, count: 0, bytes: 0, path: path));
      expect(d('Camera', 'DCIM/Camera/'), isTrue);
      expect(d('Screenshots', 'DCIM/Screenshots/'), isTrue);
      expect(d('WhatsApp Images', 'Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Images/'), isTrue);
      expect(d('Download', 'Download/'), isFalse);
    });
  });

  group('conditions', () {
    const ready = Settings(
      homeNetworks: ['Maison'],
      destination: DestinationConfig(host: 'nas', folder: 'Photos'),
    );
    Blocker? check(Settings s, {bool wifi = true, String? ssid = '"Maison"', bool charging = false}) =>
        blockerFor(s, DeviceState.fromMap({'wifi': wifi, 'ssid': ssid, 'enCharge': charging}));

    test('seulement sur le Wi-Fi de la maison', () {
      expect(check(ready), isNull);
      expect(check(ready, wifi: false), Blocker.notOnWifi);
      expect(check(ready, ssid: '"Café"'), Blocker.otherNetwork);
      expect(check(ready, ssid: '<unknown ssid>'), Blocker.ssidUnknown);
      expect(check(const Settings()), Blocker.noDestination);
      expect(check(ready.copyWith(homeNetworks: [])), Blocker.noHomeNetwork);
    });

    test('en charge si demandé', () {
      final s = ready.copyWith(requireCharging: true);
      expect(check(s), Blocker.notCharging);
      expect(check(s, charging: true), isNull);
      expect(describeBlocker(Blocker.notCharging), contains('charge'));
    });
  });

  group('passage complet', () {
    late SettingsStore settingsStore;
    late HistoryStore history;
    Destination? destination;

    setUp(() async {
      settingsStore = SettingsStore(File('${temp.path}/reglages.json'));
      history = HistoryStore(File('${temp.path}/historique.json'));
      destination = nas;
      await settingsStore.save(
        const Settings(
          homeNetworks: ['Maison'],
          destination: DestinationConfig(host: '192.168.1.10', folder: 'Photos'),
        ),
      );
    });

    BackupJob job() => BackupJob(
      system: phone,
      settingsStore: settingsStore,
      historyStore: history,
      index: index,
      createDestination: (_) async => destination,
    );

    test('envoie les albums usuels, et garde la trace dans l\'historique', () async {
      phone.add('cam.jpg');
      phone.add('capture.png', album: 'shots');
      phone.add('telechargement.pdf', album: 'dl');
      final record = await job().run(RunTrigger.manual);
      expect(record.outcome, RunOutcome.success);
      expect(record.sent, 2);
      expect(record.message, startsWith('2 fichiers envoyés'));
      expect(nas.files.keys.where((k) => k.contains('telechargement')), isEmpty);

      final again = await job().run(RunTrigger.scheduled);
      expect(again.message, 'Tout était déjà sauvegardé.');
      expect((await history.load()).length, 2);
    });

    test('les albums choisis remplacent les albums usuels', () async {
      await settingsStore.save((await settingsStore.load()).copyWith(albums: {'dl'}));
      phone.add('cam.jpg');
      phone.add('telechargement.pdf', album: 'dl');
      expect((await job().run(RunTrigger.manual)).sent, 1);
      expect(nas.files.keys.single, '2026/11/telechargement.pdf');
    });

    test('ailleurs qu\'à la maison, rien n\'est tenté', () async {
      phone.add('cam.jpg');
      phone.state = const DeviceState(onWifi: true, ssid: 'Café', charging: true);
      final record = await job().run(RunTrigger.scheduled);
      expect(record.outcome, RunOutcome.skipped);
      expect(nas.opened, isFalse);
      expect(nas.files, isEmpty);
      // Les attentes successives ne s'empilent pas dans l'historique.
      await job().run(RunTrigger.scheduled);
      expect((await history.load()).length, 1);
    });

    test('NAS injoignable : erreur expliquée en français', () async {
      phone.add('cam.jpg');
      nas.openFailure = DestinationFailure.unreachable;
      final record = await job().run(RunTrigger.manual);
      expect(record.outcome, RunOutcome.failed);
      expect(record.message, contains('ne répond pas'));
    });

    test('sans protocole branché, la raison est donnée honnêtement', () async {
      destination = null;
      final record = await job().run(RunTrigger.manual);
      expect(record.outcome, RunOutcome.failed);
      expect(record.message, contains('pas encore branché'));
    });

    test('Wi-Fi perdu pendant l\'envoi : arrêt propre, reprise ensuite', () async {
      for (var i = 0; i < 4; i++) {
        phone.add('IMG_$i.jpg');
      }
      final stop = StopSignal();
      final j = BackupJob(
        system: phone,
        settingsStore: settingsStore,
        historyStore: history,
        index: index,
        createDestination: (_) async => nas,
        stop: stop,
        onProgress: (p) {
          if (p.filesDone == 2) stop.stop(describeBlocker(Blocker.notOnWifi));
        },
      );
      final record = await j.run(RunTrigger.newMedia);
      expect(record.outcome, RunOutcome.interrupted);
      expect(record.sent, 2);
      expect(record.message, startsWith('En attente du Wi-Fi'));
      expect((await job().run(RunTrigger.scheduled)).sent, 2);
    });

    test('l\'historique se relit, même abîmé', () async {
      await history.add(
        RunRecord(
          start: DateTime(2026),
          end: DateTime(2026),
          outcome: RunOutcome.success,
          trigger: RunTrigger.manual,
          sent: 3,
        ),
      );
      expect((await history.load()).single.sent, 3);
      history.file!.writeAsStringSync('pas du json');
      expect(await history.load(), isEmpty);
    });
  });

  test('empreinte SHA-256 identique à celle d\'un outil standard', () {
    expect(
      sha256.convert('abc'.codeUnits).toString(),
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
  });
}
