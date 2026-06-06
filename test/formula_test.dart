import 'package:flutter_test/flutter_test.dart';
import 'package:vault_notes/utils/formula_evaluator.dart';

void main() {
  test('Formula Evaluator Shorthand and Cell References Test', () {
    final grid = [
      ['10', '20', '30'],
      ['5', '=A1+B1', '=C1-A2'],
      ['=A1*B1/2', 'Text', '=A1+B3'],
    ];

    expect(FormulaEvaluator.evaluate(grid[1][1], grid), equals('30'));
    expect(FormulaEvaluator.evaluate(grid[1][2], grid), equals('25'));
    expect(FormulaEvaluator.evaluate(grid[2][0], grid), equals('100'));
    expect(FormulaEvaluator.evaluate(grid[2][2], grid), equals('10'));
  });
}
