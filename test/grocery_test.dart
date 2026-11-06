import 'package:flutter_test/flutter_test.dart';
import 'package:vault_notes/models.dart';
import 'package:vault_notes/utils/grocery_catalog.dart';

void main() {
  group('Legacy grocery items', () {
    test('"Rice (2 kg)" is split into name, quantity and unit', () {
      final item = GroceryItem.fromJson({'id': '1', 'name': 'Rice (2 kg)', 'isPurchased': false, 'createdAt': '2026-01-01T00:00:00.000'});
      expect(item.name, 'Rice');
      expect(item.quantity, '2');
      expect(item.unit, 'kg');
      expect(item.quantityLabel, '2 kg');
    });

    test('half / unit-only / plain names', () {
      expect(splitLegacyGroceryName('Milk (half kg)'), (name: 'Milk', quantity: '1/2', unit: 'kg'));
      expect(splitLegacyGroceryName('Bread (packet)'), (name: 'Bread', quantity: '', unit: 'packet'));
      expect(splitLegacyGroceryName('Eggs (12)'), (name: 'Eggs', quantity: '12', unit: ''));
      expect(splitLegacyGroceryName('Tomato'), (name: 'Tomato', quantity: '', unit: ''));
    });

    test('new format round-trips and is not re-split', () {
      final item = GroceryItem(name: 'Dal (Toor)', quantity: '1', unit: 'kg', category: 'Pulses & Lentils');
      final back = GroceryItem.fromJson(item.toJson());
      expect(back.name, 'Dal (Toor)');
      expect(back.quantityLabel, '1 kg');
      expect(back.category, 'Pulses & Lentils');
    });
  });

  group('Typed input', () {
    test('parses quantity and unit', () {
      expect(parseGroceryInput('tomato 1 kg'), (name: 'tomato', quantity: '1', unit: 'kg'));
      expect(parseGroceryInput('milk 2L'), (name: 'milk', quantity: '2', unit: 'L'));
      expect(parseGroceryInput('eggs 12'), (name: 'eggs', quantity: '12', unit: ''));
      expect(parseGroceryInput('ghee 500 gms'), (name: 'ghee', quantity: '500', unit: 'g'));
    });

    test('does not eat words that look like units', () {
      expect(parseGroceryInput('Green gram').name, 'Green gram');
      expect(parseGroceryInput('Bread pack').name, 'Bread pack');
      expect(parseGroceryInput('Onion').name, 'Onion');
    });

    test('quantity stepper', () {
      expect(stepQuantity('', 1), '1');
      expect(stepQuantity('1', 0.25), '1.25');
      expect(stepQuantity('1/2', 0.25), '0.75');
      expect(stepQuantity('1', -1), '');
    });
  });

  group('Catalog search', () {
    final catalog = [
      CatalogItem.fromJson({
        'id': '1',
        'category': 'Vegetables',
        'default_unit': 'kg',
        'common_units': ['kg', 'g'],
        'names': {'en': 'Tomato', 'te': 'టమాటా', 'hi': 'टमाटर'},
        'search_terms': {'en': ['tomato', 'tamatar'], 'te': ['టమాటా']},
      }),
      CatalogItem.fromJson({
        'id': '2',
        'category': 'Condiments',
        'names': {'en': 'Tomato Ketchup'},
        'search_terms': {'en': ['ketchup', 'tomato sauce']},
      }),
    ];

    test('prefix and shorter names rank first', () {
      final r = searchCatalog(catalog, 'tom');
      expect(r.first.name, 'Tomato');
      expect(r.length, 2);
    });

    test('matches other languages and phonetic terms', () {
      expect(searchCatalog(catalog, 'టమా').single.name, 'Tomato');
      expect(searchCatalog(catalog, 'tamatar').single.name, 'Tomato');
      expect(catalog.first.localName, 'టమాటా · टमाटर');
    });

    test('category order puts unknown categories last', () {
      expect(groceryCategoryRank('Vegetables'), lessThan(groceryCategoryRank('Household')));
      expect(groceryCategoryRank(''), groceryCategoryRank('Other'));
      expect(groceryCategoryRank('Something new'), groceryCategoryRank('Other'));
    });
  });
}
