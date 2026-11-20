import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sbackup/core/backup_index.dart';
import 'package:sbackup/core/destination.dart';
import 'package:sbackup/core/engine.dart';
import 'package:sbackup/core/settings.dart';
import 'package:sbackup/platform/smb_destination.dart';

import 'support/fakes.dart';

/// Faux NAS derrière le canal `sbackup/smb`, qui suit le même contrat que `SmbChannel.kt` :
/// chemins relatifs au dossier de destination, écriture par morceaux à une position donnée,
/// renommage refusé si la cible existe, erreurs signalées par code.
class FakeSmbNas {
  final files = <String, Uint8List>{};
  final dirs = <String>{};
  final calls = <String>[];
  final _handles = <int, String>{};
  var _next = 1;
  String? password = 'secret';

  /// Code d'erreur renvoyé à la prochaine écriture de morceau (coupure simulée).
  String? failNextWrite;

  Future<Object?> handle(MethodCall call) async {
    calls.add(call.method);
    final args = (call.arguments as Map?)?.cast<String, Object?>() ?? const {};
    String path([String key = 'chemin']) => args[key]! as String;
    switch (call.method) {
      case 'ouvrir':
        if (args['hote'] != '192.168.1.10') throw PlatformException(code: 'injoignable');
        if (args['partage'] != 'home') throw PlatformException(code: 'permission', message: 'STATUS_BAD_NETWORK_NAME');
        if (password != 'secret') throw PlatformException(code: 'authentification');
        return null;
      case 'fermer':
        return null;
      case 'taille':
        return files[path()]?.length;
      case 'creerDossiers':
        dirs.add(path());
        return null;
      case 'ouvrirEcriture':
        final target = path();
        if (args['ajout'] != true || !files.containsKey(target)) files[target] = Uint8List(0);
        _handles[_next] = target;
        return _next++;
      case 'ecrireMorceau':
        final code = failNextWrite;
        if (code != null) {
          failNextWrite = null;
          throw PlatformException(code: code);
        }
        final target = _handles[args['id']]!;
        final bytes = args['octets']! as Uint8List;
        final position = args['position']! as int;
        final current = files[target]!;
        expect(position, current.length, reason: 'écriture à la suite du fichier');
        files[target] = Uint8List.fromList([...current, ...bytes]);
        return null;
      case 'ouvrirLecture':
        _handles[_next] = path();
        return _next++;
      case 'lireMorceau':
        final data = files[_handles[args['id']]]!;
        final start = args['position']! as int;
        final end = (start + (args['taille']! as int)).clamp(0, data.length);
        return start >= data.length ? Uint8List(0) : Uint8List.sublistView(data, start, end);
      case 'fermerFichier':
        _handles.remove(args['id']);
        return null;
      case 'renommer':
        final to = path('vers');
        if (files.containsKey(to)) return false;
        files[to] = files.remove(path('de'))!;
        return true;
    }
    throw MissingPluginException(call.method);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeSmbNas nas;
  late Directory temp;
  late FakePhone phone;
  late BackupIndex index;
  const config = DestinationConfig(host: '192.168.1.10', user: 'shine');

  setUp(() {
    nas = FakeSmbNas();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(smbChannel, nas.handle);
    temp = Directory.systemTemp.createTempSync('sbackup-smb');
    phone = FakePhone(temp);
    index = BackupIndex(File('${temp.path}/index.jsonl'));
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(smbChannel, null);
    temp.deleteSync(recursive: true);
  });

  Future<EngineResult> run() async {
    final destination = SmbDestination(config);
    await destination.open();
    await index.load();
    try {
      return await BackupEngine(destination: destination, index: index).run(phone.items, onProgress: (_) {});
    } finally {
      await destination.close();
    }
  }

  test('sauvegarde complète par le canal SMB, avec des fichiers de plusieurs morceaux', () async {
    final big = phone.add('VID.mp4', size: smbChunk * 2 + 12345, video: true);
    final small = phone.add('IMG.jpg', size: 3000);
    final result = await run();
    expect(result.sent, 2);
    expect(nas.files['2026/11/VID.mp4'], File(big.path).readAsBytesSync());
    expect(nas.files['2026/11/IMG.jpg'], File(small.path).readAsBytesSync());
    expect(nas.dirs, containsAll([partialFolder, '2026/11']));
    // Écrit en morceaux d'au plus 1 Mio, relu de même pour la vérification.
    expect(nas.calls.where((c) => c == 'ecrireMorceau'), hasLength(4));
    expect(nas.files.keys.where((k) => k.startsWith(partialFolder)), isEmpty);
  });

  test('coupure du NAS en plein envoi, puis reprise sans renvoyer le début', () async {
    final item = phone.add('VID.mp4', size: smbChunk * 3, video: true);
    nas.failNextWrite = null;
    var writes = 0;
    final original = nas.handle;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(smbChannel, (call) {
      if (call.method == 'ecrireMorceau' && ++writes == 3) throw PlatformException(code: 'coupure');
      return original(call);
    });
    final cut = await run();
    expect(cut.fatal?.failure, DestinationFailure.interrupted);
    final partial = nas.files.entries.singleWhere((e) => e.key.startsWith(partialFolder));
    expect(partial.value.length, smbChunk * 2);

    nas.calls.clear();
    final resumed = await run();
    expect(resumed.sent, 1);
    expect(nas.calls.where((c) => c == 'ecrireMorceau'), hasLength(1));
    expect(nas.files['2026/11/VID.mp4'], File(item.path).readAsBytesSync());
  });

  test('un fichier du même nom sur le NAS n\'est jamais écrasé', () async {
    nas.files['2026/11/IMG.jpg'] = Uint8List.fromList([1, 2, 3]);
    phone.add('IMG.jpg');
    expect((await run()).sent, 1);
    expect(nas.files['2026/11/IMG.jpg'], [1, 2, 3]);
    expect(nas.files.containsKey('2026/11/IMG (2).jpg'), isTrue);
  });

  test('les erreurs d\'Android deviennent des erreurs expliquées', () async {
    Future<DestinationFailure?> openWith(DestinationConfig c) async {
      try {
        await SmbDestination(c).open();
        return null;
      } on DestinationException catch (e) {
        return e.failure;
      }
    }

    expect(await openWith(config), isNull);
    expect(await openWith(config.copyWith(host: '192.168.1.99')), DestinationFailure.unreachable);
    expect(await openWith(config.copyWith(share: 'photo')), DestinationFailure.permission);
    nas.password = 'autre';
    expect(await openWith(config), DestinationFailure.authentication);
    expect(failureFromCode('plein'), DestinationFailure.full);
    expect(failureFromCode('inconnu'), DestinationFailure.other);
  });

  test('libellé lisible du dossier de destination', () {
    expect(SmbDestination(config).label, r'\\192.168.1.10\home\Photos\Téléphone');
  });
}
