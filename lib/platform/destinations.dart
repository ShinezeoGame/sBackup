import '../core/destination.dart';
import '../core/settings.dart';

/// Crée la destination réseau décrite par les réglages.
///
/// Le protocole du NAS (SMB, WebDAV, SFTP…) n'est pas encore choisi : tant qu'il ne l'est
/// pas, aucune destination réelle n'existe et la sauvegarde le dit (`BackupJob`). Le moteur,
/// l'index et l'interface ne dépendent que de `Destination`.
Future<Destination?> createDestination(DestinationConfig config) async => null;
