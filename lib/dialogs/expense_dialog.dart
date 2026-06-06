import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models.dart';
import '../providers.dart';
import 'calculator_dialog.dart';

class ExpenseDialog extends ConsumerStatefulWidget {
  final Expense? expense;
  final String? initialCategory;
  const ExpenseDialog({super.key, this.expense, this.initialCategory});

  @override
  ConsumerState<ExpenseDialog> createState() => _ExpenseDialogState();
}

class _ExpenseDialogState extends ConsumerState<ExpenseDialog> {
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  final _noteFocusNode = FocusNode();
  final _titleFocusNode = FocusNode();
  late String _selectedCategory;
  late String _type;
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.expense?.category ?? widget.initialCategory ?? '';
    _type = widget.expense?.type ?? 'Out';
    _selectedDate = widget.expense?.date ?? DateTime.now();
    if (widget.expense != null) {
      _titleController.text = widget.expense!.title;
      _amountController.text = NumberFormat.decimalPattern('en_IN').format(widget.expense!.amount);
      _noteController.text = widget.expense!.note ?? '';
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    _noteFocusNode.dispose();
    _titleFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(expenseCategoriesProvider);
    if (_selectedCategory.isEmpty && categories.isNotEmpty) {
      _selectedCategory = categories.first;
    }
    
    return AlertDialog(
      scrollable: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
      contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Text(
                widget.expense == null ? 'Add Expense' : 'Edit Expense', 
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.calculate, size: 20, color: Color(0xFF1D63D2)),
                onPressed: () async {
                  FocusScope.of(context).unfocus();
                  final result = await showDialog<String>(
                    context: context,
                    barrierDismissible: true,
                    builder: (context) => const CalculatorDialog(),
                  );
                  if (result != null && result != 'Error') {
                    setState(() => _amountController.text = NumberFormat.decimalPattern('en_IN').format(double.tryParse(result) ?? 0));
                  }
                },
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      content: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: MediaQuery.of(context).size.width,
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            RawAutocomplete<String>(
              textEditingController: _titleController,
              focusNode: _titleFocusNode,
              optionsBuilder: (TextEditingValue textEditingValue) {
                if (textEditingValue.text.isEmpty) {
                  return const Iterable<String>.empty();
                }
                final query = textEditingValue.text.toLowerCase();
                return ref.read(expensesProvider)
                    .map((e) => e.title.trim())
                    .toSet()
                    .where((title) => title.toLowerCase().contains(query) && title.toLowerCase() != query)
                    .take(5);
              },
              onSelected: (String selection) {
                final matched = ref.read(expensesProvider)
                    .where((e) => e.title.trim().toLowerCase() == selection.trim().toLowerCase())
                    .toList();
                if (matched.isNotEmpty) {
                  matched.sort((a, b) => b.date.compareTo(a.date));
                  final latest = matched.first;
                  setState(() {
                    _amountController.text = NumberFormat.decimalPattern('en_IN').format(latest.amount);
                    _selectedCategory = latest.category;
                    _type = latest.type;
                    if (latest.note != null) {
                      _noteController.text = latest.note!;
                    }
                  });
                } else {
                  setState(() {});
                }
              },
              fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    prefixIcon: const Icon(Icons.title, size: 18),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  ),
                  onChanged: (v) => setState(() {}),
                  style: const TextStyle(fontSize: 13),
                  autofocus: widget.expense == null,
                );
              },
              optionsViewBuilder: (context, onSelected, options) {
                return Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: MediaQuery.of(context).size.width - 96,
                      constraints: const BoxConstraints(maxHeight: 150),
                      child: ListView.builder(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: options.length,
                        itemBuilder: (BuildContext context, int index) {
                          final option = options.elementAt(index);
                          return InkWell(
                            onTap: () => onSelected(option),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              child: Text(option, style: const TextStyle(fontSize: 13, color: Colors.black87)),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _amountController,
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => _noteFocusNode.requestFocus(),
                    decoration: InputDecoration(
                      labelText: 'Amount',
                      hintText: '0.00',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      prefixIcon: const Icon(Icons.currency_rupee, size: 18),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                      ThousandsSeparatorInputFormatter(),
                    ],
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: ExcludeFocus(
                    child: InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _selectedDate,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                          builder: (context, child) {
                            return Theme(
                              data: Theme.of(context).copyWith(
                                colorScheme: const ColorScheme.light(
                                  primary: Color(0xFF1D63D2),
                                  onPrimary: Colors.white,
                                  onSurface: Colors.black,
                                ),
                              ),
                              child: child!,
                            );
                          },
                        );
                        if (picked != null) {
                          setState(() => _selectedDate = picked);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today, size: 16, color: Color(0xFF1D63D2)),
                            const SizedBox(width: 6),
                            Text(
                              "${_selectedDate.day} ${['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][_selectedDate.month-1]}",
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _noteController,
              focusNode: _noteFocusNode,
              textInputAction: TextInputAction.done,
              maxLines: 1,
              decoration: InputDecoration(
                labelText: 'Note (optional)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                prefixIcon: const Icon(Icons.notes, size: 18),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              ),
              style: const TextStyle(fontSize: 13),
              onSubmitted: (_) => _handleSave(),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 28,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: categories.length,
                itemBuilder: (context, index) {
                  final cat = categories[index];
                  final isSelected = cat == _selectedCategory;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(cat, style: const TextStyle(fontSize: 10)),
                      selected: isSelected,
                      onSelected: (val) {
                        if (val) setState(() => _selectedCategory = cat);
                      },
                      padding: EdgeInsets.zero,
                      labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _typeButton('In', 'In', Colors.green),
                const SizedBox(width: 6),
                _typeButton('Out', 'Out', Colors.red),
                const SizedBox(width: 6),
                _typeButton('NA', 'None', Colors.grey),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
        ),
        FilledButton(
          onPressed: _handleSave,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF1D63D2),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: Text(widget.expense == null ? 'Add Expense' : 'Update Expense'),
        ),
      ],
    );
  }

  Widget _typeButton(String type, String label, Color color) {
    final isSelected = _type == type;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _type = type),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? color : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isSelected ? color : Colors.grey.shade300),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.grey.shade600,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  void _handleSave() {
    final title = _titleController.text.trim();
    final amountStr = _amountController.text.trim();
    final note = _noteController.text.trim();

    if (title.isEmpty || amountStr.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill all required fields')));
      return;
    }

    final amount = double.tryParse(amountStr.replaceAll(',', ''));
    if (amount == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid amount')));
      return;
    }

    final newExpense = Expense(
      id: widget.expense?.id,
      title: title,
      amount: amount,
      type: _type,
      category: _selectedCategory,
      note: note.isEmpty ? null : note,
      date: _selectedDate,
    );

    if (widget.expense == null) {
      ref.read(expensesProvider.notifier).addExpense(newExpense);
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Transaction Added')));
    } else {
      final hasChanges = newExpense.title != widget.expense!.title ||
          newExpense.amount != widget.expense!.amount ||
          newExpense.type != widget.expense!.type ||
          newExpense.category != widget.expense!.category ||
          newExpense.note != widget.expense!.note ||
          newExpense.date != widget.expense!.date;

      if (!hasChanges) {
        Navigator.pop(context);
        return;
      }

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Update Expense?'),
          content: const Text('Do you want to save the changes to this expense?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('No')),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                ref.read(expensesProvider.notifier).updateExpense(newExpense);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Transaction Updated')));
              },
              child: const Text('Yes'),
            ),
          ],
        ),
      );
    }
  }
}

class ThousandsSeparatorInputFormatter extends TextInputFormatter {
  static final NumberFormat _formatter = NumberFormat.decimalPattern('en_IN');

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) return newValue.copyWith(text: '');
    
    String text = newValue.text.replaceAll(',', '');
    if (text == '.') return newValue.copyWith(text: '0.', selection: const TextSelection.collapsed(offset: 2));

    List<String> parts = text.split('.');
    String integerPart = parts[0];
    String? decimalPart = parts.length > 1 ? parts[1] : null;

    if (integerPart.isEmpty && decimalPart != null) integerPart = '0';
    
    double? value = double.tryParse(integerPart);
    if (value == null) return oldValue;

    String formatted = _formatter.format(value);
    if (decimalPart != null) formatted += '.$decimalPart';

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
