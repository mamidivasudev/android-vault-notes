import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../notification_service.dart';
import '../widgets/top_toast.dart';
import 'extras_models.dart';
import 'extras_store.dart';
import 'extras_widgets.dart';

const _types = ['Birthday', 'Anniversary', 'Other'];
String _emoji(String type) => type == 'Birthday' ? '🎂' : type == 'Anniversary' ? '💍' : '📅';

class ImportantDatesView extends ConsumerWidget {
  const ImportantDatesView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final dates = [...ref.watch(importantDatesProvider)]..sort((a, b) => a.daysUntil(now).compareTo(b.daysUntil(now)));
    final scheme = Theme.of(context).colorScheme;

    return ExtrasScaffold(
      onAdd: () => showDateEditor(context, ref, null),
      child: dates.isEmpty
          ? const ExtrasEmpty(icon: Icons.cake_outlined, text: 'No dates yet', hint: 'Tap + to add birthdays and anniversaries. You get a reminder every year.')
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
              children: [
                for (final d in dates)
                  () {
                    final days = d.daysUntil(now);
                    final years = d.yearsOnNext(now);
                    final when = days == 0 ? 'Today 🎉' : days == 1 ? 'Tomorrow' : 'in $days days';
                    final today = days == 0;
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      color: today ? scheme.primary.withValues(alpha: 0.12) : null,
                      child: ListTile(
                        onTap: () => showDateEditor(context, ref, d),
                        leading: Text(_emoji(d.type), style: const TextStyle(fontSize: 28)),
                        title: Text(d.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text([
                          DateFormat('d MMMM').format(d.inYear(now.year)),
                          if (years != null && years > 0) d.type == 'Birthday' ? 'turns $years' : '$years years',
                        ].join('  ·  ')),
                        trailing: Text(
                          when,
                          style: TextStyle(fontWeight: FontWeight.w800, color: days <= 7 ? scheme.primary : null),
                        ),
                      ),
                    );
                  }(),
              ],
            ),
    );
  }
}

Future<void> showDateEditor(BuildContext context, WidgetRef ref, ImportantDate? date) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _DateEditor(date: date),
  );
}

class _DateEditor extends ConsumerStatefulWidget {
  final ImportantDate? date;
  const _DateEditor({this.date});

  @override
  ConsumerState<_DateEditor> createState() => _DateEditorState();
}

class _DateEditorState extends ConsumerState<_DateEditor> {
  late final _title = TextEditingController(text: widget.date?.title ?? '');
  late final _notes = TextEditingController(text: widget.date?.notes ?? '');
  late String _type = widget.date?.type ?? 'Birthday';
  late DateTime? _picked = widget.date == null
      ? null
      : DateTime(widget.date!.year ?? DateTime.now().year, widget.date!.month, widget.date!.day);
  late bool _knowYear = widget.date == null || widget.date!.year != null;
  late bool _dayBefore = widget.date?.remindDayBefore ?? true;

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    final picked = _picked;
    if (title.isEmpty || picked == null) {
      showTopToast(context, 'Enter a name and pick the date', icon: Icons.info, color: kToastBlue);
      return;
    }
    final d = ImportantDate(
      id: widget.date?.id,
      title: title,
      type: _type,
      month: picked.month,
      day: picked.day,
      year: _knowYear ? picked.year : null,
      remindDayBefore: _dayBefore,
      notes: _notes.text.trim(),
    );
    await NotificationService().requestPermissions();
    await ref.read(importantDatesProvider.notifier).save(d);
    if (!mounted) return;
    showTopToast(context, widget.date == null ? '$title added' : '$title updated');
    Navigator.pop(context);
  }

  Future<void> _delete() async {
    final d = widget.date!;
    if (!await confirmYesNo(context, 'Delete?', 'Delete ${d.title}?')) return;
    final notifier = ref.read(importantDatesProvider.notifier);
    await notifier.delete(d.id);
    if (!mounted) return;
    showTopToast(context, '${d.title} deleted', icon: Icons.delete, color: kToastRed, actionLabel: 'UNDO', onAction: () => notifier.save(d));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return ExtrasSheet(
      title: widget.date == null ? 'New date' : 'Edit date',
      onSave: _save,
      onDelete: widget.date == null ? null : _delete,
      children: [
        Wrap(
          spacing: 6,
          children: [
            for (final t in _types)
              ChoiceChip(label: Text('${_emoji(t)} $t'), selected: _type == t, onSelected: (_) => setState(() => _type = t)),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _title,
          autofocus: widget.date == null,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Name', hintText: "e.g. Amma's birthday", border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        DateField(label: 'Date', value: _picked, onChanged: (d) => setState(() => _picked = d)),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('I know the year'),
          subtitle: const Text('Shows the age / number of years'),
          value: _knowYear,
          onChanged: (v) => setState(() => _knowYear = v ?? false),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Remind me the day before'),
          subtitle: const Text('At 7 PM, plus 9 AM on the day'),
          value: _dayBefore,
          onChanged: (v) => setState(() => _dayBefore = v),
        ),
        TextField(controller: _notes, decoration: const InputDecoration(labelText: 'Notes (optional)', hintText: 'e.g. gift ideas', border: OutlineInputBorder())),
      ],
    );
  }
}
