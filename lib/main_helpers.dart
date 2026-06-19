import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';
import 'providers.dart';
import 'dialogs/expense_dialog.dart';
import 'dialogs/link_dialog.dart';
import 'views/note_editor.dart';

// --- Category Helpers ---

void addCategory(BuildContext context, WidgetRef ref) {
  final controller = TextEditingController();
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      scrollable: true,
      title: const Text('Add Category'),
      content: SingleChildScrollView(
        child: TextField(
          controller: controller, 
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Category Name'),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(
          onPressed: () {
            if (controller.text.isNotEmpty) {
              ref.read(categoriesProvider.notifier).addCategory(controller.text);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Category "${controller.text}" added')));
            }
          },
          child: const Text('Add'),
        ),
      ],
    ),
  );
}

void addLinkCategory(BuildContext context, WidgetRef ref) {
  final controller = TextEditingController();
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      scrollable: true,
      title: const Text('Add Link Category'),
      content: SingleChildScrollView(
        child: TextField(
          controller: controller, 
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Category Name'),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(
          onPressed: () {
            final name = controller.text.trim();
            if (name.isEmpty) return;
            if (name == 'All' || name == 'General') {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('"All" and "General" are reserved category names')),
              );
              return;
            }
            ref.read(linkCategoriesProvider.notifier).addCategory(name);
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Link Category "$name" added')));
          },
          child: const Text('Add'),
        ),
      ],
    ),
  );
}

void manageCategoriesDialog(BuildContext context, WidgetRef ref) {
  showDialog(
    context: context,
    builder: (context) => _CategoryManagementDialog(
      ref: ref,
      title: 'Manage Note Categories',
      provider: categoriesProvider,
      isGeneralProtected: true,
    ),
  );
}

void manageExpenseCategoriesDialog(BuildContext context, WidgetRef ref) {
  showDialog(
    context: context,
    builder: (context) => _CategoryManagementDialog(
      ref: ref,
      title: 'Manage Expense Categories',
      provider: expenseCategoriesProvider,
      isGeneralProtected: false, // Expenses use 'General', 'Uncategorized', etc.
      exclude: const ['All', 'Other'],
    ),
  );
}

void manageLinkCategoriesDialog(BuildContext context, WidgetRef ref) {
  showDialog(
    context: context,
    builder: (context) => _CategoryManagementDialog(
      ref: ref,
      title: 'Manage Link Categories',
      provider: linkCategoriesProvider,
      isGeneralProtected: false,
      exclude: const ['All', 'General'],
    ),
  );
}

void addTableCategory(BuildContext context, WidgetRef ref) {
  final controller = TextEditingController();
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      scrollable: true,
      title: const Text('Add Table Category'),
      content: SingleChildScrollView(
        child: TextField(
          controller: controller, 
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Category Name'),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(
          onPressed: () {
            if (controller.text.isNotEmpty) {
              ref.read(tableCategoriesProvider.notifier).addCategory(controller.text);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Table Category "${controller.text}" added')));
            }
          },
          child: const Text('Add'),
        ),
      ],
    ),
  );
}

void manageTableCategoriesDialog(BuildContext context, WidgetRef ref) {
  showDialog(
    context: context,
    builder: (context) => _CategoryManagementDialog(
      ref: ref,
      title: 'Manage Table Categories',
      provider: tableCategoriesProvider,
      isGeneralProtected: true,
      exclude: const ['All', 'All Cards'],
    ),
  );
}

class _CategoryManagementDialog extends StatefulWidget {
  final WidgetRef ref;
  final String title;
  final dynamic provider; // NotifierProvider
  final bool isGeneralProtected;
  final List<String> exclude;

  const _CategoryManagementDialog({
    required this.ref,
    required this.title,
    required this.provider,
    this.isGeneralProtected = false,
    this.exclude = const [],
  });

  @override
  State<_CategoryManagementDialog> createState() => _CategoryManagementDialogState();
}

class _CategoryManagementDialogState extends State<_CategoryManagementDialog> {
  bool isEditing = false;
  bool isDeleting = false;
  Set<String> toDelete = {};
  final Map<String, TextEditingController> _controllers = {};

  @override
  void dispose() {
    for (var c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _initControllers(List<String> categories) {
    for (var cat in categories) {
      if (!_controllers.containsKey(cat)) {
        _controllers[cat] = TextEditingController(text: cat);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final allCategories = widget.ref.watch(widget.provider) as List<String>;
    final customCategories = allCategories.where((c) {
      if (widget.exclude.contains(c)) return false;
      if (widget.isGeneralProtected && c == 'General') return false;
      return true;
    }).toList();

    if (isEditing) _initControllers(customCategories);

    return AlertDialog(
      titlePadding: EdgeInsets.zero,
      title: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                isEditing ? 'Edit Categories' : (isDeleting ? 'Delete Categories' : widget.title),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            if (!isEditing && !isDeleting) ...[
              IconButton(
                icon: const Icon(Icons.add_rounded, size: 24, color: Color(0xFF1D63D2)), 
                onPressed: () {
                  if (widget.provider == categoriesProvider) {
                    addCategory(context, widget.ref);
                  } else if (widget.provider == expenseCategoriesProvider) addExpenseCategory(context, widget.ref);
                  else if (widget.provider == linkCategoriesProvider) addLinkCategory(context, widget.ref);
                  else if (widget.provider == tableCategoriesProvider) addTableCategory(context, widget.ref);
                }
              ),
              IconButton(icon: const Icon(Icons.edit, size: 20), onPressed: () => setState(() => isEditing = true)),
              IconButton(icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red), onPressed: () => setState(() => isDeleting = true)),
            ] else if (isDeleting) ...[
              IconButton(
                icon: Icon(toDelete.length == customCategories.length ? Icons.deselect : Icons.select_all),
                onPressed: () {
                  setState(() {
                    if (toDelete.length == customCategories.length) {
                      toDelete.clear();
                    } else {
                      toDelete = Set.from(customCategories);
                    }
                  });
                }
              ),
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: toDelete.isEmpty ? null : () {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Delete Categories?'),
                      content: Text('Are you sure you want to delete ${toDelete.length} categories?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                        TextButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            widget.ref.read(widget.provider.notifier).deleteCategories(toDelete.toList());
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${toDelete.length} categories deleted')));
                            setState(() {
                              isDeleting = false;
                              toDelete.clear();
                            });
                          },
                          child: const Text('Delete', style: TextStyle(color: Colors.red)),
                        ),
                      ],
                    ),
                  );
                }
              ),
              IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => isDeleting = false)),
            ],
            if (isEditing) IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => isEditing = false)),
          ],
        ),
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: customCategories.isEmpty
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('No custom categories found.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
              )
            : ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: customCategories.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final cat = customCategories[index];
                    if (isEditing) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: TextField(
                          controller: _controllers[cat],
                          decoration: InputDecoration(
                            isDense: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          ),
                        ),
                      );
                    } else if (isDeleting) {
                      return CheckboxListTile(
                        title: Text(cat),
                        value: toDelete.contains(cat),
                        onChanged: (val) {
                          setState(() {
                            if (val == true) {
                              toDelete.add(cat);
                            } else {
                              toDelete.remove(cat);
                            }
                          });
                        },
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                      );
                    } else {
                      return ListTile(
                        title: Text(cat),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      );
                    }
                  },
                ),
              ),
      ),
      actions: [
        if (isEditing) ...[
          TextButton(
            onPressed: () => setState(() => isEditing = false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Update Categories?'),
                  content: const Text('Are you sure you want to save all renamed categories?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        final notifier = widget.ref.read(widget.provider.notifier);
                        for (var cat in customCategories) {
                          final newName = _controllers[cat]?.text ?? '';
                          if (newName.isNotEmpty && newName != cat) {
                            notifier.renameCategory(cat, newName);
                          }
                        }
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Categories updated')));
                        setState(() => isEditing = false);
                      },
                      child: const Text('Update', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              );
            },
            child: const Text('Update', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
          ),
        ] else
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
    );
  }
}

// --- Note Options ---

void showNoteOptions(BuildContext context, WidgetRef ref, Note note) {
  showModalBottomSheet(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Icon(note.isLocked ? Icons.lock_open : Icons.lock, color: const Color(0xFF1D63D2)),
            title: Text(note.isLocked ? 'Unlock' : 'Lock'),
            onTap: () {
              if (note.isLocked) {
                verifyPasscode(context, ref, onSuccess: () {
                  ref.read(notesProvider.notifier).toggleLock(note.id);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Note Unlocked')));
                });
              } else {
                ref.read(notesProvider.notifier).toggleLock(note.id);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Note Locked')));
              }
            },
          ),
          if (!note.isLocked) ...[
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined, color: Color(0xFF1D63D2)),
              title: const Text('Scan Text (OCR)'),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => NoteEditor(note: note, openOcrOnStart: true)),
                );
              },
            ),
            ListTile(
              leading: Icon(note.isPinned ? Icons.push_pin : Icons.push_pin_outlined, color: const Color(0xFF1D63D2)),
              title: Text(note.isPinned ? 'Unpin' : 'Pin'),
              onTap: () {
                ref.read(notesProvider.notifier).togglePin(note.id);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(note.isPinned ? 'Note Unpinned' : 'Note Pinned')));
              },
            ),
            ListTile(
              leading: Icon(note.isFavorite ? Icons.favorite : Icons.favorite_border, color: Colors.pink),
              title: Text(note.isFavorite ? 'Remove from Favorites' : 'Add to Favorites'),
              onTap: () {
                ref.read(notesProvider.notifier).toggleFavorite(note.id);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(note.isFavorite ? 'Removed from Favorites' : 'Added to Favorites')));
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy, color: Color(0xFF1D63D2)),
              title: const Text('Copy'),
              onTap: () {
                Clipboard.setData(ClipboardData(text: note.content));
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
              },
            ),
            ListTile(
              leading: const Icon(Icons.share, color: Color(0xFF1D63D2)),
              title: const Text('Share'),
              onTap: () {
                Share.share("${note.title}\n\n${note.content}");
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_move, color: Color(0xFF1D63D2)),
              title: const Text('Move to Category'),
              onTap: () {
                Navigator.pop(context);
                _moveNoteDialog(context, ref, note);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Delete Note', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _confirmDelete(context, ref, note.id);
              },
            ),
          ],
        ],
      ),
    ),
  );
}

void _moveNoteDialog(BuildContext context, WidgetRef ref, Note note) {
  final categories = ref.read(categoriesProvider);
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Move to Category'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: categories.length,
          itemBuilder: (context, index) {
            final cat = categories[index];
            return ListTile(
              title: Text(cat),
              onTap: () {
                ref.read(notesProvider.notifier).moveNote(note.id, cat);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Note moved to $cat')));
              },
            );
          },
        ),
      ),
    ),
  );
}

void _confirmDelete(BuildContext context, WidgetRef ref, String id) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Delete Note?'),
      content: const Text('Are you sure you want to move this note to the Recycle Bin?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(
          onPressed: () {
            ref.read(notesProvider.notifier).deleteNote(id);
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Moved to Recycle Bin')));
          },
          child: const Text('Delete', style: TextStyle(color: Colors.red)),
        ),
      ],
    ),
  );
}

// --- Expense Options ---

void showExpenseOptions(BuildContext context, WidgetRef ref, Expense exp) {
  showModalBottomSheet(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Icon(exp.isLocked ? Icons.lock_open : Icons.lock, color: const Color(0xFF1D63D2)),
            title: Text(exp.isLocked ? 'Unlock' : 'Lock'),
            onTap: () {
              if (exp.isLocked) {
                verifyPasscode(context, ref, onSuccess: () {
                  ref.read(expensesProvider.notifier).toggleLock(exp.id);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Expense Unlocked')));
                });
              } else {
                ref.read(expensesProvider.notifier).toggleLock(exp.id);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Expense Locked')));
              }
            },
          ),
          if (!exp.isLocked) ...[
            ListTile(
              leading: Icon(exp.isPinned ? Icons.push_pin : Icons.push_pin_outlined, color: const Color(0xFF1D63D2)),
              title: Text(exp.isPinned ? 'Unpin' : 'Pin'),
              onTap: () {
                ref.read(expensesProvider.notifier).togglePin(exp.id);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(exp.isPinned ? 'Expense Unpinned' : 'Expense Pinned')));
              },
            ),
            ListTile(
              leading: Icon(exp.isFavorite ? Icons.favorite : Icons.favorite_border, color: Colors.pink),
              title: Text(exp.isFavorite ? 'Remove from Favorites' : 'Add to Favorites'),
              onTap: () {
                ref.read(expensesProvider.notifier).toggleFavorite(exp.id);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(exp.isFavorite ? 'Removed from Favorites' : 'Added to Favorites')));
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit, color: Color(0xFF1D63D2)),
              title: const Text('Edit'),
              onTap: () {
                Navigator.pop(context);
                showDialog(context: context, useRootNavigator: true, builder: (context) => ExpenseDialog(expense: exp));
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy, color: Color(0xFF1D63D2)),
              title: const Text('Copy'),
              onTap: () {
                Clipboard.setData(ClipboardData(text: '${exp.title}: ₹${exp.amount}'));
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
              },
            ),
            ListTile(
              leading: const Icon(Icons.share, color: Color(0xFF1D63D2)),
              title: const Text('Share'),
              onTap: () {
                Share.share('${exp.title}: ₹${exp.amount}');
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.move_to_inbox, color: Color(0xFF1D63D2)),
              title: const Text('Move to Category'),
              onTap: () {
                Navigator.pop(context);
                _moveExpenseDialog(context, ref, exp);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Delete', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Delete Expense?'),
                    content: const Text('Move this expense to the Recycle Bin?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                      TextButton(
                        onPressed: () {
                          ref.read(expensesProvider.notifier).deleteExpense(exp.id);
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Moved to Recycle Bin')));
                        },
                        child: const Text('Delete', style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ],
      ),
    ),
  );
}

void _moveExpenseDialog(BuildContext context, WidgetRef ref, Expense expense) {
  final categories = ref.read(expenseCategoriesProvider).where((c) => c != 'All').toList();
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Move to Category'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: categories.map((cat) => ListTile(
          title: Text(cat),
          onTap: () {
            ref.read(expensesProvider.notifier).moveExpense(expense.id, cat);
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Expense moved to $cat')));
          },
        )).toList(),
      ),
    ),
  );
}

// --- General Flow ---

void createNewNote(BuildContext context, WidgetRef ref) {
  final selectedCat = ref.read(selectedCategoryProvider);
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (context) => NoteEditor(
        note: Note(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          title: '', 
          content: '', 
          category: selectedCat,
        ), 
        isNew: true,
      ),
    ),
  );
}

void createNewExpense(BuildContext context, WidgetRef ref) {
  final selectedCat = ref.read(selectedExpenseCategoryProvider);
  showDialog(context: context, builder: (context) => ExpenseDialog(initialCategory: selectedCat));
}

void createNewLink(BuildContext context, WidgetRef ref) {
  final selectedCat = ref.read(selectedLinkCategoryProvider);
  showDialog(context: context, builder: (context) => LinkDialog(initialCategory: selectedCat));
}

// --- Note Options ---

void showCategoryOptions(BuildContext context, WidgetRef ref, String category) {
  showModalBottomSheet(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit),
            title: const Text('Rename Category'),
            onTap: () {
              Navigator.pop(context);
              _renameCategoryManual(context, ref, category);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.red),
            title: const Text('Delete', style: TextStyle(color: Colors.red)),
            onTap: () {
              Navigator.pop(context);
              _confirmDeleteCategory(context, ref, category);
            },
          ),
        ],
      ),
    ),
  );
}

void _renameCategoryManual(BuildContext context, WidgetRef ref, String oldName) {
  final controller = TextEditingController(text: oldName);
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Rename Category'),
      content: TextField(controller: controller, autofocus: true),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(
          onPressed: () {
            if (controller.text.isNotEmpty) {
              ref.read(categoriesProvider.notifier).renameCategory(oldName, controller.text);
              Navigator.pop(context);
            }
          },
          child: const Text('Rename'),
        ),
      ],
    ),
  );
}

void _confirmDeleteCategory(BuildContext context, WidgetRef ref, String category) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Delete Category?'),
      content: Text('Are you sure you want to delete "$category"? All notes in this category will be moved to "General".'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(
          onPressed: () {
            ref.read(categoriesProvider.notifier).deleteCategory(category);
            Navigator.pop(context);
          },
          child: const Text('Delete', style: TextStyle(color: Colors.red)),
        ),
      ],
    ),
  );
}

// --- Link Options ---

void showLinkCategoryOptions(BuildContext context, WidgetRef ref, String category) {
  showModalBottomSheet(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit),
            title: const Text('Rename Category'),
            onTap: () {
              Navigator.pop(context);
              _renameLinkCategoryManual(context, ref, category);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.red),
            title: const Text('Delete', style: TextStyle(color: Colors.red)),
            onTap: () {
              Navigator.pop(context);
              _confirmDeleteLinkCategory(context, ref, category);
            },
          ),
        ],
      ),
    ),
  );
}

void _renameLinkCategoryManual(BuildContext context, WidgetRef ref, String oldName) {
  final controller = TextEditingController(text: oldName);
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Rename Category'),
      content: TextField(controller: controller, autofocus: true),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(
          onPressed: () {
            if (controller.text.isNotEmpty) {
              ref.read(linkCategoriesProvider.notifier).renameCategory(oldName, controller.text);
              Navigator.pop(context);
            }
          },
          child: const Text('Rename'),
        ),
      ],
    ),
  );
}

void _confirmDeleteLinkCategory(BuildContext context, WidgetRef ref, String category) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Delete Category?'),
      content: Text('Are you sure you want to delete "$category"? All links in this category will be moved to "All".'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(
          onPressed: () {
            ref.read(linkCategoriesProvider.notifier).deleteCategory(category);
            Navigator.pop(context);
          },
          child: const Text('Delete', style: TextStyle(color: Colors.red)),
        ),
      ],
    ),
  );
}

// --- Expense Options ---

void addExpenseCategory(BuildContext context, WidgetRef ref) {
  final controller = TextEditingController();
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      scrollable: true,
      title: const Text('Add Expense Category'),
      content: SingleChildScrollView(
        child: TextField(
          controller: controller, 
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Category Name'),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(
          onPressed: () {
            if (controller.text.isNotEmpty) {
              ref.read(expenseCategoriesProvider.notifier).addCategory(controller.text);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Expense Category "${controller.text}" added')));
            }
          },
          child: const Text('Add'),
        ),
      ],
    ),
  );
}

void showExpenseCategoryOptions(BuildContext context, WidgetRef ref, String category) {
  showModalBottomSheet(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (category != 'General') ...[
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Rename Category'),
              onTap: () {
                Navigator.pop(context);
                _renameExpenseCategory(context, ref, category);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Delete Category'),
              onTap: () {
                Navigator.pop(context);
                ref.read(expenseCategoriesProvider.notifier).deleteCategory(category);
              },
            ),
          ],
          ListTile(
            leading: const Icon(Icons.account_balance_wallet_outlined, color: Color(0xFF1D63D2)),
            title: const Text('Set Monthly Budget'),
            onTap: () {
              Navigator.pop(context);
              _showBudgetDialog(context, ref, category);
            },
          ),
        ],
      ),
    ),
  );
}

void _showBudgetDialog(BuildContext context, WidgetRef ref, String category) {
  final budgets = ref.read(expenseBudgetProvider);
  final currentBudget = budgets[category];
  final controller = TextEditingController(
    text: currentBudget != null ? currentBudget.toStringAsFixed(0) : '',
  );

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('Budget – $category', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          labelText: 'Monthly Limit (₹)',
          prefixText: '₹ ',
        ),
      ),
      actions: [
        if (currentBudget != null)
          TextButton(
            onPressed: () {
              ref.read(expenseBudgetProvider.notifier).clearBudget(category);
              Navigator.pop(context);
            },
            child: const Text('Clear Budget', style: TextStyle(color: Colors.red)),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
        ),
        TextButton(
          onPressed: () {
            final val = double.tryParse(controller.text);
            if (val != null && val > 0) {
              ref.read(expenseBudgetProvider.notifier).setBudget(category, val);
            }
            Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

void _renameExpenseCategory(BuildContext context, WidgetRef ref, String oldName) {
  final controller = TextEditingController(text: oldName);
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Rename Category'),
      content: TextField(controller: controller, autofocus: true),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(
          onPressed: () {
            if (controller.text.isNotEmpty) {
              ref.read(expenseCategoriesProvider.notifier).renameCategory(oldName, controller.text);
              Navigator.pop(context);
            }
          },
          child: const Text('Rename'),
        ),
      ],
    ),
  );
}

// --- Passcode Helper ---

void verifyPasscode(BuildContext context, WidgetRef ref, {required VoidCallback onSuccess}) async {
  // Read directly from SharedPreferences to avoid race conditions on app launch
  final prefs = await SharedPreferences.getInstance();
  final isLockEnabled = prefs.getBool('security_lock_enabled') ?? true;
  if (!isLockEnabled) {
    onSuccess();
    return;
  }

  final requiredPass = prefs.getString('vault_lock_password') ?? '1851421';

  if (requiredPass.isEmpty) {
    onSuccess();
    return;
  }

  // 1. Try Biometric Authentication first
  final LocalAuthentication auth = LocalAuthentication();
  bool canAuthenticate = false;
  try {
    canAuthenticate = await auth.canCheckBiometrics || await auth.isDeviceSupported();
  } catch (e) {
    canAuthenticate = false;
  }

  if (canAuthenticate) {
    try {
      final bool didAuthenticate = await auth.authenticate(
        localizedReason: 'Please authenticate to unlock',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
      if (didAuthenticate) {
        await Future.delayed(const Duration(milliseconds: 50));
        onSuccess();
        return;
      }
    } catch (e) {
      debugPrint('Biometric authentication error: $e');
    }
  }

  // 2. Fallback to Numeric Passcode Dialog if biometrics are unavailable, failed, or canceled
  if (!context.mounted) return;
  showDialog(
    context: context,
    builder: (context) => _SecurityVerificationDialog(
      requiredPass: requiredPass,
      onSuccess: onSuccess,
    ),
  );
}

class _SecurityVerificationDialog extends StatefulWidget {
  final String requiredPass;
  final VoidCallback onSuccess;

  const _SecurityVerificationDialog({
    required this.requiredPass,
    required this.onSuccess,
  });

  @override
  State<_SecurityVerificationDialog> createState() => _SecurityVerificationDialogState();
}

class _SecurityVerificationDialogState extends State<_SecurityVerificationDialog> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _canCheckBiometrics = false;

  @override
  void initState() {
    super.initState();
    _checkBiometrics();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) {
          _focusNode.requestFocus();
          SystemChannels.textInput.invokeMethod('TextInput.show');
        }
      });
      // Delay and try auto-triggering biometric auth to resolve keyboard/transition race conditions
      Future.delayed(const Duration(milliseconds: 350), () {
        if (mounted && _canCheckBiometrics) {
          _authenticateWithBiometrics();
        }
      });
    });
  }

  Future<void> _checkBiometrics() async {
    final LocalAuthentication auth = LocalAuthentication();
    try {
      final can = await auth.canCheckBiometrics || await auth.isDeviceSupported();
      if (mounted) {
        setState(() {
          _canCheckBiometrics = can;
        });
      }
    } catch (_) {}
  }

  Future<void> _authenticateWithBiometrics() async {
    final LocalAuthentication auth = LocalAuthentication();
    try {
      final bool didAuthenticate = await auth.authenticate(
        localizedReason: 'Please authenticate to unlock',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
      if (didAuthenticate && mounted) {
        Navigator.pop(context);
        widget.onSuccess();
      }
    } catch (e) {
      debugPrint('Biometric authentication error inside dialog: $e');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Security Verification'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Enter your 7-digit passcode:', style: TextStyle(fontSize: 13)),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  autofocus: false,
                  obscureText: true,
                  decoration: const InputDecoration(
                    hintText: 'Passcode',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  maxLength: 7,
                ),
              ),
              if (_canCheckBiometrics) ...[
                const SizedBox(width: 12),
                IconButton(
                  icon: const Icon(Icons.fingerprint, size: 40, color: Color(0xFF1D63D2)),
                  onPressed: _authenticateWithBiometrics,
                  tooltip: 'Authenticate with Fingerprint',
                ),
              ],
            ],
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(
          onPressed: () {
            if (_controller.text == widget.requiredPass) {
              Navigator.pop(context);
              widget.onSuccess();
            } else {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Incorrect passcode')));
            }
          }, 
          child: const Text('Verify'),
        ),
      ],
    );
  }
}
void exportExpensesToTXT(BuildContext context, List<Expense> expenses, String categoryName) async {
  if (expenses.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No expenses to export!')),
    );
    return;
  }

  final StringBuffer txtContent = StringBuffer();
  txtContent.writeln('--- Expenses Export ($categoryName) ---');
  txtContent.writeln('Date | Title | Category | Type | Amount | Note');
  txtContent.writeln('-' * 50);

  final formatter = DateFormat('yyyy-MM-dd HH:mm');
  for (var e in expenses) {
    txtContent.writeln(
      '${formatter.format(e.date)} | ${e.title} | ${e.category} | ${e.type} | ₹${e.amount} | ${e.note ?? ""}'
    );
  }

  try {
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/expenses_${categoryName.toLowerCase().replaceAll(' ', '_')}.txt');
    await file.writeAsString(txtContent.toString());

    final xFile = XFile(file.path);
    await Share.shareXFiles([xFile], subject: 'Expenses Export (TXT) - $categoryName');
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Failed to export expenses: $e')),
    );
  }
}

void exportExpensesToCSV(BuildContext context, List<Expense> expenses, String categoryName) async {
  if (expenses.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No expenses to export!')),
    );
    return;
  }

  final StringBuffer csvContent = StringBuffer();
  csvContent.writeln('Date,Title,Category,Type,Amount,Note');

  final formatter = DateFormat('yyyy-MM-dd HH:mm');
  for (var e in expenses) {
    String cleanTitle = e.title.replaceAll('"', '""');
    if (cleanTitle.contains(',') || cleanTitle.contains('\n') || cleanTitle.contains('"')) {
      cleanTitle = '"$cleanTitle"';
    }
    String cleanCategory = e.category.replaceAll('"', '""');
    if (cleanCategory.contains(',') || cleanCategory.contains('\n') || cleanCategory.contains('"')) {
      cleanCategory = '"$cleanCategory"';
    }
    String cleanNote = (e.note ?? '').replaceAll('"', '""');
    if (cleanNote.contains(',') || cleanNote.contains('\n') || cleanNote.contains('"')) {
      cleanNote = '"$cleanNote"';
    }
    
    csvContent.writeln(
      '${formatter.format(e.date)},$cleanTitle,$cleanCategory,${e.type},${e.amount},$cleanNote'
    );
  }

  try {
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/expenses_${categoryName.toLowerCase().replaceAll(' ', '_')}.csv');
    await file.writeAsString(csvContent.toString());

    final xFile = XFile(file.path);
    await Share.shareXFiles([xFile], subject: 'Expenses Export - $categoryName');
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Failed to export expenses: $e')),
    );
  }
}

void exportTableToCSV(BuildContext context, VaultTable table) async {
  if (table.columns.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Table is empty!')),
    );
    return;
  }

  final StringBuffer csvContent = StringBuffer();
  
  // Header row
  final List<String> headers = table.columns.map((col) {
    String text = col.text.replaceAll('"', '""');
    if (text.contains(',') || text.contains('\n') || text.contains('"')) {
      return '"$text"';
    }
    return text;
  }).toList();
  csvContent.writeln(headers.join(','));

  // Rows
  for (var row in table.rows) {
    final List<String> rowCells = row.map((cell) {
      String text = cell.text.replaceAll('"', '""');
      if (text.contains(',') || text.contains('\n') || text.contains('"')) {
        return '"$text"';
      }
      return text;
    }).toList();
    csvContent.writeln(rowCells.join(','));
  }

  try {
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/${table.title.toLowerCase().replaceAll(' ', '_')}.csv');
    await file.writeAsString(csvContent.toString());

    final xFile = XFile(file.path);
    await Share.shareXFiles([xFile], subject: 'Table Export - ${table.title}');
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Failed to export table: $e')),
    );
  }
}
