import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import '../core/destination.dart';
import '../core/settings.dart';

/// Canal vers `android/…/SmbChannel.kt` (bibliothèque smbj).
const smbChannel = MethodChannel('sbackup/smb');

/// Taille des morceaux échangés avec Android (écriture et relecture).
const smbChunk = 1 << 20;

/// Le NAS en partage Windows (SMB 2/3) : `\\<hôte>\<partage>\<dossier>`.
///
/// Le travail réseau se fait côté Android ; ici, le contrat de [Destination] est traduit en
/// appels du canal, et les erreurs Android en [DestinationFailure].
class SmbDestination implements Destination {
  SmbDestination(this.config, {this.channel = smbChannel});

  final DestinationConfig config;
  final MethodChannel channel;

  @override
  String get label => '\\\\${config.host}\\${config.share}\\${config.folder.replaceAll('/', '\\')}';

  Future<T?> _call<T>(String method, [Map<String, Object?>? arguments]) async {
    try {
      return await channel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (e) {
      throw DestinationException(failureFromCode(e.code), e.message ?? '');
    } on MissingPluginException {
      throw const DestinationException(DestinationFailure.other, 'Partage Windows indisponible sur cet appareil');
    }
  }

  @override
  Future<void> open() => _call<void>('ouvrir', {
    'hote': config.host,
    'partage': config.share,
    'dossier': config.folder,
    'utilisateur': config.user,
  });

  @override
  Future<void> close() => _call<void>('fermer');

  @override
  Future<int?> sizeOf(String path) async => (await _call<num>('taille', {'chemin': path}))?.toInt();

  @override
  Future<void> makeDirs(String path) => _call<void>('creerDossiers', {'chemin': path});

  @override
  Future<void> write(String path, Stream<List<int>> data, {required bool append}) async {
    var position = append ? (await sizeOf(path) ?? 0) : 0;
    final id = (await _call<int>('ouvrirEcriture', {'chemin': path, 'ajout': append}))!;
    final buffer = BytesBuilder(copy: false);
    Future<void> flush() async {
      if (buffer.isEmpty) return;
      final bytes = buffer.takeBytes();
      await _call<void>('ecrireMorceau', {'id': id, 'octets': bytes, 'position': position});
      position += bytes.length;
    }

    try {
      // Les erreurs de [data] (fichier illisible, arrêt demandé) remontent telles quelles.
      await for (final chunk in data) {
        buffer.add(chunk);
        if (buffer.length >= smbChunk) await flush();
      }
      await flush();
    } finally {
      try {
        await _call<void>('fermerFichier', {'id': id});
      } on DestinationException {
        // Liaison coupée : le fichier sera refermé par le NAS.
      }
    }
  }

  @override
  Stream<List<int>> read(String path) async* {
    final id = (await _call<int>('ouvrirLecture', {'chemin': path}))!;
    var position = 0;
    try {
      while (true) {
        final bytes = await _call<Uint8List>('lireMorceau', {'id': id, 'position': position, 'taille': smbChunk});
        if (bytes == null || bytes.isEmpty) break;
        position += bytes.length;
        yield bytes;
      }
    } finally {
      try {
        await _call<void>('fermerFichier', {'id': id});
      } on DestinationException {
        // Sans conséquence : lecture seule.
      }
    }
  }

  @override
  Future<bool> renameNoReplace(String from, String to) async =>
      await _call<bool>('renommer', {'de': from, 'vers': to}) ?? false;
}

/// Code d'erreur envoyé par `SmbChannel.classify` → nature de l'échec.
DestinationFailure failureFromCode(String code) => switch (code) {
  'injoignable' => DestinationFailure.unreachable,
  'authentification' => DestinationFailure.authentication,
  'permission' => DestinationFailure.permission,
  'plein' => DestinationFailure.full,
  'coupure' => DestinationFailure.interrupted,
  _ => DestinationFailure.other,
};

/// Mot de passe du NAS : gardé chiffré côté Android, jamais relu par l'interface.
class NasPassword {
  const NasPassword({this.channel = smbChannel});

  final MethodChannel channel;

  Future<void> save(String password) => channel.invokeMethod<void>('enregistrerMotDePasse', {'motDePasse': password});

  Future<bool> isSaved() async => await channel.invokeMethod<bool>('motDePasseEnregistre') ?? false;
}
