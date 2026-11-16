import 'package:uuid/uuid.dart';

/// Key for one calendar day, e.g. "2026-11-16".
String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime? _date(dynamic v) => v == null ? null : DateTime.tryParse(v.toString());
double _num(dynamic v) => v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;
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

// ── Money lent / borrowed ────────────────────────────────────────────────────

class MoneyPayment {
  final double amount;
  final DateTime date;
  final String note;

  MoneyPayment({required this.amount, required this.date, this.note = ''});

  Map<String, dynamic> toJson() => {'amount': amount, 'date': date.toIso8601String(), if (note.isNotEmpty) 'note': note};

  factory MoneyPayment.fromJson(Map<String, dynamic> j) =>
      MoneyPayment(amount: _num(j['amount']), date: _date(j['date']) ?? DateTime.now(), note: j['note']?.toString() ?? '');
}

class MoneyEntry {
  final String id;
  final String person;
  final double amount;
  final bool lent; // true = I gave the money, false = I borrowed it
  final DateTime date;
  final DateTime? dueDate;
  final String note;
  final List<MoneyPayment> payments;

  MoneyEntry({
    String? id,
    required this.person,
    required this.amount,
    required this.lent,
    required this.date,
    this.dueDate,
    this.note = '',
    List<MoneyPayment>? payments,
  })  : id = id ?? const Uuid().v4(),
        payments = payments ?? [];

  double get paid => payments.fold(0, (s, p) => s + p.amount);
  double get remaining => (amount - paid).clamp(0, double.infinity).toDouble();
  bool get settled => remaining < 0.01;
  bool isOverdue([DateTime? now]) {
    if (settled || dueDate == null) return false;
    final today = DateTime.now();
    return dueDate!.isBefore(DateTime((now ?? today).year, (now ?? today).month, (now ?? today).day));
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'person': person,
        'amount': amount,
        'lent': lent,
        'date': date.toIso8601String(),
        if (dueDate != null) 'dueDate': dueDate!.toIso8601String(),
        'note': note,
        'payments': payments.map((p) => p.toJson()).toList(),
      };

  factory MoneyEntry.fromJson(Map<String, dynamic> j) => MoneyEntry(
        id: j['id']?.toString(),
        person: j['person']?.toString() ?? '',
        amount: _num(j['amount']),
        lent: j['lent'] != false,
        date: _date(j['date']) ?? DateTime.now(),
        dueDate: _date(j['dueDate']),
        note: j['note']?.toString() ?? '',
        payments: (j['payments'] as List? ?? [])
            .whereType<Map>()
            .map((p) => MoneyPayment.fromJson(Map<String, dynamic>.from(p)))
            .toList(),
      );

  MoneyEntry copyWith({
    String? person,
    double? amount,
    bool? lent,
    DateTime? date,
    Object? dueDate = _keep,
    String? note,
    List<MoneyPayment>? payments,
  }) =>
      MoneyEntry(
        id: id,
        person: person ?? this.person,
        amount: amount ?? this.amount,
        lent: lent ?? this.lent,
        date: date ?? this.date,
        dueDate: dueDate == _keep ? this.dueDate : dueDate as DateTime?,
        note: note ?? this.note,
        payments: payments ?? this.payments,
      );
}

// ── Important dates ──────────────────────────────────────────────────────────

class ImportantDate {
  final String id;
  final String title;
  final String type; // Birthday, Anniversary, Other
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
  }) : id = id ?? const Uuid().v4();

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
      );
}

// ── Journal ──────────────────────────────────────────────────────────────────

class JournalEntry {
  final String id;
  final DateTime day;
  final String text;
  final String mood; // an emoji, '' = none
  final DateTime updatedAt;

  JournalEntry({String? id, required this.day, this.text = '', this.mood = '', DateTime? updatedAt})
      : id = id ?? const Uuid().v4(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'day': dayKey(day),
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
