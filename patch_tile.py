import re

filepath = r'D:\MY FOLDER\AndroidCodes\vault_notes\lib\views\grocery_view.dart'
with open(filepath, 'r', encoding='utf-8') as f:
    content = f.read()

pattern = re.compile(r'      trailing: Icon\([\s\S]*?onTap: \(\) {[\s\S]*?ref\.read\(groceryProvider\.notifier\)\.toggleItem\(item\.id\);[\s\S]*?},[\s\S]*?onLongPress: \(\) {[\s\S]*?showModalBottomSheet\([\s\S]*?}\);[\s\S]*?},[\s\S]*?\);', re.MULTILINE)

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

new_content = pattern.sub(replacement, content, count=1)

if content != new_content:
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(new_content)
    print("Updated successfully")
else:
    print("Target not found")
