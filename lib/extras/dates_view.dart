import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../notification_service.dart';
import '../widgets/top_toast.dart';
import 'extras_models.dart';
import 'extras_store.dart';
import 'extras_widgets.dart';

/// Built-in categories, in the order they are offered. Household counts days
/// since the date; the others come round every year.
const _builtIn = [
  DateCategory(name: 'Household', since: true),
  DateCategory(name: 'Birthday'),
  DateCategory(name: 'Anniversary'),
  DateCategory(name: 'Other'),
];

String _emoji(String type) => switch (type) {
      'Household' => '🏠',
      'Birthday' => '🎂',
      'Anniversary' => '💍',
      'Other' => '📅',
      _ => '📌',
    };

/// Months and days from [start] to [end] (both dates only), e.g. "5 months - 25 days".
String _span(DateTime start, DateTime end) {
  var months = end.month - start.month + 12 * (end.year - start.year);
  var days = end.day - start.day;
  if (days < 0) {
    months--;
    days += DateTime(end.year, end.month, 0).day; // days in the month before [end]
  }
  return [
    if (months > 0) '$months month${months == 1 ? '' : 's'}',
    if (days > 0) '$days day${days == 1 ? '' : 's'}',
  ].join(' - ');
}

/// "4 days", "1 month - 3 days" since [from] (today = "Today").
String _since(DateTime from) {
  final now = DateTime.now();
  final start = DateTime(from.year, from.month, from.day);
  final today = DateTime(now.year, now.month, now.day);
  if (!start.isBefore(today)) return 'Today';
  var months = today.month - start.month + 12 * (today.year - start.year);
  var days = today.day - start.day;
  if (days < 0) {
    months--;
    days += DateTime(today.year, today.month, 0).day;
  }
  return [
    if (months > 0) '$months month${months == 1 ? '' : 's'}',
    if (days > 0) '$days day${days == 1 ? '' : 's'}',
  ].join(' - ');
}

class ImportantDatesView extends ConsumerStatefulWidget {
  const ImportantDatesView({super.key});

  @override
  ConsumerState<ImportantDatesView> createState() => _ImportantDatesViewState();
}

class _ImportantDatesViewState extends ConsumerState<ImportantDatesView> {
  final Set<String> _selected = {};
  bool _selecting = false;

  void _startSelecting(String id) => setState(() {
        _selecting = true;
        _selected.add(id);
      });

  void _toggle(String id) => setState(() => _selected.contains(id) ? _selected.remove(id) : _selected.add(id));

  void _stopSelecting() => setState(() {
        _selecting = false;
        _selected.clear();
      });

  Future<void> _deleteSelected(List<ImportantDate> all) async {
    if (_selected.isEmpty) {
      showTopToast(context, 'Tick the dates to delete first', icon: Icons.info, color: kToastBlue);
      return;
    }
    final n = _selected.length;
    if (!await confirmYesNo(context, 'Delete?', 'Delete $n date${n == 1 ? '' : 's'}?')) return;
    final removed = all.where((d) => _selected.contains(d.id)).toList();
    final notifier = ref.read(importantDatesProvider.notifier);
    await notifier.deleteMany({..._selected});
    if (!mounted) return;
    _stopSelecting();
    showTopToast(context, '$n date${n == 1 ? '' : 's'} deleted',
        icon: Icons.delete, color: kToastRed, actionLabel: 'UNDO', onAction: () => notifier.restoreMany(removed));
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final all = ref.watch(importantDatesProvider);
    final scheme = Theme.of(context).colorScheme;

    // "Since" items first (Household, then any own "since" categories), then yearly ones.
    final sinceGroups = <String, List<ImportantDate>>{};
    for (final d in all.where((d) => d.isHousehold)) {
      sinceGroups.putIfAbsent(d.type, () => []).add(d);
    }
    final sinceOrder = sinceGroups.keys.toList()..sort((a, b) => a == 'Household' ? -1 : b == 'Household' ? 1 : a.compareTo(b));
    for (final list in sinceGroups.values) {
      list.sort((a, b) => b.startDate.compareTo(a.startDate));
    }
    final yearly = all.where((d) => !d.isHousehold).toList()..sort((a, b) => a.daysUntil(now).compareTo(b.daysUntil(now)));

    Widget tile(ImportantDate d) {
      final selected = _selected.contains(d.id);
      final String subtitle;
      final String trailing;
      var highlight = false;
      if (d.isHousehold) {
        subtitle = [
          'Since ${DateFormat('d MMM yyyy').format(d.startDate)}',
          if (d.remindOn != null) 'Reminder ${DateFormat('d MMM yyyy').format(d.remindOn!)}',
        ].join('\n'); // one per line
        trailing = _since(d.startDate);
      } else {
        final days = d.daysUntil(now);
        final years = d.yearsOnNext(now);
        highlight = days == 0;
        // Date (with the year when known), then the age / number of years, one per line.
        subtitle = [
          d.year == null
              ? DateFormat('d MMMM').format(d.inYear(now.year))
              : DateFormat('d MMMM yyyy').format(DateTime(d.year!, d.month, d.day)),
          if (years != null && years > 0) '$years year${years == 1 ? '' : 's'}',
        ].join('\n');
        trailing = days == 0
            ? 'Today 🎉'
            : days == 1
                ? 'Tomorrow'
                : 'in ${_span(DateUtils.dateOnly(now), d.nextFrom(now))}'; // "in 24 days" / "in 5 months - 25 days"
      }
      return Card(
        margin: const EdgeInsets.symmetric(vertical: 3),
        color: selected ? scheme.primary.withValues(alpha: 0.15) : highlight ? scheme.primary.withValues(alpha: 0.10) : null,
        child: ListTile(
          onTap: () => _selecting ? _toggle(d.id) : showDateEditor(context, ref, d),
          onLongPress: () => _selecting ? _toggle(d.id) : _startSelecting(d.id),
          leading: _selecting
              ? Checkbox(value: selected, onChanged: (_) => _toggle(d.id))
              : Text(_emoji(d.type), style: const TextStyle(fontSize: 28)),
          title: Text(d.title, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(subtitle),
              // Notes as one light-blue line, like on expense cards.
              if (d.notes.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    d.notes,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Color(0xFF60A5FA), fontSize: 13),
                  ),
                ),
            ],
          ),
          trailing: Text(trailing, style: TextStyle(fontWeight: FontWeight.w800, color: scheme.primary)),
        ),
      );
    }

    final allSelected = all.isNotEmpty && _selected.length == all.length;
    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _stopSelecting();
      },
      child: ExtrasScaffold(
        onAdd: () => showDateEditor(context, ref, null),
        child: Column(
          children: [
            if (_selecting)
              Material(
                color: scheme.primary.withValues(alpha: 0.08),
                child: Row(
                  children: [
                    IconButton(tooltip: 'Cancel', icon: const Icon(Icons.close), onPressed: _stopSelecting),
                    Expanded(child: Text('${_selected.length} selected', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
                    IconButton(
                      tooltip: 'Select all',
                      icon: Icon(allSelected ? Icons.check_box : Icons.check_box_outline_blank),
                      onPressed: () => setState(() {
                        allSelected ? _selected.clear() : _selected.addAll(all.map((d) => d.id));
                      }),
                    ),
                    IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => _deleteSelected(all)),
                  ],
                ),
              ),
            Expanded(
              child: all.isEmpty
                  ? const ExtrasEmpty(
                      icon: Icons.event_outlined,
                      text: 'No dates yet',
                      hint: 'Tap + to add household items (like gas used date), birthdays or anniversaries.',
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                      children: [
                        for (final type in sinceOrder) ...[
                          ExtrasHeading(type),
                          for (final d in sinceGroups[type]!) tile(d),
                          const SizedBox(height: 8),
                        ],
                        if (yearly.isNotEmpty) ...[
                          if (sinceOrder.isNotEmpty) const ExtrasHeading('Upcoming'),
                          for (final d in yearly) tile(d),
                        ],
                      ],
                    ),
            ),
          ],
        ),
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
  late DateCategory _category = widget.date == null
      ? _builtIn.first
      : DateCategory(name: widget.date!.type, since: widget.date!.since);
  // A new date starts on today; it can be changed before saving.
  late DateTime? _picked = widget.date == null
      ? DateUtils.dateOnly(DateTime.now())
      : DateTime(widget.date!.year ?? DateTime.now().year, widget.date!.month, widget.date!.day);
  // Off for new dates: the picker starts on today, so its year is usually not the real birth year.
  late bool _knowYear = widget.date != null && widget.date!.year != null;
  late bool _dayBefore = widget.date?.remindDayBefore ?? true;
  late DateTime? _remindOn = widget.date?.remindOn;

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
    // Changing a saved date asks first.
    if (widget.date != null && !await confirmYesNo(context, 'Update?', 'Save the changes to $title?')) return;
    if (!mounted) return;
    final since = _category.since;
    final d = ImportantDate(
      id: widget.date?.id,
      title: title,
      type: _category.name,
      since: since,
      month: picked.month,
      day: picked.day,
      year: since || _knowYear ? picked.year : null, // "since" items need the full date
      remindDayBefore: _dayBefore,
      notes: _notes.text.trim(),
      remindOn: since ? _remindOn : null,
    );
    if (!since || _remindOn != null) await NotificationService().requestPermissions();
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

  /// "Started again today" (a new gas cylinder / oil packet): fills the form
  /// with today, keeping the reminder the same gap ahead. Saved with Update.
  void _restartToday() {
    final today = DateUtils.dateOnly(DateTime.now());
    final start = _picked;
    final remind = _remindOn;
    final gap = start == null || remind == null ? null : DateUtils.dateOnly(remind).difference(DateUtils.dateOnly(start)).inDays;
    setState(() {
      _picked = today;
      if (gap != null) _remindOn = today.add(Duration(days: gap));
    });
    showTopToast(context, 'Set to today — tap Update to save', icon: Icons.restart_alt, color: kToastBlue);
  }

  Future<void> _newCategory() async {
    final name = TextEditingController();
    var since = false;
    final created = await showDialog<DateCategory>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: const Text('New category'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. Vehicle, Bills, Health', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              RadioGroup<bool>(
                groupValue: since,
                onChanged: (v) => setDialog(() => since = v ?? false),
                child: const Column(
                  children: [
                    RadioListTile<bool>(
                      contentPadding: EdgeInsets.zero,
                      value: false,
                      title: Text('Repeats every year'),
                      subtitle: Text('Like a birthday, with reminders'),
                    ),
                    RadioListTile<bool>(
                      contentPadding: EdgeInsets.zero,
                      value: true,
                      title: Text('Counts days since'),
                      subtitle: Text('Like Household: "Since 12 Nov · 4 days"'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final n = name.text.trim();
                if (n.isNotEmpty) Navigator.pop(ctx, DateCategory(name: n, since: since));
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
    if (created == null || !mounted) return;
    final taken = [..._builtIn, ...ref.read(dateCategoriesProvider)].any((c) => c.name.toLowerCase() == created.name.toLowerCase());
    if (taken) {
      showTopToast(context, '${created.name} already exists', icon: Icons.info, color: kToastBlue);
      return;
    }
    await ref.read(dateCategoriesProvider.notifier).save(created);
    if (mounted) setState(() => _category = created);
  }

  Future<void> _deleteCategory(DateCategory c) async {
    if (!await confirmYesNo(context, 'Delete category?', 'Remove "${c.name}"? Dates already saved in it are kept.')) return;
    await ref.read(dateCategoriesProvider.notifier).remove(c.name.toLowerCase());
    if (mounted && _category.name == c.name) setState(() => _category = _builtIn.first);
  }

  @override
  Widget build(BuildContext context) {
    final own = ref.watch(dateCategoriesProvider);
    final categories = [
      ..._builtIn,
      ...own,
      // An old date whose category was removed still shows its own chip.
      if (![..._builtIn, ...own].any((c) => c.name == _category.name)) _category,
    ];
    final since = _category.since;
    return ExtrasSheet(
      title: widget.date == null ? 'New date' : 'Edit date',
      onSave: _save,
      saveLabel: widget.date == null ? 'Save' : 'Update',
      onDelete: widget.date == null ? null : _delete,
      children: [
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final c in categories)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GestureDetector(
                    // Long-press your own categories to remove them.
                    onLongPress: own.contains(c) ? () => _deleteCategory(c) : null,
                    child: ChoiceChip(
                      label: Text('${_emoji(c.name)} ${c.name}'),
                      selected: _category.name == c.name,
                      onSelected: (_) => setState(() => _category = c),
                    ),
                  ),
                ),
              ActionChip(avatar: const Icon(Icons.add, size: 18), label: const Text('New'), onPressed: _newCategory),
            ],
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _title,
          autofocus: widget.date == null,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: 'Name',
            hintText: since ? 'e.g. Gas used date' : "e.g. Amma's birthday",
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        DateField(label: since ? 'Started on' : 'Date', value: _picked, onChanged: (d) => setState(() => _picked = d)),
        if (since) ...[
          const SizedBox(height: 12),
          DateField(
            label: 'Reminder date (optional)',
            value: _remindOn,
            clearable: true,
            onChanged: (d) => setState(() => _remindOn = d),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Text('A notification at 9 AM on this day',
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
          ),
        ],
        if (since && widget.date != null && widget.date!.isHousehold) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(icon: const Icon(Icons.restart_alt), label: const Text('Started again today'), onPressed: _restartToday),
        ],
        if (since) const SizedBox(height: 12),
        if (!since)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('I know the year'),
            subtitle: const Text('Shows the age / number of years'),
            value: _knowYear,
            onChanged: (v) => setState(() => _knowYear = v ?? false),
          ),
        if (!since)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Remind me the day before'),
            subtitle: const Text('At 7 PM, plus 9 AM on the day'),
            value: _dayBefore,
            onChanged: (v) => setState(() => _dayBefore = v),
          ),
        TextField(controller: _notes, decoration: const InputDecoration(labelText: 'Notes (optional)', border: OutlineInputBorder())),
      ],
    );
  }
}
