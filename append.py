import sys

filepath = r"D:\MY FOLDER\AndroidCodes\vault_notes\lib\views\grocery_view.dart"
code = """

class GroceryMasterListView extends ConsumerStatefulWidget {
  const GroceryMasterListView({Key? key}) : super(key: key);

  @override
  ConsumerState<GroceryMasterListView> createState() => _GroceryMasterListViewState();
}

class _GroceryMasterListViewState extends ConsumerState<GroceryMasterListView> {
  final TextEditingController _searchController = TextEditingController();
  
  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      if (mounted) setState(() {});
    });
  }
  
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
"""

with open(filepath, 'a', encoding='utf-8') as f:
    f.write(code)
