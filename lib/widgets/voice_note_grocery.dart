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

class _VoiceGrocerySheetState extends ConsumerState<_VoiceGrocerySheet> {
  List<({String name, String quantity})> _items = [];
  final Set<int> _ticked = {};
  bool _listening = true;

  void _heard(String words) {
    final found = parseSpokenGrocery(words);
    setState(() {
      final start = _items.length;
      _items = [..._items, ...found];
      _ticked.addAll([for (var i = start; i < _items.length; i++) i]);
      _listening = false;
    });
  }

  Future<void> _add() async {
    final chosen = [for (final i in _ticked.toList()..sort()) _items[i]];
    if (chosen.isEmpty) {
      showTopToast(context, 'Tick the items to add', icon: Icons.info, color: kToastBlue);
      return;
    }
    final catalog = ref.read(groceryCatalogItemsProvider);
    final notifier = ref.read(groceryProvider.notifier);
    var added = 0;
    for (final it in chosen) {
      // Use the catalog's spelling, category and Telugu/Hindi names when known.
      final match = findCatalogItem(catalog, it.name);
      final result = await notifier.addItem(
        match?.name ?? it.name,
        quantity: it.quantity,
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
              if (_items.isEmpty) const Text("Didn't find any items. Tap Speak again."),
              for (var i = 0; i < _items.length; i++)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _ticked.contains(i),
                  onChanged: (v) => setState(() => v == true ? _ticked.add(i) : _ticked.remove(i)),
                  title: Text(_items[i].name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: _items[i].quantity.isEmpty ? null : Text(_items[i].quantity),
                ),
              const SizedBox(height: 12),
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
                  FilledButton(onPressed: _add, child: Text(_ticked.isEmpty ? 'Add' : 'Add ${_ticked.length}')),
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
