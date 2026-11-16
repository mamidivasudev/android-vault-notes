import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../widgets/top_toast.dart';
import 'extras_models.dart';
import 'extras_store.dart';
import 'extras_widgets.dart';

const _moods = ['😄', '🙂', '😐', '😔', '😠'];

class JournalView extends ConsumerStatefulWidget {
  const JournalView({super.key});

  @override
  ConsumerState<JournalView> createState() => _JournalViewState();
}

class _JournalViewState extends ConsumerState<JournalView> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Opens today's entry, creating it if there is none yet.
  void _openToday() {
    final today = dayKey(DateTime.now());
    final existing = ref.read(journalProvider).where((e) => dayKey(e.day) == today).firstOrNull;
    openJournalEntry(context, existing ?? JournalEntry(day: DateTime.now()));
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim().toLowerCase();
    final entries = ref.watch(journalProvider).where((e) => q.isEmpty || e.text.toLowerCase().contains(q)).toList()
      ..sort((a, b) {
        final byDay = b.day.compareTo(a.day);
        return byDay != 0 ? byDay : b.updatedAt.compareTo(a.updatedAt);
      });
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);

    return ExtrasScaffold(
      onAdd: _openToday,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search journal',
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
                    text: q.isEmpty ? 'No entries yet' : 'Nothing found',
                    hint: q.isEmpty ? 'Tap + to write about your day' : 'Try other words',
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
                    children: [
                      for (final e in entries)
                        Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => openJournalEntry(context, e),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(DateFormat('EEE, d MMM yyyy').format(e.day), style: const TextStyle(fontWeight: FontWeight.w700)),
                                      ),
                                      if (e.mood.isNotEmpty) Text(e.mood, style: const TextStyle(fontSize: 20)),
                                    ],
                                  ),
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
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

void openJournalEntry(BuildContext context, JournalEntry entry) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => _JournalEditor(entry: entry)));
}

/// Writing page. Saves automatically when you go back.
class _JournalEditor extends ConsumerStatefulWidget {
  final JournalEntry entry;
  const _JournalEditor({required this.entry});

  @override
  ConsumerState<_JournalEditor> createState() => _JournalEditorState();
}

class _JournalEditorState extends ConsumerState<_JournalEditor> {
  late final _text = TextEditingController(text: widget.entry.text);
  late DateTime _day = widget.entry.day;
  late String _mood = widget.entry.mood;
  bool _deleted = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  bool get _changed => _text.text != widget.entry.text || _mood != widget.entry.mood || dayKey(_day) != dayKey(widget.entry.day);

  Future<void> _saveIfNeeded() async {
    if (_deleted) return;
    final isNew = !ref.read(journalProvider).any((e) => e.id == widget.entry.id);
    // A brand-new entry left empty is not kept.
    if (isNew && _text.text.trim().isEmpty && _mood.isEmpty) return;
    if (!isNew && !_changed) return;
    await ref.read(journalProvider.notifier).save(widget.entry.copyWith(day: _day, text: _text.text, mood: _mood));
  }

  Future<void> _delete() async {
    final isNew = !ref.read(journalProvider).any((e) => e.id == widget.entry.id);
    if (!isNew && !await confirmYesNo(context, 'Delete?', 'Delete this journal entry?')) return;
    _deleted = true;
    final notifier = ref.read(journalProvider.notifier);
    final original = widget.entry;
    if (!isNew) await notifier.remove(original.id);
    if (!mounted) return;
    if (!isNew) {
      showTopToast(context, 'Entry deleted', icon: Icons.delete, color: kToastRed, actionLabel: 'UNDO', onAction: () => notifier.save(original));
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _saveIfNeeded();
      },
      child: Scaffold(
        appBar: AppBar(
          title: InkWell(
            onTap: () async {
              final picked = await showDatePicker(context: context, initialDate: _day, firstDate: DateTime(1900), lastDate: DateTime(2200));
              if (picked != null) setState(() => _day = picked);
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(DateFormat('EEE, d MMM yyyy').format(_day)),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_drop_down),
              ],
            ),
          ),
          actions: [
            IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline), onPressed: _delete),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (final m in _moods)
                      InkWell(
                        borderRadius: BorderRadius.circular(24),
                        onTap: () => setState(() => _mood = _mood == m ? '' : m),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _mood == m ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.15) : Colors.transparent,
                          ),
                          child: Text(m, style: TextStyle(fontSize: _mood == m ? 30 : 24)),
                        ),
                      ),
                  ],
                ),
                const Divider(),
                Expanded(
                  child: TextField(
                    controller: _text,
                    autofocus: widget.entry.text.isEmpty,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    keyboardType: TextInputType.multiline,
                    textCapitalization: TextCapitalization.sentences,
                    style: const TextStyle(fontSize: 16, height: 1.5),
                    decoration: const InputDecoration(hintText: 'How was your day?', border: InputBorder.none),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
