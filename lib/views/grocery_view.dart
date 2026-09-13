import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models.dart';
import '../providers.dart';
import '../profiles/providers/theme_provider.dart';

class GroceryView extends ConsumerStatefulWidget {
  const GroceryView({super.key});

  @override
  ConsumerState<GroceryView> createState() => _GroceryViewState();
}

class _GroceryViewState extends ConsumerState<GroceryView> {
  final TextEditingController _itemController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollAll = ScrollController();
  final ScrollController _scrollToBuy = ScrollController();
  final ScrollController _scrollPurchased = ScrollController();
  String _selectedUnit = '-';
  final TextEditingController _qtyController = TextEditingController();
  bool _hideSuggestions = false;

  @override
  @override
  void initState() {
    super.initState();
    _itemController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _itemController.dispose();
    _qtyController.dispose();
    _focusNode.dispose();
    _scrollAll.dispose();
    _scrollToBuy.dispose();
    _scrollPurchased.dispose();
    super.dispose();
  }

  void _add() {
    final text = _itemController.text.trim();
    if (text.isNotEmpty) {
      String finalItem = text;
      
      final qty = _qtyController.text.trim();
      final unit = _selectedUnit == '-' ? '' : _selectedUnit;

      if (qty.isNotEmpty || unit.isNotEmpty) {
        final parts = <String>[];
        if (qty.isNotEmpty) parts.add(qty);
        if (unit.isNotEmpty) parts.add(unit);
        
        if (parts.isNotEmpty) {
          finalItem = '$text (${parts.join(' ')})';
        }
      }
      
      ref.read(groceryProvider.notifier).addItem(finalItem);
      _itemController.clear();
      _qtyController.clear();
      setState(() { 
        _selectedUnit = '-'; 
        _hideSuggestions = false;
      });
      _focusNode.requestFocus();
      Future.delayed(const Duration(milliseconds: 100), () {
      void scrollBottom(ScrollController c) {
        if (c.hasClients) {
          c.animateTo(c.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
        }
      }
      scrollBottom(_scrollAll);
      scrollBottom(_scrollToBuy);
    });
      
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Item saved', textAlign: TextAlign.center),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.only(
            bottom: MediaQuery.of(context).size.height - 200, 
            left: 60, 
            right: 60
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        ),
      );
    }
  }

  void _showDeleteDialog() {
    final allItems = ref.read(groceryProvider);
    Set<String> selectedIds = {};

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Select Items to Delete'),
            content: SizedBox(
              width: double.maxFinite,
              height: 400,
              child: ListView.builder(
                itemCount: allItems.length,
                itemBuilder: (context, index) {
                  final item = allItems[index];
                  return CheckboxListTile(
                    title: Text(item.name, style: TextStyle(
                      decoration: item.isPurchased ? TextDecoration.lineThrough : null,
                    )),
                    value: selectedIds.contains(item.id),
                    onChanged: (val) {
                      setDialogState(() {
                        if (val == true) {
                          selectedIds.add(item.id);
                        } else {
                          selectedIds.remove(item.id);
                        }
                      });
                    },
                  );
                },
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              TextButton(
                onPressed: () {
                  if (selectedIds.isNotEmpty) {
                    ref.read(groceryProvider.notifier).deleteMultiple(selectedIds);
                  }
                  Navigator.pop(context);
                },
                child: const Text('Delete', style: TextStyle(color: Colors.red)),
              ),
            ],
          );
        }
      ),
    );
  }

  void _edit(GroceryItem item) {
    String parsedName = item.name;
    String parsedQty = '';
    String parsedUnit = '-';

    final match = RegExp(r'^(.*?)\s*\((.*?)\)$').firstMatch(item.name);
    if (match != null) {
      parsedName = match.group(1)!;
      String qtyStr = match.group(2)!;
      final units = ['kilograms', 'grams', 'half kg', '1/4 kg', 'kg', 'g', 'liter', 'L', 'ml', 'packet', 'piece', 'dozen', 'rupees'];
      bool found = false;
      for (var u in units) {
        if (qtyStr.endsWith(u)) {
          parsedUnit = u;
          parsedQty = qtyStr.substring(0, qtyStr.length - u.length).trim();
          found = true;
          break;
        }
      }
      if (!found) {
        parsedQty = qtyStr;
      }
    }

    final editNameController = TextEditingController(text: parsedName);
    if (parsedQty == '-') parsedQty = '';
    final editQtyController = TextEditingController(text: parsedQty);
    String currentUnit = parsedUnit;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Edit Item'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: editNameController,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Item Name', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Container(
                        height: 56,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade400),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: currentUnit,
                            isExpanded: true,
                            items: ['-', 'kg', 'half kg', 'grams', '1/4 kg', 'liter', 'ml', 'packet', 'piece', 'dozen', 'rupees']
                                .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                                .toList(),
                            onChanged: (val) {
                              setDialogState(() { currentUnit = val!; });
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: Container(
                        height: 56,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade400),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: editQtyController,
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  hintText: '-',
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                            ),
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.arrow_drop_down, size: 20),
                              padding: EdgeInsets.zero,
                              onSelected: (val) {
                                if (val == '-') {
                                  editQtyController.clear();
                                } else {
                                  editQtyController.text = val;
                                }
                              },
                              itemBuilder: (_) => ['-', '1', '2', '3', '4', '5', '6', '7', '8', '9', '10']
                                  .map((q) => PopupMenuItem(value: q, child: Text(q)))
                                  .toList(),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                )
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              TextButton(
                onPressed: () {
                  String finalName = editNameController.text.trim();
                  if (finalName.isNotEmpty) {
                    final q = editQtyController.text.trim();
                    final u = currentUnit == '-' ? '' : currentUnit;
                    if (q.isNotEmpty || u.isNotEmpty) {
                      final parts = [];
                      if (q.isNotEmpty) parts.add(q);
                      if (u.isNotEmpty) parts.add(u);
                      finalName = '$finalName (${parts.join(' ')})';
                    }
                    ref.read(groceryProvider.notifier).editItem(item.id, finalName);
                  }
                  Navigator.pop(context);
                },
                child: const Text('Save'),
              ),
            ],
          );
        }
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
    final items = ref.watch(groceryProvider);

    final pending = items.where((e) => !e.isPurchased).toList();
    final purchased = items.where((e) => e.isPurchased).toList();

    Widget buildList(List<GroceryItem> list, ScrollController controller) {
      return list.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.shopping_cart_outlined, size: 64, color: isDark ? Colors.white30 : Colors.black26),
                  const SizedBox(height: 16),
                  Text('No items here.', style: TextStyle(color: isDark ? Colors.white54 : Colors.black54, fontSize: 16)),
                ],
              ),
            )
          : Scrollbar(
              controller: controller,
              thumbVisibility: true,
              child: ListView.builder(
                controller: controller,
                itemCount: list.length,
                itemBuilder: (context, index) {
                  return _buildItemTile(list[index], isDark);
                },
              ),
            );
    }

    Widget buildSuggestions() {
      final query = _itemController.text.trim().toLowerCase();
      if (query.isEmpty) return const SizedBox.shrink();
      
      final catalogAsync = ref.watch(groceryCatalogProvider);
      return catalogAsync.when(
        data: (catalog) {
          final suggestions = catalog.where((item) {
            final names = item['names'] as Map<String, dynamic>? ?? {};
            final searchTerms = item['search_terms'] as Map<String, dynamic>? ?? {};
            
            for (var v in names.values) {
              if (v.toString().toLowerCase().contains(query)) return true;
            }
            for (var list in searchTerms.values) {
              if (list is List) {
                if (list.any((t) => t.toString().toLowerCase().contains(query))) return true;
              }
            }
            return false;
          }).take(4).toList();

          if (suggestions.isEmpty) return const SizedBox.shrink();

          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[850] : Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)]
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: suggestions.map((item) {
                final itemName = item['names']?['en']?.toString() ?? 'Unknown';
                String subtitle = '';
                final names = item['names'] as Map<String, dynamic>? ?? {};
                if (names.containsKey('te') && names['te'] != null) subtitle += names['te'].toString() + " ";
                if (names.containsKey('hi') && names['hi'] != null) subtitle += names['hi'].toString() + " ";
                if (names.containsKey('local') && names['local'] != null) subtitle += names['local'].toString();

                return ListTile(
                  dense: true,
                  title: Text(itemName),
                  subtitle: subtitle.trim().isNotEmpty ? Text(subtitle.trim(), style: const TextStyle(fontSize: 10)) : null,
                  onTap: () {
                    _itemController.text = itemName;
                    _itemController.selection = TextSelection.fromPosition(TextPosition(offset: itemName.length));
                    _focusNode.requestFocus();
                  }
                );
              }).toList()
            )
          );
        },
        loading: () => const SizedBox.shrink(),
        error: (_, __) => const SizedBox.shrink(),
      );
    }

    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          // Tabs & Settings
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, top: 8),
            child: Row(
              children: [
                Expanded(
                  child: TabBar(
                    labelColor: isDark ? Colors.white : Colors.black87,
                    unselectedLabelColor: isDark ? Colors.white30 : Colors.black38,
                    indicatorColor: Colors.blue,
                    labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    tabs: [
                      Tab(text: 'ALL (${items.length})'),
                      Tab(text: 'TO BUY (${pending.length})'),
                      Tab(text: 'PURCHASED (${purchased.length})'),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: Icon(Icons.settings_outlined, color: isDark ? Colors.white70 : Colors.black87),
                  onSelected: (value) {
                    if (value == 'MasterList') {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const GroceryMasterListView()));
                    } else if (value == 'Delete') {
                      _showDeleteDialog();
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$value coming soon')));
                    }
                  },
                  itemBuilder: (context) {
                    return const [
                      PopupMenuItem(value: 'MasterList', child: Text('Master List')),
                      PopupMenuDivider(),
                      PopupMenuItem(value: 'Delete', child: Text('Delete Items', style: TextStyle(color: Colors.red))),
                      PopupMenuDivider(),
                      PopupMenuItem(value: 'Share', child: Text('Share List')),
                      PopupMenuItem(value: 'Export', child: Text('Export List')),
                      PopupMenuItem(value: 'Import', child: Text('Import List')),
                    ];
                  },
                )
              ],
            ),
          ),
          
          // List area
          Expanded(
            child: Stack(
              children: [
                TabBarView(
                  children: [
                    buildList(items, _scrollAll),
                    buildList(pending, _scrollToBuy),
                    buildList(purchased, _scrollPurchased),
                  ],
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: buildSuggestions(),
                ),
              ],
            ),
          ),

          // Input area (WhatsApp style at bottom)
          SafeArea(
            bottom: true,
            child: Padding(
              padding: const EdgeInsets.only(left: 12.0, right: 12.0, bottom: 12.0, top: 4.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _itemController,
                      focusNode: _focusNode,
                      textInputAction: TextInputAction.done,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'Add grocery item...',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                        filled: true,
                        fillColor: isDark ? Colors.grey.shade900 : Colors.white,
                      ),
                      onChanged: (val) {
                        if (_hideSuggestions) {
                          setState(() { _hideSuggestions = false; });
                        }
                      },
                      onSubmitted: (_) => _add(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey.shade900 : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade400, width: 1),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedUnit,
                        isDense: true,
                        menuMaxHeight: 300,
                        icon: const Icon(Icons.arrow_drop_down, size: 20),
                        style: TextStyle(fontSize: 13, color: isDark ? Colors.white : Colors.black87),
                        items: ['-', 'kg', 'half kg', 'grams', '1/4 kg', 'liter', 'ml', 'packet', 'piece']
                            .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                            .toList(),
                        onChanged: (val) {
                          setState(() { _selectedUnit = val!; });
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Container(
                    height: 48,
                    width: 65,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey.shade900 : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade400, width: 1),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _qtyController,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              hintText: '-',
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ),
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.arrow_drop_down, size: 20),
                          padding: EdgeInsets.zero,
                          onSelected: (val) {
                            setState(() {
                              if (val == '-') {
                                _qtyController.clear();
                              } else {
                                _qtyController.text = val;
                              }
                            });
                          },
                          itemBuilder: (_) => ['-', '1', '2', '3', '4', '5', '6', '7', '8', '9', '10']
                              .map((q) => PopupMenuItem(value: q, child: Text(q)))
                              .toList(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: const Color(0xFF1DA75E),
                    child: IconButton(
                      icon: const Icon(Icons.check, color: Colors.white),
                      onPressed: _add,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      )
    );
  }

  Widget _buildItemTile(GroceryItem item, bool isDark) {
    String displayName = item.name;
    String displayQty = '';
    
    final match = RegExp(r'^(.*?)\s*\((.*?)\)$').firstMatch(item.name);
    if (match != null) {
      displayName = match.group(1)!;
      displayQty = match.group(2)!;
    }

    return ListTile(
      title: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 1,
            child: Text(
              displayName,
              style: TextStyle(
                decoration: item.isPurchased ? TextDecoration.lineThrough : null,
                color: item.isPurchased 
                    ? (isDark ? Colors.white30 : Colors.black38) 
                    : (isDark ? Colors.white : Colors.black87),
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: displayQty.isNotEmpty
                ? Padding(
                    padding: const EdgeInsets.only(left: 8.0),
                    child: Text(
                      displayQty,
                      textAlign: TextAlign.left,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        decoration: item.isPurchased ? TextDecoration.lineThrough : null,
                        color: item.isPurchased 
                            ? (isDark ? Colors.white30 : Colors.black38) 
                            : (isDark ? Colors.white70 : Colors.black54),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 20),
            color: Colors.blue,
            onPressed: () => _edit(item),
          ),
          Icon(
            item.isPurchased ? Icons.check_circle : Icons.check_circle_outline,
            color: item.isPurchased ? Colors.green : Colors.grey.withOpacity(0.5),
          ),
        ],
      ),
      onTap: () {
        ref.read(groceryProvider.notifier).toggleItem(item.id);
      },
    );
  }
}

class GroceryMasterListView extends ConsumerStatefulWidget {
  const GroceryMasterListView({super.key});

  @override
  ConsumerState<GroceryMasterListView> createState() => _GroceryMasterListViewState();
}

class _GroceryMasterListViewState extends ConsumerState<GroceryMasterListView> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showAddItemDialog() {
    final enController = TextEditingController();
    final localController = TextEditingController();
    final searchController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add Custom Item'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: enController, decoration: const InputDecoration(labelText: 'English Name (e.g. Rice)')),
                TextField(controller: localController, decoration: const InputDecoration(labelText: 'Local Name (e.g. బియ్యం)')),
                TextField(controller: searchController, decoration: const InputDecoration(labelText: 'Search Keywords (comma separated)')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            TextButton(
              onPressed: () {
                if (enController.text.trim().isNotEmpty) {
                  ref.read(groceryCatalogProvider.notifier).addCustomItem(
                    enController.text.trim(),
                    localController.text.trim(),
                    searchController.text.trim()
                  );
                }
                Navigator.pop(context);
              },
              child: const Text('Add')
            ),
          ],
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    final catalogAsync = ref.watch(groceryCatalogProvider);
    final query = _searchController.text.trim().toLowerCase();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Grocery Master List'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search catalog...',
                filled: true,
                fillColor: Theme.of(context).cardColor,
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
          ),
        ),
      ),
      body: catalogAsync.when(
        data: (catalog) {
          final items = catalog.where((item) {
            if (query.isEmpty) return true;
            final names = item['names'] as Map<String, dynamic>? ?? {};
            final searchTerms = item['search_terms'] as Map<String, dynamic>? ?? {};
            
            for (var v in names.values) {
              if (v.toString().toLowerCase().contains(query)) return true;
            }
            for (var list in searchTerms.values) {
              if (list is List) {
                if (list.any((t) => t.toString().toLowerCase().contains(query))) return true;
              }
            }
            return false;
          }).toList();

          if (items.isEmpty) return const Center(child: Text('No items found.'));

          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              final enName = item['names']?['en']?.toString() ?? 'Unknown';
              String subtitle = '';
              final names = item['names'] as Map<String, dynamic>? ?? {};
              if (names.containsKey('te') && names['te'] != null) subtitle += names['te'].toString() + " ";
              if (names.containsKey('hi') && names['hi'] != null) subtitle += names['hi'].toString() + " ";
              if (names.containsKey('local') && names['local'] != null) subtitle += names['local'].toString();

              return ListTile(
                title: Text(enName),
                subtitle: subtitle.trim().isNotEmpty ? Text(subtitle.trim()) : null,
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddItemDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}
