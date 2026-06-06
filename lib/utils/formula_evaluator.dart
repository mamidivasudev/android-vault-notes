import 'dart:math';
import 'package:intl/intl.dart';

class FormulaEvaluator {
  static final _numberFormat = NumberFormat("#,##,##0.##", "en_IN");

  static String evaluate(String formula, List<List<String>> grid, {List<List<String?>>? bgColors}) {
    return _evaluateWithVisited(formula, grid, bgColors: bgColors, visited: {});
  }

  static String _evaluateWithVisited(String formula, List<List<String>> grid, {List<List<String?>>? bgColors, required Set<String> visited}) {
    if (formula.isEmpty) return '';
    
    // If not a formula, check if it's a number and format it
    if (!formula.startsWith('=')) {
      final cleanVal = formula.replaceAll(',', '');
      if (_isNumeric(cleanVal)) {
        return _format(double.parse(cleanVal));
      }
      return formula;
    }
    
    try {
      String expression = formula.substring(1).toUpperCase().replaceAll(' ', '');
      
      // 1. Evaluate all functions inside the expression
      expression = expression.replaceAllMapped(RegExp(r'COUNTIFCOLOR\(([^)]+)\)'), (match) {
        return _handleCountIfColor(match.group(0)!, grid, bgColors);
      });
      expression = expression.replaceAllMapped(RegExp(r'COUNTIF\(([^)]+)\)'), (match) {
        return _handleCountIf(match.group(0)!, grid);
      });
      expression = expression.replaceAllMapped(RegExp(r'COUNT\(([^)]+)\)'), (match) {
        return _handleCount(match.group(0)!, grid);
      });
      expression = expression.replaceAllMapped(RegExp(r'SUM\(([^)]+)\)'), (match) {
        return _handleSum(match.group(0)!, grid);
      });
      expression = expression.replaceAllMapped(RegExp(r'AVG\(([^)]+)\)'), (match) {
        return _handleAvg(match.group(0)!, grid);
      });

      // 2. Replace cell references (e.g., A1, B2) with evaluated values
      final cellRefRegex = RegExp(r'\b([A-Z]+)(\d+)\b');
      expression = expression.replaceAllMapped(cellRefRegex, (match) {
        final colStr = match.group(1)!;
        final rowStr = match.group(2)!;
        
        final col = _colLetterToIndex(colStr);
        final row = int.parse(rowStr) - 1;
        
        if (row >= 0 && row < grid.length && col >= 0 && col < grid[row].length) {
          final cellKey = '$colStr$rowStr';
          if (visited.contains(cellKey)) {
            return '0';
          }
          final cellVal = grid[row][col];
          final String evaluatedVal;
          if (cellVal.startsWith('=')) {
            final newVisited = Set<String>.from(visited)..add(cellKey);
            evaluatedVal = _evaluateWithVisited(cellVal, grid, bgColors: bgColors, visited: newVisited).replaceAll(',', '');
          } else {
            evaluatedVal = cellVal.replaceAll(',', '');
          }
          return _isNumeric(evaluatedVal) ? evaluatedVal : '0';
        }
        return '0';
      });

      // 3. Robust math evaluation (+, -, *, /, nested parentheses)
      return _evaluateMath(expression);
    } catch (e) {
      return '#ERROR';
    }
  }

  static String _format(double value) {
    // Custom Indian formatting logic since standard en_IN locale can be inconsistent on some devices
    String s = value.toString();
    List<String> parts = s.split('.');
    String integerPart = parts[0];
    String decimalPart = parts.length > 1 ? parts[1] : '';

    if (integerPart.length <= 3) {
      s = integerPart;
    } else {
      String lastThree = integerPart.substring(integerPart.length - 3);
      String other = integerPart.substring(0, integerPart.length - 3);
      String result = '';
      int count = 0;
      for (int i = other.length - 1; i >= 0; i--) {
        result = other[i] + result;
        count++;
        if (count == 2 && i != 0) {
          result = ',$result';
          count = 0;
        }
      }
      s = '$result,$lastThree';
    }

    if (decimalPart.isNotEmpty && decimalPart != '0' && decimalPart != '00') {
      // Limit to 2 decimal places and remove trailing zeros
      if (decimalPart.length > 2) decimalPart = decimalPart.substring(0, 2);
      decimalPart = decimalPart.replaceAll(RegExp(r'0+$'), '');
      if (decimalPart.isNotEmpty) s += '.$decimalPart';
    }
    return s;
  }

  static int _colLetterToIndex(String letter) {
    int index = 0;
    for (int i = 0; i < letter.length; i++) {
      index = index * 26 + (letter.codeUnitAt(i) - 'A'.codeUnitAt(0) + 1);
    }
    return index - 1;
  }

  static bool _isNumeric(String s) {
    return double.tryParse(s) != null;
  }

  static String _handleCount(String expression, List<List<String>> grid) {
    final range = expression.substring(6, expression.length - 1);
    final parts = range.split(':');
    if (parts.length != 2) return '0';

    final startMatch = RegExp(r'([A-Z]+)(\d+)').firstMatch(parts[0]);
    final endMatch = RegExp(r'([A-Z]+)(\d+)').firstMatch(parts[1]);
    
    if (startMatch == null || endMatch == null) return '0';

    final startCol = _colLetterToIndex(startMatch.group(1)!);
    final startRow = int.parse(startMatch.group(2)!) - 1;
    final endCol = _colLetterToIndex(endMatch.group(1)!);
    final endRow = int.parse(endMatch.group(2)!) - 1;

    int count = 0;
    for (int r = min(startRow, endRow); r <= max(startRow, endRow); r++) {
      for (int c = min(startCol, endCol); c <= max(startCol, endCol); c++) {
        if (r >= 0 && r < grid.length && c >= 0 && c < grid[r].length) {
          if (grid[r][c].trim().isNotEmpty) count++;
        }
      }
    }
    return _format(count.toDouble());
  }

  static double _parseExpression(String str) {
    int pos = -1;
    int ch = -1;

    void nextChar() {
      pos++;
      ch = (pos < str.length) ? str.codeUnitAt(pos) : -1;
    }

    bool eat(int charToEat) {
      while (ch == 32) { // space
        nextChar();
      }
      if (ch == charToEat) {
        nextChar();
        return true;
      }
      return false;
    }

    late double Function() parseExpression;

    double parseFactor() {
      if (eat(43)) return parseFactor(); // unary plus
      if (eat(45)) return -parseFactor(); // unary minus

      double x;
      int startPos = pos;
      if (eat(40)) { // parenthesis '('
        x = parseExpression();
        eat(41); // parenthesis ')'
      } else if ((ch >= 48 && ch <= 57) || ch == 46) { // numbers and decimal point
        while ((ch >= 48 && ch <= 57) || ch == 46) {
          nextChar();
        }
        x = double.parse(str.substring(startPos, pos));
      } else {
        throw Exception("Unexpected character in expression");
      }

      return x;
    }

    double parseTerm() {
      double x = parseFactor();
      for (;;) {
        if (eat(42)) {
          x *= parseFactor(); // multiplication '*'
        } else if (eat(47)) x /= parseFactor(); // division '/'
        else return x;
      }
    }

    parseExpression = () {
      double x = parseTerm();
      for (;;) {
        if (eat(43)) {
          x += parseTerm(); // addition '+'
        } else if (eat(45)) x -= parseTerm(); // subtraction '-'
        else return x;
      }
    };

    nextChar();
    double x = parseExpression();
    if (pos < str.length) throw Exception("Unexpected trailing character in expression");
    return x;
  }

  static String _evaluateMath(String expression) {
    try {
      final double total = _parseExpression(expression);
      return _format(total);
    } catch (e) {
      // Fallback to old simple math evaluation in case of any parsing error
      final List<String> terms = [];
      final List<String> ops = [];
      
      String currentTerm = '';
      for (int i = 0; i < expression.length; i++) {
        final char = expression[i];
        if (char == '+' || char == '-') {
          terms.add(currentTerm);
          ops.add(char);
          currentTerm = '';
        } else {
          currentTerm += char;
        }
      }
      terms.add(currentTerm);

      double total = double.tryParse(terms[0]) ?? 0;
      for (int i = 0; i < ops.length; i++) {
        final nextVal = double.tryParse(terms[i + 1]) ?? 0;
        if (ops[i] == '+') {
          total += nextVal;
        } else {
          total -= nextVal;
        }
      }

      return _format(total);
    }
  }

  static String _handleCountIf(String expression, List<List<String>> grid) {
    final argsStr = expression.substring(8, expression.length - 1);
    final parts = argsStr.split(',');
    if (parts.length != 2) return '0';

    final rangeParts = parts[0].split(':');
    if (rangeParts.length != 2) return '0';

    final startMatch = RegExp(r'([A-Z]+)(\d+)').firstMatch(rangeParts[0]);
    final endMatch = RegExp(r'([A-Z]+)(\d+)').firstMatch(rangeParts[1]);
    
    if (startMatch == null || endMatch == null) return '0';

    final startCol = _colLetterToIndex(startMatch.group(1)!);
    final startRow = int.parse(startMatch.group(2)!) - 1;
    final endCol = _colLetterToIndex(endMatch.group(1)!);
    final endRow = int.parse(endMatch.group(2)!) - 1;

    String criteria = parts[1];
    if (criteria.startsWith('"') && criteria.endsWith('"')) {
      criteria = criteria.substring(1, criteria.length - 1);
    }
    
    int count = 0;
    for (int r = min(startRow, endRow); r <= max(startRow, endRow); r++) {
      for (int c = min(startCol, endCol); c <= max(startCol, endCol); c++) {
        if (r >= 0 && r < grid.length && c >= 0 && c < grid[r].length) {
          if (grid[r][c].trim().toUpperCase() == criteria) {
            count++;
          }
        }
      }
    }
    return _format(count.toDouble());
  }

  static String _handleCountIfColor(String expression, List<List<String>> grid, List<List<String?>>? bgColors) {
    if (bgColors == null) return '0'; // Colors not available

    final argsStr = expression.substring(13, expression.length - 1);
    final parts = argsStr.split(',');
    if (parts.length != 2) return '0';

    final rangeParts = parts[0].split(':');
    if (rangeParts.length != 2) return '0';

    final startMatch = RegExp(r'([A-Z]+)(\d+)').firstMatch(rangeParts[0]);
    final endMatch = RegExp(r'([A-Z]+)(\d+)').firstMatch(rangeParts[1]);
    
    if (startMatch == null || endMatch == null) return '0';

    final startCol = _colLetterToIndex(startMatch.group(1)!);
    final startRow = int.parse(startMatch.group(2)!) - 1;
    final endCol = _colLetterToIndex(endMatch.group(1)!);
    final endRow = int.parse(endMatch.group(2)!) - 1;

    String criteria = parts[1];
    if (criteria.startsWith('"') && criteria.endsWith('"')) {
      criteria = criteria.substring(1, criteria.length - 1);
    }
    
    int count = 0;
    for (int r = min(startRow, endRow); r <= max(startRow, endRow); r++) {
      for (int c = min(startCol, endCol); c <= max(startCol, endCol); c++) {
        if (r >= 0 && r < grid.length && c >= 0 && c < grid[r].length) {
          if (grid[r][c].trim().toUpperCase() == criteria) {
            // Check if it has a color
            if (r < bgColors.length && c < bgColors[r].length && bgColors[r][c] != null) {
              count++;
            }
          }
        }
      }
    }
    return _format(count.toDouble());
  }

  static String _handleSum(String expression, List<List<String>> grid) {
    final range = expression.substring(4, expression.length - 1);
    final parts = range.split(':');
    if (parts.length != 2) return '0';

    final startMatch = RegExp(r'([A-Z]+)(\d+)').firstMatch(parts[0]);
    final endMatch = RegExp(r'([A-Z]+)(\d+)').firstMatch(parts[1]);
    
    if (startMatch == null || endMatch == null) return '0';

    final startCol = _colLetterToIndex(startMatch.group(1)!);
    final startRow = int.parse(startMatch.group(2)!) - 1;
    final endCol = _colLetterToIndex(endMatch.group(1)!);
    final endRow = int.parse(endMatch.group(2)!) - 1;

    double sum = 0;
    for (int r = min(startRow, endRow); r <= max(startRow, endRow); r++) {
      for (int c = min(startCol, endCol); c <= max(startCol, endCol); c++) {
        if (r >= 0 && r < grid.length && c >= 0 && c < grid[r].length) {
          final val = grid[r][c].replaceAll(',', '');
          if (_isNumeric(val)) {
            sum += double.parse(val);
          }
        }
      }
    }
    return _format(sum);
  }

  static String _handleAvg(String expression, List<List<String>> grid) {
    final range = expression.substring(4, expression.length - 1);
    final parts = range.split(':');
    if (parts.length != 2) return '0';

    final startMatch = RegExp(r'([A-Z]+)(\d+)').firstMatch(parts[0]);
    final endMatch = RegExp(r'([A-Z]+)(\d+)').firstMatch(parts[1]);
    
    if (startMatch == null || endMatch == null) return '0';

    final startCol = _colLetterToIndex(startMatch.group(1)!);
    final startRow = int.parse(startMatch.group(2)!) - 1;
    final endCol = _colLetterToIndex(endMatch.group(1)!);
    final endRow = int.parse(endMatch.group(2)!) - 1;

    double sum = 0;
    int count = 0;
    for (int r = min(startRow, endRow); r <= max(startRow, endRow); r++) {
      for (int c = min(startCol, endCol); c <= max(startCol, endCol); c++) {
        if (r >= 0 && r < grid.length && c >= 0 && c < grid[r].length) {
          final val = grid[r][c].replaceAll(',', '');
          if (_isNumeric(val)) {
            sum += double.parse(val);
            count++;
          }
        }
      }
    }
    return count == 0 ? '0' : _format(sum / count);
  }
}
