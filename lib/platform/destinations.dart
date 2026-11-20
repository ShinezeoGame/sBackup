import '../core/destination.dart';
import '../core/settings.dart';
import 'smb_destination.dart';

/// Crée la destination réseau décrite par les réglages : le NAS en partage Windows (SMB).
Future<Destination?> createDestination(DestinationConfig config) async =>
    config.isComplete ? SmbDestination(config) : null;
