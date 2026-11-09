import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../models.dart';
import '../providers.dart';
import '../utils/grocery_catalog.dart';
import '../utils/undo_helpers.dart';
import '../widgets/top_toast.dart';

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

const _flyDuration = Duration(milliseconds: 320);

/// "₹1,250" or "₹49.50".
String groceryRupees(double amount) => '₹${NumberFormat('#,##0.##').format(amount)}';

/// The list as a neat plain-text document, to-buy items first.
String groceryListText(List<GroceryItem> items, DateTime when) {
  const width = 36;
  final line = '-' * width;
  final out = StringBuffer()
    ..writeln('GROCERY LIST')
    ..writeln('Saved: ${DateFormat('dd MMM yyyy, h:mm a').format(when)}')
    ..writeln('=' * width);

  void section(String title, String mark, List<GroceryItem> list) {
    if (list.isEmpty) return;
    out
      ..writeln()
      ..writeln('$title (${list.length})')
      ..writeln(line);
    for (final i in list) {
      final name = '$mark ${i.name}';
      final details = [
        if (i.quantityLabel.isNotEmpty) i.quantityLabel,
        if (i.price != null) groceryRupees(i.price!),
      ].join('  ');
      out.writeln(details.isEmpty ? name : '${name.padRight(width - 10)}  $details');
    }
  }

  section('TO BUY', '[ ]', items.where((i) => !i.isPurchased).toList());
  final bought = items.where((i) => i.isPurchased).toList();
  section('BOUGHT', '[x]', bought);
  if (bought.any((i) => i.price != null)) {
    out
      ..writeln(line)
      ..writeln('TOTAL: ${groceryRupees(bought.fold<double>(0, (sum, i) => sum + (i.price ?? 0)))}');
  }
  return out.toString();
}

class _GroceryViewState extends ConsumerState<GroceryView> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  bool _boughtTab = false; // false = To buy, true = Bought
  final _pages = PageController(keepPage: false);
  final Set<String> _flying = {}; // cards sliding over to the other tab
  bool _askingPrice = false;

  @override
  void initState() {
    super.initState();
    _input.addListener(() {
      if (!mounted) return;
      // Typing replaces the tabs with suggestions; come back on To buy.
      setState(() {
        if (_input.text.trim().isNotEmpty) _boughtTab = false;
      });
    });
  }

  @override
  void dispose() {
    _pages.dispose();
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
  void _openBrowse() {
    ref.read(selectedGroceryProvider.notifier).clear();
    ref.read(isSelectionModeProvider.notifier).setState(false);
    Navigator.push(context, MaterialPageRoute(builder: (_) => const GroceryMasterListView()));
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

  /// Lets the user pick where to save the list as a neat .txt file.
  Future<void> _saveAsText(List<GroceryItem> items) async {
    if (items.isEmpty) {
      showGroceryToast(context, 'Nothing to save — the list is empty', icon: Icons.info, color: _infoBlue);
      return;
    }
    final now = DateTime.now();
    try {
      final saved = await FilePicker.saveFile(
        dialogTitle: 'Save grocery list',
        fileName: 'Grocery_List_${DateFormat('yyyy-MM-dd').format(now)}.txt',
        type: FileType.custom,
        allowedExtensions: const ['txt'],
        bytes: Uint8List.fromList(utf8.encode(groceryListText(items, now))),
      );
      if (saved != null && mounted) showGroceryToast(context, 'List saved', icon: Icons.save_alt);
    } catch (e) {
      if (mounted) showGroceryToast(context, 'Could not save the list', icon: Icons.error, color: _removeRed);
    }
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
      () async => deleteGroceryWithUndo(context, ref, ids, confirm: false),
    );
  }

  void _onMenu(String value, List<GroceryItem> items) {
    switch (value) {
      case 'share':
        _share(items);
        break;
      case 'clearBought':
        _clearBought(items);
        break;
      case 'clearAll':
        if (items.isEmpty) return;
        _confirm(
          'Clear items list?',
          'Remove all ${items.length} item${items.length == 1 ? '' : 's'}?',
          () async => deleteGroceryWithUndo(context, ref, items.map((i) => i.id).toSet(), confirm: false),
        );
        break;
      case 'saveTxt':
        _saveAsText(items);
        break;
      case 'catalog':
        _openBrowse();
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
        _buildInput(items, bought),
        _buildHeader(items, toBuy, bought),
        Expanded(
          child: typing ? _buildSuggestions(items) : _buildList(items, toBuy, bought),
        ),
      ],
    );
  }

  /// Thin progress bar; the counts are on the To buy / Bought tabs.
  Widget _buildHeader(List<GroceryItem> items, List<GroceryItem> toBuy, List<GroceryItem> bought) {
    if (items.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: bought.length / items.length,
          minHeight: 4,
          backgroundColor: scheme.onSurface.withValues(alpha: 0.08),
          valueColor: const AlwaysStoppedAnimation(_green),
        ),
      ),
    );
  }

  /// ⋮ menu, shown after the Browse products button.
  List<Widget> _listActions(List<GroceryItem> items, List<GroceryItem> bought) {
    return [
      PopupMenuButton<String>(
        tooltip: 'More',
        onSelected: (v) => _onMenu(v, items),
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'catalog', child: ListTile(leading: Icon(Icons.storefront_rounded), title: Text('Browse products'), contentPadding: EdgeInsets.zero)),
          const PopupMenuItem(value: 'share', child: ListTile(leading: Icon(Icons.share_outlined), title: Text('Share list'), contentPadding: EdgeInsets.zero)),
          const PopupMenuItem(value: 'saveTxt', child: ListTile(leading: Icon(Icons.save_alt), title: Text('Save list'), contentPadding: EdgeInsets.zero)),
          if (bought.isNotEmpty)
            const PopupMenuItem(value: 'clearBought', child: ListTile(leading: Icon(Icons.playlist_remove), title: Text('Clear bought'), contentPadding: EdgeInsets.zero)),
          if (items.isNotEmpty)
            const PopupMenuItem(value: 'clearAll', child: ListTile(leading: Icon(Icons.delete_sweep_outlined, color: Colors.red), title: Text('Clear items list'), contentPadding: EdgeInsets.zero)),
        ],
      ),
    ];
  }

  Widget _buildInput(List<GroceryItem> items, List<GroceryItem> bought) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 0, 6),
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
                  hintText: 'Search or add',
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
                padding: const EdgeInsets.symmetric(horizontal: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              ),
              icon: const Icon(Icons.storefront_rounded, size: 20),
              label: const Text('Browse products', style: TextStyle(fontSize: 12)),
              onPressed: () => _openBrowse(),
            ),
          ),
          ..._listActions(items, bought),
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
      _boughtTab = false; // the tabs are rebuilt on To buy next time
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
              'Type above to add items, or browse products.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.storefront_rounded),
              label: const Text('Browse products'),
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
          flying: _flying.contains(item.id),
          onToggle: () async {
            if (selecting) {
              ref.read(selectedGroceryProvider.notifier).toggle(item.id);
            } else {
              if (_flying.contains(item.id) || _askingPrice) return; // already on its way
              double? price;
              if (!item.isPurchased) {
                _askingPrice = true;
                price = await askGroceryPrice(context, item.name);
                _askingPrice = false;
                if (!mounted) return;
              } else {
                _askingPrice = true;
                final ok = await confirmYesNo(
                  context,
                  'Move to To buy?',
                  'Move ${item.name} back to To buy?${item.price != null ? ' Its price will be removed.' : ''}',
                );
                _askingPrice = false;
                if (!ok || !mounted) return;
              }
              _flying.add(item.id);
              HapticFeedback.lightImpact();
              setState(() {});
              final notifier = ref.read(groceryProvider.notifier);
              // Let the card slide away first, then move it to the other list.
              Future.delayed(_flyDuration, () async {
                await notifier.toggleItem(item.id, price: price);
                if (mounted) setState(() => _flying.remove(item.id));
              });
              item.isPurchased
                  ? showGroceryToast(context, '${item.name} back on the list', icon: Icons.undo, color: _infoBlue)
                  : showGroceryToast(context, price == null ? '${item.name} bought' : '${item.name} bought · ${groceryRupees(price)}');
            }
          },
          onLongPress: () {
            if (!selecting) {
              ref.read(grocerySelectBoughtProvider.notifier).set(_boughtTab);
              ref.read(isSelectionModeProvider.notifier).setState(true);
              ref.read(selectedGroceryProvider.notifier).toggle(item.id);
            }
          },
          onEdit: () => showGroceryItemEditor(context, ref, item),
        );

    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
    Widget page(List<GroceryItem> list, String emptyText, Color emptyColor) => list.isEmpty
        ? Center(child: Text(emptyText, style: TextStyle(color: emptyColor, fontWeight: FontWeight.w600)))
        : ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.only(bottom: 32),
            children: [for (final item in list) row(item)],
          );

    // A page with its Clear button, which turns on the tick boxes.
    Widget withClear(List<GroceryItem> list, bool boughtPage, String emptyText, Color emptyColor) {
      final showTotal = boughtPage && list.any((i) => i.price != null);
      final total = list.fold<double>(0, (sum, i) => sum + (i.price ?? 0));
      return Column(
          children: [
            if (list.isNotEmpty && !selecting)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    if (boughtPage)
                      TextButton(
                        style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                        onPressed: () => _confirm(
                          'Shop again?',
                          'Move all ${list.length} bought item${list.length == 1 ? '' : 's'} back to To buy?${showTotal ? ' Their prices will be removed.' : ''}',
                          () async {
                            await ref.read(groceryProvider.notifier).uncheckAll();
                            if (mounted) showGroceryToast(context, 'All items moved to To buy', icon: Icons.replay, color: _infoBlue);
                          },
                        ),
                        child: const Text('Shop again'),
                      ),
                    const Spacer(),
                    TextButton(
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                      onPressed: () {
                        ref.read(grocerySelectBoughtProvider.notifier).set(boughtPage);
                        ref.read(isSelectionModeProvider.notifier).setState(true);
                      },
                      child: const Text('Clear'),
                    ),
                  ],
                ),
              ),
            if (boughtPage && list.isNotEmpty) const Divider(height: 1, indent: 12, endIndent: 12),
            if (showTotal)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Total ${groceryRupees(total)}', style: const TextStyle(color: _green, fontSize: 15, fontWeight: FontWeight.w800)),
                ),
              ),
            Expanded(child: page(list, emptyText, emptyColor)),
          ],
        );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 2, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: SegmentedButton<bool>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                  segments: [
                    ButtonSegment(value: false, label: _TabLabel(title: 'To buy', count: toBuy.length)),
                    ButtonSegment(value: true, label: _TabLabel(title: 'Bought', count: bought.length)),
                  ],
                  selected: {_boughtTab},
                  // The tab stays put while items are being ticked.
                  onSelectionChanged: selecting ? null : (v) {
                    setState(() => _boughtTab = v.first);
                    _pages.animateToPage(v.first ? 1 : 0, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
                  },
                ),
              ),
            ],
          ),
        ),
        // Swipe left / right between To buy and Bought.
        Expanded(
          child: PageView(
            controller: _pages,
            physics: selecting ? const NeverScrollableScrollPhysics() : null,
            onPageChanged: (i) => setState(() => _boughtTab = i == 1),
            children: [
              withClear(toBuy, false, 'Everything is bought ✓', _green),
              withClear(bought, true, 'Nothing bought yet', muted),
            ],
          ),
        ),
      ],
    );
  }
}

/// Tab title with its count; the count flashes green and pops when it goes up.
class _TabLabel extends StatefulWidget {
  final String title;
  final int count;
  const _TabLabel({required this.title, required this.count});

  @override
  State<_TabLabel> createState() => _TabLabelState();
}

class _TabLabelState extends State<_TabLabel> with SingleTickerProviderStateMixin {
  late final AnimationController _flash = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
  late final Animation<double> _glow = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0).chain(CurveTween(curve: Curves.easeOutBack)), weight: 25),
    TweenSequenceItem(tween: ConstantTween(1.0), weight: 35),
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0).chain(CurveTween(curve: Curves.easeIn)), weight: 40),
  ]).animate(_flash);

  @override
  void didUpdateWidget(_TabLabel old) {
    super.didUpdateWidget(old);
    if (widget.count > old.count) _flash.forward(from: 0);
  }

  @override
  void dispose() {
    _flash.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(widget.title),
        const SizedBox(width: 5),
        AnimatedBuilder(
          animation: _glow,
          builder: (context, _) {
            final t = _glow.value.clamp(0.0, 1.0);
            return Transform.scale(
              scale: 1 + 0.3 * _glow.value,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: _green.withValues(alpha: t),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${widget.count}',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Color.lerp(DefaultTextStyle.of(context).style.color, Colors.white, t),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;
  final bool? expanded; // null = not foldable
  final VoidCallback? onTap;
  const _SectionHeader({required this.title, required this.count, this.expanded, this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, expanded == null ? 14 : 12, 14, expanded == null ? 4 : 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '${title.toUpperCase()}  ·  $count',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: color),
              ),
            ),
            if (expanded != null) Icon(expanded! ? Icons.expand_less : Icons.expand_more, size: 20, color: color),
          ],
        ),
      ),
    );
  }
}

class _GroceryRow extends StatelessWidget {
  final GroceryItem item;
  final bool selecting;
  final bool selected;
  final bool flying; // sliding over to the other tab
  final VoidCallback onToggle;
  final VoidCallback onLongPress;
  final VoidCallback onEdit;

  const _GroceryRow({
    super.key,
    required this.item,
    required this.selecting,
    required this.selected,
    this.flying = false,
    required this.onToggle,
    required this.onLongPress,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final done = item.isPurchased != flying; // shows the new state as soon as it is tapped
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
        onTap: selecting ? onToggle : onEdit,
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
              if (item.price != null) ...[
                const SizedBox(width: 8),
                Text(groceryRupees(item.price!), style: const TextStyle(color: _green, fontSize: 14, fontWeight: FontWeight.w800)),
              ],
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
                const SizedBox(width: 2),
                // Tick on the right (the only control that marks bought):
                // outlined grey while to buy, filled green once bought.
                InkResponse(
                  onTap: onToggle,
                  radius: 24,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: AnimatedContainer(
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
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    // Bought is the tab on the right: to-buy cards leave rightwards, bought ones leftwards.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: AnimatedSlide(
        offset: flying ? Offset(item.isPurchased ? -1.1 : 1.1, 0) : Offset.zero,
        duration: _flyDuration,
        curve: Curves.easeInCubic,
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
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(color: _green, borderRadius: BorderRadius.circular(14)),
                  child: const Text('Add', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                ),
                ?menu,
              ],
            ),
      onTap: onListToBuy ? null : onTap,
    );
  }
}

// ── Price dialog ────────────────────────────────────────────────────────────

/// Asks what was paid, with the number keypad. Cancel (or an empty box)
/// returns null: the item is still bought, just without a price.
Future<double?> askGroceryPrice(BuildContext context, String name) {
  final controller = TextEditingController();
  return showDialog<double>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      void submit() => Navigator.pop(dialogContext, double.tryParse(controller.text.trim()));
      return AlertDialog(
        title: Text(name),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => submit(),
          decoration: const InputDecoration(labelText: 'Enter price', prefixText: '₹ ', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(onPressed: submit, child: const Text('Save')),
        ],
      );
    },
  );
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
              QuantitySuggestionChips(controller: controller, category: category, onPicked: submit),
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
  late final TextEditingController _price = TextEditingController(
    text: widget.item.price == null ? '' : NumberFormat('0.##').format(widget.item.price),
  );

  @override
  void dispose() {
    _name.dispose();
    _qty.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    await ref.read(groceryProvider.notifier).updateItem(widget.item.copyWith(
          name: name,
          quantity: _qty.text.trim(),
          unit: '',
          price: widget.item.isPurchased ? double.tryParse(_price.text.trim()) : null,
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
          if (widget.item.isPurchased) ...[
            const SizedBox(height: 14),
            TextField(
              controller: _price,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
              decoration: const InputDecoration(labelText: 'Price (optional)', prefixText: '₹ ', border: OutlineInputBorder()),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              TextButton.icon(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                label: const Text('Delete', style: TextStyle(color: Colors.red)),
                onPressed: () async {
                  final navigator = Navigator.of(context);
                  if (await deleteGroceryWithUndo(context, ref, {widget.item.id})) navigator.pop();
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
  final Set<String> _openCategories = {'Vegetables'};
  final Map<String, GlobalKey> _chipKeys = {};

  /// Picks a category (null = All) and brings its chip into view.
  void _selectCategory(String? category) {
    setState(() => _category = category);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final chip = _chipKeys[category ?? '']?.currentContext;
      if (chip != null && chip.mounted) {
        Scrollable.ensureVisible(chip, alignment: 0.5, duration: const Duration(milliseconds: 220));
      }
    });
  }

  /// Swipe left = next category, swipe right = previous one.
  void _swipeCategory(DragEndDetails details, List<String> categories) {
    final speed = details.primaryVelocity ?? 0;
    if (speed.abs() < 200) return;
    final order = <String?>[null, ...categories];
    final next = order.indexOf(_category) + (speed < 0 ? 1 : -1);
    if (next >= 0 && next < order.length) _selectCategory(order[next]);
  }

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

    // Rows to show: a String is a category heading, a CatalogItem is a product.
    final foldable = query.isEmpty && _category == null;
    final counts = <String, int>{};
    for (final i in catalog) {
      counts[i.category] = (counts[i.category] ?? 0) + 1;
    }
    final rows = <Object>[];
    if (foldable) {
      String? previous;
      for (final item in items) {
        if (item.category != previous) rows.add(item.category);
        previous = item.category;
        if (_openCategories.contains(item.category)) rows.add(item);
      }
    } else {
      if (query.isEmpty && _category != null) rows.add(_category!);
      rows.addAll(items);
    }

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Row(children: [Icon(Icons.storefront_rounded), SizedBox(width: 10), Text('Browse products')]),
        actions: [
          TextButton(
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
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
                      key: _chipKeys.putIfAbsent('', GlobalKey.new),
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(label: const Text('All'), selected: _category == null, onSelected: (_) => _selectCategory(null)),
                    ),
                    for (final c in categories)
                      Padding(
                        key: _chipKeys.putIfAbsent(c, GlobalKey.new),
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(c),
                          selected: _category == c,
                          onSelected: (v) => _selectCategory(v ? c : null),
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
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragEnd: (d) => _swipeCategory(d, categories),
        child: SafeArea(top: false, child: loading && catalog.isEmpty
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
                        label: const Text('Add it as a new product'),
                        onPressed: _showAddItemDialog,
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  key: ValueKey(_category ?? 'all'), // each category starts at the top
                  // Keep the last rows above the phone's nav buttons and the New item button.
                  padding: const EdgeInsets.only(bottom: 88),
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    if (row is String) {
                      return _SectionHeader(
                        title: row,
                        count: counts[row] ?? 0,
                        expanded: foldable ? _openCategories.contains(row) : null,
                        onTap: foldable
                            ? () => setState(() {
                                  if (!_openCategories.remove(row)) _openCategories.add(row);
                                })
                            : null,
                      );
                    }
                    final item = row as CatalogItem;
                    final existing = onList[item.name.toLowerCase()];
                    return _SuggestionTile(
                      item: item,
                      existing: existing,
                      onTap: () => _add(item),
                      onRemove: (id) => ref.read(groceryProvider.notifier).deleteMultiple({id}),
                      onMenu: (action) => action == 'edit' ? _showItemDialog(edit: item) : _deleteProduct(item),
                    );
                  },
                ))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddItemDialog,
        icon: const Icon(Icons.add),
        label: const Text('New item'),
      ),
    );
  }
}

// ── Toasts ──────────────────────────────────────────────────────────────────

/// Short "✓ item added" pill at the top of the screen.
void showGroceryAddedToast(BuildContext context, String label) =>
    showGroceryToast(context, '$label added');

/// Grocery feedback toast (see [showTopToast]).
void showGroceryToast(
  BuildContext context,
  String message, {
  IconData icon = Icons.check_circle,
  Color color = _green,
}) =>
    showTopToast(context, message, icon: icon, color: color);

// ── Quantity suggestion chips ───────────────────────────────────────────────

/// Tappable quantity suggestions under a quantity box; they follow what is
/// typed ("2" → 2 kg, 2 packets…). Tapping one fills the box.
class QuantitySuggestionChips extends StatelessWidget {
  final TextEditingController controller;
  final String category;
  final VoidCallback? onPicked; // runs after a chip fills the box

  const QuantitySuggestionChips({super.key, required this.controller, this.category = '', this.onPicked});

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
                  onPressed: () {
                    controller.value = TextEditingValue(
                      text: o,
                      selection: TextSelection.collapsed(offset: o.length),
                    );
                    onPicked?.call();
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}
