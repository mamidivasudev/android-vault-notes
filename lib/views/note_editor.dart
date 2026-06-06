import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models.dart';
import '../providers.dart';

class NoteEditor extends ConsumerStatefulWidget {
  final Note note;
  final bool isNew;
  const NoteEditor({super.key, required this.note, this.isNew = false});
  @override
  ConsumerState<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends ConsumerState<NoteEditor> {
  late TextEditingController _titleController;
  late TextEditingController _contentController;
  late String _selectedCategory;
  late bool _isEditing;
  final FocusNode _contentFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.note.title);
    _contentController = TextEditingController(text: widget.note.content);
    _selectedCategory = widget.note.category;
    _isEditing = widget.isNew;
  }

  void _clearAll() {
    setState(() {
      _titleController.clear();
      _contentController.clear();
    });
  }

  @override
  void dispose() {
    _contentFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider);
    final fontSize = ref.watch(fontSizeProvider);
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        
        final hasChanges = _titleController.text != widget.note.title ||
            _contentController.text != widget.note.content ||
            _selectedCategory != widget.note.category;

        if (hasChanges && _isEditing) {
          final shouldPop = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Unsaved Changes'),
              content: const Text('You have unsaved changes. Discard them and go back?'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
                TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes', style: TextStyle(color: Colors.red))),
              ],
            ),
          );
          if (shouldPop == true && mounted) Navigator.pop(context);
        } else {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.isNew ? 'New Note' : (_isEditing ? 'Editing Note' : 'View Note')),
          actions: [
            IconButton(icon: const Icon(Icons.copy), onPressed: _copy, tooltip: 'Copy'),
            IconButton(icon: const Icon(Icons.share), onPressed: _share, tooltip: 'Share'),
            if (_isEditing) 
              IconButton(
                icon: const Icon(Icons.save, color: Color(0xFF1D63D2)), 
                onPressed: _save, 
                tooltip: 'Save'
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
                  children: categories.map((cat) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(cat, style: const TextStyle(fontSize: 12)),
                      selected: cat == _selectedCategory,
                      onSelected: (val) { if (val) setState(() => _selectedCategory = cat); },
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  )).toList(),
                ),
              ),
              const SizedBox(height: 16),
              _isEditing 
                ? TextField(
                    controller: _titleController,
                    onChanged: (_) => setState(() {}),
                    autofocus: widget.isNew,
                    style: GoogleFonts.lexend(fontSize: 22, fontWeight: FontWeight.bold),
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                    decoration: InputDecoration(
                      hintText: 'Title', 
                      border: InputBorder.none,
                      suffixIcon: _titleController.text.isNotEmpty 
                        ? IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _titleController.clear())) 
                        : null,
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      _titleController.text.isEmpty ? 'Untitled Note' : _titleController.text,
                      style: GoogleFonts.lexend(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                  ),
              const Divider(height: 1),
              Expanded(
                child: _isEditing 
                  ? TextField(
                      controller: _contentController,
                      focusNode: _contentFocusNode,
                      onChanged: (_) => setState(() {}),
                      maxLines: null,
                      expands: true,
                      style: TextStyle(fontSize: fontSize + 2, height: 1.6),
                      decoration: InputDecoration(
                        hintText: 'Start typing...', 
                        border: InputBorder.none,
                        suffixIcon: _contentController.text.isNotEmpty 
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.start,
                              children: [
                                IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _contentController.clear())),
                              ],
                            )
                          : null,
                      ),
                    )
                  : SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Linkify(
                          onOpen: (link) async {
                            final uri = Uri.parse(link.url);
                            try { await launchUrl(uri, mode: LaunchMode.externalApplication); } catch (e) {}
                          },
                          text: _contentController.text,
                          style: TextStyle(fontSize: fontSize + 2, height: 1.6),
                          linkStyle: const TextStyle(color: Color(0xFF1D63D2), decoration: TextDecoration.underline),
                        ),
                      ),
                    ),
              ),
              // ── Word / Character count status bar ──
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Builder(builder: (_) {
                  final text = _contentController.text;
                  final words = text.trim().isEmpty ? 0 : text.trim().split(RegExp(r'\s+')).length;
                  final chars = text.length;
                  return Text(
                    "$words ${words == 1 ? 'word' : 'words'} \u00b7 $chars ${chars == 1 ? 'char' : 'chars'}",
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.45),
                      letterSpacing: 0.2,
                    ),
                  );
                }),
              ),
            ],
          ),
        ),
        floatingActionButton: widget.isNew ? null : FloatingActionButton(
          onPressed: () {
            if (_isEditing) {
              // Trying to switch to View mode
              final hasChanges = _titleController.text != widget.note.title ||
                  _contentController.text != widget.note.content ||
                  _selectedCategory != widget.note.category;
  
              if (hasChanges) {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Unsaved Changes'),
                    content: const Text('You have unsaved changes. What would you like to do?'),
                    actions: [
                      TextButton(
                        onPressed: () {
                          Navigator.pop(ctx); // Close dialog
                          setState(() => _isEditing = false); // Discard changes (visually)
                          // Note: controllers still have the text, but toggle to view mode
                        },
                        child: const Text('Discard', style: TextStyle(color: Colors.red)),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(ctx); // Close dialog
                          _save(); // Trigger save logic
                        },
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                );
              } else {
                setState(() => _isEditing = false);
              }
            } else {
              setState(() => _isEditing = true);
              Future.delayed(const Duration(milliseconds: 100), () {
                if (mounted) _contentFocusNode.requestFocus();
              });
            }
          },
          backgroundColor: const Color(0xFF1D63D2),
          foregroundColor: Colors.white,
          tooltip: _isEditing ? 'View Mode' : 'Edit Mode',
          child: Icon(_isEditing ? Icons.visibility_outlined : Icons.edit),
        ),
      ),
    );
  }

  void _save() {
    final updatedNote = widget.note.copyWith(
      title: _titleController.text.trim(),
      content: _contentController.text.trim(),
      category: _selectedCategory,
      createdAt: DateTime.now(),
    );

    if (widget.isNew) {
      ref.read(notesProvider.notifier).addNote(updatedNote);
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Note Saved')));
    } else {
      final hasChanges = updatedNote.title != widget.note.title ||
          updatedNote.content != widget.note.content ||
          updatedNote.category != widget.note.category;

      if (!hasChanges) {
        Navigator.pop(context);
        return;
      }

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Update Note?'),
          content: const Text('Do you want to save the changes to this note?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('No'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx); 
                ref.read(notesProvider.notifier).updateNote(updatedNote);
                Navigator.pop(context); 
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Note Updated')));
              },
              child: const Text('Yes'),
            ),
          ],
        ),
      );
    }
  }

  void _copy() {
    Clipboard.setData(ClipboardData(text: _contentController.text));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
  }

  void _share() {
    Share.share("${_titleController.text}\n\n${_contentController.text}");
  }
}
