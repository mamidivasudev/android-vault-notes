// Understands spoken Dates and Medicines entries.

const _months = {
  'jan': 1, 'january': 1, 'feb': 2, 'february': 2, 'mar': 3, 'march': 3, 'apr': 4, 'april': 4,
  'may': 5, 'jun': 6, 'june': 6, 'jul': 7, 'july': 7, 'aug': 8, 'august': 8, 'sep': 9, 'sept': 9,
  'september': 9, 'oct': 10, 'october': 10, 'nov': 11, 'november': 11, 'dec': 12, 'december': 12,
};

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

String _clean(String s) => s.replaceAll(RegExp(r'[,.]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

// ── Dates ────────────────────────────────────────────────────────────────────

class SpokenDate {
  final String title;
  final String type; // Household, Birthday, Anniversary, Other
  final DateTime? date; // start date / the day itself
  final bool yearKnown;
  final DateTime? remindOn;
  const SpokenDate({required this.title, required this.type, this.date, this.yearKnown = false, this.remindOn});
}

/// "gas started today, remind in 30 days" → Household · Gas · today · reminder +30 days.
/// "Amma birthday 15 March" → Birthday · Amma birthday · 15 March.
SpokenDate parseSpokenDate(String spoken, {DateTime? now}) {
  final today = DateTime((now ?? DateTime.now()).year, (now ?? DateTime.now()).month, (now ?? DateTime.now()).day);
  var t = ' ${_clean(spoken.toLowerCase())} ';

  // Reminder part first, so its date is not taken as the main date.
  DateTime? remind;
  final inMatch = RegExp(r' remind(?:er)?(?: me)? (?:in|after) (\d+|a|an|one) (day|days|week|weeks|month|months|year|years) ').firstMatch(t);
  if (inMatch != null) {
    final n = int.tryParse(inMatch.group(1)!) ?? 1;
    final unit = inMatch.group(2)!;
    remind = unit.startsWith('day')
        ? today.add(Duration(days: n))
        : unit.startsWith('week')
            ? today.add(Duration(days: 7 * n))
            : unit.startsWith('month')
                ? DateTime(today.year, today.month + n, today.day)
                : DateTime(today.year + n, today.month, today.day);
    t = t.replaceRange(inMatch.start, inMatch.end, ' ');
  }
  final onMatch = RegExp(r' remind(?:er)?(?: me)? on (.+?)$').firstMatch(t.trimRight());
  if (remind == null && onMatch != null) {
    remind = _findDate(' ${onMatch.group(1)!} ', today)?.date;
    t = '${t.substring(0, onMatch.start)} ';
  }

  // Type from key words.
  final type = RegExp(r' (?:birthday|bday|b day|born) ').hasMatch(t)
      ? 'Birthday'
      : RegExp(r' (?:anniversary|marriage|wedding) ').hasMatch(t)
          ? 'Anniversary'
          : RegExp(r' (?:started|start|used|opened|since|refill(?:ed)?|cylinder|changed|bought) ').hasMatch(t) ||
                  remind != null
              ? 'Household'
              : 'Other';

  // Main date.
  final found = _findDate(t, today);
  if (found != null) t = t.replaceRange(found.start, found.end, ' ');

  // Title: what is left, without filler words.
  const filler = {
    'add', 'on', 'is', 'was', 'the', 'date', 'from', 'started', 'start', 'used', 'opened', 'since', 'of', 'for',
    'remind', 'reminder', 'me', 'my',
  };
  final words = t.split(' ').where((w) => w.isNotEmpty && !filler.contains(w)).toList();
  // Household titles keep the item ("gas"); "used date" style wording reads better than "started".
  final title = _cap(words.join(' '));
  return SpokenDate(
    title: type == 'Household' && title.isNotEmpty && !title.toLowerCase().contains('date') ? '$title used date' : title,
    type: type,
    date: found?.date ?? (type == 'Household' ? today : null),
    yearKnown: found?.yearKnown ?? type == 'Household',
    remindOn: remind,
  );
}

({DateTime date, bool yearKnown, int start, int end})? _findDate(String t, DateTime today) {
  for (final w in const {'today': 0, 'yesterday': -1, 'tomorrow': 1}.entries) {
    final m = RegExp(' ${w.key} ').firstMatch(t);
    if (m != null) return (date: today.add(Duration(days: w.value)), yearKnown: true, start: m.start, end: m.end);
  }
  final monthNames = _months.keys.join('|');
  // "15 march 1995", "15th of march"
  var m = RegExp(' (\\d{1,2})(?:st|nd|rd|th)?(?: of)? ($monthNames)(?: (\\d{4}))? ').firstMatch(t);
  if (m != null) {
    return _build(int.parse(m.group(1)!), _months[m.group(2)!]!, m.group(3), today, m.start, m.end);
  }
  // "march 15 1995"
  m = RegExp(' ($monthNames) (\\d{1,2})(?:st|nd|rd|th)?(?: (\\d{4}))? ').firstMatch(t);
  if (m != null) {
    return _build(int.parse(m.group(2)!), _months[m.group(1)!]!, m.group(3), today, m.start, m.end);
  }
  // "15/3/1995", "15-3"
  m = RegExp(r' (\d{1,2})[/-](\d{1,2})(?:[/-](\d{2,4}))? ').firstMatch(t);
  if (m != null) {
    var y = m.group(3);
    if (y != null && y.length == 2) y = '20$y';
    return _build(int.parse(m.group(1)!), int.parse(m.group(2)!), y, today, m.start, m.end);
  }
  return null;
}

({DateTime date, bool yearKnown, int start, int end})? _build(int day, int month, String? year, DateTime today, int s, int e) {
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  final y = year == null ? today.year : int.parse(year);
  return (date: DateTime(y, month, day), yearKnown: year != null, start: s, end: e);
}

// ── Medicines ────────────────────────────────────────────────────────────────

/// "Dolo 650 at 8 AM and 9 PM" → name Dolo 650, times 08:00 and 21:00.
({String name, String dose, List<String> times}) parseSpokenMedicine(String spoken) {
  var t = ' ${_clean(spoken.toLowerCase().replaceAll('a.m.', 'am').replaceAll('p.m.', 'pm'))} ';
  final times = <String>{};

  String hhmm(int h, int m) => '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';

  // "8 am", "8:30 pm", "9pm"
  for (final m in RegExp(r' (\d{1,2})(?::(\d{2}))? ?(am|pm) ').allMatches(t).toList().reversed) {
    var h = int.parse(m.group(1)!) % 12;
    if (m.group(3) == 'pm') h += 12;
    times.add(hhmm(h, int.tryParse(m.group(2) ?? '0') ?? 0));
    t = t.replaceRange(m.start, m.end, ' ');
  }
  // "morning", "night" …
  const parts = {'morning': 8, 'afternoon': 14, 'evening': 18, 'night': 21, 'bedtime': 22};
  for (final p in parts.entries) {
    if (t.contains(' ${p.key} ')) {
      times.add(hhmm(p.value, 0));
      t = t.replaceAll(' ${p.key} ', ' ');
    }
  }

  // Dose: "1 tablet", "5 ml", "2 drops".
  var dose = '';
  final d = RegExp(r' (\d+(?:\.\d+)?|half|one|two) (tablet|tablets|tab|capsule|capsules|ml|drop|drops|spoon|spoons|puff|puffs) ').firstMatch(t);
  if (d != null) {
    dose = '${d.group(1)} ${d.group(2)}';
    t = t.replaceRange(d.start, d.end, ' ');
  }

  const filler = {'add', 'at', 'and', 'take', 'daily', 'every', 'day', 'in', 'the', 'medicine', 'tablet', 'times', 'a', 'on', 'of', 'before', 'after', 'food'};
  final name = t.split(' ').where((w) => w.isNotEmpty && !filler.contains(w)).join(' ');
  return (
    name: name.split(' ').map(_cap).join(' '),
    dose: dose,
    times: times.toList()..sort(),
  );
}
