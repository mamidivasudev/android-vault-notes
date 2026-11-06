/// Typed view of the bundled grocery catalog
/// (assets/indian_grocery_master_v2_multilingual_search.json) plus the user's
/// own catalog items.
class CatalogItem {
  final String id;
  final String name; // English
  final String localName; // Telugu / Hindi / custom local name
  final String category;
  final String defaultUnit;
  final List<String> units;
  final List<String> _terms; // lower-cased search terms in every language

  CatalogItem({
    required this.id,
    required this.name,
    required this.localName,
    required this.category,
    required this.defaultUnit,
    required this.units,
    required List<String> terms,
  }) : _terms = terms;

  factory CatalogItem.fromJson(Map<dynamic, dynamic> json) {
    final names = (json['names'] as Map?) ?? const {};
    final name = names['en']?.toString() ?? '';
    final local = [names['te'], names['hi'], names['local']]
        .where((v) => v != null && v.toString().trim().isNotEmpty)
        .map((v) => v.toString().trim())
        .join(' · ');
    final terms = <String>{name.toLowerCase()};
    for (final v in names.values) {
      if (v != null) terms.add(v.toString().toLowerCase());
    }
    final searchTerms = (json['search_terms'] as Map?) ?? const {};
    for (final list in searchTerms.values) {
      if (list is List) terms.addAll(list.map((t) => t.toString().toLowerCase()));
    }
    final units = (json['common_units'] as List?)?.map((u) => u.toString()).toList() ?? const <String>[];
    return CatalogItem(
      id: json['id']?.toString() ?? name,
      name: name,
      localName: local,
      category: json['category']?.toString() ?? 'Other',
      defaultUnit: json['default_unit']?.toString() ?? (units.isNotEmpty ? units.first : ''),
      units: units,
      terms: terms.where((t) => t.isNotEmpty).toList(),
    );
  }

  /// 3 = name starts with query, 2 = a term starts with it, 1 = contains, 0 = no match.
  int matchScore(String q) {
    if (q.isEmpty) return 0;
    if (name.toLowerCase().startsWith(q)) return 3;
    var best = 0;
    for (final t in _terms) {
      if (t.startsWith(q)) return 2;
      if (best == 0 && t.contains(q)) best = 1;
    }
    return best;
  }
}

/// Order categories appear in on the shopping list (roughly how a shop is laid out).
const List<String> kGroceryCategoryOrder = [
  'Vegetables',
  'Fruits',
  'Dairy',
  'Bakery & Breakfast',
  'Grains & Rice',
  'Pulses & Lentils',
  'Spices',
  'Oils & Sweeteners',
  'Dry Fruits & Nuts',
  'Condiments',
  'Snacks & Sweets',
  'Beverages',
  'Household',
  'Personal Care',
  'Pooja',
  'Other',
];

/// Units offered when an item has no catalog-specific ones.
const List<String> kGroceryUnits = ['kg', 'g', 'L', 'ml', 'pack', 'pc', 'dozen', 'bottle', 'box'];

int groceryCategoryRank(String category) {
  final i = kGroceryCategoryOrder.indexOf(category.isEmpty ? 'Other' : category);
  return i == -1 ? kGroceryCategoryOrder.length - 1 : i;
}

/// Best catalog matches for [query], best first.
List<CatalogItem> searchCatalog(List<CatalogItem> catalog, String query, {int limit = 30}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];
  final scored = <(int, CatalogItem)>[];
  for (final item in catalog) {
    final s = item.matchScore(q);
    if (s > 0) scored.add((s, item));
  }
  scored.sort((a, b) {
    final byScore = b.$1.compareTo(a.$1);
    if (byScore != 0) return byScore;
    final byLen = a.$2.name.length.compareTo(b.$2.name.length); // shorter = more general
    if (byLen != 0) return byLen;
    return a.$2.name.compareTo(b.$2.name);
  });
  return scored.take(limit).map((e) => e.$2).toList();
}

/// Catalog entry whose English name equals [name] (case-insensitive).
CatalogItem? findCatalogItem(List<CatalogItem> catalog, String name) {
  final n = name.trim().toLowerCase();
  for (final item in catalog) {
    if (item.name.toLowerCase() == n) return item;
  }
  return null;
}

/// Splits typed text like "rice 2 kg", "milk 1L" or "eggs 12" into a name and
/// an optional quantity / unit.
({String name, String quantity, String unit}) parseGroceryInput(String text) {
  final t = text.trim();
  final m = RegExp(
    r'^(.*?)\s+(\d+(?:\.\d+)?|\d+/\d+|half|quarter)?\s*(kg|kgs|kilograms?|g|gm|gms|grams?|l|ltr|litres?|liters?|ml|packs?|packets?|pcs?|pieces?|dozen|bottles?|box(?:es)?)?$',
    caseSensitive: false,
  ).firstMatch(t);
  // A number is required: otherwise "Green gram" or "Bread pack" would lose a word.
  if (m == null || m.group(2) == null || m.group(1)!.trim().isEmpty) {
    return (name: t, quantity: '', unit: '');
  }
  var qty = m.group(2) ?? '';
  if (qty.toLowerCase() == 'half') qty = '1/2';
  if (qty.toLowerCase() == 'quarter') qty = '1/4';
  return (name: m.group(1)!.trim(), quantity: qty, unit: _normaliseUnit(m.group(3) ?? ''));
}

String _normaliseUnit(String u) {
  final l = u.toLowerCase();
  if (l.isEmpty) return '';
  if (l.startsWith('kg') || l.startsWith('kilo')) return 'kg';
  if (l == 'g' || l.startsWith('gm') || l.startsWith('gram')) return 'g';
  if (l == 'l' || l.startsWith('ltr') || l.startsWith('lit')) return 'L';
  if (l == 'ml') return 'ml';
  if (l.startsWith('pack')) return 'pack';
  if (l.startsWith('pc') || l.startsWith('piece')) return 'pc';
  if (l == 'dozen') return 'dozen';
  if (l.startsWith('bottle')) return 'bottle';
  if (l.startsWith('box')) return 'box';
  return u;
}

/// Adds [delta] to a quantity string ("" counts as 0; fractions become decimals).
String stepQuantity(String quantity, num delta) {
  double current;
  final frac = RegExp(r'^(\d+)/(\d+)$').firstMatch(quantity.trim());
  if (frac != null) {
    current = int.parse(frac.group(1)!) / int.parse(frac.group(2)!);
  } else {
    current = double.tryParse(quantity.trim()) ?? 0;
  }
  final next = current + delta;
  if (next <= 0) return '';
  return next == next.roundToDouble() ? next.toInt().toString() : next.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
}

/// Picture for a grocery row: a keyword match on the name first, then the
/// category, then a basket.
String groceryEmoji(String name, [String category = '']) {
  final n = name.toLowerCase();
  for (final e in _kNameEmoji.entries) {
    for (final k in e.key.split('|')) {
      if (n.contains(k)) return e.value;
    }
  }
  return _kCategoryEmoji[category] ?? '🛒';
}

const Map<String, String> _kNameEmoji = {
  'tomato': '🍅', 'potato': '🥔', 'onion': '🧅', 'garlic': '🧄', 'ginger': '🫚',
  'carrot': '🥕', 'brinjal|eggplant': '🍆', 'chilli|chili': '🌶️', 'capsicum|bell pepper': '🫑',
  'cucumber': '🥒', 'corn': '🌽', 'broccoli': '🥦', 'cabbage|lettuce|spinach|palak|leaf|leaves|coriander|mint|methi|greens': '🥬',
  'beans|peas|drumstick|okra|bhindi|ladies finger': '🫛', 'mushroom': '🍄', 'sweet potato': '🍠',
  'coconut': '🥥', 'mango': '🥭', 'banana': '🍌', 'apple': '🍎', 'grape': '🍇', 'orange|mosambi': '🍊',
  'lemon|lime': '🍋', 'watermelon': '🍉', 'melon': '🍈', 'pineapple': '🍍', 'strawberr': '🍓',
  'cherry': '🍒', 'peach': '🍑', 'pear': '🍐', 'kiwi': '🥝', 'avocado': '🥑', 'pomegranate|guava|papaya': '🍎',
  'milk': '🥛', 'curd|yogurt|yoghurt|buttermilk': '🥛', 'cheese|paneer': '🧀', 'butter|ghee': '🧈', 'egg': '🥚',
  'bread|bun|pav': '🍞', 'biscuit|cookie': '🍪', 'cake': '🍰', 'croissant': '🥐',
  'rice|poha|rava|sooji|semolina': '🍚', 'atta|flour|maida|wheat|besan': '🌾', 'noodle|pasta|vermicelli': '🍜',
  'dal|lentil|gram|chana|rajma|moong|urad|toor': '🫘', 'oil': '🫗', 'sugar|jaggery|gur': '🧂', 'honey': '🍯',
  'salt': '🧂', 'turmeric|masala|pepper|jeera|cumin|mustard|spice|clove|cardamom|cinnamon': '🧂',
  'almond|cashew|walnut|pista|raisin|nut|peanut|groundnut': '🥜', 'chocolate': '🍫', 'chips': '🍟', 'sweet|candy': '🍬',
  'tea': '🍵', 'coffee': '☕', 'juice': '🧃', 'water': '💧', 'soft drink|cola|soda': '🥤',
  'chicken': '🍗', 'mutton|meat': '🥩', 'fish|prawn': '🐟',
  'soap|shampoo|detergent|washing': '🧼', 'toothpaste|toothbrush|brush': '🪥', 'tissue|toilet': '🧻',
  'sponge|scrub': '🧽', 'broom|mop': '🧹', 'agarbatti|incense|camphor|diya|pooja': '🪔',
};

const Map<String, String> _kCategoryEmoji = {
  'Vegetables': '🥬', 'Fruits': '🍎', 'Dairy': '🥛', 'Bakery & Breakfast': '🍞', 'Grains & Rice': '🍚',
  'Pulses & Lentils': '🫘', 'Spices': '🧂', 'Oils & Sweeteners': '🫗', 'Dry Fruits & Nuts': '🥜',
  'Condiments': '🫙', 'Snacks & Sweets': '🍪', 'Beverages': '🥤', 'Household': '🧽',
  'Personal Care': '🧴', 'Pooja': '🪔', 'Other': '🛒',
};

// ── Quantity suggestions ────────────────────────────────────────────────────

/// Every quantity unit the app suggests: (singular, plural).
const List<(String, String)> kQuantityUnits = [
  ('kg', 'kg'),
  ('g', 'g'),
  ('L', 'L'),
  ('ml', 'ml'),
  ('packet', 'packets'),
  ('piece', 'pieces'),
  ('dozen', 'dozen'),
  ('bunch', 'bunches'),
  ('bottle', 'bottles'),
  ('box', 'boxes'),
  ('pouch', 'pouches'),
  ('can', 'cans'),
  ('tin', 'tins'),
  ('jar', 'jars'),
  ('bag', 'bags'),
  ('sachet', 'sachets'),
  ('bar', 'bars'),
  ('roll', 'rolls'),
  ('tray', 'trays'),
  ('strip', 'strips'),
  ('loaf', 'loaves'),
  ('cup', 'cups'),
  ('tube', 'tubes'),
  ('pair', 'pairs'),
];

/// Units that fit each category best, most common first.
const Map<String, List<String>> _kCategoryUnits = {
  'Vegetables': ['kg', 'g', 'piece', 'bunch', 'dozen', 'bag'],
  'Fruits': ['kg', 'dozen', 'piece', 'g', 'box'],
  'Dairy': ['L', 'ml', 'packet', 'g', 'kg', 'cup', 'tray', 'dozen'],
  'Bakery & Breakfast': ['packet', 'loaf', 'piece', 'box', 'g', 'dozen'],
  'Grains & Rice': ['kg', 'g', 'bag', 'packet'],
  'Pulses & Lentils': ['kg', 'g', 'packet'],
  'Spices': ['g', 'packet', 'kg', 'box', 'jar'],
  'Oils & Sweeteners': ['L', 'ml', 'kg', 'bottle', 'packet', 'jar', 'can', 'tin'],
  'Dry Fruits & Nuts': ['g', 'kg', 'packet', 'box'],
  'Condiments': ['bottle', 'jar', 'packet', 'g', 'ml', 'sachet'],
  'Snacks & Sweets': ['packet', 'box', 'g', 'kg', 'piece', 'bar'],
  'Beverages': ['L', 'ml', 'bottle', 'packet', 'can', 'box', 'g'],
  'Household': ['piece', 'packet', 'bottle', 'L', 'kg', 'roll', 'box'],
  'Personal Care': ['piece', 'bottle', 'tube', 'packet', 'bar', 'ml', 'g'],
  'Pooja': ['packet', 'box', 'piece', 'bunch', 'g'],
};

const List<String> _kDefaultUnitOrder = ['kg', 'g', 'packet', 'piece', 'L', 'ml', 'dozen', 'bottle', 'box', 'bunch'];

/// Typical amounts offered for a unit when no number is typed yet.
const Map<String, List<String>> _kUnitAmounts = {
  'kg': ['1', '2', '½', '5'],
  'g': ['100', '250', '500', '50'],
  'L': ['1', '2', '½'],
  'ml': ['200', '500', '100'],
  'dozen': ['1', '½', '2'],
};

String _qtyUnitLabel(String number, (String, String) unit) {
  final n = double.tryParse(number);
  final single = number == '½' || number == '1' || (n != null && n <= 1);
  return '$number ${single ? unit.$1 : unit.$2}';
}

/// Quantity suggestions for what was typed so far ("2" → 2 kg, 2 packets…;
/// "pa" → 1 packet, 2 packets; "" → the usual amounts for [category]).
List<String> suggestQuantities(String typed, {String category = '', int limit = 8}) {
  final t = typed.trim().toLowerCase();
  final order = <String>[
    ...?_kCategoryUnits[category],
    ..._kDefaultUnitOrder,
    for (final u in kQuantityUnits) u.$1,
  ];
  final seenUnits = <String>{};
  final units = <(String, String)>[];
  for (final name in order) {
    if (!seenUnits.add(name)) continue;
    final u = kQuantityUnits.where((e) => e.$1 == name).firstOrNull;
    if (u != null) units.add(u);
  }

  final out = <String>[];
  void add(String s) {
    if (out.length < limit && !out.any((o) => o.toLowerCase() == s.toLowerCase())) out.add(s);
  }

  final m = RegExp(r'^(\d+(?:[.,]\d+)?|½|1/2)\s*(.*)$').firstMatch(t);
  if (m != null) {
    final number = m.group(1)! == '1/2' ? '½' : m.group(1)!.replaceAll(',', '.');
    final rest = m.group(2)!.trim();
    for (final u in units) {
      if (rest.isEmpty || u.$1.toLowerCase().startsWith(rest) || u.$2.toLowerCase().startsWith(rest)) {
        add(_qtyUnitLabel(number, u));
      }
    }
    return out;
  }

  // No number: match units (and "half …") by name, or show the usual ones.
  final matching = t.isEmpty
      ? units.take(4).toList()
      : units.where((u) => u.$1.toLowerCase().startsWith(t) || u.$2.toLowerCase().startsWith(t)).toList();
  if (t.isNotEmpty && 'half'.startsWith(t)) {
    add('½ kg');
    add('½ dozen');
    add('½ L');
  }
  for (final u in matching) {
    for (final amount in _kUnitAmounts[u.$1] ?? const ['1', '2']) {
      add(_qtyUnitLabel(amount, u));
      if (t.isEmpty && out.length >= (units.indexOf(u) + 1) * 2) break; // 2 per unit when empty
    }
  }
  return out;
}
