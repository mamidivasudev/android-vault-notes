import 'package:uuid/uuid.dart';

class Note {
  final String id;
  final String title;
  final String content;
  final String category;
  final DateTime createdAt;
  final bool isLocked;
  final bool isPinned;
  final bool isFavorite;
  final int orderIndex;

  Note({
    String? id,
    required this.title,
    required this.content,
    required this.category,
    DateTime? createdAt,
    this.isLocked = false,
    this.isPinned = false,
    this.isFavorite = false,
    this.orderIndex = 0,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'content': content,
        'category': category,
        'createdAt': createdAt.toIso8601String(),
        'isLocked': isLocked,
        'isPinned': isPinned,
        'isFavorite': isFavorite,
        'orderIndex': orderIndex,
      };

  factory Note.fromJson(Map<String, dynamic> json) => Note(
        id: json['id'],
        title: json['title'] ?? '',
        content: json['content'] ?? '',
        category: json['category'] ?? 'General',
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? json['updatedAt']?.toString() ?? '') ?? DateTime.now(),
        isLocked: json['isLocked'] == true,
        isPinned: json['isPinned'] == true,
        isFavorite: json['isFavorite'] == true,
        orderIndex: json['orderIndex'] ?? 0,
      );

  Note copyWith({
    String? title,
    String? content,
    String? category,
    DateTime? createdAt,
    bool? isLocked,
    bool? isPinned,
    bool? isFavorite,
    int? orderIndex,
  }) =>
      Note(
        id: id,
        title: title ?? this.title,
        content: content ?? this.content,
        category: category ?? this.category,
        createdAt: createdAt ?? this.createdAt,
        isLocked: isLocked ?? this.isLocked,
        isPinned: isPinned ?? this.isPinned,
        isFavorite: isFavorite ?? this.isFavorite,
        orderIndex: orderIndex ?? this.orderIndex,
      );
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
      };

  factory Expense.fromJson(Map<String, dynamic> json) => Expense(
        id: json['id'],
        title: json['title'] ?? '',
        amount: (json['amount'] ?? 0).toDouble(),
        category: json['category'] ?? 'General',
        date: DateTime.tryParse(json['date']?.toString() ?? '') ?? DateTime.now(),
        type: json['type'] ?? 'Out',
        note: json['note'],
        isLocked: json['isLocked'] == true,
        isPinned: json['isPinned'] == true,
        isFavorite: json['isFavorite'] == true,
        orderIndex: json['orderIndex'] ?? 0,
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
        orderIndex: json['orderIndex'] ?? 0,
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
        orderIndex: json['orderIndex'] ?? 0,
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

class VaultCard {
  final String id;
  final String bankName;
  final String cardType; // Credit Card, Debit Card
  final String cardNumber;
  final String expiryDate;
  final String cvv;
  final String holderName;
  final String category;
  final DateTime createdAt;
  final bool isPinned;
  final bool isLocked;
  final String? cardColor;

  VaultCard({
    String? id,
    required this.bankName,
    required this.cardType,
    required this.cardNumber,
    required this.expiryDate,
    required this.cvv,
    this.holderName = '',
    this.category = 'All Cards',
    DateTime? createdAt,
    this.isPinned = false,
    this.isLocked = true,
    this.cardColor,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  VaultCard copyWith({
    String? bankName,
    String? cardType,
    String? cardNumber,
    String? expiryDate,
    String? cvv,
    String? holderName,
    String? category,
    bool? isPinned,
    bool? isLocked,
    String? cardColor,
  }) {
    return VaultCard(
      id: id,
      bankName: bankName ?? this.bankName,
      cardType: cardType ?? this.cardType,
      cardNumber: cardNumber ?? this.cardNumber,
      expiryDate: expiryDate ?? this.expiryDate,
      cvv: cvv ?? this.cvv,
      holderName: holderName ?? this.holderName,
      category: category ?? this.category,
      createdAt: createdAt,
      isPinned: isPinned ?? this.isPinned,
      isLocked: isLocked ?? this.isLocked,
      cardColor: cardColor ?? this.cardColor,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'bankName': bankName,
        'cardType': cardType,
        'cardNumber': cardNumber,
        'expiryDate': expiryDate,
        'cvv': cvv,
        'holderName': holderName,
        'category': category,
        'createdAt': createdAt.toIso8601String(),
        'isPinned': isPinned,
        'isLocked': isLocked,
        'cardColor': cardColor,
      };

  factory VaultCard.fromJson(Map<String, dynamic> json) => VaultCard(
        id: json['id']?.toString(),
        bankName: json['bankName']?.toString() ?? '',
        cardType: json['cardType']?.toString() ?? 'Debit Card',
        cardNumber: json['cardNumber']?.toString() ?? '',
        expiryDate: json['expiryDate']?.toString() ?? '',
        cvv: json['cvv']?.toString() ?? '',
        holderName: json['holderName']?.toString() ?? '',
        category: json['category']?.toString() ?? 'All Cards',
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
        isPinned: json['isPinned'] == true,
        isLocked: json['isLocked'] == true,
        cardColor: json['cardColor']?.toString(),
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
      };

  factory Bill.fromJson(Map<String, dynamic> json) {
    final list = json['reminderDaysBeforeList'] as List<dynamic>?;
    final List<int> parsedList = list != null
        ? list.map((e) => e as int).toList()
        : [json['reminderDaysBefore'] as int? ?? 2];

    return Bill(
        id: json['id']?.toString(),
        title: json['title']?.toString() ?? '',
        amount: (json['amount'] ?? 0.0).toDouble(),
        dueDate: json['dueDate'] as int? ?? 1,
        reminderDaysBefore: json['reminderDaysBefore'] as int? ?? 2,
        reminderDaysBeforeList: parsedList,
        reminderHour: json['reminderHour'] as int? ?? 9,
        reminderMinute: json['reminderMinute'] as int? ?? 0,
        isPaid: json['isPaid'] == true,
        lastPaidDate: json['lastPaidDate'] != null ? DateTime.tryParse(json['lastPaidDate'].toString()) : null,
        reminderEnabled: json['reminderEnabled'] ?? true,
        type: json['type']?.toString() ?? 'Credit Card',
        note: json['note']?.toString(),
        totalLoanAmount: json['totalLoanAmount'] != null ? (json['totalLoanAmount'] as num).toDouble() : null,
        totalEmis: json['totalEmis'] as int?,
        paidEmis: json['paidEmis'] as int?,
        lastEmiPaidMonth: json['lastEmiPaidMonth']?.toString(),
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
    DateTime? lastPaidDate,
    bool? reminderEnabled,
    String? type,
    String? note,
    double? totalLoanAmount,
    int? totalEmis,
    int? paidEmis,
    Object? lastEmiPaidMonth = _sentinel,
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
        lastPaidDate: lastPaidDate ?? this.lastPaidDate,
        reminderEnabled: reminderEnabled ?? this.reminderEnabled,
        type: type ?? this.type,
        note: note ?? this.note,
        totalLoanAmount: totalLoanAmount ?? this.totalLoanAmount,
        totalEmis: totalEmis ?? this.totalEmis,
        paidEmis: paidEmis ?? this.paidEmis,
        lastEmiPaidMonth: lastEmiPaidMonth == _sentinel ? this.lastEmiPaidMonth : lastEmiPaidMonth as String?,
      );
}

const _sentinel = Object();

class FuelEntry {
  final String date; // stored as yyyy-MM-dd
  final double odometer; // km reading at time of entry
  final double rupees; // amount paid
  final double? liters; // liters filled (null if not a full-tank fill)
  final String? comments; // optional comments
  final bool airFilled;

  FuelEntry({
    required this.date,
    required this.odometer,
    required this.rupees,
    this.liters,
    this.comments,
    this.airFilled = false,
  });

  Map<String, dynamic> toJson() => {
        'date': date,
        'odometer': odometer,
        'rupees': rupees,
        'liters': liters,
        'comments': comments,
        'airFilled': airFilled,
      };

  factory FuelEntry.fromJson(Map<String, dynamic> json) => FuelEntry(
        date: json['date'],
        odometer: (json['odometer'] as num).toDouble(),
        rupees: (json['rupees'] as num).toDouble(),
        liters: json['liters'] == null ? null : (json['liters'] as num).toDouble(),
        comments: json['comments'] as String?,
        airFilled: json['airFilled'] as bool? ?? false,
      );
}
