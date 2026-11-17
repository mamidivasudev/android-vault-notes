/// Turns a spoken sentence into an expense: "add milk rupees 33" →
/// title "Milk", amount 33. A category is picked when one of [categories] is
/// named ("petrol 500 in travel"), otherwise [category] is null.
({String title, double? amount, String? category}) parseSpokenExpense(
  String spoken, {
  List<String> categories = const [],
}) {
  var text = ' ${spoken.toLowerCase().replaceAll('₹', ' rupees ').replaceAll(RegExp(r'\s+'), ' ').trim()} ';

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
  };
  final words = text.split(' ').where((w) => w.isNotEmpty && !filler.contains(w)).toList();
  final title = words.join(' ');
  return (
    title: title.isEmpty ? '' : title[0].toUpperCase() + title.substring(1),
    amount: amount,
    category: category,
  );
}
