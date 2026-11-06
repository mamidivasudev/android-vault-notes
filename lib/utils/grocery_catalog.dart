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
