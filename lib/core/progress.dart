/// Avancement d'une sauvegarde en cours, transmis à l'interface et à la notification.
enum BackupPhase { idle, preparing, sending, verifying, finishing }

class BackupProgress {
  const BackupProgress({
    this.phase = BackupPhase.idle,
    this.filesDone = 0,
    this.filesTotal = 0,
    this.bytesDone = 0,
    this.bytesTotal = 0,
    this.currentFile = '',
  });

  final BackupPhase phase;
  final int filesDone;
  final int filesTotal;
  final int bytesDone;
  final int bytesTotal;
  final String currentFile;

  static const idle = BackupProgress();

  bool get running => phase != BackupPhase.idle;

  double? get fraction => bytesTotal <= 0 ? null : (bytesDone / bytesTotal).clamp(0.0, 1.0);

  Map<String, Object> toMap() => {
    'phase': phase.name,
    'faits': filesDone,
    'total': filesTotal,
    'octetsFaits': bytesDone,
    'octetsTotal': bytesTotal,
    'fichier': currentFile,
  };

  factory BackupProgress.fromMap(Map<Object?, Object?> map) => BackupProgress(
    phase: BackupPhase.values.firstWhere((p) => p.name == map['phase'], orElse: () => BackupPhase.idle),
    filesDone: (map['faits'] as num?)?.toInt() ?? 0,
    filesTotal: (map['total'] as num?)?.toInt() ?? 0,
    bytesDone: (map['octetsFaits'] as num?)?.toInt() ?? 0,
    bytesTotal: (map['octetsTotal'] as num?)?.toInt() ?? 0,
    currentFile: map['fichier'] as String? ?? '',
  );
}

/// Taille lisible : « 4,2 Mo », « 1,3 Go ».
String formatBytes(int bytes) {
  const units = ['octets', 'Ko', 'Mo', 'Go', 'To'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1000 && unit < units.length - 1) {
    value /= 1000;
    unit++;
  }
  if (unit == 0) return bytes <= 1 ? '$bytes octet' : '$bytes octets';
  final text = value >= 100 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
  return '${text.replaceAll('.', ',')} ${units[unit]}';
}

/// « 1 photo », « 3 fichiers ».
String plural(int n, String singular, [String? pluralForm]) =>
    '${_thousands(n)} ${n == 1 ? singular : (pluralForm ?? '${singular}s')}';

String _thousands(int n) {
  final s = n.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buffer.write(' ');
    buffer.write(s[i]);
  }
  return buffer.toString();
}
