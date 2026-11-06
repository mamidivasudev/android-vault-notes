import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../models.dart';
import '../providers.dart';
import '../utils/grocery_catalog.dart';
import '../utils/undo_helpers.dart';

const _green = Color(0xFF16A34A);

/// Shopping list: one list grouped by category, quick add with catalog
/// suggestions, "Buy again" from history and a collapsible "Bought" section.
class GroceryView extends ConsumerStatefulWidget {
  const GroceryView({super.key});

  @override
  ConsumerState<GroceryView> createState() => _GroceryViewState();
}

class _GroceryViewState extends ConsumerState<GroceryView> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  bool _showBought = true;

  @override
  void initState() {
    super.initState();
    _input.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  // ── Adding ────────────────────────────────────────────────────────────────

  /// Quantity the user already typed ("tomato 1 kg" → "1 kg").
  String _typedQuantity() {
    final parsed = parseGroceryInput(_input.text);
    return [parsed.quantity, parsed.unit].where((p) => p.isNotEmpty).join(' ');
  }

  /// Adds the typed text. Items not found in the catalog can be saved to it.
  Future<void> _addTyped() async {
    final parsed = parseGroceryInput(_input.text);
    if (parsed.name.isEmpty) return;
    final match = findCatalogItem(ref.read(groceryCatalogItemsProvider), parsed.name);
    await _pickQuantityAndAdd(
      match?.name ?? _capitalise(parsed.name),
      category: match?.category ?? '',
      localName: match?.localName ?? '',
      offerSave: match == null,
    );
  }

  Future<void> _addCatalog(CatalogItem item) =>
      _pickQuantityAndAdd(item.name, category: item.category, localName: item.localName, offerSave: false);

  /// Asks for a free-text quantity, then adds the item.
  Future<void> _pickQuantityAndAdd(
    String name, {
    required String category,
    required String localName,
    required bool offerSave,
  }) async {
    final already = ref.read(groceryProvider).any((i) => !i.isPurchased && i.name.toLowerCase() == name.toLowerCase());
    if (already) {
      _input.clear();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('$name is already on your list'), duration: const Duration(seconds: 2)));
      return;
    }
    final answer = await askGroceryQuantity(
      context,
      name,
      initialQuantity: _typedQuantity(),
      localName: localName,
      offerSave: offerSave,
    );
    if (answer == null || !mounted) return;
    if (answer.saveToCatalog) {
      await ref.read(groceryCatalogProvider.notifier).addCustomItem(name, '', '', category: 'Other');
    }
    await _add(name, quantity: answer.quantity, category: category, localName: localName);
  }

  Future<void> _add(
    String name, {
    String quantity = '',
    String category = '',
    String localName = '',
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await ref.read(groceryProvider.notifier).addItem(
          name,
          quantity: quantity,
          category: category,
          localName: localName,
        );
    if (!mounted) return;
    HapticFeedback.selectionClick();
    _input.clear();
    _focus.requestFocus(); // keep the keyboard up for the next item
    final message = switch (result) {
      GroceryAddResult.added => null, // the item appearing is feedback enough
      GroceryAddResult.alreadyOnList => '$name is already on your list',
      GroceryAddResult.movedBack => '$name moved back to your list',
      GroceryAddResult.ignored => null,
    };
    if (message != null) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 2)));
    }
  }

  static String _capitalise(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  // ── List actions ──────────────────────────────────────────────────────────

  void _share(List<GroceryItem> items) {
    final toBuy = items.where((i) => !i.isPurchased).toList();
    if (toBuy.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nothing to buy — the list is empty')));
      return;
    }
    final buffer = StringBuffer('🛒 Shopping list (${toBuy.length})\n');
    buffer.writeln();
    for (final i in toBuy) {
      buffer.writeln('☐ ${i.name}${i.quantityLabel.isNotEmpty ? ' — ${i.quantityLabel}' : ''}');
    }
    Share.share(buffer.toString().trim());
  }

  /// Yes / No question; runs [run] only on Yes.
  Future<void> _confirm(String title, String message, Future<void> Function() run) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes')),
        ],
      ),
    );
    if (ok == true && mounted) await run();
  }

  void _clearBought(List<GroceryItem> items) {
    final ids = items.where((i) => i.isPurchased).map((i) => i.id).toSet();
    if (ids.isEmpty) return;
    _confirm(
      'Clear bought items?',
      'Remove ${ids.length} bought item${ids.length == 1 ? '' : 's'} from the list?',
      () async => deleteGroceryWithUndo(context, ref, ids),
    );
  }

  void _onMenu(String value, List<GroceryItem> items) {
    switch (value) {
      case 'share':
        _share(items);
        break;
      case 'shopAgain':
        _confirm('Shop again?', 'Move every bought item back to the list?',
            () => ref.read(groceryProvider.notifier).uncheckAll());
        break;
      case 'clearBought':
        _clearBought(items);
        break;
      case 'clearAll':
        if (items.isEmpty) return;
        _confirm(
          'Clear the whole list?',
          'Remove all ${items.length} item${items.length == 1 ? '' : 's'}?',
          () async => deleteGroceryWithUndo(context, ref, items.map((i) => i.id).toSet()),
        );
        break;
      case 'catalog':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const GroceryMasterListView()));
        break;
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(groceryProvider);
    final toBuy = items.where((i) => !i.isPurchased).toList();
    final bought = items.where((i) => i.isPurchased).toList()
      ..sort((a, b) => (b.purchasedAt ?? b.createdAt).compareTo(a.purchasedAt ?? a.createdAt));
    final typing = _input.text.trim().isNotEmpty;

    return Column(
      children: [
        _buildHeader(items, toBuy, bought),
        _buildInput(),
        Expanded(
          child: typing ? _buildSuggestions(items) : _buildList(items, toBuy, bought),
        ),
      ],
    );
  }

  Widget _buildHeader(List<GroceryItem> items, List<GroceryItem> toBuy, List<GroceryItem> bought) {
    final scheme = Theme.of(context).colorScheme;
    final total = items.length;
    final progress = total == 0 ? 0.0 : bought.length / total;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 4, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  total == 0
                      ? 'Your list is empty'
                      : toBuy.isEmpty
                          ? 'All ${bought.length} bought 🎉'
                          : '${toBuy.length} to buy · ${bought.length} bought',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: scheme.onSurface.withValues(alpha: 0.08),
                    valueColor: const AlwaysStoppedAnimation(_green),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Share list',
            icon: const Icon(Icons.share_outlined),
            onPressed: () => _share(items),
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (v) => _onMenu(v, items),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'catalog', child: ListTile(leading: Icon(Icons.menu_book_outlined), title: Text('Browse catalog'), contentPadding: EdgeInsets.zero)),
              if (bought.isNotEmpty)
                const PopupMenuItem(value: 'shopAgain', child: ListTile(leading: Icon(Icons.replay), title: Text('Shop again'), contentPadding: EdgeInsets.zero)),
              if (bought.isNotEmpty)
                const PopupMenuItem(value: 'clearBought', child: ListTile(leading: Icon(Icons.playlist_remove), title: Text('Clear bought'), contentPadding: EdgeInsets.zero)),
              if (items.isNotEmpty)
                const PopupMenuItem(value: 'clearAll', child: ListTile(leading: Icon(Icons.delete_sweep_outlined, color: Colors.red), title: Text('Clear whole list'), contentPadding: EdgeInsets.zero)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInput() {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: TextField(
        controller: _input,
        focusNode: _focus,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _addTyped(),
        decoration: InputDecoration(
          hintText: 'Add item — e.g. tomato 1 kg',
          prefixIcon: const Icon(Icons.add_shopping_cart),
          suffixIcon: _input.text.isEmpty
              ? null
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(icon: const Icon(Icons.close), tooltip: 'Clear', onPressed: _input.clear),
                    IconButton(
                      icon: const Icon(Icons.check_circle, color: _green),
                      tooltip: 'Add',
                      onPressed: _addTyped,
                    ),
                  ],
                ),
          filled: true,
          fillColor: scheme.onSurface.withValues(alpha: 0.05),
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
        ),
      ),
    );
  }

  // ── Suggestions while typing ──────────────────────────────────────────────

  Widget _buildSuggestions(List<GroceryItem> items) {
    final catalog = ref.watch(groceryCatalogItemsProvider);
    final parsed = parseGroceryInput(_input.text);
    final matches = searchCatalog(catalog, parsed.name);
    final onList = {for (final i in items) i.name.toLowerCase(): i};
    final exact = matches.any((m) => m.name.toLowerCase() == parsed.name.toLowerCase());
    final typedLabel = [parsed.quantity, parsed.unit].where((p) => p.isNotEmpty).join(' ');

    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (!exact)
          ListTile(
            leading: const CircleAvatar(backgroundColor: _green, child: Icon(Icons.add, color: Colors.white)),
            title: Text('Add "${_capitalise(parsed.name)}"', style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(matches.isEmpty
                ? 'Not found — you can save it to your items for next time'
                : 'Add exactly what you typed'),
            onTap: _addTyped,
          ),
        for (final m in matches)
          _SuggestionTile(
            item: m,
            existing: onList[m.name.toLowerCase()],
            quantityHint: typedLabel.isNotEmpty ? typedLabel : null,
            onTap: () => _addCatalog(m),
            onRemove: (id) => deleteGroceryWithUndo(context, ref, {id}),
          ),
        if (matches.isEmpty && catalog.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }

  // ── The list ──────────────────────────────────────────────────────────────

  Widget _buildList(List<GroceryItem> items, List<GroceryItem> toBuy, List<GroceryItem> bought) {
    final selected = ref.watch(selectedGroceryProvider);
    final selecting = selected.isNotEmpty || ref.watch(isSelectionModeProvider);

    if (items.isEmpty) {
      return ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const SizedBox(height: 40),
          Icon(Icons.shopping_basket_outlined, size: 72, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.25)),
          const SizedBox(height: 12),
          const Center(child: Text('Nothing on your list', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
          const SizedBox(height: 6),
          Center(
            child: Text(
              'Type above to add items, or browse the catalog.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.menu_book_outlined),
              label: const Text('Browse catalog'),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GroceryMasterListView())),
            ),
          ),
        ],
      );
    }

    Widget row(GroceryItem item) => _GroceryRow(
          key: ValueKey(item.id),
          item: item,
          selecting: selecting,
          selected: selected.contains(item.id),
          onToggle: () {
            if (selecting) {
              ref.read(selectedGroceryProvider.notifier).toggle(item.id);
            } else {
              HapticFeedback.lightImpact();
              ref.read(groceryProvider.notifier).toggleItem(item.id);
            }
          },
          onLongPress: () {
            if (!selecting) {
              ref.read(isSelectionModeProvider.notifier).setState(true);
              ref.read(selectedGroceryProvider.notifier).toggle(item.id);
            }
          },
          onEdit: () => showGroceryItemEditor(context, ref, item),
          onDelete: () => deleteGroceryWithUndo(context, ref, {item.id}),
        );

    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        if (toBuy.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: Text('Everything is bought ✓', style: TextStyle(color: _green.withValues(alpha: 0.9), fontWeight: FontWeight.w600)),
            ),
          ),
        // One plain list in the order items were added (no category headings).
        for (final item in toBuy) row(item),
        if (bought.isNotEmpty) ...[
          const SizedBox(height: 8),
          InkWell(
            onTap: () => setState(() => _showBought = !_showBought),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
              child: Row(
                children: [
                  Icon(_showBought ? Icons.expand_less : Icons.expand_more, size: 20),
                  const SizedBox(width: 6),
                  Text('Bought (${bought.length})', style: const TextStyle(fontWeight: FontWeight.w700)),
                  const Spacer(),
                  TextButton(onPressed: () => _clearBought(items), child: const Text('Clear')),
                ],
              ),
            ),
          ),
          if (_showBought)
            for (final item in bought) row(item),
        ],
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;
  const _SectionHeader({required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Text(
        '${title.toUpperCase()}  ·  $count',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: color),
      ),
    );
  }
}

class _GroceryRow extends StatelessWidget {
  final GroceryItem item;
  final bool selecting;
  final bool selected;
  final VoidCallback onToggle;
  final VoidCallback onLongPress;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _GroceryRow({
    super.key,
    required this.item,
    required this.selecting,
    required this.selected,
    required this.onToggle,
    required this.onLongPress,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final done = item.isPurchased;
    final muted = scheme.onSurface.withValues(alpha: 0.45);

    final tile = Material(
      color: selected ? scheme.primary.withValues(alpha: 0.10) : Colors.transparent,
      child: InkWell(
        onTap: onToggle,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Row(
            children: [
              if (selecting)
                Checkbox(value: selected, onChanged: (_) => onToggle())
              else
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 26,
                  height: 26,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: done ? _green : Colors.transparent,
                    border: Border.all(color: done ? _green : muted, width: 2),
                  ),
                  child: done ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
                ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        decoration: done ? TextDecoration.lineThrough : null,
                        color: done ? muted : null,
                      ),
                    ),
                    if (item.localName.isNotEmpty)
                      Text(item.localName, style: TextStyle(fontSize: 11, color: muted), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              if (!selecting)
                InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: onEdit,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: item.quantityLabel.isEmpty ? Colors.transparent : scheme.primary.withValues(alpha: done ? 0.05 : 0.12),
                      borderRadius: BorderRadius.circular(16),
                      border: item.quantityLabel.isEmpty ? Border.all(color: muted.withValues(alpha: 0.4)) : null,
                    ),
                    child: Text(
                      item.quantityLabel.isEmpty ? '+ qty' : item.quantityLabel,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: item.quantityLabel.isEmpty ? muted : (done ? muted : scheme.primary),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    if (selecting) return tile;
    return Dismissible(
      key: ValueKey('dismiss_${item.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (_) => onDelete(),
      child: tile,
    );
  }
}

class _SuggestionTile extends StatelessWidget {
  final CatalogItem item;
  final GroceryItem? existing;
  final String? quantityHint;
  final VoidCallback onTap;
  final void Function(String id) onRemove;

  const _SuggestionTile({
    required this.item,
    required this.existing,
    required this.onTap,
    required this.onRemove,
    this.quantityHint,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final onListToBuy = existing != null && !existing!.isPurchased;
    return ListTile(
      dense: true,
      title: Text(item.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      subtitle: Text(
        [if (item.localName.isNotEmpty) item.localName, item.category].join('  ·  '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: onListToBuy
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle, color: _green, size: 20),
                const SizedBox(width: 4),
                Text(
                  existing!.quantityLabel.isNotEmpty ? 'Added · ${existing!.quantityLabel}' : 'Added',
                  style: const TextStyle(color: _green, fontSize: 12, fontWeight: FontWeight.w700),
                ),
                IconButton(
                  tooltip: 'Remove from list',
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  icon: Icon(Icons.close, color: scheme.onSurface.withValues(alpha: 0.6)),
                  onPressed: () => onRemove(existing!.id),
                ),
              ],
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (quantityHint != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text(quantityHint!, style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700)),
                  ),
                Icon(existing != null ? Icons.replay : Icons.add_circle, color: _green),
              ],
            ),
      onTap: onListToBuy ? null : onTap,
    );
  }
}

// ── Quantity dialog ─────────────────────────────────────────────────────────

/// Small "how much?" box shown when an item is picked. The quantity is free
/// text ("1 kg", "2 packets", "dozen"…) and optional. When [offerSave] is
/// true (the item wasn't found in the catalog) it also asks whether to save
/// the item for quicker search next time. Returns null if cancelled.
Future<({String quantity, bool saveToCatalog})?> askGroceryQuantity(
  BuildContext context,
  String name, {
  String initialQuantity = '',
  String localName = '',
  bool offerSave = false,
}) {
  final controller = TextEditingController(text: initialQuantity);
  var save = true;
  return showDialog<({String quantity, bool saveToCatalog})>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) {
        void submit() => Navigator.pop(dialogContext, (quantity: controller.text.trim(), saveToCatalog: offerSave && save));
        return AlertDialog(
          title: Text(name),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Telugu · Hindi names, so the item is easy to recognise.
              if (localName.isNotEmpty) ...[
                Text(
                  localName,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(dialogContext).colorScheme.onSurface.withValues(alpha: 0.75),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              TextField(
                controller: controller,
                autofocus: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => submit(),
                decoration: const InputDecoration(
                  labelText: 'Quantity (optional)',
                  hintText: 'e.g. 1 kg, 2 packets, 1 dozen',
                  border: OutlineInputBorder(),
                ),
              ),
              if (offerSave) ...[
                const SizedBox(height: 8),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: save,
                  onChanged: (v) => setDialogState(() => save = v ?? false),
                  title: const Text('Save to my items'),
                  subtitle: const Text('Not found in the list — save it so it shows up when you search next time'),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(onPressed: submit, child: const Text('Add')),
          ],
        );
      },
    ),
  );
}

// ── Edit sheet ──────────────────────────────────────────────────────────────

Future<void> showGroceryItemEditor(BuildContext context, WidgetRef ref, GroceryItem item) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _GroceryEditSheet(item: item),
  );
}

class _GroceryEditSheet extends ConsumerStatefulWidget {
  final GroceryItem item;
  const _GroceryEditSheet({required this.item});

  @override
  ConsumerState<_GroceryEditSheet> createState() => _GroceryEditSheetState();
}

class _GroceryEditSheetState extends ConsumerState<_GroceryEditSheet> {
  late final TextEditingController _name = TextEditingController(text: widget.item.name);
  // Quantity is one free-text box ("1 kg", "2 packets"); old quantity + unit are joined.
  late final TextEditingController _qty = TextEditingController(text: widget.item.quantityLabel);

  @override
  void dispose() {
    _name.dispose();
    _qty.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    await ref.read(groceryProvider.notifier).updateItem(widget.item.copyWith(
          name: name,
          quantity: _qty.text.trim(),
          unit: '',
        ));
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(left: 20, right: 20, bottom: MediaQuery.viewInsetsOf(context).bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Item', border: OutlineInputBorder()),
          ),
          if (widget.item.localName.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Text(widget.item.localName, style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6))),
            ),
          const SizedBox(height: 14),
          TextField(
            controller: _qty,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
            decoration: const InputDecoration(
              labelText: 'Quantity (optional)',
              hintText: 'e.g. 1 kg, 2 packets, 1 dozen',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              TextButton.icon(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                label: const Text('Delete', style: TextStyle(color: Colors.red)),
                onPressed: () {
                  final navigator = Navigator.of(context);
                  deleteGroceryWithUndo(context, ref, {widget.item.id});
                  navigator.pop();
                },
              ),
              const Spacer(),
              FilledButton(onPressed: _save, child: const Text('Save')),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Catalog browser ─────────────────────────────────────────────────────────

class GroceryMasterListView extends ConsumerStatefulWidget {
  const GroceryMasterListView({super.key});

  @override
  ConsumerState<GroceryMasterListView> createState() => _GroceryMasterListViewState();
}

class _GroceryMasterListViewState extends ConsumerState<GroceryMasterListView> {
  final _searchController = TextEditingController();
  String? _category;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _add(CatalogItem item) async {
    final messenger = ScaffoldMessenger.of(context);
    final answer = await askGroceryQuantity(context, item.name, localName: item.localName);
    if (answer == null) return;
    final result = await ref.read(groceryProvider.notifier).addItem(
          item.name,
          quantity: answer.quantity,
          category: item.category,
          localName: item.localName,
        );
    HapticFeedback.selectionClick();
    // A green "Added" tick shows on the row, so only unusual cases need a message.
    final message = switch (result) {
      GroceryAddResult.added => null,
      GroceryAddResult.alreadyOnList => '${item.name} is already on your list',
      GroceryAddResult.movedBack => '${item.name} moved back to your list',
      GroceryAddResult.ignored => null,
    };
    if (message == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(duration: const Duration(seconds: 2), content: Text(message)));
  }

  void _showAddItemDialog() {
    final enController = TextEditingController(text: _searchController.text.trim());
    final localController = TextEditingController();
    final keywordsController = TextEditingController();
    var category = _category ?? 'Other';
    var unit = '';

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Add to catalog'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: enController, decoration: const InputDecoration(labelText: 'Name (e.g. Rice)')),
                TextField(controller: localController, decoration: const InputDecoration(labelText: 'Local name (e.g. బియ్యం)')),
                TextField(controller: keywordsController, decoration: const InputDecoration(labelText: 'Other search words (comma separated)')),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: category,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: [for (final c in kGroceryCategoryOrder) DropdownMenuItem(value: c, child: Text(c))],
                  onChanged: (v) => setDialogState(() => category = v ?? 'Other'),
                ),
                DropdownButtonFormField<String>(
                  initialValue: unit,
                  decoration: const InputDecoration(labelText: 'Usual unit'),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('None')),
                    for (final u in kGroceryUnits) DropdownMenuItem(value: u, child: Text(u)),
                  ],
                  onChanged: (v) => setDialogState(() => unit = v ?? ''),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final name = enController.text.trim();
                if (name.isEmpty) return;
                ref.read(groceryCatalogProvider.notifier).addCustomItem(
                      name,
                      localController.text.trim(),
                      keywordsController.text.trim(),
                      category: category,
                      unit: unit,
                    );
                Navigator.pop(dialogContext);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(groceryCatalogItemsProvider);
    final loading = ref.watch(groceryCatalogProvider).isLoading;
    final onList = {for (final i in ref.watch(groceryProvider)) i.name.toLowerCase(): i};
    final query = _searchController.text.trim();

    var items = query.isEmpty ? catalog : searchCatalog(catalog, query, limit: 300);
    if (_category != null) items = items.where((i) => i.category == _category).toList();
    if (query.isEmpty) {
      items = [...items]..sort((a, b) {
          final byCat = groceryCategoryRank(a.category).compareTo(groceryCategoryRank(b.category));
          return byCat != 0 ? byCat : a.name.compareTo(b.name);
        });
    }
    final categories = kGroceryCategoryOrder.where((c) => catalog.any((i) => i.category == c)).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Grocery catalog'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(108),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search in English, తెలుగు or हिंदी…',
                    filled: true,
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
                  ),
                ),
              ),
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(label: const Text('All'), selected: _category == null, onSelected: (_) => setState(() => _category = null)),
                    ),
                    for (final c in categories)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(c),
                          selected: _category == c,
                          onSelected: (v) => setState(() => _category = v ? c : null),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: loading && catalog.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('No items found.'),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.add),
                        label: const Text('Add it to the catalog'),
                        onPressed: _showAddItemDialog,
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final existing = onList[item.name.toLowerCase()];
                    final showHeader = query.isEmpty && (index == 0 || items[index - 1].category != item.category);
                    final tile = _SuggestionTile(
                      item: item,
                      existing: existing,
                      onTap: () => _add(item),
                      onRemove: (id) => deleteGroceryWithUndo(context, ref, {id}),
                    );
                    if (!showHeader) return tile;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [_SectionHeader(title: item.category, count: catalog.where((i) => i.category == item.category).length), tile],
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddItemDialog,
        icon: const Icon(Icons.add),
        label: const Text('Custom item'),
      ),
    );
  }
}
