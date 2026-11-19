import 'dart:convert';
import 'dart:io';

/// Issue d'un passage de sauvegarde.
enum RunOutcome {
  /// Tout ce qui était à sauvegarder l'a été.
  success,

  /// Terminé, mais certains fichiers n'ont pas pu être envoyés.
  partial,

  /// Arrêté en route (Wi-Fi perdu, débranché, annulé) : la suite reprendra plus tard.
  interrupted,

  /// Rien n'a pu être fait (NAS injoignable, configuration incomplète…).
  failed,

  /// Les conditions n'étaient pas réunies : rien n'a été tenté.
  skipped,
}

/// Ce qui a déclenché le passage.
enum RunTrigger { manual, scheduled, newMedia }

/// Un passage de sauvegarde, pour l'historique.
class RunRecord {
  RunRecord({
    required this.start,
    required this.end,
    required this.outcome,
    required this.trigger,
    this.sent = 0,
    this.alreadySaved = 0,
    this.bytes = 0,
    this.message = '',
    this.errors = const [],
  });

  final DateTime start;
  final DateTime end;
  final RunOutcome outcome;
  final RunTrigger trigger;

  /// Fichiers envoyés pendant ce passage.
  final int sent;

  /// Fichiers trouvés déjà présents sur le NAS (reconnus sans être renvoyés).
  final int alreadySaved;
  final int bytes;

  /// Résumé en une phrase (« 12 photos sauvegardées », « Le NAS ne répond pas »).
  final String message;

  /// Fichiers en échec et leur explication, en français.
  final List<String> errors;

  Map<String, Object> toJson() => {
    'debut': start.millisecondsSinceEpoch,
    'fin': end.millisecondsSinceEpoch,
    'issue': outcome.name,
    'declencheur': trigger.name,
    'envoyes': sent,
    'dejaLa': alreadySaved,
    'octets': bytes,
    'message': message,
    'erreurs': errors,
  };

  static RunRecord? tryParse(Object? json) {
    if (json is! Map) return null;
    try {
      DateTime date(Object? v) => DateTime.fromMillisecondsSinceEpoch((v as num).toInt());
      return RunRecord(
        start: date(json['debut']),
        end: date(json['fin']),
        outcome: RunOutcome.values.byName(json['issue'] as String),
        trigger: RunTrigger.values.byName(json['declencheur'] as String),
        sent: (json['envoyes'] as num?)?.toInt() ?? 0,
        alreadySaved: (json['dejaLa'] as num?)?.toInt() ?? 0,
        bytes: (json['octets'] as num?)?.toInt() ?? 0,
        message: json['message'] as String? ?? '',
        errors: [for (final e in json['erreurs'] as List? ?? const []) '$e'],
      );
    } on Object {
      return null;
    }
  }
}

/// Historique des passages, du plus récent au plus ancien.
class HistoryStore {
  HistoryStore(this.file);

  final File? file;

  /// Nombre de passages conservés.
  static const keep = 100;

  Future<List<RunRecord>> load() async {
    final f = file;
    if (f == null || !await f.exists()) return [];
    try {
      final list = jsonDecode(await f.readAsString()) as List;
      return [for (final item in list) ?RunRecord.tryParse(item)];
    } on Object {
      return [];
    }
  }

  /// Ajoute un passage. Les passages « rien à faire » successifs ne s'empilent pas : seul
  /// le dernier est gardé, pour que l'historique reste lisible.
  Future<List<RunRecord>> add(RunRecord record) async {
    final list = await load();
    if (record.outcome == RunOutcome.skipped && list.isNotEmpty && list.first.outcome == RunOutcome.skipped) {
      list.removeAt(0);
    }
    list.insert(0, record);
    if (list.length > keep) list.removeRange(keep, list.length);
    final f = file;
    if (f != null) {
      await f.parent.create(recursive: true);
      final temp = File('${f.path}.tmp');
      await temp.writeAsString(jsonEncode([for (final r in list) r.toJson()]), flush: true);
      await temp.rename(f.path);
    }
    return list;
  }
}
