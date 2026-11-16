import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../widgets/top_toast.dart';
import 'extras_models.dart';
import 'extras_store.dart';
import 'extras_widgets.dart';

class JournalView extends ConsumerStatefulWidget {
  const JournalView({super.key});

  @override
  ConsumerState<JournalView> createState() => _JournalViewState();
}

class _JournalViewState extends ConsumerState<JournalView> {
  final _search = TextEditingController();
  final Set<String> _selected = {};
  bool _selecting = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// A new entry dated now (the date and time can be changed for a past entry).
  void _newEntry() => openJournalEntry(context, JournalEntry(day: DateTime.now()));

  void _toggle(String id) => setState(() => _selected.contains(id) ? _selected.remove(id) : _selected.add(id));

  void _stopSelecting() => setState(() {
        _selecting = false;
        _selected.clear();
      });

  Future<void> _deleteSelected(List<JournalEntry> all) async {
    if (_selected.isEmpty) {
      showTopToast(context, 'Tick the entries to delete first', icon: Icons.info, color: kToastBlue);
      return;
    }
    final n = _selected.length;
    if (!await confirmYesNo(context, 'Delete?', 'Delete $n diary entr${n == 1 ? 'y' : 'ies'}?')) return;
    final removed = all.where((e) => _selected.contains(e.id)).toList();
    final notifier = ref.read(journalProvider.notifier);
    await notifier.removeMany({..._selected});
    if (!mounted) return;
    _stopSelecting();
    showTopToast(context, '$n entr${n == 1 ? 'y' : 'ies'} deleted',
        icon: Icons.delete, color: kToastRed, actionLabel: 'UNDO', onAction: () => notifier.restoreMany(removed));
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(journalProvider);
    final q = _search.text.trim().toLowerCase();
    final entries = all.where((e) => q.isEmpty || e.text.toLowerCase().contains(q)).toList()
      ..sort((a, b) {
        final byDay = b.day.compareTo(a.day);
        return byDay != 0 ? byDay : b.updatedAt.compareTo(a.updatedAt);
      });
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurface.withValues(alpha: 0.6);
    final allSelected = entries.isNotEmpty && entries.every((e) => _selected.contains(e.id));

    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _stopSelecting();
      },
      child: ExtrasScaffold(
        onAdd: _newEntry,
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
                        allSelected ? _selected.clear() : _selected.addAll(entries.map((e) => e.id));
                      }),
                    ),
                    IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => _deleteSelected(all)),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search diary',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: q.isEmpty ? null : IconButton(icon: const Icon(Icons.close), onPressed: () => setState(_search.clear)),
                    isDense: true,
                    filled: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                  ),
                ),
              ),
            Expanded(
              child: entries.isEmpty
                  ? ExtrasEmpty(
                      icon: Icons.menu_book_outlined,
                      text: q.isEmpty ? 'No diary entries yet' : 'Nothing found',
                      hint: q.isEmpty ? 'Tap + to write about your day' : 'Try other words',
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
                      children: [
                        for (final e in entries)
                          Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            color: _selected.contains(e.id) ? scheme.primary.withValues(alpha: 0.15) : null,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => _selecting ? _toggle(e.id) : openJournalEntry(context, e),
                              onLongPress: () => _selecting
                                  ? _toggle(e.id)
                                  : setState(() {
                                      _selecting = true;
                                      _selected.add(e.id);
                                    }),
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (_selecting)
                                      Padding(
                                        padding: const EdgeInsets.only(right: 8),
                                        child: Checkbox(value: _selected.contains(e.id), onChanged: (_) => _toggle(e.id)),
                                      ),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(_when(e.day), style: const TextStyle(fontWeight: FontWeight.w700)),
                                          const SizedBox(height: 6),
                                          Text(
                                            e.text.isEmpty ? 'Empty entry' : e.text,
                                            maxLines: 3,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(color: e.text.isEmpty ? muted : null, height: 1.4),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Mon, 16 Nov 2026 · 5:30 PM" (older entries saved without a time show the date only).
String _when(DateTime d) {
  final date = DateFormat('EEE, d MMM yyyy').format(d);
  return d.hour == 0 && d.minute == 0 ? date : '$date · ${DateFormat('h:mm a').format(d)}';
}

void openJournalEntry(BuildContext context, JournalEntry entry) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => _JournalEditor(entry: entry)));
}

/// Writing page. New entry: Clear / Save. Saved entry: Delete / Update (asks first).
class _JournalEditor extends ConsumerStatefulWidget {
  final JournalEntry entry;
  const _JournalEditor({required this.entry});

  @override
  ConsumerState<_JournalEditor> createState() => _JournalEditorState();
}

class _JournalEditorState extends ConsumerState<_JournalEditor> {
  late final _text = TextEditingController(text: widget.entry.text);
  late DateTime _day = widget.entry.day;
  late final bool _isNew = !ref.read(journalProvider).any((e) => e.id == widget.entry.id);
  bool _done = false; // saved, updated or deleted: leave without asking

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  bool get _changed => _isNew ? _text.text.trim().isNotEmpty : (_text.text != widget.entry.text || _day != widget.entry.day);

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(context: context, initialDate: _day, firstDate: DateTime(1900), lastDate: DateTime(2200));
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_day));
    final t = time ?? TimeOfDay.fromDateTime(_day);
    setState(() => _day = DateTime(date.year, date.month, date.day, t.hour, t.minute));
  }

  Future<void> _write() => ref.read(journalProvider.notifier).save(widget.entry.copyWith(day: _day, text: _text.text));

  Future<void> _save() async {
    if (_text.text.trim().isEmpty) {
      showTopToast(context, 'Write something first', icon: Icons.info, color: kToastBlue);
      return;
    }
    await _write();
    if (!mounted) return;
    _done = true;
    showTopToast(context, 'Diary saved');
    Navigator.pop(context);
  }

  Future<void> _update() async {
    if (!_changed) {
      Navigator.pop(context);
      return;
    }
    if (!await confirmYesNo(context, 'Update?', 'Save the changes to this diary entry?')) return;
    await _write();
    if (!mounted) return;
    _done = true;
    showTopToast(context, 'Diary updated', icon: Icons.edit, color: kToastBlue);
    Navigator.pop(context);
  }

  Future<void> _clear() async {
    if (_text.text.isEmpty) return;
    if (!await confirmYesNo(context, 'Clear?', 'Clear all the text?')) return;
    _text.clear();
  }

  Future<void> _delete() async {
    if (!await confirmYesNo(context, 'Delete?', 'Delete this diary entry?')) return;
    final notifier = ref.read(journalProvider.notifier);
    final original = widget.entry;
    await notifier.remove(original.id);
    if (!mounted) return;
    _done = true;
    showTopToast(context, 'Diary entry deleted', icon: Icons.delete, color: kToastRed, actionLabel: 'UNDO', onAction: () => notifier.save(original));
    Navigator.pop(context);
  }

  /// Going back with unsaved writing asks whether to keep it.
  Future<void> _onBack() async {
    final keep = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_isNew ? 'Save this entry?' : 'Save changes?'),
        content: const Text('You have unsaved writing.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes')),
        ],
      ),
    );
    if (keep == null || !mounted) return; // dialog dismissed: stay
    if (keep) await _write();
    if (!mounted) return;
    _done = true;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _done || !_changed,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        appBar: AppBar(
          // Date and time of the entry; tap to change it (for a past day).
          title: InkWell(
            onTap: _pickDateTime,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: Text(_when(_day), style: const TextStyle(fontSize: 16), overflow: TextOverflow.ellipsis)),
                const Icon(Icons.arrow_drop_down),
              ],
            ),
          ),
          actions: [
            if (_isNew) ...[
              TextButton(onPressed: _clear, child: const Text('Clear')),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilledButton(onPressed: _save, child: const Text('Save')),
              ),
            ] else ...[
              IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: _delete),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilledButton(onPressed: _update, child: const Text('Update')),
              ),
            ],
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _text,
              autofocus: true, // keyboard opens straight away
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(fontSize: 16, height: 1.5),
              decoration: const InputDecoration(hintText: 'Write your diary…', border: InputBorder.none),
            ),
          ),
        ),
      ),
    );
  }
}
