import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../models.dart';
import '../providers.dart';
import '../utils/grocery_catalog.dart';
import '../utils/undo_helpers.dart';

const _infoBlue = Color(0xFF3B6FD8);
const _removeRed = Color(0xFFD9534F);
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
      showGroceryToast(context, '$name is already on your list', icon: Icons.info, color: _infoBlue);
      return;
    }
    final answer = await askGroceryQuantity(
      context,
      name,
      initialQuantity: _typedQuantity(),
      localName: localName,
      category: category,
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
    final result = await ref.read(groceryProvider.notifier).addItem(
          name,
          quantity: quantity,
          category: category,
          localName: localName,
        );
    if (!mounted) return;
    HapticFeedback.selectionClick();
    if (result == GroceryAddResult.added) {
      showGroceryAddedToast(context, quantity.isEmpty ? name : '$name · $quantity');
    }
    _input.clear();
    _focus.requestFocus(); // keep the keyboard up for the next item
    final message = switch (result) {
      GroceryAddResult.added => null, // the item appearing is feedback enough
      GroceryAddResult.alreadyOnList => '$name is already on your list',
      GroceryAddResult.movedBack => '$name moved back to your list',
      GroceryAddResult.ignored => null,
    };
    if (message != null) showGroceryToast(context, message, icon: Icons.info, color: _infoBlue);
  }

  static String _capitalise(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  /// Opens Browse products; leaves selection mode first so the list is
  /// back to normal on return.
  void _openBrowse({bool manage = false}) {
    ref.read(selectedGroceryProvider.notifier).clear();
    ref.read(isSelectionModeProvider.notifier).setState(false);
    Navigator.push(context, MaterialPageRoute(builder: (_) => GroceryMasterListView(manage: manage)));
  }

  // ── List actions ──────────────────────────────────────────────────────────

  void _share(List<GroceryItem> items) {
    final toBuy = items.where((i) => !i.isPurchased).toList();
    if (toBuy.isEmpty) {
      showGroceryToast(context, 'Nothing to buy — the list is empty', icon: Icons.info, color: _infoBlue);
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
            () async {
          await ref.read(groceryProvider.notifier).uncheckAll();
          if (mounted) showGroceryToast(context, 'All items back on the list', icon: Icons.replay, color: _infoBlue);
        });
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
        _openBrowse(manage: true);
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
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 42,
              child: TextField(
                controller: _input,
                focusNode: _focus,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _addTyped(),
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search or add item',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _input.text.isEmpty
                      ? null
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.check_circle, color: _green, size: 22),
                              tooltip: 'Add',
                              visualDensity: VisualDensity.compact,
                              onPressed: _addTyped,
                            ),
                            IconButton(icon: const Icon(Icons.close, size: 20), tooltip: 'Clear', visualDensity: VisualDensity.compact, onPressed: _input.clear),
                          ],
                        ),
                  filled: true,
                  fillColor: scheme.onSurface.withValues(alpha: 0.05),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 42,
            child: FilledButton.tonalIcon(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              ),
              icon: const Icon(Icons.storefront_rounded, size: 20),
              label: const Text('Browse products', style: TextStyle(fontSize: 12)),
              onPressed: () => _openBrowse(),
            ),
          ),
        ],
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
            onRemove: (id) => ref.read(groceryProvider.notifier).deleteMultiple({id}),
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
              onPressed: () => _openBrowse(),
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
              item.isPurchased
                  ? showGroceryToast(context, '${item.name} back on the list', icon: Icons.undo, color: _infoBlue)
                  : showGroceryToast(context, '${item.name} bought');
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

    final border = done ? _green.withValues(alpha: 0.55) : scheme.outlineVariant.withValues(alpha: 0.6);
    final radius = BorderRadius.circular(12);

    final card = Material(
      color: selected
          ? scheme.primary.withValues(alpha: 0.12)
          : done
              ? _green.withValues(alpha: 0.08)
              : scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: selected ? scheme.primary : border)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onToggle,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
          child: Row(
            children: [
              if (selecting) Checkbox(value: selected, onChanged: (_) => onToggle()),
              // Item picture with a thin divider after it.
              SizedBox(
                width: 34,
                child: Text(
                  groceryEmoji(item.name, item.category),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, color: Colors.black.withValues(alpha: done ? 0.55 : 1)),
                ),
              ),
              Container(
                width: 1,
                height: 28,
                margin: const EdgeInsets.symmetric(horizontal: 10),
                color: scheme.outlineVariant.withValues(alpha: 0.7),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        decoration: done ? TextDecoration.lineThrough : null,
                        color: done ? muted : null,
                      ),
                    ),
                    if (item.localName.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(item.localName, style: TextStyle(fontSize: 11, color: muted), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                ),
              ),
              if (!selecting) ...[
                const SizedBox(width: 8),
                InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: onEdit,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: item.quantityLabel.isEmpty
                          ? Colors.transparent
                          : done
                              ? scheme.onSurface.withValues(alpha: 0.08)
                              : scheme.primary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(16),
                      border: item.quantityLabel.isEmpty ? Border.all(color: muted.withValues(alpha: 0.4)) : null,
                    ),
                    child: Text(
                      item.quantityLabel.isEmpty ? '+ qty' : item.quantityLabel,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: item.quantityLabel.isEmpty ? muted : (done ? scheme.onSurface.withValues(alpha: 0.8) : scheme.primary),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // Tick on the right: outlined grey while to buy, filled green once bought.
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: done ? _green : Colors.transparent,
                    border: Border.all(color: done ? _green : muted, width: 1.6),
                  ),
                  child: Icon(Icons.check, size: 15, color: done ? Colors.white : muted),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    const gap = EdgeInsets.symmetric(horizontal: 12, vertical: 3);
    if (selecting) return Padding(padding: gap, child: card);
    return Padding(
      padding: gap,
      child: Dismissible(
        key: ValueKey('dismiss_${item.id}'),
        direction: DismissDirection.endToStart,
        background: Container(
          decoration: BoxDecoration(color: Colors.red, borderRadius: radius),
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 24),
          child: const Icon(Icons.delete_outline, color: Colors.white),
        ),
        onDismissed: (_) => onDelete(),
        child: card,
      ),
    );
  }
}

class _SuggestionTile extends StatelessWidget {
  final CatalogItem item;
  final GroceryItem? existing;
  final String? quantityHint;
  final VoidCallback onTap;
  final void Function(String id) onRemove;
  final void Function(String action)? onMenu; // 'edit' / 'delete' (Browse products only)

  const _SuggestionTile({
    required this.item,
    required this.existing,
    required this.onTap,
    required this.onRemove,
    this.quantityHint,
    this.onMenu,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final onListToBuy = existing != null && !existing!.isPurchased;
    final menu = onMenu == null
        ? null
        : PopupMenuButton<String>(
            tooltip: 'More',
            padding: EdgeInsets.zero,
            icon: Icon(Icons.more_vert, size: 20, color: scheme.onSurface.withValues(alpha: 0.6)),
            onSelected: onMenu,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Edit'), contentPadding: EdgeInsets.zero)),
              PopupMenuItem(
                value: 'delete',
                child: ListTile(leading: Icon(Icons.delete_outline, color: Colors.red), title: Text('Delete'), contentPadding: EdgeInsets.zero),
              ),
            ],
          );
    return ListTile(
      dense: true,
      visualDensity: const VisualDensity(vertical: -3),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14),
      minLeadingWidth: 30,
      leading: Text(groceryEmoji(item.name, item.category), style: const TextStyle(fontSize: 22)),
      title: Text(item.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      subtitle: item.localName.isEmpty
          ? null
          : Text(item.localName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
      trailing: onListToBuy
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle, color: _green, size: 20),
                if (existing!.quantityLabel.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  Text(
                    existing!.quantityLabel,
                    style: const TextStyle(color: _green, fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                ],
                IconButton(
                  tooltip: 'Remove from list',
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  icon: Icon(Icons.close, color: scheme.onSurface.withValues(alpha: 0.6)),
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Remove item?'),
                        content: Text('Remove ${item.name} from your list?'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
                          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes')),
                        ],
                      ),
                    );
                    if (ok != true) return;
                    onRemove(existing!.id);
                    if (context.mounted) {
                      showGroceryToast(context, '${item.name} removed', icon: Icons.remove_circle, color: _removeRed);
                    }
                  },
                ),
                ?menu,
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
                ?menu,
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
  String category = '',
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
              QuantitySuggestionChips(controller: controller, category: category),
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
    if (!mounted) return;
    showGroceryToast(context, '$name updated', icon: Icons.edit, color: _infoBlue);
    Navigator.pop(context);
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
          QuantitySuggestionChips(controller: _qty, category: widget.item.category),
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
  /// [manage] (opened from the ⋮ menu) adds Edit / Delete on each product and Reset.
  final bool manage;
  const GroceryMasterListView({super.key, this.manage = false});

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
    final answer = await askGroceryQuantity(context, item.name, localName: item.localName, category: item.category);
    if (answer == null) return;
    final result = await ref.read(groceryProvider.notifier).addItem(
          item.name,
          quantity: answer.quantity,
          category: item.category,
          localName: item.localName,
        );
    HapticFeedback.selectionClick();
    if (result == GroceryAddResult.added && mounted) {
      showGroceryAddedToast(context, answer.quantity.isEmpty ? item.name : '${item.name} · ${answer.quantity}');
    }
    // Only unusual cases need a bottom message.
    final message = switch (result) {
      GroceryAddResult.added => null,
      GroceryAddResult.alreadyOnList => '${item.name} is already on your list',
      GroceryAddResult.movedBack => '${item.name} moved back to your list',
      GroceryAddResult.ignored => null,
    };
    if (message == null || !mounted) return;
    showGroceryToast(context, message, icon: Icons.info, color: _infoBlue);
  }

  void _showAddItemDialog() => _showItemDialog();

  Future<bool> _yesNo(String title, String message) async {
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
    return ok == true;
  }

  Future<void> _deleteProduct(CatalogItem item) async {
    if (!await _yesNo('Delete product?', 'Remove ${item.name} from Browse products? Items already on your list stay.')) return;
    await ref.read(groceryCatalogProvider.notifier).deleteItem(item.id);
    if (mounted) showGroceryToast(context, '${item.name} deleted', icon: Icons.delete, color: _removeRed);
  }

  Future<void> _resetCatalog() async {
    if (!await _yesNo(
      'Reset products?',
      'Go back to the original product list. Products you saved, edited or deleted will be undone. Your shopping list is not touched.',
    )) {
      return;
    }
    await ref.read(groceryCatalogProvider.notifier).resetCatalog();
    if (mounted) showGroceryToast(context, 'Products reset to default', icon: Icons.restart_alt, color: _infoBlue);
  }

  /// Add a new product, or edit [edit].
  void _showItemDialog({CatalogItem? edit}) {
    final enController = TextEditingController(text: edit?.name ?? _searchController.text.trim());
    final localController = TextEditingController(text: edit?.localName ?? '');
    final keywordsController = TextEditingController();
    var category = edit?.category ?? _category ?? 'Other';
    if (!kGroceryCategoryOrder.contains(category)) category = 'Other';
    var unit = edit?.defaultUnit ?? '';
    if (!kGroceryUnits.contains(unit)) unit = '';

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(edit == null ? 'New product' : 'Edit product'),
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
                if (edit != null) {
                  ref.read(groceryCatalogProvider.notifier).editItem(
                        edit.id,
                        englishName: name,
                        localName: localController.text.trim(),
                        oldLocalName: edit.localName,
                        searchKeywords: keywordsController.text.trim(),
                        category: category,
                        unit: unit,
                      );
                  Navigator.pop(dialogContext);
                  showGroceryToast(context, '$name updated', icon: Icons.edit, color: _infoBlue);
                  return;
                }
                ref.read(groceryCatalogProvider.notifier).addCustomItem(
                      name,
                      localController.text.trim(),
                      keywordsController.text.trim(),
                      category: category,
                      unit: unit,
                    );
                Navigator.pop(dialogContext);
                showGroceryToast(context, '$name saved to products', icon: Icons.bookmark_added);
              },
              child: Text(edit == null ? 'Add' : 'Save'),
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
        title: const Row(children: [Icon(Icons.storefront_rounded), SizedBox(width: 10), Text('Browse products')]),
        actions: [
          if (widget.manage)
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (v) {
              if (v == 'new') _showItemDialog();
              if (v == 'reset') _resetCatalog();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'new', child: ListTile(leading: Icon(Icons.add), title: Text('New product'), contentPadding: EdgeInsets.zero)),
              PopupMenuItem(
                value: 'reset',
                child: ListTile(leading: Icon(Icons.restart_alt), title: Text('Reset to default'), contentPadding: EdgeInsets.zero),
              ),
            ],
          ),
        ],
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
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close),
                            tooltip: 'Clear',
                            onPressed: () => setState(_searchController.clear),
                          ),
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
      // Stop the list above the phone's nav buttons.
      body: SafeArea(top: false, child: loading && catalog.isEmpty
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
                  // Keep the last rows above the phone's nav buttons and the New item button.
                  padding: const EdgeInsets.only(bottom: 88),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final existing = onList[item.name.toLowerCase()];
                    final showHeader = query.isEmpty && (index == 0 || items[index - 1].category != item.category);
                    final tile = _SuggestionTile(
                      item: item,
                      existing: existing,
                      onTap: () => _add(item),
                      onRemove: (id) => ref.read(groceryProvider.notifier).deleteMultiple({id}),
                      onMenu: !widget.manage ? null : (action) => action == 'edit' ? _showItemDialog(edit: item) : _deleteProduct(item),
                    );
                    if (!showHeader) return tile;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [_SectionHeader(title: item.category, count: catalog.where((i) => i.category == item.category).length), tile],
                    );
                  },
                )),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddItemDialog,
        icon: const Icon(Icons.add),
        label: const Text('New item'),
      ),
    );
  }
}

// ── "Added" toast ───────────────────────────────────────────────────────────

OverlayEntry? _groceryToast;

/// Short "✓ item added" pill that drops in at the top of the screen.
void showGroceryAddedToast(BuildContext context, String label) =>
    showGroceryToast(context, '$label added');

/// Small coloured pill that drops in at the top of the screen and fades away
/// by itself. Used as feedback for every Grocery action.
void showGroceryToast(
  BuildContext context,
  String message, {
  IconData icon = Icons.check_circle,
  Color color = _green,
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  _groceryToast?.remove();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) => Positioned(
      top: MediaQuery.viewPaddingOf(ctx).top + 12,
      left: 24,
      right: 24,
      child: IgnorePointer(
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            builder: (_, t, child) => Opacity(
              opacity: t,
              child: Transform.translate(offset: Offset(0, -16 * (1 - t)), child: child),
            ),
            child: Material(
              color: color,
              elevation: 6,
              borderRadius: BorderRadius.circular(24),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        message,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  _groceryToast = entry;
  overlay.insert(entry);
  Future.delayed(const Duration(milliseconds: 1600), () {
    if (_groceryToast == entry) _groceryToast = null;
    if (entry.mounted) entry.remove();
  });
}

// ── Quantity suggestion chips ───────────────────────────────────────────────

/// Tappable quantity suggestions under a quantity box; they follow what is
/// typed ("2" → 2 kg, 2 packets…). Tapping one fills the box.
class QuantitySuggestionChips extends StatelessWidget {
  final TextEditingController controller;
  final String category;

  const QuantitySuggestionChips({super.key, required this.controller, this.category = ''});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final typed = value.text.trim();
        final options = suggestQuantities(typed, category: category)
            .where((o) => o.toLowerCase() != typed.toLowerCase())
            .toList();
        if (options.isEmpty) return const SizedBox(height: 4);
        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final o in options)
                ActionChip(
                  label: Text(o, style: const TextStyle(fontSize: 13)),
                  visualDensity: VisualDensity.compact,
                  backgroundColor: scheme.primary.withValues(alpha: 0.10),
                  side: BorderSide.none,
                  onPressed: () => controller.value = TextEditingValue(
                    text: o,
                    selection: TextSelection.collapsed(offset: o.length),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
