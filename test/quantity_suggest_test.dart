import 'package:flutter_test/flutter_test.dart';
import 'package:vault_notes/utils/grocery_catalog.dart';

void main() {
  test('a number suggests units, best ones for the category first', () {
    final r = suggestQuantities('2', category: 'Dairy');
    expect(r.first, '2 L');
    expect(r, contains('2 packets'));
  });

  test('number plus start of a unit narrows it down', () {
    expect(suggestQuantities('3 pa'), ['3 packets', '3 pairs']);
    expect(suggestQuantities('1 pa').first, '1 packet');
  });

  test('empty box shows usual amounts for the category', () {
    expect(suggestQuantities('', category: 'Vegetables').first, '1 kg');
    expect(suggestQuantities(''), isNotEmpty);
  });

  test('unit name or "half" without a number', () {
    expect(suggestQuantities('doz'), contains('1 dozen'));
    expect(suggestQuantities('half'), contains('½ kg'));
  });
}
