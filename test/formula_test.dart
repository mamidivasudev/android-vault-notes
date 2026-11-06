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

  test('SUM of 1,000 or more is not reduced to 0', () {
    final grid = [
      ['1,000'],
      ['500'],
      ['=SUM(A1:A2)'],
      ['=SUM(A1:A2)+1'],
    ];
    expect(FormulaEvaluator.evaluate(grid[2][0], grid), equals('1,500'));
    expect(FormulaEvaluator.evaluate(grid[3][0], grid), equals('1,501'));
  });

  test('SUM and AVG include cells that contain formulas', () {
    final grid = [
      ['10', '=A1*2'],
      ['20', '=A2*2'],
      ['', '=SUM(B1:B2)'],
      ['', '=AVG(B1:B2)'],
    ];
    expect(FormulaEvaluator.evaluate(grid[2][1], grid), equals('60'));
    expect(FormulaEvaluator.evaluate(grid[3][1], grid), equals('30'));
  });

  test('A range that includes the formula cell itself terminates', () {
    final grid = [
      ['5'],
      ['=SUM(A1:A2)'],
    ];
    expect(FormulaEvaluator.evaluate(grid[1][0], grid), isNot('#ERROR'));
  });

  test('Division by zero shows #DIV/0!', () {
    final grid = [
      ['10', '0', '=A1/B1'],
    ];
    expect(FormulaEvaluator.evaluate(grid[0][2], grid), equals('#DIV/0!'));
  });
}
