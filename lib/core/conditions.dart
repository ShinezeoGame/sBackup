import 'settings.dart';

/// État du téléphone au moment de décider s'il faut sauvegarder.
class DeviceState {
  const DeviceState({required this.onWifi, this.ssid, required this.charging, this.ssidReadable = true});

  final bool onWifi;

  /// Nom du Wi-Fi, ou `null` s'il est inconnu.
  final String? ssid;

  /// Android ne donne le nom du Wi-Fi qu'avec l'autorisation de localisation (« toujours »
  /// pour l'arrière-plan) et la localisation activée.
  final bool ssidReadable;
  final bool charging;

  factory DeviceState.fromMap(Map<Object?, Object?> map) => DeviceState(
    onWifi: map['wifi'] == true,
    ssid: _cleanSsid(map['ssid'] as String?),
    ssidReadable: map['ssidLisible'] != false,
    charging: map['enCharge'] == true,
  );

  /// Android entoure le nom de guillemets et le remplace par `<unknown ssid>` quand il
  /// ne veut pas le donner.
  static String? _cleanSsid(String? raw) {
    if (raw == null) return null;
    var s = raw.trim();
    if (s.length >= 2 && s.startsWith('"') && s.endsWith('"')) s = s.substring(1, s.length - 1);
    if (s.isEmpty || s == '<unknown ssid>') return null;
    return s;
  }
}

/// Pourquoi la sauvegarde attend, ou `null` si elle peut partir.
enum Blocker { noDestination, noHomeNetwork, notOnWifi, ssidUnknown, otherNetwork, notCharging }

Blocker? blockerFor(Settings settings, DeviceState state) {
  if (!settings.destination.isComplete) return Blocker.noDestination;
  if (settings.homeNetworks.isEmpty) return Blocker.noHomeNetwork;
  if (!state.onWifi) return Blocker.notOnWifi;
  final ssid = state.ssid;
  if (ssid == null) return Blocker.ssidUnknown;
  if (!settings.homeNetworks.any((home) => home == ssid)) return Blocker.otherNetwork;
  if (settings.requireCharging && !state.charging) return Blocker.notCharging;
  return null;
}

/// Explication en français d'une attente.
String describeBlocker(Blocker blocker) => switch (blocker) {
  Blocker.noDestination => 'Indiquez le NAS où sauvegarder.',
  Blocker.noHomeNetwork => 'Indiquez le Wi-Fi de la maison.',
  Blocker.notOnWifi => 'En attente du Wi-Fi de la maison.',
  Blocker.ssidUnknown => 'Le nom du Wi-Fi n\'est pas lisible : autorisez la localisation « toujours » et activez-la.',
  Blocker.otherNetwork => 'Ce Wi-Fi n\'est pas celui de la maison : rien n\'est envoyé.',
  Blocker.notCharging => 'En attente de la mise en charge du téléphone.',
};
