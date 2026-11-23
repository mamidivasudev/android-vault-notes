const _monthNames = {
  'jan': 1, 'january': 1, 'feb': 2, 'february': 2, 'mar': 3, 'march': 3, 'apr': 4, 'april': 4, 'may': 5,
  'jun': 6, 'june': 6, 'jul': 7, 'july': 7, 'aug': 8, 'august': 8, 'sep': 9, 'sept': 9, 'september': 9,
  'oct': 10, 'october': 10, 'nov': 11, 'november': 11, 'dec': 12, 'december': 12,
};

/// Turns a spoken sentence into an expense: "add milk rupees 33" →
/// title "Milk", amount 33. A category is picked when one of [categories] is
/// named ("petrol 500 in travel"), otherwise [category] is null.
/// A date can be said too ("on 21st", "date 22nd", "yesterday",
/// "21st november"); without one, [date] is today. A day still ahead this
/// month ("on 25th" on the 23rd) means last month.
({String title, double? amount, String? category, DateTime date}) parseSpokenExpense(
  String spoken, {
  List<String> categories = const [],
  DateTime? now,
}) {
  final clock = now ?? DateTime.now();
  final today = DateTime(clock.year, clock.month, clock.day);
  var text = ' ${spoken.toLowerCase().replaceAll('₹', ' rupees ').replaceAll(RegExp(r'[,.](?!\d)'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim()} ';

  // Date (taken out first so its number is not read as the amount).
  var date = today;
  final relative = RegExp(r' (?:on )?(day before yesterday|yesterday|today) ').firstMatch(text);
  if (relative != null) {
    final w = relative.group(1)!;
    date = today.subtract(Duration(days: w == 'yesterday' ? 1 : w == 'today' ? 0 : 2));
    text = text.replaceRange(relative.start, relative.end, ' ');
  } else {
    final months = _monthNames.keys.join('|');
    // "on 21st", "date 22nd", "on date 21", "dated 5 november", "21st of november"
    final m = RegExp(' (?:(?:on|dated|date)(?: the)? )*(\\d{1,2})(st|nd|rd|th)?(?: of)?(?: ($months))?(?: (\\d{4}))?(?= )')
        .allMatches(text)
        .where((m) => m.group(2) != null || m.group(3) != null || RegExp(r'^ (?:on|dated|date)').hasMatch(m.group(0)!))
        .firstOrNull;
    if (m != null) {
      final day = int.parse(m.group(1)!);
      final month = m.group(3) != null ? _monthNames[m.group(3)!]! : today.month;
      var year = m.group(4) != null ? int.parse(m.group(4)!) : today.year;
      var d = DateTime(year, month, day);
      // Said without a month and still ahead this month → last month.
      if (m.group(3) == null && m.group(4) == null && d.isAfter(today)) d = DateTime(year, month - 1, day);
      // A named month still ahead this year → last year.
      if (m.group(3) != null && m.group(4) == null && d.isAfter(today)) d = DateTime(year - 1, month, day);
      if (day >= 1 && day <= 31) {
        date = d;
        text = text.replaceRange(m.start, m.end, ' ');
      }
    }
  }

  // Category: "in grocery", "under bills", "category travel" (longest name first).
  String? category;
  final named = [...categories.where((c) => c.trim().isNotEmpty && c != 'All')]
    ..sort((a, b) => b.length.compareTo(a.length));
  for (final c in named) {
    final m = RegExp(r' (?:in|under|category|to) ' + RegExp.escape(c.toLowerCase()) + r'(?: category)? ').firstMatch(text);
    if (m != null) {
      category = c;
      text = text.replaceRange(m.start, m.end, ' ');
      break;
    }
  }

  // Amount: prefer a number said next to "rupees"/"rs", else the last number.
  double? amount;
  final number = r'(\d[\d,]*(?:\.\d+)?)';
  final money = RegExp(' (?:rs\\.?|rupees?|inr) ?$number| $number ?(?:rs\\.?|rupees?|inr|bucks)\\b');
  final m = money.firstMatch(text);
  if (m != null) {
    amount = double.tryParse((m.group(1) ?? m.group(2))!.replaceAll(',', ''));
    text = text.replaceRange(m.start, m.end, ' ');
  } else {
    final all = RegExp(' $number(?= )').allMatches(text).toList();
    if (all.isNotEmpty) {
      final last = all.last;
      amount = double.tryParse(last.group(1)!.replaceAll(',', ''));
      text = text.replaceRange(last.start, last.end, ' ');
    }
  }

  // What is left is the item, without filler words.
  const filler = {
    'add', 'added', 'spent', 'spend', 'paid', 'pay', 'bought', 'buy', 'for', 'on', 'of', 'the', 'a', 'an',
    'rupees', 'rupee', 'rs', 'inr', 'amount', 'expense', 'please', 'today', 'and', 'only', 'is', 'was',
    'date', 'dated',
  };
  final words = text.split(' ').where((w) => w.isNotEmpty && !filler.contains(w)).toList();
  final title = words.join(' ');
  return (
    title: title.isEmpty ? '' : title[0].toUpperCase() + title.substring(1),
    amount: amount,
    category: category,
    date: date,
  );
}
