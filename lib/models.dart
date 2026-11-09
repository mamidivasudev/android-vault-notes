import 'package:uuid/uuid.dart';

class Note {
  final String id;
  final String title;
  final String content;
  final String category;
  final DateTime createdAt;
  final DateTime? updatedAt; // last time the title/content/category was edited
  final bool isLocked;
  final bool isPinned;
  final bool isFavorite;
  final int orderIndex;
  final int colorIndex; // 0 = default, see NoteColors in widgets/note_card.dart
  final bool isChecklist; // content is stored as "[ ] item" / "[x] item" lines
  final DateTime? deletedAt; // set when moved to the Recycle Bin

  Note({
    String? id,
    required this.title,
    required this.content,
    required this.category,
    DateTime? createdAt,
    this.updatedAt,
    this.isLocked = false,
    this.isPinned = false,
    this.isFavorite = false,
    this.orderIndex = 0,
    this.colorIndex = 0,
    this.isChecklist = false,
    this.deletedAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  /// The most recent of created / edited time.
  DateTime get lastModified => updatedAt ?? createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'content': content,
        'category': category,
        'createdAt': createdAt.toIso8601String(),
        if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
        'isLocked': isLocked,
        'isPinned': isPinned,
        'isFavorite': isFavorite,
        'orderIndex': orderIndex,
        if (colorIndex != 0) 'colorIndex': colorIndex,
        if (isChecklist) 'isChecklist': true,
        if (deletedAt != null) 'deletedAt': deletedAt!.toIso8601String(),
      };

  factory Note.fromJson(Map<String, dynamic> json) => Note(
        id: json['id']?.toString(),
        title: json['title'] ?? '',
        content: json['content'] ?? '',
        category: json['category'] ?? 'General',
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? json['updatedAt']?.toString() ?? '') ?? DateTime.now(),
        updatedAt: json['updatedAt'] != null ? DateTime.tryParse(json['updatedAt'].toString()) : null,
        isLocked: json['isLocked'] == true,
        isPinned: json['isPinned'] == true,
        isFavorite: json['isFavorite'] == true,
        orderIndex: (json['orderIndex'] as num?)?.toInt() ?? 0,
        colorIndex: (json['colorIndex'] as num?)?.toInt() ?? 0,
        isChecklist: json['isChecklist'] == true,
        deletedAt: json['deletedAt'] != null ? DateTime.tryParse(json['deletedAt'].toString()) : null,
      );

  Note copyWith({
    String? title,
    String? content,
    String? category,
    DateTime? createdAt,
    Object? updatedAt = _sentinel,
    bool? isLocked,
    bool? isPinned,
    bool? isFavorite,
    int? orderIndex,
    int? colorIndex,
    bool? isChecklist,
    Object? deletedAt = _sentinel,
  }) =>
      Note(
        id: id,
        title: title ?? this.title,
        content: content ?? this.content,
        category: category ?? this.category,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt == _sentinel ? this.updatedAt : updatedAt as DateTime?,
        isLocked: isLocked ?? this.isLocked,
        isPinned: isPinned ?? this.isPinned,
        isFavorite: isFavorite ?? this.isFavorite,
        orderIndex: orderIndex ?? this.orderIndex,
        colorIndex: colorIndex ?? this.colorIndex,
        isChecklist: isChecklist ?? this.isChecklist,
        deletedAt: deletedAt == _sentinel ? this.deletedAt : deletedAt as DateTime?,
      );
}

/// One line of a checklist note.
class ChecklistItem {
  final String text;
  final bool checked;
  const ChecklistItem(this.text, this.checked);

  static final _pattern = RegExp(r'^\[( |x|X)\] ?(.*)$');

  static List<ChecklistItem> parse(String content) {
    if (content.isEmpty) return [];
    return content.split('\n').map((line) {
      final m = _pattern.firstMatch(line);
      if (m == null) return ChecklistItem(line, false);
      return ChecklistItem(m.group(2) ?? '', m.group(1)!.toLowerCase() == 'x');
    }).toList();
  }

  static String serialize(List<ChecklistItem> items) =>
      items.map((i) => '[${i.checked ? 'x' : ' '}] ${i.text}').join('\n');

  /// Converts plain text lines to checklist lines (and back).
  static String fromPlainText(String text) => serialize(
      text.split('\n').where((l) => l.trim().isNotEmpty).map((l) => ChecklistItem(l.trim(), false)).toList());
  static String toPlainText(String content) => parse(content).map((i) => i.text).join('\n');
}

class Expense {
  final String id;
  final String title;
  final double amount;
  final String category;
  final DateTime date;
  final String type;
  final String? note;
  final bool isLocked;
  final bool isPinned;
  final bool isFavorite;
  final int orderIndex;
  final DateTime? deletedAt; // set when moved to the Recycle Bin

  Expense({
    String? id,
    required this.title,
    required this.amount,
    required this.category,
    required this.date,
    this.type = 'Out',
    this.note,
    this.isLocked = false,
    this.isPinned = false,
    this.isFavorite = false,
    this.orderIndex = 0,
    this.deletedAt,
  }) : id = id ?? const Uuid().v4();

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'amount': amount,
        'category': category,
        'date': date.toIso8601String(),
        'type': type,
        'note': note,
        'isLocked': isLocked,
        'isPinned': isPinned,
        'isFavorite': isFavorite,
        'orderIndex': orderIndex,
        if (deletedAt != null) 'deletedAt': deletedAt!.toIso8601String(),
      };

  factory Expense.fromJson(Map<String, dynamic> json) => Expense(
        id: json['id'],
        title: json['title'] ?? '',
        amount: (json['amount'] is num) ? (json['amount'] as num).toDouble() : (double.tryParse(json['amount']?.toString() ?? '') ?? 0),
        category: json['category'] ?? 'General',
        date: DateTime.tryParse(json['date']?.toString() ?? '') ?? DateTime.now(),
        type: json['type'] ?? 'Out',
        note: json['note'],
        isLocked: json['isLocked'] == true,
        isPinned: json['isPinned'] == true,
        isFavorite: json['isFavorite'] == true,
        orderIndex: (json['orderIndex'] as num?)?.toInt() ?? 0,
        deletedAt: json['deletedAt'] != null ? DateTime.tryParse(json['deletedAt'].toString()) : null,
      );

  Expense copyWith({
    String? title,
    double? amount,
    String? category,
    DateTime? date,
    String? type,
    String? note,
    bool? isLocked,
    bool? isPinned,
    bool? isFavorite,
    int? orderIndex,
    Object? deletedAt = _sentinel,
  }) =>
      Expense(
        id: id,
        title: title ?? this.title,
        amount: amount ?? this.amount,
        category: category ?? this.category,
        date: date ?? this.date,
        type: type ?? this.type,
        note: note ?? this.note,
        isLocked: isLocked ?? this.isLocked,
        isPinned: isPinned ?? this.isPinned,
        isFavorite: isFavorite ?? this.isFavorite,
        orderIndex: orderIndex ?? this.orderIndex,
        deletedAt: deletedAt == _sentinel ? this.deletedAt : deletedAt as DateTime?,
      );
}

class LinkItem {
  final String id;
  final String title;
  final String url;
  final String category;
  final DateTime createdAt;
  final bool isLocked;
  final bool isPinned;
  final bool isFavorite;
  final int orderIndex;
  final DateTime? deletedAt; // set when moved to the Recycle Bin

  LinkItem({
    String? id,
    required this.title,
    required this.url,
    required this.category,
    DateTime? createdAt,
    this.isLocked = false,
    this.isPinned = false,
    this.isFavorite = false,
    this.orderIndex = 0,
    this.deletedAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'url': url,
        'category': category,
        'createdAt': createdAt.toIso8601String(),
        'isLocked': isLocked,
        'isPinned': isPinned,
        'isFavorite': isFavorite,
        'orderIndex': orderIndex,
        if (deletedAt != null) 'deletedAt': deletedAt!.toIso8601String(),
      };

  factory LinkItem.fromJson(Map<String, dynamic> json) => LinkItem(
        id: json['id'],
        title: json['title'] ?? '',
        url: json['url'] ?? '',
        category: json['category'] ?? 'All',
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
        isLocked: json['isLocked'] == true,
        isPinned: json['isPinned'] == true,
        isFavorite: json['isFavorite'] == true,
        orderIndex: (json['orderIndex'] as num?)?.toInt() ?? 0,
        deletedAt: json['deletedAt'] != null ? DateTime.tryParse(json['deletedAt'].toString()) : null,
      );

  LinkItem copyWith({
    String? title,
    String? url,
    String? category,
    DateTime? createdAt,
    bool? isLocked,
    bool? isPinned,
    bool? isFavorite,
    int? orderIndex,
    Object? deletedAt = _sentinel,
  }) =>
      LinkItem(
        id: id,
        title: title ?? this.title,
        url: url ?? this.url,
        category: category ?? this.category,
        createdAt: createdAt ?? this.createdAt,
        isLocked: isLocked ?? this.isLocked,
        isPinned: isPinned ?? this.isPinned,
        isFavorite: isFavorite ?? this.isFavorite,
        orderIndex: orderIndex ?? this.orderIndex,
        deletedAt: deletedAt == _sentinel ? this.deletedAt : deletedAt as DateTime?,
      );
}

class VaultTableCell {
  final String text;
  final String alignment; // 'left', 'center', 'right'
  final bool isBold;
  final String? backgroundColor;
  final String? textColor;
  final bool isPaid;

  VaultTableCell({
    required this.text,
    this.alignment = 'left',
    this.isBold = false,
    this.backgroundColor,
    this.textColor,
    this.isPaid = false,
  });

  Map<String, dynamic> toJson() => {
        'text': text,
        'alignment': alignment,
        'isBold': isBold,
        'backgroundColor': backgroundColor,
        'textColor': textColor,
        'isPaid': isPaid,
      };

  factory VaultTableCell.fromJson(dynamic json) {
    if (json == null) return VaultTableCell(text: '');
    if (json is String) {
      return VaultTableCell(text: json);
    }
    return VaultTableCell(
      text: json['text']?.toString() ?? '',
      alignment: json['alignment']?.toString() ?? 'left',
      isBold: json['isBold'] == true,
      backgroundColor: json['backgroundColor']?.toString(),
      textColor: json['textColor']?.toString(),
      isPaid: json['isPaid'] == true,
    );
  }

  VaultTableCell copyWith({
    String? text,
    String? alignment,
    bool? isBold,
    String? backgroundColor,
    String? textColor,
    bool? isPaid,
  }) =>
      VaultTableCell(
        text: text ?? this.text,
        alignment: alignment ?? this.alignment,
        isBold: isBold ?? this.isBold,
        backgroundColor: backgroundColor ?? this.backgroundColor,
        textColor: textColor ?? this.textColor,
        isPaid: isPaid ?? this.isPaid,
      );
}

class VaultTable {
  final String id;
  final String title;
  final String description;
  final List<VaultTableCell> columns;
  final List<List<VaultTableCell>> rows;
  final String category;
  final DateTime createdAt;
  final bool isPinned;
  final bool isLocked;
  final bool isFavorite;
  final List<double> columnWidths;
  final int orderIndex;

  VaultTable({
    String? id,
    required this.title,
    this.description = '',
    required this.columns,
    required this.rows,
    required this.category,
    List<double>? columnWidths,
    DateTime? createdAt,
    this.isPinned = false,
    this.isLocked = false,
    this.isFavorite = false,
    this.orderIndex = 0,
  })  : id = id ?? const Uuid().v4(),
        columnWidths = columnWidths ?? List.generate(columns.length, (_) => 120.0),
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'columns': columns.map((c) => c.toJson()).toList(),
        'rows': rows.map((row) => row.map((cell) => cell.toJson()).toList()).toList(),
        'category': category,
        'columnWidths': columnWidths,
        'createdAt': createdAt.toIso8601String(),
        'isPinned': isPinned,
        'isLocked': isLocked,
        'isFavorite': isFavorite,
        'orderIndex': orderIndex,
      };

  factory VaultTable.fromJson(Map<String, dynamic> json) => VaultTable(
        id: json['id']?.toString(),
        title: json['title']?.toString() ?? 'Untitled Table',
        description: json['description']?.toString() ?? '',
        columns: (json['columns'] as List? ?? ['Column 1'])
            .map((c) => VaultTableCell.fromJson(c))
            .toList(),
        rows: (json['rows'] as List? ?? [])
            .map((row) => (row as List? ?? []).map((cell) => VaultTableCell.fromJson(cell)).toList())
            .toList(),
        category: json['category']?.toString() ?? 'General',
        columnWidths: json['columnWidths'] != null 
            ? List<double>.from(json['columnWidths'].map((w) => (w ?? 120.0).toDouble()))
            : null,
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
        isPinned: json['isPinned'] == true,
        isLocked: json['isLocked'] == true,
        isFavorite: json['isFavorite'] == true,
        orderIndex: (json['orderIndex'] as num?)?.toInt() ?? 0,
      );

  VaultTable copyWith({
    String? title,
    String? description,
    List<VaultTableCell>? columns,
    List<List<VaultTableCell>>? rows,
    String? category,
    List<double>? columnWidths,
    bool? isPinned,
    bool? isLocked,
    bool? isFavorite,
    int? orderIndex,
  }) =>
      VaultTable(
        id: id,
        title: title ?? this.title,
        description: description ?? this.description,
        columns: columns ?? this.columns,
        rows: rows ?? this.rows,
        category: category ?? this.category,
        columnWidths: columnWidths ?? this.columnWidths,
        isPinned: isPinned ?? this.isPinned,
        isLocked: isLocked ?? this.isLocked,
        isFavorite: isFavorite ?? this.isFavorite,
        createdAt: createdAt,
        orderIndex: orderIndex ?? this.orderIndex,
      );
}


class Reminder {
  final String id;
  final String title;
  final String description;
  final DateTime dateTime;
  final bool isDismissed;
  final DateTime createdAt;
  final String repeatType;
  final DateTime? referenceDate;

  Reminder({
    String? id,
    required this.title,
    required this.description,
    required this.dateTime,
    this.isDismissed = false,
    DateTime? createdAt,
    this.repeatType = 'none',
    this.referenceDate,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'dateTime': dateTime.toIso8601String(),
        'isDismissed': isDismissed,
        'createdAt': createdAt.toIso8601String(),
        'repeatType': repeatType,
        'referenceDate': referenceDate?.toIso8601String(),
      };

  factory Reminder.fromJson(Map<String, dynamic> json) => Reminder(
        id: json['id']?.toString(),
        title: json['title']?.toString() ?? '',
        description: json['description']?.toString() ?? '',
        dateTime: DateTime.tryParse(json['dateTime']?.toString() ?? '') ?? DateTime.now(),
        isDismissed: json['isDismissed'] == true,
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
        repeatType: json['repeatType']?.toString() ?? 'none',
        referenceDate: json['referenceDate'] != null ? DateTime.tryParse(json['referenceDate'].toString()) : null,
      );

  Reminder copyWith({
    String? title,
    String? description,
    DateTime? dateTime,
    bool? isDismissed,
    DateTime? createdAt,
    String? repeatType,
    Object? referenceDate = _sentinel,
  }) =>
      Reminder(
        id: id,
        title: title ?? this.title,
        description: description ?? this.description,
        dateTime: dateTime ?? this.dateTime,
        isDismissed: isDismissed ?? this.isDismissed,
        createdAt: createdAt ?? this.createdAt,
        repeatType: repeatType ?? this.repeatType,
        referenceDate: referenceDate == _sentinel ? this.referenceDate : referenceDate as DateTime?,
      );
}

class Bill {
  final String id;
  final String title;
  final double amount;
  final int dueDate; // Day of the month (1-31)
  final int reminderDaysBefore;
  final List<int> reminderDaysBeforeList;
  final int reminderHour;
  final int reminderMinute;
  final bool isPaid;
  final DateTime? lastPaidDate;
  final bool reminderEnabled;
  final String? type;
  final String? note;
  final double? totalLoanAmount;
  final int? totalEmis;
  final int? paidEmis;
  final String? lastEmiPaidMonth; // e.g. '2026-08', to avoid double-counting
  final double? interestRate;
  final double? emiAmount;

  Bill({
    String? id,
    required this.title,
    this.amount = 0.0,
    required this.dueDate,
    this.reminderDaysBefore = 2,
    List<int>? reminderDaysBeforeList,
    this.reminderHour = 9,
    this.reminderMinute = 0,
    this.isPaid = false,
    this.lastPaidDate,
    this.reminderEnabled = true,
    this.type = 'Credit Card',
    this.note,
    this.totalLoanAmount,
    this.totalEmis,
    this.paidEmis,
    this.lastEmiPaidMonth,
    this.interestRate,
    this.emiAmount,
  }) : id = id ?? const Uuid().v4(),
       reminderDaysBeforeList = reminderDaysBeforeList ?? [reminderDaysBefore];

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'amount': amount,
        'dueDate': dueDate,
        'reminderDaysBefore': reminderDaysBefore,
        'reminderDaysBeforeList': reminderDaysBeforeList,
        'reminderHour': reminderHour,
        'reminderMinute': reminderMinute,
        'isPaid': isPaid,
        'lastPaidDate': lastPaidDate?.toIso8601String(),
        'reminderEnabled': reminderEnabled,
        'type': type,
        'note': note,
        'totalLoanAmount': totalLoanAmount,
        'totalEmis': totalEmis,
        'paidEmis': paidEmis,
        'lastEmiPaidMonth': lastEmiPaidMonth,
        'interestRate': interestRate,
        'emiAmount': emiAmount,
      };

  factory Bill.fromJson(Map<String, dynamic> json) {
    final list = json['reminderDaysBeforeList'] as List<dynamic>?;
    final List<int> parsedList = list != null
        ? list.whereType<num>().map((e) => e.toInt()).toList()
        : [(json['reminderDaysBefore'] as num?)?.toInt() ?? 2];

    return Bill(
        id: json['id']?.toString(),
        title: json['title']?.toString() ?? '',
        amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
        dueDate: ((json['dueDate'] as num?)?.toInt() ?? 1).clamp(1, 31),
        reminderDaysBefore: (json['reminderDaysBefore'] as num?)?.toInt() ?? 2,
        reminderDaysBeforeList: parsedList,
        reminderHour: (json['reminderHour'] as num?)?.toInt() ?? 9,
        reminderMinute: (json['reminderMinute'] as num?)?.toInt() ?? 0,
        isPaid: json['isPaid'] == true,
        lastPaidDate: json['lastPaidDate'] != null ? DateTime.tryParse(json['lastPaidDate'].toString()) : null,
        reminderEnabled: json['reminderEnabled'] ?? true,
        type: json['type']?.toString() ?? 'Credit Card',
        note: json['note']?.toString(),
        totalLoanAmount: json['totalLoanAmount'] != null ? (json['totalLoanAmount'] as num).toDouble() : null,
        totalEmis: (json['totalEmis'] as num?)?.toInt(),
        paidEmis: (json['paidEmis'] as num?)?.toInt(),
        lastEmiPaidMonth: json['lastEmiPaidMonth']?.toString(),
        interestRate: json['interestRate'] != null ? (json['interestRate'] as num).toDouble() : null,
        emiAmount: json['emiAmount'] != null ? (json['emiAmount'] as num).toDouble() : null,
      );
  }

  Bill copyWith({
    String? title,
    double? amount,
    int? dueDate,
    int? reminderDaysBefore,
    List<int>? reminderDaysBeforeList,
    int? reminderHour,
    int? reminderMinute,
    bool? isPaid,
    Object? lastPaidDate = _sentinel,
    bool? reminderEnabled,
    String? type,
    String? note,
    double? totalLoanAmount,
    int? totalEmis,
    int? paidEmis,
    Object? lastEmiPaidMonth = _sentinel,
    Object? interestRate = _sentinel,
    Object? emiAmount = _sentinel,
  }) =>
      Bill(
        id: id,
        title: title ?? this.title,
        amount: amount ?? this.amount,
        dueDate: dueDate ?? this.dueDate,
        reminderDaysBefore: reminderDaysBefore ?? this.reminderDaysBefore,
        reminderDaysBeforeList: reminderDaysBeforeList ?? this.reminderDaysBeforeList,
        reminderHour: reminderHour ?? this.reminderHour,
        reminderMinute: reminderMinute ?? this.reminderMinute,
        isPaid: isPaid ?? this.isPaid,
        lastPaidDate: lastPaidDate == _sentinel ? this.lastPaidDate : lastPaidDate as DateTime?,
        reminderEnabled: reminderEnabled ?? this.reminderEnabled,
        type: type ?? this.type,
        note: note ?? this.note,
        totalLoanAmount: totalLoanAmount ?? this.totalLoanAmount,
        totalEmis: totalEmis ?? this.totalEmis,
        paidEmis: paidEmis ?? this.paidEmis,
        lastEmiPaidMonth: lastEmiPaidMonth == _sentinel ? this.lastEmiPaidMonth : lastEmiPaidMonth as String?,
        interestRate: interestRate == _sentinel ? this.interestRate : interestRate as double?,
        emiAmount: emiAmount == _sentinel ? this.emiAmount : emiAmount as double?,
      );
}

extension BillCycle on Bill {
  /// Billing cycle ('yyyy-MM' of the due date) the last payment covered.
  /// A payment covers the due date nearest to when it was made, so paying a
  /// bill due on the 2nd on the 30th of the previous month counts for the 2nd.
  String? get paidCycle {
    if (lastPaidDate != null) return billCycleKey(billCycleDueFor(lastPaidDate!, dueDate));
    return lastEmiPaidMonth;
  }

  /// Cycle that is "current" at [when]: the due date nearest to it.
  String currentCycle([DateTime? when]) => billCycleKey(billCycleDueFor(when ?? DateTime.now(), dueDate));

  /// True when the bill was paid for the cycle that is current at [when].
  bool isPaidForCycle([DateTime? when]) => isPaid && paidCycle == currentCycle(when);
}

/// The due date of a bill in [year]/[month], clamped to the month's length
/// (a bill due on the 31st is due on the 28th/29th in February).
DateTime billDueDate(int year, int month, int dueDay) {
  final daysInMonth = DateTime(year, month + 1, 0).day;
  final first = DateTime(year, month, 1); // normalises month 0 / 13
  return DateTime(first.year, first.month, dueDay.clamp(1, daysInMonth));
}

String billCycleKey(DateTime due) => '${due.year}-${due.month.toString().padLeft(2, '0')}';

/// The due date closest to [when] (ties go to the upcoming one).
DateTime billCycleDueFor(DateTime when, int dueDay) {
  final day = DateTime(when.year, when.month, when.day);
  DateTime? best;
  int bestDiff = 1 << 30;
  for (final offset in const [-1, 0, 1]) {
    final due = billDueDate(when.year, when.month + offset, dueDay);
    final diff = due.difference(day).inDays.abs();
    if (diff < bestDiff || (diff == bestDiff && due.isAfter(best!))) {
      best = due;
      bestDiff = diff;
    }
  }
  return best!;
}

const _sentinel = Object();

class FuelEntry {
  final String date; // stored as yyyy-MM-dd
  final double odometer; // km reading at time of entry
  final double rupees; // amount paid
  final double? liters; // liters filled (null if not a full-tank fill)
  final String? comments; // optional comments
  final bool airFilled;
  /// Whether the tank was filled to full. Null for entries saved before this
  /// flag existed (those are treated as full fills, the old behaviour).
  final bool? isFullTank;

  FuelEntry({
    required this.date,
    required this.odometer,
    required this.rupees,
    this.liters,
    this.comments,
    this.airFilled = false,
    this.isFullTank,
  });

  /// Odometer 0 means "not recorded".
  bool get hasOdometer => odometer > 0;

  Map<String, dynamic> toJson() => {
        'date': date,
        'odometer': odometer,
        'rupees': rupees,
        'liters': liters,
        'comments': comments,
        'airFilled': airFilled,
        if (isFullTank != null) 'isFullTank': isFullTank,
      };

  factory FuelEntry.fromJson(Map<String, dynamic> json) => FuelEntry(
        date: json['date']?.toString() ?? '',
        odometer: (json['odometer'] as num?)?.toDouble() ?? 0,
        rupees: (json['rupees'] as num?)?.toDouble() ?? 0,
        liters: (json['liters'] as num?)?.toDouble(),
        comments: json['comments']?.toString(),
        airFilled: json['airFilled'] == true,
        isFullTank: json['isFullTank'] is bool ? json['isFullTank'] as bool : null,
      );
}

class ServiceEntry {
  final String id;
  final String date; // stored as yyyy-MM-dd
  final double odometer; // km reading at time of service
  final double cost; // amount paid for the service
  final double nextServiceOdometer; // expected km for next service
  final String? comments; // optional comments (what was done)

  ServiceEntry({
    required this.id,
    required this.date,
    required this.odometer,
    required this.cost,
    required this.nextServiceOdometer,
    this.comments,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date,
        'odometer': odometer,
        'cost': cost,
        'nextServiceOdometer': nextServiceOdometer,
        'comments': comments,
      };

  factory ServiceEntry.fromJson(Map<String, dynamic> json) => ServiceEntry(
        id: json['id']?.toString() ?? const Uuid().v4(),
        date: json['date']?.toString() ?? '',
        odometer: (json['odometer'] as num?)?.toDouble() ?? 0,
        cost: (json['cost'] as num?)?.toDouble() ?? 0,
        nextServiceOdometer: (json['nextServiceOdometer'] as num?)?.toDouble() ?? 0,
        comments: json['comments']?.toString(),
      );
}


class GroceryItem {
  final String id;
  final String name;
  final bool isPurchased;
  final DateTime createdAt;
  final String quantity; // e.g. "2", "1.5", "1/2"; empty = not set
  final String unit; // e.g. "kg", "pack"; empty = not set
  final String category; // catalog category, e.g. "Vegetables"; empty = Other
  final String localName; // Telugu/Hindi name from the catalog, for display
  final DateTime? purchasedAt;
  final double? price; // what was paid; only set on bought items

  GroceryItem({
    String? id,
    required this.name,
    this.isPurchased = false,
    DateTime? createdAt,
    this.quantity = '',
    this.unit = '',
    this.category = '',
    this.localName = '',
    this.purchasedAt,
    this.price,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  /// "2 kg", "3", "pack" or '' when nothing is set.
  String get quantityLabel => [quantity, unit].where((p) => p.isNotEmpty).join(' ');

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'isPurchased': isPurchased,
        'createdAt': createdAt.toIso8601String(),
        'quantity': quantity,
        'unit': unit,
        'category': category,
        if (localName.isNotEmpty) 'localName': localName,
        if (purchasedAt != null) 'purchasedAt': purchasedAt!.toIso8601String(),
        if (price != null) 'price': price,
      };

  factory GroceryItem.fromJson(Map<String, dynamic> json) {
    var name = json['name']?.toString() ?? '';
    var quantity = json['quantity']?.toString() ?? '';
    var unit = json['unit']?.toString() ?? '';
    // Items saved before quantity/unit had their own fields stored them inside
    // the name, e.g. "Rice (2 kg)". Split those once so nothing is lost.
    if (!json.containsKey('quantity') && !json.containsKey('unit')) {
      final legacy = splitLegacyGroceryName(name);
      name = legacy.name;
      quantity = legacy.quantity;
      unit = legacy.unit;
    }
    return GroceryItem(
      id: json['id']?.toString(),
      name: name,
      isPurchased: json['isPurchased'] == true,
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
      quantity: quantity,
      unit: unit,
      category: json['category']?.toString() ?? '',
      localName: json['localName']?.toString() ?? '',
      purchasedAt: DateTime.tryParse(json['purchasedAt']?.toString() ?? ''),
      price: double.tryParse(json['price']?.toString() ?? ''),
    );
  }

  GroceryItem copyWith({
    String? name,
    bool? isPurchased,
    String? quantity,
    String? unit,
    String? category,
    String? localName,
    Object? purchasedAt = _sentinel,
    Object? price = _sentinel,
  }) {
    return GroceryItem(
      id: id,
      name: name ?? this.name,
      isPurchased: isPurchased ?? this.isPurchased,
      createdAt: createdAt,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      category: category ?? this.category,
      localName: localName ?? this.localName,
      purchasedAt: purchasedAt == _sentinel ? this.purchasedAt : purchasedAt as DateTime?,
      price: price == _sentinel ? this.price : price as double?,
    );
  }
}

/// Splits an old-style grocery name such as "Rice (2 kg)" or "Milk (half kg)"
/// into name / quantity / unit. Names without "( … )" are returned unchanged.
({String name, String quantity, String unit}) splitLegacyGroceryName(String raw) {
  final m = RegExp(r'^(.*?)\s*\((.*?)\)\s*$').firstMatch(raw);
  if (m == null || m.group(1)!.trim().isEmpty) return (name: raw.trim(), quantity: '', unit: '');
  final name = m.group(1)!.trim();
  final inside = m.group(2)!.trim();
  final q = RegExp(r'^(\d+(?:\.\d+)?|\d+/\d+|half|quarter)\s*(.*)$', caseSensitive: false).firstMatch(inside);
  if (q == null) return (name: name, quantity: '', unit: inside);
  var quantity = q.group(1)!;
  if (quantity.toLowerCase() == 'half') quantity = '1/2';
  if (quantity.toLowerCase() == 'quarter') quantity = '1/4';
  return (name: name, quantity: quantity, unit: q.group(2)!.trim());
}
