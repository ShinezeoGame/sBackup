import 'dart:convert';
import 'dart:io';

/// Thème de l'interface : automatique (suit le réglage du système), clair ou sombre.
enum AppThemeMode { auto, light, dark }

/// Où et comment joindre le NAS. Le protocole sera branché une fois choisi ; les champs
/// communs à tous (adresse, dossier, identifiant) sont déjà là.
class DestinationConfig {
  const DestinationConfig({this.host = '', this.folder = '', this.user = ''});

  /// Adresse du NAS sur le réseau de la maison (`192.168.1.10` ou `nas.local`).
  final String host;

  /// Dossier de destination sur le NAS (`Photos/Téléphone`).
  final String folder;
  final String user;

  bool get isComplete => host.trim().isNotEmpty && folder.trim().isNotEmpty;

  Map<String, Object> toJson() => {'hote': host, 'dossier': folder, 'utilisateur': user};

  factory DestinationConfig.fromJson(Map<String, dynamic> map) => DestinationConfig(
    host: map['hote'] as String? ?? '',
    folder: map['dossier'] as String? ?? '',
    user: map['utilisateur'] as String? ?? '',
  );

  DestinationConfig copyWith({String? host, String? folder, String? user}) =>
      DestinationConfig(host: host ?? this.host, folder: folder ?? this.folder, user: user ?? this.user);
}

class Settings {
  const Settings({
    this.theme = AppThemeMode.auto,
    this.autoBackup = true,
    this.homeNetworks = const [],
    this.requireCharging = false,
    this.albums,
    this.destination = const DestinationConfig(),
    this.deepVerify = true,
  });

  final AppThemeMode theme;

  /// Sauvegarder tout seul, en arrière-plan, quand les conditions sont réunies.
  final bool autoBackup;

  /// Noms (SSID) des Wi-Fi de la maison. Ailleurs, rien n'est envoyé.
  final List<String> homeNetworks;

  /// N'envoyer que lorsque le téléphone est en charge.
  final bool requireCharging;

  /// Albums à sauvegarder (identifiants) ; `null` tant que l'utilisateur n'a pas choisi :
  /// les albums usuels sont alors pris (`isDefaultAlbum`).
  final Set<String>? albums;
  final DestinationConfig destination;

  /// Relire chaque fichier sur le NAS et comparer son empreinte SHA-256 à l'original.
  /// Sinon, seule la taille est comparée.
  final bool deepVerify;

  Settings copyWith({
    AppThemeMode? theme,
    bool? autoBackup,
    List<String>? homeNetworks,
    bool? requireCharging,
    Set<String>? albums,
    DestinationConfig? destination,
    bool? deepVerify,
  }) => Settings(
    theme: theme ?? this.theme,
    autoBackup: autoBackup ?? this.autoBackup,
    homeNetworks: homeNetworks ?? this.homeNetworks,
    requireCharging: requireCharging ?? this.requireCharging,
    albums: albums ?? this.albums,
    destination: destination ?? this.destination,
    deepVerify: deepVerify ?? this.deepVerify,
  );

  Map<String, Object?> toJson() => {
    'theme': theme.name,
    'auto': autoBackup,
    'wifi': homeNetworks,
    'charge': requireCharging,
    'albums': albums?.toList(),
    'destination': destination.toJson(),
    'verificationComplete': deepVerify,
  };

  factory Settings.fromJson(Map<String, dynamic> map) => Settings(
    theme: AppThemeMode.values.firstWhere((m) => m.name == map['theme'], orElse: () => AppThemeMode.auto),
    autoBackup: map['auto'] as bool? ?? true,
    homeNetworks: [
      for (final ssid in map['wifi'] as List? ?? const [])
        if (ssid is String) ssid,
    ],
    requireCharging: map['charge'] as bool? ?? false,
    albums: map['albums'] is List ? {for (final id in map['albums'] as List) '$id'} : null,
    destination: map['destination'] is Map<String, dynamic>
        ? DestinationConfig.fromJson(map['destination'] as Map<String, dynamic>)
        : const DestinationConfig(),
    deepVerify: map['verificationComplete'] as bool? ?? true,
  );
}

/// Réglages sur le disque, dans un fichier JSON lu aussi par la sauvegarde en arrière-plan
/// (qui tourne dans un autre moteur Flutter que l'interface).
class SettingsStore {
  SettingsStore(this.file);

  final File? file;

  Future<Settings> load() async {
    final f = file;
    if (f == null || !await f.exists()) return const Settings();
    try {
      return Settings.fromJson(jsonDecode(await f.readAsString()) as Map<String, dynamic>);
    } on Object {
      return const Settings();
    }
  }

  Future<void> save(Settings settings) async {
    final f = file;
    if (f == null) return;
    await f.parent.create(recursive: true);
    // Écriture dans un fichier voisin puis renommage : jamais de réglages à moitié écrits.
    final temp = File('${f.path}.tmp');
    await temp.writeAsString(jsonEncode(settings.toJson()), flush: true);
    await temp.rename(f.path);
  }
}
