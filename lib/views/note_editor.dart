import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../main_helpers.dart' show noteShareText, pickNoteColor, setNoteReminder, exportNote;
import '../models.dart';
import '../providers.dart';
import '../services/ocr_service.dart';
import '../widgets/note_card.dart' show NoteColors;

class NoteEditor extends ConsumerStatefulWidget {
  final Note note;
  final bool isNew;
  final bool openOcrOnStart;
  const NoteEditor({super.key, required this.note, this.isNew = false, this.openOcrOnStart = false});
  @override
  ConsumerState<NoteEditor> createState() => _NoteEditorState();
}

/// One editable row of a checklist.
class _ChecklistRow {
  final TextEditingController controller;
  final FocusNode focusNode = FocusNode();
  bool checked;
  _ChecklistRow(String text, this.checked) : controller = TextEditingController(text: text);
  void dispose() {
    controller.dispose();
    focusNode.dispose();
  }
}

class _NoteEditorState extends ConsumerState<NoteEditor> {
  /// The last saved version of the note; edits are compared against this.
  late Note _original;
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;
  late String _selectedCategory;
  late bool _isEditing;
  late bool _isChecklist;
  late int _colorIndex;
  List<_ChecklistRow> _rows = [];
  bool _isOcrLoading = false;
  final FocusNode _contentFocusNode = FocusNode();
  Timer? _draftTimer;

  @override
  void initState() {
    super.initState();
    _original = widget.note;
    _titleController = TextEditingController(text: widget.note.title);
    _contentController = TextEditingController(text: widget.note.isChecklist ? '' : widget.note.content);
    _selectedCategory = widget.note.category;
    _isEditing = widget.isNew;
    _isChecklist = widget.note.isChecklist;
    _colorIndex = widget.note.colorIndex;
    if (_isChecklist) _rows = _rowsFrom(widget.note.content);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _offerDraftRestore();
      // Auto-launch OCR if opened via the scan shortcut from the notes list
      if (widget.openOcrOnStart && mounted) _launchOcr();
    });
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    _titleController.dispose();
    _contentController.dispose();
    _contentFocusNode.dispose();
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  // ── State helpers ──────────────────────────────────────────────────────────

  List<_ChecklistRow> _rowsFrom(String content) {
    final items = ChecklistItem.parse(content);
    final rows = items.map((i) => _ChecklistRow(i.text, i.checked)).toList();
    return rows.isEmpty ? [_ChecklistRow('', false)] : rows;
  }

  void _replaceRows(List<_ChecklistRow> rows) {
    for (final r in _rows) {
      r.dispose();
    }
    _rows = rows;
  }

  /// Current body as it would be saved (empty checklist rows are dropped).
  String _currentContent() {
    if (_isChecklist) {
      return ChecklistItem.serialize(_rows
          .where((r) => r.controller.text.trim().isNotEmpty)
          .map((r) => ChecklistItem(r.controller.text.trim(), r.checked))
          .toList());
    }
    return _contentController.text.trim();
  }

  /// Plain text of the body, used for word counts.
  String _plainText() => _isChecklist ? _rows.map((r) => r.controller.text).join('\n') : _contentController.text;

  Note _editedNote() => _original.copyWith(
        title: _titleController.text.trim(),
        content: _currentContent(),
        category: _selectedCategory,
        isChecklist: _isChecklist,
        colorIndex: _colorIndex,
      );

  bool get _hasChanges {
    final e = _editedNote();
    return e.title != _original.title.trim() ||
        e.content != _original.content.trim() ||
        e.category != _original.category ||
        e.isChecklist != _original.isChecklist ||
        e.colorIndex != _original.colorIndex;
  }

  /// Resets every field back to the last saved version.
  void _resetToOriginal() {
    _titleController.text = _original.title;
    _contentController.text = _original.isChecklist ? '' : _original.content;
    _selectedCategory = _original.category;
    _isChecklist = _original.isChecklist;
    _colorIndex = _original.colorIndex;
    _replaceRows(_isChecklist ? _rowsFrom(_original.content) : []);
  }

  void _onEdited() {
    setState(() {});
    _scheduleDraftSave();
  }

  // ── Drafts (crash / app-kill recovery) ─────────────────────────────────────

  String get _draftKey => widget.isNew ? 'note_draft_new' : 'note_draft_${widget.note.id}';
  bool get _draftsEnabled => !widget.note.isLocked;

  void _scheduleDraftSave() {
    if (!_draftsEnabled) return;
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 800), () async {
      final prefs = await SharedPreferences.getInstance();
      if (!_hasChanges) {
        await prefs.remove(_draftKey);
        return;
      }
      final e = _editedNote();
      await prefs.setString(
        _draftKey,
        jsonEncode({
          'title': e.title,
          'content': e.content,
          'category': e.category,
          'isChecklist': e.isChecklist,
          'colorIndex': e.colorIndex,
          'savedAt': DateTime.now().toIso8601String(),
        }),
      );
    });
  }

  Future<void> _clearDraft() async {
    _draftTimer?.cancel();
    if (!_draftsEnabled) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_draftKey);
  }

  Future<void> _offerDraftRestore() async {
    if (!_draftsEnabled) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_draftKey);
    if (raw == null) return;
    Map<String, dynamic> draft;
    try {
      draft = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      await prefs.remove(_draftKey);
      return;
    }
    final sameAsSaved = draft['title'] == _original.title.trim() &&
        draft['content'] == _original.content.trim() &&
        draft['category'] == _original.category &&
        draft['isChecklist'] == _original.isChecklist &&
        draft['colorIndex'] == _original.colorIndex;
    if (sameAsSaved) {
      await prefs.remove(_draftKey);
      return;
    }
    if (!mounted) return;
    final savedAt = DateTime.tryParse(draft['savedAt']?.toString() ?? '');
    final restore = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore unsaved changes?'),
        content: Text(
          'This note has changes that were never saved'
          '${savedAt != null ? ' (${DateFormat('MMM d, h:mm a').format(savedAt)})' : ''}.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Discard', style: TextStyle(color: Colors.red))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Restore')),
        ],
      ),
    );
    if (restore != true) {
      await prefs.remove(_draftKey);
      return;
    }
    if (!mounted) return;
    final categories = ref.read(categoriesProvider);
    setState(() {
      _titleController.text = draft['title']?.toString() ?? '';
      final cat = draft['category']?.toString() ?? _original.category;
      _selectedCategory = categories.contains(cat) ? cat : _original.category;
      _colorIndex = (draft['colorIndex'] as num?)?.toInt() ?? 0;
      _isChecklist = draft['isChecklist'] == true;
      final content = draft['content']?.toString() ?? '';
      if (_isChecklist) {
        _contentController.clear();
        _replaceRows(_rowsFrom(content));
      } else {
        _contentController.text = content;
        _replaceRows([]);
      }
      _isEditing = true;
    });
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider);
    final fontSize = ref.watch(fontSizeProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasReminder = ref.watch(remindersProvider).any((r) => r.id == noteReminderId(widget.note.id) && !r.isDismissed);
    final bg = NoteColors.background(_colorIndex, isDark);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _handleBack();
      },
      child: Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          backgroundColor: bg,
          title: Text(widget.isNew ? 'New Note' : (_isEditing ? 'Editing Note' : 'View Note')),
          actions: [
            _isOcrLoading
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : IconButton(
                    icon: const Icon(Icons.document_scanner_outlined),
                    onPressed: _launchOcr,
                    tooltip: 'Scan text from camera (OCR)',
                  ),
            if (hasReminder)
              IconButton(
                icon: const Icon(Icons.notifications_active, color: Color(0xFFF59E0B)),
                tooltip: 'Reminder',
                onPressed: () => setNoteReminder(context, ref, _original),
              ),
            if (_isEditing)
              IconButton(
                icon: const Icon(Icons.save, color: Color(0xFF1D63D2)),
                onPressed: () => _save(),
                tooltip: 'Save',
              ),
            PopupMenuButton<String>(
              onSelected: _onMenu,
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'checklist',
                  child: ListTile(
                    leading: Icon(_isChecklist ? Icons.notes : Icons.checklist),
                    title: Text(_isChecklist ? 'Convert to text' : 'Convert to checklist'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: 'color',
                  child: ListTile(leading: Icon(Icons.palette_outlined), title: Text('Color'), contentPadding: EdgeInsets.zero),
                ),
                PopupMenuItem(
                  value: 'reminder',
                  child: ListTile(
                    leading: Icon(hasReminder ? Icons.notifications_active : Icons.notifications_none),
                    title: Text(hasReminder ? 'Edit reminder' : 'Set reminder'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: 'copy',
                  child: ListTile(leading: Icon(Icons.copy), title: Text('Copy'), contentPadding: EdgeInsets.zero),
                ),
                const PopupMenuItem(
                  value: 'share',
                  child: ListTile(leading: Icon(Icons.share), title: Text('Share'), contentPadding: EdgeInsets.zero),
                ),
                const PopupMenuItem(
                  value: 'txt',
                  child: ListTile(leading: Icon(Icons.description_outlined), title: Text('Export .txt'), contentPadding: EdgeInsets.zero),
                ),
                const PopupMenuItem(
                  value: 'pdf',
                  child: ListTile(leading: Icon(Icons.picture_as_pdf_outlined), title: Text('Export PDF'), contentPadding: EdgeInsets.zero),
                ),
              ],
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: categories
                      .map((cat) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(cat, style: const TextStyle(fontSize: 12)),
                              selected: cat == _selectedCategory,
                              onSelected: (val) {
                                if (!val) return;
                                if (!_isEditing) setState(() => _isEditing = true);
                                _selectedCategory = cat;
                                _onEdited();
                              },
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ))
                      .toList(),
                ),
              ),
              const SizedBox(height: 16),
              _isEditing
                  ? TextField(
                      controller: _titleController,
                      onChanged: (_) => _onEdited(),
                      autofocus: widget.isNew,
                      style: GoogleFonts.lexend(fontSize: 22, fontWeight: FontWeight.bold),
                      textInputAction: TextInputAction.next,
                      onSubmitted: (_) {
                        if (_isChecklist && _rows.isNotEmpty) {
                          _rows.first.focusNode.requestFocus();
                        } else {
                          _contentFocusNode.requestFocus();
                        }
                      },
                      decoration: InputDecoration(
                        hintText: 'Title',
                        border: InputBorder.none,
                        suffixIcon: _titleController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: () {
                                  _titleController.clear();
                                  _onEdited();
                                })
                            : null,
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: SelectableText(
                        _titleController.text.isEmpty ? 'Untitled Note' : _titleController.text,
                        style: GoogleFonts.lexend(fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                    ),
              const Divider(height: 1),
              Expanded(child: _isChecklist ? _buildChecklist(fontSize) : _buildTextBody(fontSize)),
              _buildStatusBar(),
            ],
          ),
        ),
        floatingActionButton: widget.isNew
            ? null
            : FloatingActionButton(
                onPressed: _toggleEditMode,
                backgroundColor: const Color(0xFF1D63D2),
                foregroundColor: Colors.white,
                tooltip: _isEditing ? 'View Mode' : 'Edit Mode',
                child: Icon(_isEditing ? Icons.visibility_outlined : Icons.edit),
              ),
      ),
    );
  }

  Widget _buildTextBody(double fontSize) {
    final style = TextStyle(fontSize: fontSize + 2, height: 1.6);
    if (_isEditing) {
      return TextField(
        controller: _contentController,
        focusNode: _contentFocusNode,
        onChanged: (_) => _onEdited(),
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        keyboardType: TextInputType.multiline,
        style: style,
        decoration: const InputDecoration(hintText: 'Start typing...', border: InputBorder.none),
      );
    }
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: SelectableLinkify(
          onOpen: (link) async {
            try {
              await launchUrl(Uri.parse(link.url), mode: LaunchMode.externalApplication);
            } catch (_) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open link')));
              }
            }
          },
          text: _contentController.text.isEmpty ? ' ' : _contentController.text,
          style: style,
          linkStyle: const TextStyle(color: Color(0xFF1D63D2), decoration: TextDecoration.underline),
        ),
      ),
    );
  }

  Widget _buildChecklist(double fontSize) {
    final style = TextStyle(fontSize: fontSize + 1, height: 1.4);
    final doneStyle = style.copyWith(
      decoration: TextDecoration.lineThrough,
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
    );

    if (!_isEditing) {
      final visible = _rows.where((r) => r.controller.text.trim().isNotEmpty).toList();
      if (visible.isEmpty) {
        return const Center(child: Text('Empty checklist', style: TextStyle(color: Colors.grey)));
      }
      return ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          for (final row in visible)
            InkWell(
              onTap: () => _toggleItemInViewMode(row),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Checkbox(value: row.checked, onChanged: (_) => _toggleItemInViewMode(row)),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(row.controller.text, style: row.checked ? doneStyle : style),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        for (int i = 0; i < _rows.length; i++)
          Row(
            key: ObjectKey(_rows[i]),
            children: [
              Checkbox(
                value: _rows[i].checked,
                onChanged: (v) {
                  _rows[i].checked = v ?? false;
                  _onEdited();
                },
              ),
              Expanded(
                child: TextField(
                  controller: _rows[i].controller,
                  focusNode: _rows[i].focusNode,
                  style: _rows[i].checked ? doneStyle : style,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(hintText: 'List item', border: InputBorder.none, isDense: true),
                  onChanged: (_) => _onEdited(),
                  onSubmitted: (_) => _insertRowAfter(i),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: 'Remove item',
                onPressed: () => _removeRow(i),
              ),
            ],
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _insertRowAfter(_rows.length - 1),
            icon: const Icon(Icons.add),
            label: const Text('Add item'),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusBar() {
    final text = _plainText();
    final words = text.trim().isEmpty ? 0 : text.trim().split(RegExp(r'\s+')).length;
    final chars = text.length;
    var label = "$words ${words == 1 ? 'word' : 'words'} · $chars ${chars == 1 ? 'char' : 'chars'}";
    if (_isChecklist) {
      final items = _rows.where((r) => r.controller.text.trim().isNotEmpty).toList();
      label = '${items.where((r) => r.checked).length}/${items.length} done · $label';
    }
    if (!widget.isNew && _original.updatedAt != null) {
      label += ' · Edited ${DateFormat('MMM d, h:mm a').format(_original.updatedAt!)}';
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  // ── Checklist actions ──────────────────────────────────────────────────────

  void _insertRowAfter(int index) {
    final row = _ChecklistRow('', false);
    setState(() => _rows.insert(index + 1, row));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) row.focusNode.requestFocus();
    });
  }

  void _removeRow(int index) {
    setState(() {
      _rows.removeAt(index).dispose();
      if (_rows.isEmpty) _rows.add(_ChecklistRow('', false));
    });
    _scheduleDraftSave();
  }

  /// Ticking items while viewing saves straight away.
  Future<void> _toggleItemInViewMode(_ChecklistRow row) async {
    setState(() => row.checked = !row.checked);
    final updated = _original.copyWith(content: _currentContent(), updatedAt: DateTime.now());
    await ref.read(notesProvider.notifier).updateNote(updated);
    _original = updated;
  }

  void _toggleChecklistMode() {
    if (!_isEditing) setState(() => _isEditing = true);
    setState(() {
      if (_isChecklist) {
        _contentController.text = _rows.map((r) => r.controller.text).where((t) => t.trim().isNotEmpty).join('\n');
        _replaceRows([]);
        _isChecklist = false;
      } else {
        _replaceRows(_rowsFrom(ChecklistItem.fromPlainText(_contentController.text)));
        _contentController.clear();
        _isChecklist = true;
      }
    });
    _scheduleDraftSave();
  }

  // ── Menu / mode ────────────────────────────────────────────────────────────

  Future<void> _onMenu(String value) async {
    switch (value) {
      case 'checklist':
        _toggleChecklistMode();
        break;
      case 'color':
        final color = await pickNoteColor(context, _colorIndex);
        if (color == null || color == _colorIndex) return;
        setState(() => _colorIndex = color);
        if (!widget.isNew && !_isEditing) {
          // Viewing: apply the colour straight away
          final updated = _original.copyWith(colorIndex: color);
          await ref.read(notesProvider.notifier).updateNote(updated);
          _original = updated;
        } else {
          _scheduleDraftSave();
        }
        break;
      case 'reminder':
        if (widget.isNew) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Save the note first to add a reminder')));
          return;
        }
        await setNoteReminder(context, ref, _editedNote());
        break;
      case 'copy':
        Clipboard.setData(ClipboardData(text: noteShareText(_editedNote())));
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
        break;
      case 'share':
        Share.share(noteShareText(_editedNote()));
        break;
      case 'txt':
        exportNote(context, _editedNote(), asPdf: false);
        break;
      case 'pdf':
        exportNote(context, _editedNote(), asPdf: true);
        break;
    }
  }

  Future<void> _toggleEditMode() async {
    if (!_isEditing) {
      setState(() => _isEditing = true);
      Future.delayed(const Duration(milliseconds: 100), () {
        if (!mounted) return;
        if (_isChecklist && _rows.isNotEmpty) {
          _rows.last.focusNode.requestFocus();
        } else {
          _contentFocusNode.requestFocus();
        }
      });
      return;
    }
    if (!_hasChanges) {
      setState(() => _isEditing = false);
      return;
    }
    final choice = await _askUnsaved('Save your changes before switching to view mode?');
    if (choice == 'save') {
      await _save(close: false);
    } else if (choice == 'discard') {
      await _clearDraft();
      setState(() {
        _resetToOriginal();
        _isEditing = false;
      });
    }
  }

  Future<void> _handleBack() async {
    final navigator = Navigator.of(context);
    if (!_isEditing || !_hasChanges) {
      await _clearDraft();
      navigator.pop();
      return;
    }
    final choice = await _askUnsaved('You have unsaved changes.');
    if (choice == 'save') {
      await _save();
    } else if (choice == 'discard') {
      await _clearDraft();
      navigator.pop();
    }
  }

  /// Returns 'save', 'discard', or null (cancel).
  Future<String?> _askUnsaved(String message) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unsaved Changes'),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'discard'), child: const Text('Discard', style: TextStyle(color: Colors.red))),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('Save')),
        ],
      ),
    );
  }

  Future<void> _save({bool close = true}) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final notifier = ref.read(notesProvider.notifier);
    final edited = _editedNote();

    if (widget.isNew) {
      if (edited.title.isEmpty && edited.content.isEmpty) {
        await _clearDraft();
        navigator.pop();
        messenger.showSnackBar(const SnackBar(content: Text('Empty note discarded')));
        return;
      }
      final added = await notifier.addNote(edited.copyWith(createdAt: DateTime.now(), updatedAt: null));
      await _clearDraft();
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text(added ? 'Note saved' : 'Note was already saved')));
      return;
    }

    if (!_hasChanges) {
      await _clearDraft();
      if (close) {
        navigator.pop();
      } else {
        setState(() => _isEditing = false);
      }
      return;
    }

    // Keep the original created date; record the edit time separately.
    final updated = edited.copyWith(updatedAt: DateTime.now());
    await notifier.updateNote(updated);
    await _clearDraft();
    _original = updated;
    if (close) {
      navigator.pop();
    } else if (mounted) {
      setState(() => _isEditing = false);
    }
    messenger.showSnackBar(const SnackBar(content: Text('Note updated')));
  }

  // ── OCR ────────────────────────────────────────────────────────────────────

  Future<void> _launchOcr() async {
    final source = await _showOcrSourcePicker();
    if (source == null || !mounted) return;

    setState(() => _isOcrLoading = true);
    String? text;
    try {
      text = await OcrService.pickAndRecognize(source);
    } catch (_) {
      text = null;
    } finally {
      if (mounted) setState(() => _isOcrLoading = false);
    }
    if (!mounted) return;

    if (text == null || text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No text detected in the image.')));
      return;
    }
    _showOcrResult(text);
  }

  Future<ImageSource?> _showOcrSourcePicker() async {
    return showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2)),
              ),
              Text('Scan Text', style: GoogleFonts.lexend(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              const Divider(),
              ListTile(
                leading: const CircleAvatar(backgroundColor: Color(0xFF1D63D2), child: Icon(Icons.camera_alt, color: Colors.white)),
                title: const Text('Take a Photo'),
                subtitle: const Text('Open camera and capture'),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: const CircleAvatar(backgroundColor: Color(0xFF475569), child: Icon(Icons.photo_library, color: Colors.white)),
                title: const Text('Choose from Gallery'),
                subtitle: const Text('Pick an existing image'),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _applyOcrText(String recognized, {required bool replace}) {
    setState(() {
      _isEditing = true;
      if (_isChecklist) {
        final newRows = recognized
            .split('\n')
            .where((l) => l.trim().isNotEmpty)
            .map((l) => _ChecklistRow(l.trim(), false))
            .toList();
        if (replace) {
          _replaceRows(newRows.isEmpty ? [_ChecklistRow('', false)] : newRows);
        } else {
          // Drop a trailing empty row before appending
          if (_rows.isNotEmpty && _rows.last.controller.text.trim().isEmpty) _rows.removeLast().dispose();
          _rows.addAll(newRows);
          if (_rows.isEmpty) _rows.add(_ChecklistRow('', false));
        }
      } else {
        final current = _contentController.text;
        _contentController.text = replace || current.isEmpty ? recognized : '$current\n\n$recognized';
      }
    });
    _scheduleDraftSave();
  }

  void _showOcrResult(String recognizedText) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        expand: false,
        builder: (_, scrollCtrl) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Row(
                children: [
                  const Icon(Icons.document_scanner_outlined, size: 20, color: Color(0xFF1D63D2)),
                  const SizedBox(width: 8),
                  Text('Recognized Text', style: GoogleFonts.lexend(fontSize: 16, fontWeight: FontWeight.w600)),
                ],
              ),
              const Divider(height: 20),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: SingleChildScrollView(
                    controller: scrollCtrl,
                    child: SelectableText(recognizedText, style: const TextStyle(fontSize: 14, height: 1.6)),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _applyOcrText(recognizedText, replace: false);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Text appended to note ✓')));
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Append'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF1D63D2),
                        side: const BorderSide(color: Color(0xFF1D63D2)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _applyOcrText(recognizedText, replace: true);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Note content replaced ✓')));
                      },
                      icon: const Icon(Icons.swap_horiz),
                      label: const Text('Replace'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF1D63D2),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Discard', style: TextStyle(color: Colors.grey)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
