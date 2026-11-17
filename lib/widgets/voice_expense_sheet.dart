import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../models.dart';
import '../providers.dart';
import '../utils/voice_expense.dart';
import 'top_toast.dart';

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
  final _speech = SpeechToText();
  final _title = TextEditingController();
  final _amount = TextEditingController();
  String _heard = '';
  String? _category;
  bool _listening = false;
  bool _done = false; // a result is shown for checking
  String? _problem; // mic not allowed / speech not available / nothing heard

  List<String> get _categories => ref.read(expenseCategoriesProvider).where((c) => c != 'All' && c.trim().isNotEmpty).toList();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _speech.cancel();
    _title.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _problem = null;
      _done = false;
      _heard = '';
    });
    final ready = await _speech.initialize(
      onError: (e) {
        if (!mounted || _done) return;
        setState(() {
          _listening = false;
          _problem = e.errorMsg.contains('no_match') || e.errorMsg.contains('speech_timeout')
              ? "Didn't catch that. Tap the mic and try again."
              : 'Could not listen (${e.errorMsg}). Check the internet or try again.';
        });
      },
      onStatus: (s) {
        if (!mounted) return;
        if (s == 'done' || s == 'notListening') setState(() => _listening = false);
      },
    );
    if (!mounted) return;
    if (!ready) {
      setState(() => _problem = 'Voice input is not available. Allow the microphone for this app in phone Settings.');
      return;
    }
    HapticFeedback.selectionClick();
    setState(() => _listening = true);
    await _speech.listen(
      onResult: (r) {
        if (!mounted) return;
        setState(() => _heard = r.recognizedWords);
        if (r.finalResult) _useResult(r.recognizedWords);
      },
      listenOptions: SpeechListenOptions(
        localeId: 'en_IN',
        partialResults: true,
        listenFor: const Duration(seconds: 20),
        pauseFor: const Duration(seconds: 3),
        cancelOnError: true,
      ),
    );
  }

  void _useResult(String words) {
    final cats = _categories;
    final parsed = parseSpokenExpense(words, categories: cats);
    // Category said aloud, else the last-used one, else the first.
    final last = ref.read(selectedExpenseCategoryProvider);
    setState(() {
      _listening = false;
      _done = true;
      _title.text = parsed.title;
      _amount.text = parsed.amount == null ? '' : NumberFormat('0.##').format(parsed.amount);
      _category = parsed.category ?? (cats.contains(last) ? last : (cats.isNotEmpty ? cats.first : null));
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
          Expense(title: title, amount: amount, category: _category!, date: DateTime.now(), type: 'Out'),
        );
    if (!mounted) return;
    if (!added) {
      showTopToast(context, 'Already saved today with the same amount', icon: Icons.info, color: kToastBlue);
      return;
    }
    showTopToast(context, '$title · ₹${NumberFormat('#,##0.##').format(amount)} saved');
    Navigator.pop(context);
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
            const SizedBox(height: 4),
            Text('Say something like "add milk rupees 33"', style: TextStyle(color: muted)),
            const SizedBox(height: 16),
            if (!_done) ...[
              Center(
                child: GestureDetector(
                  onTap: _listening ? () => _speech.stop() : _start,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: _listening ? 96 : 80,
                    height: _listening ? 96 : 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _listening ? Colors.red : scheme.primary,
                      boxShadow: _listening ? [BoxShadow(color: Colors.red.withValues(alpha: 0.4), blurRadius: 24, spreadRadius: 4)] : null,
                    ),
                    child: Icon(_listening ? Icons.mic : Icons.mic_none, color: Colors.white, size: 40),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _problem ?? (_listening ? (_heard.isEmpty ? 'Listening…' : _heard) : 'Tap the mic to speak'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: _problem != null ? Colors.red : null, fontWeight: FontWeight.w600),
              ),
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
