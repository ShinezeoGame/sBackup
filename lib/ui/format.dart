/// Dates en français, sans dépendance : « aujourd'hui à 18 h 45 », « le 12 novembre ».
library;

const _months = [
  'janvier',
  'février',
  'mars',
  'avril',
  'mai',
  'juin',
  'juillet',
  'août',
  'septembre',
  'octobre',
  'novembre',
  'décembre',
];

String formatTime(DateTime d) => '${d.hour} h ${d.minute.toString().padLeft(2, '0')}';

String formatDay(DateTime d, DateTime now) {
  final day = DateTime(d.year, d.month, d.day);
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'aujourd\'hui';
  if (diff == 1) return 'hier';
  final date = '${d.day == 1 ? '1er' : d.day} ${_months[d.month - 1]}';
  return d.year == now.year ? 'le $date' : 'le $date ${d.year}';
}

String formatWhen(DateTime d, DateTime now) => '${formatDay(d, now)} à ${formatTime(d)}';
