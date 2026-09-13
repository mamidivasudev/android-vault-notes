import re

filepath = r'D:\MY FOLDER\AndroidCodes\vault_notes\lib\views\grocery_view.dart'
with open(filepath, 'r', encoding='utf-8') as f:
    content = f.read()

target = '''  void _showDeleteDialog() {
    bool clearToBuy = false;
    bool clearPurchased = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Delete Items'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CheckboxListTile(
                  title: const Text('To Buy Items'),
                  value: clearToBuy,
                  onChanged: (val) {
                    setDialogState(() { clearToBuy = val!; });
                  },
                ),
                CheckboxListTile(
                  title: const Text('Purchased Items'),
                  value: clearPurchased,
                  onChanged: (val) {
                    setDialogState(() { clearPurchased = val!; });
                  },
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              TextButton(
                onPressed: () {
                  if (clearToBuy && clearPurchased) {
                    ref.read(groceryProvider.notifier).clearAll();
                  } else if (clearToBuy) {
                    ref.read(groceryProvider.notifier).clearToBuy();
                  } else if (clearPurchased) {
                    ref.read(groceryProvider.notifier).clearPurchased();
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
  }'''

replacement = '''  void _showDeleteDialog() {
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
  }'''

if target in content:
    content = content.replace(target, replacement)
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(content)
    print("Updated successfully")
else:
    print("Target not found")
