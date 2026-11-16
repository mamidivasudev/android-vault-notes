import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../notification_service.dart';
import '../widgets/top_toast.dart';
import 'extras_models.dart';
import 'extras_store.dart';
import 'extras_widgets.dart';

const _lentColor = Color(0xFF16A34A); // money coming back to me
const _borrowedColor = Color(0xFFDC2626); // money I have to return

class MoneyView extends ConsumerStatefulWidget {
  const MoneyView({super.key});

  @override
  ConsumerState<MoneyView> createState() => _MoneyViewState();
}

class _MoneyViewState extends ConsumerState<MoneyView> {
  bool _showSettled = false;

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(moneyProvider);
    final active = all.where((e) => !e.settled).toList();
    final toGet = active.where((e) => e.lent).fold<double>(0, (s, e) => s + e.remaining);
    final toGive = active.where((e) => !e.lent).fold<double>(0, (s, e) => s + e.remaining);
    final shown = (_showSettled ? all.where((e) => e.settled) : active).toList()
      ..sort((a, b) {
        // Overdue first, then by due date, then newest.
        final ad = a.dueDate, bd = b.dueDate;
        if (ad != null && bd != null) return ad.compareTo(bd);
        if (ad != null) return -1;
        if (bd != null) return 1;
        return b.date.compareTo(a.date);
      });

    return ExtrasScaffold(
      onAdd: () => showMoneyEditor(context, ref, null),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: [
                Expanded(child: _Total(label: "You'll get", amount: toGet, color: _lentColor)),
                const SizedBox(width: 8),
                Expanded(child: _Total(label: 'You owe', amount: toGive, color: _borrowedColor)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<bool>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: [
                  ButtonSegment(value: false, label: Text('Active ${active.length}')),
                  ButtonSegment(value: true, label: Text('Settled ${all.length - active.length}')),
                ],
                selected: {_showSettled},
                onSelectionChanged: (v) => setState(() => _showSettled = v.first),
              ),
            ),
          ),
          Expanded(
            child: shown.isEmpty
                ? ExtrasEmpty(
                    icon: Icons.currency_rupee,
                    text: _showSettled ? 'Nothing settled yet' : 'No money to track',
                    hint: _showSettled ? 'Fully paid entries show up here' : 'Tap + to note money you lent or borrowed',
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
                    children: [for (final e in shown) _MoneyCard(entry: e)],
                  ),
          ),
        ],
      ),
    );
  }
}

class _Total extends StatelessWidget {
  final String label;
  final double amount;
  final Color color;
  const _Total({required this.label, required this.amount, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(rupees(amount), style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _MoneyCard extends ConsumerWidget {
  final MoneyEntry entry;
  const _MoneyCard({required this.entry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = entry;
    final color = e.lent ? _lentColor : _borrowedColor;
    final overdue = e.isOverdue();
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => showMoneyDetails(context, ref, e.id),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(e.person, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                    child: Text(e.lent ? 'Lent' : 'Borrowed', style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                e.settled ? '${rupees(e.amount)} · settled' : '${rupees(e.remaining)} left of ${rupees(e.amount)}',
                style: TextStyle(color: color, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: e.amount <= 0 ? 1 : (e.paid / e.amount).clamp(0, 1).toDouble(),
                  minHeight: 5,
                  backgroundColor: color.withValues(alpha: 0.12),
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                [
                  DateFormat('d MMM yyyy').format(e.date),
                  if (e.dueDate != null && !e.settled) '${overdue ? 'Overdue since' : 'Due'} ${DateFormat('d MMM').format(e.dueDate!)}',
                  if (e.note.isNotEmpty) e.note,
                ].join('  ·  '),
                style: TextStyle(fontSize: 12, color: overdue ? Colors.red : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Details: payments, add payment, settle, edit, delete ─────────────────────

Future<void> showMoneyDetails(BuildContext context, WidgetRef ref, String id) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _MoneyDetails(id: id),
  );
}

class _MoneyDetails extends ConsumerWidget {
  final String id;
  const _MoneyDetails({required this.id});

  Future<double?> _askAmount(BuildContext context, String title, double max) {
    final c = TextEditingController();
    return showDialog<double>(
      context: context,
      builder: (ctx) {
        void done() => Navigator.pop(ctx, double.tryParse(c.text.trim()));
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: c,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
            onSubmitted: (_) => done(),
            decoration: InputDecoration(labelText: 'Amount', prefixText: '₹ ', helperText: 'Still due: ${rupees(max)}', border: const OutlineInputBorder()),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(onPressed: done, child: const Text('Save')),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = ref.watch(moneyProvider).where((m) => m.id == id).firstOrNull;
    if (e == null) return const SizedBox(height: 80);
    final notifier = ref.read(moneyProvider.notifier);
    final color = e.lent ? _lentColor : _borrowedColor;
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(e.person, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
              '${e.lent ? 'You lent' : 'You borrowed'} ${rupees(e.amount)} on ${DateFormat('d MMM yyyy').format(e.date)}',
              style: TextStyle(color: muted),
            ),
            if (e.note.isNotEmpty) ...[const SizedBox(height: 4), SelectableText(e.note)],
            const SizedBox(height: 12),
            Text(
              e.settled ? 'Fully settled ✓' : '${rupees(e.remaining)} still ${e.lent ? 'to collect' : 'to return'}',
              style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w800),
            ),
            if (e.dueDate != null && !e.settled)
              Text('Due ${DateFormat('d MMM yyyy').format(e.dueDate!)}', style: TextStyle(color: e.isOverdue() ? Colors.red : muted)),
            const SizedBox(height: 12),
            const ExtrasHeading('Payments'),
            if (e.payments.isEmpty) Text('No payments yet', style: TextStyle(color: muted)),
            for (var i = 0; i < e.payments.length; i++)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.check_circle, color: color),
                title: Text(rupees(e.payments[i].amount), style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(DateFormat('d MMM yyyy').format(e.payments[i].date)),
                trailing: IconButton(
                  tooltip: 'Remove payment',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () async {
                    if (!await confirmYesNo(context, 'Remove payment?', 'Remove the ${rupees(e.payments[i].amount)} payment?')) return;
                    await notifier.save(e.copyWith(payments: [...e.payments]..removeAt(i)));
                  },
                ),
              ),
            const SizedBox(height: 12),
            if (!e.settled)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('Add payment'),
                      onPressed: () async {
                        final amount = await _askAmount(context, e.lent ? 'Money received' : 'Money returned', e.remaining);
                        if (amount == null || amount <= 0) return;
                        await notifier.save(e.copyWith(payments: [...e.payments, MoneyPayment(amount: amount, date: DateTime.now())]));
                        if (context.mounted) showTopToast(context, '${rupees(amount)} payment saved');
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.done_all),
                      label: const Text('Settle all'),
                      onPressed: () async {
                        if (!await confirmYesNo(context, 'Settle?', 'Mark the remaining ${rupees(e.remaining)} as paid?')) return;
                        await notifier.save(e.copyWith(payments: [...e.payments, MoneyPayment(amount: e.remaining, date: DateTime.now())]));
                        if (context.mounted) showTopToast(context, '${e.person} settled');
                      },
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  label: const Text('Delete', style: TextStyle(color: Colors.red)),
                  onPressed: () async {
                    if (!await confirmYesNo(context, 'Delete?', 'Delete the entry for ${e.person}?')) return;
                    await notifier.delete(e.id);
                    if (!context.mounted) return;
                    showTopToast(context, '${e.person} deleted', icon: Icons.delete, color: kToastRed, actionLabel: 'UNDO', onAction: () => notifier.save(e));
                    Navigator.pop(context);
                  },
                ),
                const Spacer(),
                TextButton.icon(
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit'),
                  onPressed: () {
                    Navigator.pop(context);
                    showMoneyEditor(context, ref, e);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Add / edit ───────────────────────────────────────────────────────────────

Future<void> showMoneyEditor(BuildContext context, WidgetRef ref, MoneyEntry? entry) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _MoneyEditor(entry: entry),
  );
}

class _MoneyEditor extends ConsumerStatefulWidget {
  final MoneyEntry? entry;
  const _MoneyEditor({this.entry});

  @override
  ConsumerState<_MoneyEditor> createState() => _MoneyEditorState();
}

class _MoneyEditorState extends ConsumerState<_MoneyEditor> {
  late final _person = TextEditingController(text: widget.entry?.person ?? '');
  late final _amount = TextEditingController(
    text: widget.entry == null ? '' : NumberFormat('0.##').format(widget.entry!.amount),
  );
  late final _note = TextEditingController(text: widget.entry?.note ?? '');
  late bool _lent = widget.entry?.lent ?? true;
  late DateTime _date = widget.entry?.date ?? DateTime.now();
  late DateTime? _due = widget.entry?.dueDate;

  @override
  void dispose() {
    _person.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final person = _person.text.trim();
    final amount = double.tryParse(_amount.text.trim()) ?? 0;
    if (person.isEmpty || amount <= 0) return;
    final base = widget.entry ?? MoneyEntry(person: person, amount: amount, lent: _lent, date: _date);
    final entry = base.copyWith(person: person, amount: amount, lent: _lent, date: _date, dueDate: _due, note: _note.text.trim());
    if (_due != null) await NotificationService().requestPermissions();
    await ref.read(moneyProvider.notifier).save(entry);
    if (!mounted) return;
    showTopToast(context, widget.entry == null ? 'Saved' : '$person updated');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return ExtrasSheet(
      title: widget.entry == null ? 'Money lent / borrowed' : 'Edit',
      onSave: _save,
      children: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, label: Text('I lent'), icon: Icon(Icons.call_made)),
            ButtonSegment(value: false, label: Text('I borrowed'), icon: Icon(Icons.call_received)),
          ],
          selected: {_lent},
          onSelectionChanged: (v) => setState(() => _lent = v.first),
        ),
        const SizedBox(height: 12),
        TextField(controller: _person, autofocus: widget.entry == null, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Person', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        TextField(
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
          decoration: const InputDecoration(labelText: 'Amount', prefixText: '₹ ', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        DateField(label: 'Date', value: _date, onChanged: (d) => setState(() => _date = d ?? _date)),
        const SizedBox(height: 12),
        DateField(label: 'Due date (optional, reminds you)', value: _due, clearable: true, onChanged: (d) => setState(() => _due = d)),
        const SizedBox(height: 12),
        TextField(controller: _note, decoration: const InputDecoration(labelText: 'Note (optional)', border: OutlineInputBorder())),
      ],
    );
  }
}
