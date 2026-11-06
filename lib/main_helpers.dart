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
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'widgets/note_card.dart' show NoteColors;

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
  final hasReminder = ref.read(remindersProvider).any((r) => r.id == noteReminderId(note.id) && !r.isDismissed);
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(note.isLocked ? Icons.lock_open : Icons.lock, color: const Color(0xFF1D63D2)),
              title: Text(note.isLocked ? 'Unlock' : 'Lock'),
              onTap: () {
                final messenger = ScaffoldMessenger.of(context);
                Navigator.pop(sheetContext);
                if (note.isLocked) {
                  verifyPasscode(context, ref, onSuccess: () {
                    ref.read(notesProvider.notifier).toggleLock(note.id);
                    messenger.showSnackBar(const SnackBar(content: Text('Note Unlocked')));
                  });
                } else {
                  ref.read(notesProvider.notifier).toggleLock(note.id);
                  messenger.showSnackBar(const SnackBar(content: Text('Note Locked')));
                }
              },
            ),
            if (!note.isLocked) ...[
              ListTile(
                leading: const Icon(Icons.document_scanner_outlined, color: Color(0xFF1D63D2)),
                title: const Text('Scan Text (OCR)'),
                onTap: () {
                  Navigator.pop(sheetContext);
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
                  Navigator.pop(sheetContext);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(note.isPinned ? 'Note Unpinned' : 'Note Pinned')));
                },
              ),
              ListTile(
                leading: Icon(note.isFavorite ? Icons.favorite : Icons.favorite_border, color: Colors.pink),
                title: Text(note.isFavorite ? 'Remove from Favorites' : 'Add to Favorites'),
                onTap: () {
                  ref.read(notesProvider.notifier).toggleFavorite(note.id);
                  Navigator.pop(sheetContext);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(note.isFavorite ? 'Removed from Favorites' : 'Added to Favorites')));
                },
              ),
              ListTile(
                leading: Icon(hasReminder ? Icons.notifications_active : Icons.notifications_none, color: const Color(0xFFF59E0B)),
                title: Text(hasReminder ? 'Edit Reminder' : 'Set Reminder'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  setNoteReminder(context, ref, note);
                },
              ),
              ListTile(
                leading: const Icon(Icons.palette_outlined, color: Color(0xFF1D63D2)),
                title: const Text('Color'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  final color = await pickNoteColor(context, note.colorIndex);
                  if (color != null) {
                    ref.read(notesProvider.notifier).updateNote(note.copyWith(colorIndex: color));
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.copy, color: Color(0xFF1D63D2)),
                title: const Text('Copy'),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: noteShareText(note)));
                  Navigator.pop(sheetContext);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
                },
              ),
              ListTile(
                leading: const Icon(Icons.share, color: Color(0xFF1D63D2)),
                title: const Text('Share'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  Share.share(noteShareText(note));
                },
              ),
              ListTile(
                leading: const Icon(Icons.ios_share, color: Color(0xFF1D63D2)),
                title: const Text('Export'),
                subtitle: const Text('As a .txt or PDF file'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  showNoteExportSheet(context, note);
                },
              ),
              ListTile(
                leading: const Icon(Icons.drive_file_move, color: Color(0xFF1D63D2)),
                title: const Text('Move to Category'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _moveNoteDialog(context, ref, note);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Delete Note', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  deleteNotesWithUndo(context, ref, [note.id]);
                },
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

void _moveNoteDialog(BuildContext context, WidgetRef ref, Note note) {
  final categories = ref.read(categoriesProvider);
  showDialog(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Move to Category'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: categories.length,
          itemBuilder: (_, index) {
            final cat = categories[index];
            return ListTile(
              title: Text(cat),
              trailing: cat == note.category ? const Icon(Icons.check, size: 18) : null,
              onTap: () {
                ref.read(notesProvider.notifier).moveNote(note.id, cat);
                Navigator.pop(dialogContext);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Note moved to $cat')));
              },
            );
          },
        ),
      ),
    ),
  );
}

/// Moves notes to the Recycle Bin and shows a snackbar with an Undo action.
void deleteNotesWithUndo(BuildContext context, WidgetRef ref, List<String> ids) {
  if (ids.isEmpty) return;
  final messenger = ScaffoldMessenger.of(context);
  ref.read(notesProvider.notifier).deleteNotes(ids);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(ids.length == 1 ? 'Note moved to Recycle Bin' : '${ids.length} notes moved to Recycle Bin'),
      duration: const Duration(seconds: 5),
      action: SnackBarAction(
        label: 'UNDO',
        onPressed: () async {
          final bin = ref.read(deletedNotesProvider.notifier);
          for (final id in ids) {
            await bin.restoreNote(id);
          }
        },
      ),
    ),
  );
}

/// Title + body as plain text (checklists become "☐ item" / "☑ item").
String noteShareText(Note note) {
  final body = note.isChecklist
      ? ChecklistItem.parse(note.content).map((i) => '${i.checked ? '☑' : '☐'} ${i.text}').join('\n')
      : note.content;
  if (note.title.isEmpty) return body;
  return '${note.title}\n\n$body';
}

/// Lets the user pick a colour label. Returns the colour index or null if cancelled.
Future<int?> pickNoteColor(BuildContext context, int current) {
  return showModalBottomSheet<int>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Note color', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (int i = 0; i < NoteColors.swatches.length; i++)
                  Tooltip(
                    message: NoteColors.names[i],
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => Navigator.pop(sheetContext, i),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: i == 0 ? null : NoteColors.swatches[i],
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: i == current ? Theme.of(sheetContext).colorScheme.primary : Colors.grey.shade400,
                            width: i == current ? 3 : 1,
                          ),
                        ),
                        child: i == 0
                            ? const Icon(Icons.format_color_reset, size: 20, color: Colors.grey)
                            : (i == current ? const Icon(Icons.check, color: Colors.white, size: 20) : null),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

/// Adds, changes or removes the reminder attached to [note].
Future<void> setNoteReminder(BuildContext context, WidgetRef ref, Note note) async {
  final id = noteReminderId(note.id);
  final existing = ref.read(remindersProvider).where((r) => r.id == id && !r.isDismissed).firstOrNull;
  final messenger = ScaffoldMessenger.of(context);

  if (existing != null) {
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Note Reminder'),
        content: Text('Reminder set for ${DateFormat('EEE, MMM d · h:mm a').format(existing.dateTime)}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'remove'), child: const Text('Remove', style: TextStyle(color: Colors.red))),
          TextButton(onPressed: () => Navigator.pop(ctx, 'change'), child: const Text('Change')),
        ],
      ),
    );
    if (action == 'remove') {
      await ref.read(remindersProvider.notifier).deleteReminder(id);
      messenger.showSnackBar(const SnackBar(content: Text('Reminder removed')));
      return;
    }
    if (action != 'change') return;
  }
  if (!context.mounted) return;

  final now = DateTime.now();
  final initial = existing?.dateTime ?? now.add(const Duration(hours: 1));
  final date = await showDatePicker(
    context: context,
    initialDate: initial.isBefore(now) ? now : initial,
    firstDate: DateTime(now.year, now.month, now.day),
    lastDate: DateTime(now.year + 5),
  );
  if (date == null || !context.mounted) return;
  final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial));
  if (time == null) return;

  final when = DateTime(date.year, date.month, date.day, time.hour, time.minute);
  if (!when.isAfter(DateTime.now())) {
    messenger.showSnackBar(const SnackBar(content: Text('Pick a time in the future')));
    return;
  }

  final title = note.title.isEmpty ? 'Note reminder' : note.title;
  final description = note.isLocked ? 'Open Vault Notes to view this note' : ChecklistItem.toPlainText(note.content).trim();
  final shortDesc = description.length > 120 ? '${description.substring(0, 120)}…' : description;
  final notifier = ref.read(remindersProvider.notifier);
  final anyExisting = ref.read(remindersProvider).where((r) => r.id == id).firstOrNull;
  if (anyExisting != null) {
    await notifier.updateReminder(anyExisting.copyWith(title: title, description: shortDesc, dateTime: when, isDismissed: false));
  } else {
    await notifier.addReminder(Reminder(id: id, title: title, description: shortDesc, dateTime: when));
  }
  messenger.showSnackBar(SnackBar(content: Text('Reminder set for ${DateFormat('EEE, MMM d · h:mm a').format(when)}')));
}

void showNoteExportSheet(BuildContext context, Note note) {
  showModalBottomSheet(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.description_outlined, color: Color(0xFF1D63D2)),
            title: const Text('Export as .txt'),
            onTap: () {
              Navigator.pop(sheetContext);
              exportNote(context, note, asPdf: false);
            },
          ),
          ListTile(
            leading: const Icon(Icons.picture_as_pdf_outlined, color: Colors.red),
            title: const Text('Export as PDF'),
            onTap: () {
              Navigator.pop(sheetContext);
              exportNote(context, note, asPdf: true);
            },
          ),
        ],
      ),
    ),
  );
}

Future<void> exportNote(BuildContext context, Note note, {required bool asPdf}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final dir = await getTemporaryDirectory();
    final safeName = (note.title.isEmpty ? 'note' : note.title)
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '_');
    final baseName = safeName.isEmpty ? 'note' : (safeName.length > 50 ? safeName.substring(0, 50) : safeName);

    late File file;
    if (asPdf) {
      // Use the device's Roboto font when available so symbols like ₹ render.
      pw.Font? font;
      pw.Font? fontBold;
      try {
        final regular = File('/system/fonts/Roboto-Regular.ttf');
        if (await regular.exists()) font = pw.Font.ttf((await regular.readAsBytes()).buffer.asByteData());
        final bold = File('/system/fonts/Roboto-Bold.ttf');
        if (await bold.exists()) fontBold = pw.Font.ttf((await bold.readAsBytes()).buffer.asByteData());
      } catch (_) {}

      final doc = pw.Document(theme: font == null ? null : pw.ThemeData.withFont(base: font, bold: fontBold ?? font));
      final meta = 'Created ${DateFormat('MMM d, yyyy h:mm a').format(note.createdAt)}'
          '${note.updatedAt != null ? '  ·  Edited ${DateFormat('MMM d, yyyy h:mm a').format(note.updatedAt!)}' : ''}'
          '  ·  #${note.category}';
      doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (_) => [
          pw.Text(note.title.isEmpty ? 'Untitled Note' : note.title,
              style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.Text(meta, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
          pw.Divider(),
          if (note.isChecklist)
            ...ChecklistItem.parse(note.content).map((i) => pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 2),
                  child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                    pw.Container(
                      width: 10,
                      height: 10,
                      margin: const pw.EdgeInsets.only(top: 2, right: 8),
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(width: 1),
                        color: i.checked ? PdfColors.grey600 : null,
                      ),
                    ),
                    pw.Expanded(
                      child: pw.Text(i.text,
                          style: pw.TextStyle(
                              fontSize: 12, decoration: i.checked ? pw.TextDecoration.lineThrough : null)),
                    ),
                  ]),
                ))
          else
            // One paragraph per line so long notes can break across pages.
            ...note.content.split('\n').map((line) => pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 3),
                  child: pw.Text(line, style: const pw.TextStyle(fontSize: 12, lineSpacing: 3)),
                )),
        ],
      ));
      file = File('${dir.path}/$baseName.pdf');
      await file.writeAsBytes(await doc.save());
    } else {
      file = File('${dir.path}/$baseName.txt');
      await file.writeAsString(noteShareText(note));
    }
    await Share.shareXFiles([XFile(file.path)], subject: note.title.isEmpty ? 'Note' : note.title);
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
  }
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
            final newName = controller.text.trim();
            if (newName.isEmpty) return;
            if (newName != oldName && ref.read(categoriesProvider).contains(newName)) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('A category named "$newName" already exists')));
              return;
            }
            ref.read(categoriesProvider.notifier).renameCategory(oldName, newName);
            Navigator.pop(context);
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
      content: Text('Are you sure you want to delete "$category"? All notes in this category will be moved to the Recycle Bin.'),
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
            final newName = controller.text.trim();
            if (newName.isEmpty) return;
            if (newName != oldName && ref.read(linkCategoriesProvider).contains(newName)) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('A category named "$newName" already exists')));
              return;
            }
            ref.read(linkCategoriesProvider.notifier).renameCategory(oldName, newName);
            Navigator.pop(context);
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
            final newName = controller.text.trim();
            if (newName.isEmpty) return;
            if (newName != oldName && ref.read(expenseCategoriesProvider).contains(newName)) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('A category named "$newName" already exists')));
              return;
            }
            ref.read(expenseCategoriesProvider.notifier).renameCategory(oldName, newName);
            Navigator.pop(context);
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
