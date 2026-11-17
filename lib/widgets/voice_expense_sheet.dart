import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../providers.dart';
import '../utils/voice_expense.dart';
import 'top_toast.dart';
import 'voice_mic.dart';

/// Mic → "add milk rupees 33" → a card showing Milk · ₹33 · category · today,
/// which can be corrected before it is saved as an expense.
Future<void> showVoiceExpense(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _VoiceExpenseSheet(),
  );
}

class _VoiceExpenseSheet extends ConsumerStatefulWidget {
  const _VoiceExpenseSheet();

  @override
  ConsumerState<_VoiceExpenseSheet> createState() => _VoiceExpenseSheetState();
}

class _VoiceExpenseSheetState extends ConsumerState<_VoiceExpenseSheet> {
  final _title = TextEditingController();
  final _amount = TextEditingController();
  String _heard = '';
  String? _category;
  String _type = 'Out'; // In / Out / NA (None), like the add-expense window
  bool _done = false; // a result is shown for checking

  List<String> get _categories => ref.read(expenseCategoriesProvider).where((c) => c != 'All' && c.trim().isNotEmpty).toList();

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    super.dispose();
  }

  void _start() => setState(() {
        _done = false;
        _heard = '';
      });

  void _useResult(String words) {
    final cats = _categories;
    final parsed = parseSpokenExpense(words, categories: cats);
    // Category said aloud, else the last-used one, else the first.
    final last = ref.read(selectedExpenseCategoryProvider);
    setState(() {
      _heard = words;
      _done = true;
      _title.text = parsed.title;
      _amount.text = parsed.amount == null ? '' : NumberFormat('0.##').format(parsed.amount);
      _category = parsed.category ?? (cats.contains(last) ? last : (cats.isNotEmpty ? cats.first : null));
      // Money coming in when it is said so ("received 500 from Ravi", "salary 30000").
      _type = RegExp(r'\b(received|got|income|salary|credited|refund)\b').hasMatch(words.toLowerCase()) ? 'In' : 'Out';
    });
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    final amount = double.tryParse(_amount.text.trim().replaceAll(',', ''));
    if (title.isEmpty || amount == null || amount <= 0 || _category == null) {
      showTopToast(context, 'Add the item and an amount', icon: Icons.info, color: kToastBlue);
      return;
    }
    final added = await ref.read(expensesProvider.notifier).addExpense(
          Expense(title: title, amount: amount, category: _category!, date: DateTime.now(), type: _type),
        );
    if (!mounted) return;
    if (!added) {
      showTopToast(context, 'Already saved today with the same amount', icon: Icons.info, color: kToastBlue);
      return;
    }
    showTopToast(context, '$title · ₹${NumberFormat('#,##0.##').format(amount)} saved');
    Navigator.pop(context);
  }

  /// Same In / Out / None buttons as the add-expense window.
  Widget _typeButton(String type, String label, Color color) {
    final selected = _type == type;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => setState(() => _type = type),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? color : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: selected ? color : Colors.grey.shade300),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(color: selected ? Colors.white : Colors.grey.shade600, fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurface.withValues(alpha: 0.6);
    final cats = _categories;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewPaddingOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Add expense by voice', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            if (!_done) ...[
              VoiceMic(hint: 'Say something like "add milk rupees 33"', onResult: _useResult),
              const SizedBox(height: 8),
            ] else ...[
              Text('Heard: "$_heard"', style: TextStyle(color: muted, fontStyle: FontStyle.italic)),
              const SizedBox(height: 12),
              TextField(
                controller: _title,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Item', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^[\d,]*\.?\d{0,2}'))],
                decoration: const InputDecoration(labelText: 'Amount', prefixText: '₹ ', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              if (cats.isNotEmpty)
                DropdownButtonFormField<String>(
                  initialValue: cats.contains(_category) ? _category : cats.first,
                  decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()),
                  items: [for (final c in cats) DropdownMenuItem(value: c, child: Text(c))],
                  onChanged: (v) => setState(() => _category = v),
                ),
              const SizedBox(height: 12),
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
              Text('Date: today, ${DateFormat('d MMM yyyy').format(DateTime.now())}', style: TextStyle(color: muted)),
              const SizedBox(height: 16),
              Row(
                children: [
                  TextButton.icon(icon: const Icon(Icons.mic), label: const Text('Again'), onPressed: _start),
                  const Spacer(),
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: _save, child: const Text('Save')),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
