import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../providers.dart';
import '../utils/grocery_catalog.dart';
import 'top_toast.dart';
import 'voice_mic.dart';

// ── Notes ───────────────────────────────────────────────────────────────────

/// Speak a note: the words become the note text (title optional), shown first
/// so they can be corrected, then saved in the current category.
Future<void> showVoiceNote(BuildContext context) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _VoiceNoteSheet(),
    );

class _VoiceNoteSheet extends ConsumerStatefulWidget {
  const _VoiceNoteSheet();

  @override
  ConsumerState<_VoiceNoteSheet> createState() => _VoiceNoteSheetState();
}

class _VoiceNoteSheetState extends ConsumerState<_VoiceNoteSheet> {
  final _title = TextEditingController();
  final _text = TextEditingController();
  bool _listening = true; // mic shown; false = text shown for checking

  @override
  void dispose() {
    _title.dispose();
    _text.dispose();
    super.dispose();
  }

  void _heard(String words) {
    final sentence = words[0].toUpperCase() + words.substring(1);
    setState(() {
      // Speaking again adds to what is already there.
      _text.text = _text.text.trim().isEmpty ? sentence : '${_text.text.trim()} $sentence';
      _listening = false;
    });
  }

  Future<void> _save() async {
    final text = _text.text.trim();
    if (text.isEmpty) {
      showTopToast(context, 'Nothing to save yet', icon: Icons.info, color: kToastBlue);
      return;
    }
    final selected = ref.read(selectedCategoryProvider);
    final note = Note(title: _title.text.trim(), content: text, category: selected.isEmpty ? 'General' : selected);
    await ref.read(notesProvider.notifier).addNote(note);
    if (!mounted) return;
    showTopToast(context, 'Note saved');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return _Frame(
      title: 'Note by voice',
      children: _listening
          ? [VoiceMic(hint: 'Speak your note', onResult: _heard)]
          : [
              TextField(
                controller: _title,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Title (optional)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _text,
                minLines: 3,
                maxLines: 8,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Note', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.mic),
                    label: const Text('Speak more'),
                    onPressed: () => setState(() => _listening = true),
                  ),
                  const Spacer(),
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: _save, child: const Text('Save')),
                ],
              ),
            ],
    );
  }
}

// ── Grocery ─────────────────────────────────────────────────────────────────

/// "milk 1 litre, tomato 2 kg and bread" → three items with quantities.
List<({String name, String quantity})> parseSpokenGrocery(String spoken) {
  final parts = spoken
      .toLowerCase()
      .replaceAll(RegExp(r'^\s*(?:add|buy|get)\s+'), '')
      .split(RegExp(r'\s*(?:,|\band\b|\bthen\b|&|\balso\b)\s*'))
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty);
  final items = <({String name, String quantity})>[];
  for (final part in parts) {
    final parsed = parseGroceryInput(part);
    if (parsed.name.trim().isEmpty) continue;
    final name = parsed.name.trim();
    items.add((
      name: name[0].toUpperCase() + name.substring(1),
      quantity: [parsed.quantity, parsed.unit].where((s) => s.isNotEmpty).join(' '),
    ));
  }
  return items;
}

Future<void> showVoiceGrocery(BuildContext context) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _VoiceGrocerySheet(),
    );

class _VoiceGrocerySheet extends ConsumerStatefulWidget {
  const _VoiceGrocerySheet();

  @override
  ConsumerState<_VoiceGrocerySheet> createState() => _VoiceGrocerySheetState();
}

/// One heard item, editable before it is added.
class _HeardItem {
  final TextEditingController name;
  final TextEditingController quantity;
  bool ticked = true;
  _HeardItem(String n, String q)
      : name = TextEditingController(text: n),
        quantity = TextEditingController(text: q);
  void dispose() {
    name.dispose();
    quantity.dispose();
  }
}

class _VoiceGrocerySheetState extends ConsumerState<_VoiceGrocerySheet> {
  final List<_HeardItem> _items = [];
  bool _listening = true;

  int get _tickedCount => _items.where((i) => i.ticked && i.name.text.trim().isNotEmpty).length;

  @override
  void dispose() {
    for (final i in _items) {
      i.dispose();
    }
    super.dispose();
  }

  void _heard(String words) {
    setState(() {
      _items.addAll([for (final f in parseSpokenGrocery(words)) _HeardItem(f.name, f.quantity)]);
      _listening = false;
    });
  }

  Future<void> _add() async {
    final chosen = _items.where((i) => i.ticked && i.name.text.trim().isNotEmpty).toList();
    if (chosen.isEmpty) {
      showTopToast(context, 'Tick the items to add', icon: Icons.info, color: kToastBlue);
      return;
    }
    final catalog = ref.read(groceryCatalogItemsProvider);
    final notifier = ref.read(groceryProvider.notifier);
    var added = 0;
    for (final it in chosen) {
      final name = it.name.text.trim();
      // Use the catalog's spelling, category and Telugu/Hindi names when known.
      final match = findCatalogItem(catalog, name);
      final result = await notifier.addItem(
        match?.name ?? teluguAlias(name) ?? name,
        quantity: it.quantity.text.trim(),
        category: match?.category ?? '',
        localName: match?.localName ?? '',
      );
      if (result != GroceryAddResult.alreadyOnList && result != GroceryAddResult.ignored) added++;
    }
    if (!mounted) return;
    showTopToast(context, added == 0 ? 'Already on your list' : '$added item${added == 1 ? '' : 's'} added',
        icon: added == 0 ? Icons.info : Icons.check_circle, color: added == 0 ? kToastBlue : kToastGreen);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return _Frame(
      title: 'Grocery by voice',
      children: _listening
          ? [VoiceMic(hint: 'Say items, e.g. "milk 1 litre, tomato 2 kg and bread"', onResult: _heard)]
          : [
              if (_items.isEmpty) const Text("Didn't find any items. Tap Speak more."),
              // Each item can be corrected before adding: tick, name, quantity, remove.
              for (final it in _items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Checkbox(value: it.ticked, onChanged: (v) => setState(() => it.ticked = v ?? false)),
                      Expanded(
                        child: TextField(
                          controller: it.name,
                          textCapitalization: TextCapitalization.sentences,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(labelText: 'Item', isDense: true, border: OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 96,
                        child: TextField(
                          controller: it.quantity,
                          decoration: const InputDecoration(labelText: 'Qty', hintText: '1 kg', isDense: true, border: OutlineInputBorder()),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setState(() {
                          _items.remove(it);
                          it.dispose();
                        }),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 4),
              Row(
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.mic),
                    label: const Text('Speak more'),
                    onPressed: () => setState(() => _listening = true),
                  ),
                  const Spacer(),
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: _add, child: Text(_tickedCount == 0 ? 'Add' : 'Add $_tickedCount')),
                ],
              ),
            ],
    );
  }
}

class _Frame extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Frame({required this.title, required this.children});

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewPaddingOf(context).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              ...children,
            ],
          ),
        ),
      );
}
