import 'package:flutter_test/flutter_test.dart';
import 'package:vault_notes/models.dart';
import 'package:vault_notes/views/grocery_view.dart';

void main() {
  test('price survives saving and loading', () {
    final item = GroceryItem(name: 'Milk', isPurchased: true, price: 49.5);
    expect(GroceryItem.fromJson(item.toJson()).price, 49.5);
  });

  test('items saved before prices existed load without one', () {
    final json = GroceryItem(name: 'Milk').toJson();
    expect(json.containsKey('price'), isFalse);
    expect(GroceryItem.fromJson(json).price, isNull);
  });

  test('copyWith can clear the price', () {
    final item = GroceryItem(name: 'Milk', price: 20);
    expect(item.copyWith(price: null).price, isNull);
    expect(item.copyWith(name: 'Curd').price, 20);
  });

  test('saved text shows prices and the total', () {
    final text = groceryListText([
      GroceryItem(name: 'Rice'),
      GroceryItem(name: 'Milk', isPurchased: true, price: 50),
      GroceryItem(name: 'Beans', isPurchased: true, price: 1250.5),
      GroceryItem(name: 'Salt', isPurchased: true),
    ], DateTime(2026, 11, 9));
    expect(text, contains('₹50'));
    expect(text, contains('TOTAL: ₹1,300.5'));
  });
}
