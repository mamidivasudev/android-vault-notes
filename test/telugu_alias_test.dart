import 'package:flutter_test/flutter_test.dart';
import 'package:vault_notes/utils/grocery_catalog.dart';

void main() {
  final catalog = [
    CatalogItem(
      id: '1',
      name: 'Urad Dal',
      localName: 'మినప పప్పు · उड़द दाल',
      category: 'Pulses & Lentils',
      defaultUnit: 'kg',
      units: const ['kg'],
      terms: ['urad dal', 'మినప పప్పు', 'उड़द दाल'],
    ),
    CatalogItem(
      id: '2',
      name: 'Vermicelli',
      localName: 'సేమియా',
      category: 'Snacks & Sweets',
      defaultUnit: 'pack',
      units: const ['pack'],
      terms: ['vermicelli', 'సేమియా'],
    ),
  ];

  test('Telugu words in English letters find the item', () {
    expect(teluguAlias('minapa pappu'), 'Urad Dal');
    expect(teluguAlias('Semya'), 'Vermicelli');
    expect(teluguAlias('kandipappu'), 'Toor Dal');
    expect(findCatalogItem(catalog, 'minapa pappu')?.name, 'Urad Dal');
    expect(searchCatalog(catalog, 'semiya').first.name, 'Vermicelli');
  });

  test('Telugu script (from the Telugu mic) finds the item', () {
    expect(findCatalogItem(catalog, 'మినప పప్పు')?.name, 'Urad Dal');
  });

  test('unknown words are left alone', () {
    expect(teluguAlias('zip tags'), isNull);
    expect(findCatalogItem(catalog, 'zip tags'), isNull);
  });
}
