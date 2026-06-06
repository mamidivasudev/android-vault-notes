import 'package:flutter/material.dart';

class CalculatorDialog extends StatefulWidget {
  const CalculatorDialog({super.key});

  @override
  State<CalculatorDialog> createState() => _CalculatorDialogState();
}

class _CalculatorDialogState extends State<CalculatorDialog> {
  String _display = '0';
  String _expression = '';
  double? _firstOperand;
  String? _operator;
  bool _shouldResetDisplay = false;

  void _onDigitPress(String digit) {
    setState(() {
      if (_display == '0' || _shouldResetDisplay) {
        _display = digit;
        _shouldResetDisplay = false;
      } else {
        if (_display.length < 12) {
          _display += digit;
        }
      }
    });
  }

  void _onOperatorPress(String op) {
    if (_operator != null && !_shouldResetDisplay) {
      _onCalculate();
    }
    setState(() {
      _firstOperand = double.tryParse(_display);
      _operator = op;
      _expression = '$_display $op';
      _shouldResetDisplay = true;
    });
  }

  void _onCalculate() {
    if (_firstOperand == null || _operator == null) return;
    final secondOperand = double.tryParse(_display);
    if (secondOperand == null) return;

    double result = 0;
    switch (_operator) {
      case '+': result = _firstOperand! + secondOperand; break;
      case '-': result = _firstOperand! - secondOperand; break;
      case '×': result = _firstOperand! * secondOperand; break;
      case '÷': 
        if (secondOperand == 0) {
          _display = 'Error';
          _firstOperand = null;
          _operator = null;
          _expression = '';
          return;
        }
        result = _firstOperand! / secondOperand; 
        break;
    }

    setState(() {
      _display = result.truncateToDouble() == result 
          ? result.toInt().toString() 
          : result.toStringAsFixed(2);
      _expression = '';
      _firstOperand = null;
      _operator = null;
      _shouldResetDisplay = true;
    });
  }

  void _clear() {
    setState(() {
      _display = '0';
      _expression = '';
      _firstOperand = null;
      _operator = null;
      _shouldResetDisplay = false;
    });
  }

  void _backspace() {
    setState(() {
      if (_display.length > 1) {
        _display = _display.substring(0, _display.length - 1);
      } else {
        _display = '0';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Calculator', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      titlePadding: const EdgeInsets.fromLTRB(20, 10, 10, 0),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Display
            Container(
              padding: const EdgeInsets.all(12),
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(_expression, style: const TextStyle(color: Colors.grey, fontSize: 11)),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      _display,
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.black87),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Keypad
            _buildRow(['C', '÷', '×', '⌫']),
            _buildRow(['7', '8', '9', '-']),
            _buildRow(['4', '5', '6', '+']),
            _buildRow(['1', '2', '3', '=']),
            _buildRow(['0', '.', 'OK']),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(List<String> labels) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: labels.map((label) => _buildButton(label)).toList(),
      ),
    );
  }

  Widget _buildButton(String label) {
    bool isConfirm = label == 'OK';
    bool isOperator = ['+', '-', '×', '÷', '=', '⌫', 'C'].contains(label);
    bool isAction = label == '=' || label == 'OK';

    Color bgColor = isAction 
        ? const Color(0xFF1D63D2) 
        : (isOperator ? Colors.grey[200]! : Colors.white);
    Color textColor = isAction ? Colors.white : Colors.black87;

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: SizedBox(
          height: 40,
          child: ElevatedButton(
            onPressed: () {
              if (label == 'C') {
                _clear();
              } else if (label == '⌫') _backspace();
              else if (label == '=') _onCalculate();
              else if (label == 'OK') Navigator.pop(context, _display);
              else if (['+', '-', '×', '÷'].contains(label)) _onOperatorPress(label);
              else _onDigitPress(label);
            },
            style: ElevatedButton.styleFrom(
              padding: EdgeInsets.zero,
              backgroundColor: bgColor,
              foregroundColor: textColor,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: Colors.grey.shade300, width: 0.5),
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: label.length > 1 ? 14 : 18, 
                fontWeight: FontWeight.bold
              ),
            ),
          ),
        ),
      ),
    );
  }
}
