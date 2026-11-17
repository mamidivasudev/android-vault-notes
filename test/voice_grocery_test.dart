import 'package:flutter_test/flutter_test.dart';
import 'package:vault_notes/widgets/voice_note_grocery.dart';

void main() {
  test('several items with quantities from one sentence', () {
    final items = parseSpokenGrocery('add milk 1 litre, tomato 2 kg and bread');
    expect(items.map((i) => i.name), ['Milk', 'Tomato', 'Bread']);
    expect(items[1].quantity, '2 kg');
    expect(items[2].quantity, '');
  });

  test('a single item works too', () {
    final items = parseSpokenGrocery('eggs 1 dozen');
    expect(items, hasLength(1));
    expect(items.first.name, 'Eggs');
  });

  test('two-word names stay together', () {
    expect(parseSpokenGrocery('green gram and curd').map((i) => i.name), ['Green gram', 'Curd']);
  });
}
