import re

filepath = r'D:\MY FOLDER\AndroidCodes\vault_notes\lib\views\grocery_view.dart'
with open(filepath, 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Fix _selectedQty block
target1 = '''                  const SizedBox(width: 4),
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
                        value: _selectedQty,
                        isDense: true,
                        menuMaxHeight: 300,
                        icon: const Icon(Icons.arrow_drop_down, size: 20),
                        style: TextStyle(fontSize: 13, color: isDark ? Colors.white : Colors.black87),
                        items: ['-', '1', '2', '3', '4', '5', '6', '7', '8', '9', '10']
                            .map((q) => DropdownMenuItem(value: q, child: Text(q)))
                            .toList(),
                        onChanged: (val) {
                          setState(() { _selectedQty = val!; });
                        },
                      ),
                    ),
                  ),'''

replacement1 = '''                  const SizedBox(width: 4),
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
                  ),'''

if target1 in content:
    content = content.replace(target1, replacement1)
else:
    print('target1 not found')

# 2. Fix trailing braces at the end of _buildItemTile and remove them so the class isn't closed
# Right now it's:
#     );
#       }
#     );
#   }
# 
#   @override
#   Widget build(BuildContext context) {
target2 = '''    );
      }
    );
  }

  @override
  Widget build(BuildContext context) {'''

replacement2 = '''    );
  }

  @override
  Widget build(BuildContext context) {'''

if target2 in content:
    content = content.replace(target2, replacement2)
else:
    # Look for it again
    target2_alt = '''    );
      }
    );
  }
}

class GroceryMasterListView'''

    if target2_alt in content:
        print('wait, build() is not part of this class?')

with open(filepath, 'w', encoding='utf-8') as f:
    f.write(content)
print("Updated successfully")
