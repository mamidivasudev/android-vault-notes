import re

filepath = r'D:\MY FOLDER\AndroidCodes\vault_notes\lib\views\grocery_view.dart'
with open(filepath, 'r', encoding='utf-8') as f:
    content = f.read()

target = '''      trailing: Icon(
        item.isPurchased ? Icons.check_circle : Icons.check_circle_outline,
        color: item.isPurchased ? Colors.green : Colors.grey.withOpacity(0.5),
      ),
      onTap: () {
        ref.read(groceryProvider.notifier).toggleItem(item.id);
      },
      onLongPress: () {
        showModalBottomSheet(
          context: context,
          builder: (sheetContext) => SafeArea(
            child: Wrap(
              children: [
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Edit Item'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _edit(item);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: const Text('Delete this Item', style: TextStyle(color: Colors.red)),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Delete Item?'),
                        content: Text('Are you sure you want to delete "\"?'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                          TextButton(
                            onPressed: () {
                              Navigator.pop(context);
                              ref.read(groceryProvider.notifier).deleteItem(item.id);
                            },
                            child: const Text('Delete', style: TextStyle(color: Colors.red)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.clear_all, color: Colors.red),
                  title: const Text('Select all for delete', style: TextStyle(color: Colors.red)),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Delete All Items?'),
                        content: const Text('Are you sure you want to delete ALL items?'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                          TextButton(
                            onPressed: () {
                              Navigator.pop(context);
                              final allItems = ref.read(groceryProvider);
                              for (var i in allItems) {
                                ref.read(groceryProvider.notifier).deleteItem(i.id);
                              }
                            },
                            child: const Text('Delete All', style: TextStyle(color: Colors.red)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );'''

replacement = '''      trailing: Row(
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
    );'''

if target in content:
    content = content.replace(target, replacement)
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(content)
    print("Updated successfully")
else:
    print("Target not found")
