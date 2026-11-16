import 'package:uuid/uuid.dart';

/// Key for one calendar day, e.g. "2026-11-16".
String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime? _date(dynamic v) => v == null ? null : DateTime.tryParse(v.toString());
int? _int(dynamic v) => v is num ? v.toInt() : int.tryParse(v?.toString() ?? '');

// ── Medicines ────────────────────────────────────────────────────────────────

class Medicine {
  final String id;
  final String name;
  final String dose; // e.g. "1 tablet", "5 ml"
  final List<String> times; // "HH:mm", sorted
  final int? stock; // tablets left; null = not tracked
  final int perDose; // taken from stock each time it is ticked
  final int lowStockAt;
  final String notes;
  final bool active;
  final Map<String, List<String>> taken; // dayKey -> times ticked that day

  Medicine({
    String? id,
    required this.name,
    this.dose = '',
    List<String>? times,
    this.stock,
    this.perDose = 1,
    this.lowStockAt = 5,
    this.notes = '',
    this.active = true,
    Map<String, List<String>>? taken,
  })  : id = id ?? const Uuid().v4(),
        times = [...?times]..sort(),
        taken = taken ?? {};

  bool get isLow => stock != null && stock! <= lowStockAt;

  bool isTaken(String day, String time) => taken[day]?.contains(time) ?? false;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'dose': dose,
        'times': times,
        if (stock != null) 'stock': stock,
        'perDose': perDose,
        'lowStockAt': lowStockAt,
        'notes': notes,
        'active': active,
        'taken': taken,
      };

  factory Medicine.fromJson(Map<String, dynamic> j) => Medicine(
        id: j['id']?.toString(),
        name: j['name']?.toString() ?? '',
        dose: j['dose']?.toString() ?? '',
        times: (j['times'] as List? ?? []).map((e) => e.toString()).toList(),
        stock: _int(j['stock']),
        perDose: _int(j['perDose']) ?? 1,
        lowStockAt: _int(j['lowStockAt']) ?? 5,
        notes: j['notes']?.toString() ?? '',
        active: j['active'] != false,
        taken: {
          for (final e in ((j['taken'] as Map?) ?? {}).entries)
            e.key.toString(): (e.value as List? ?? []).map((t) => t.toString()).toList(),
        },
      );

  Medicine copyWith({
    String? name,
    String? dose,
    List<String>? times,
    Object? stock = _keep,
    int? perDose,
    int? lowStockAt,
    String? notes,
    bool? active,
    Map<String, List<String>>? taken,
  }) =>
      Medicine(
        id: id,
        name: name ?? this.name,
        dose: dose ?? this.dose,
        times: times ?? this.times,
        stock: stock == _keep ? this.stock : stock as int?,
        perDose: perDose ?? this.perDose,
        lowStockAt: lowStockAt ?? this.lowStockAt,
        notes: notes ?? this.notes,
        active: active ?? this.active,
        taken: taken ?? this.taken,
      );
}

const _keep = Object();

// ── Important dates ──────────────────────────────────────────────────────────

class ImportantDate {
  final String id;
  final String title;
  final String type; // Household, Birthday, Anniversary, Other or the user's own category
  final bool since; // counts days since the date (Household) instead of repeating yearly
  final DateTime? remindOn; // "since" items: one reminder on this day (e.g. 30 days after gas was opened)
  final int month;
  final int day;
  final int? year; // known start year, for "turns 30"
  final bool remindDayBefore;
  final String notes;

  ImportantDate({
    String? id,
    required this.title,
    this.type = 'Birthday',
    required this.month,
    required this.day,
    this.year,
    this.remindDayBefore = true,
    this.notes = '',
    bool? since,
    this.remindOn,
  })  : id = id ?? const Uuid().v4(),
        since = since ?? type == 'Household';

  /// Household items ("Gas cylinder started") count days since the date
  /// instead of coming round every year.
  bool get isHousehold => since;

  /// The full date, for household items.
  DateTime get startDate => DateTime(year ?? DateTime.now().year, month, day);

  /// The date in [year], with 29 Feb moved to 28 Feb in other years.
  DateTime inYear(int y) {
    final last = DateTime(y, month + 1, 0).day;
    return DateTime(y, month, day > last ? last : day);
  }

  /// Next time it comes round, today included.
  DateTime nextFrom(DateTime from) {
    final today = DateTime(from.year, from.month, from.day);
    final thisYear = inYear(today.year);
    return thisYear.isBefore(today) ? inYear(today.year + 1) : thisYear;
  }

  int daysUntil(DateTime from) {
    final today = DateTime(from.year, from.month, from.day);
    return nextFrom(from).difference(today).inDays;
  }

  /// "turns 30" / "30 years" on the next occurrence, when the year is known.
  int? yearsOnNext(DateTime from) => year == null ? null : nextFrom(from).year - year!;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'type': type,
        'month': month,
        'day': day,
        if (year != null) 'year': year,
        'remindDayBefore': remindDayBefore,
        'notes': notes,
        'since': since,
        if (remindOn != null) 'remindOn': remindOn!.toIso8601String(),
      };

  factory ImportantDate.fromJson(Map<String, dynamic> j) => ImportantDate(
        id: j['id']?.toString(),
        title: j['title']?.toString() ?? '',
        type: j['type']?.toString() ?? 'Other',
        month: (_int(j['month']) ?? 1).clamp(1, 12),
        day: (_int(j['day']) ?? 1).clamp(1, 31),
        year: _int(j['year']),
        remindDayBefore: j['remindDayBefore'] != false,
        notes: j['notes']?.toString() ?? '',
        since: j['since'] is bool ? j['since'] as bool : null,
        remindOn: _date(j['remindOn']),
      );
}

/// A category the user added in the Dates tab.
class DateCategory {
  final String name;
  final bool since; // true = counts days since, false = repeats every year
  const DateCategory({required this.name, this.since = false});

  Map<String, dynamic> toJson() => {'name': name, 'since': since};

  factory DateCategory.fromJson(Map<String, dynamic> j) =>
      DateCategory(name: j['name']?.toString() ?? '', since: j['since'] == true);
}

// ── Journal ──────────────────────────────────────────────────────────────────

class JournalEntry {
  final String id;
  final DateTime day; // date and time of the entry
  final String text;
  final String mood; // no longer shown; kept for old entries
  final DateTime updatedAt;

  JournalEntry({String? id, required this.day, this.text = '', this.mood = '', DateTime? updatedAt})
      : id = id ?? const Uuid().v4(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'day': day.toIso8601String(),
        'text': text,
        'mood': mood,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory JournalEntry.fromJson(Map<String, dynamic> j) => JournalEntry(
        id: j['id']?.toString(),
        day: _date(j['day']) ?? DateTime.now(),
        text: j['text']?.toString() ?? '',
        mood: j['mood']?.toString() ?? '',
        updatedAt: _date(j['updatedAt']),
      );

  JournalEntry copyWith({DateTime? day, String? text, String? mood}) =>
      JournalEntry(id: id, day: day ?? this.day, text: text ?? this.text, mood: mood ?? this.mood);
}
