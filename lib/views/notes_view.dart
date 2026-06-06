import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models.dart';
import '../providers.dart';
import '../widgets/category_chip_bar.dart';
import '../widgets/note_card.dart';
import '../widgets/empty_state.dart';
import 'note_editor.dart';
import '../main_helpers.dart';

class NotesView extends ConsumerStatefulWidget {
  const NotesView({super.key});

  @override
  ConsumerState<NotesView> createState() => _NotesViewState();
}

class _NotesViewState extends ConsumerState<NotesView> {
  late PageController _categoryPageController;
  final Map<String, GlobalKey> _chipKeys = {};

  @override
  void initState() {
    super.initState();
    _categoryPageController = PageController();
  }

  @override
  void dispose() {
    _categoryPageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider);
    final selectedCat = ref.watch(selectedCategoryProvider);
    final allNotes = ref.watch(notesProvider);
    final selectedNotes = ref.watch(selectedNotesProvider);
    final isSelectionMode = selectedNotes.isNotEmpty;
    final isSearching = ref.watch(searchQueryProvider).isNotEmpty;
    
    final fullCategories = categories;

    // Fallback if selected category is invalid or empty
    if (fullCategories.isNotEmpty && (selectedCat.isEmpty || !fullCategories.contains(selectedCat))) {
      Future.microtask(() {
        if (mounted) ref.read(selectedCategoryProvider.notifier).state = fullCategories.first;
      });
    }
    final currentSelectedCat = (fullCategories.isNotEmpty && (selectedCat.isEmpty || !fullCategories.contains(selectedCat))) ? fullCategories.first : selectedCat;

    // Sync PageController if category changes externally
    ref.listen(selectedCategoryProvider, (prev, next) {
      final index = fullCategories.indexOf(next);
      if (index != -1 && _categoryPageController.hasClients && _categoryPageController.page?.round() != index) {
        _categoryPageController.jumpToPage(index);
      }
      
      // Auto-scroll the chip into view
      final key = _chipKeys[next];
      if (key != null && key.currentContext != null) {
        Scrollable.ensureVisible(
          key.currentContext!,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          alignment: 0.5,
        );
      }
    });

    return Column(
      children: [
        if (!isSearching)
          CategoryChipBar(
            categories: fullCategories,
            selectedCategory: currentSelectedCat,
            onSelected: (cat) => ref.read(selectedCategoryProvider.notifier).state = cat,
            onLongPress: (cat) => cat == 'General' ? null : showCategoryOptions(context, ref, cat),
            onAddPressed: () => addCategory(context, ref),
            onManagePressed: () => manageCategoriesDialog(context, ref),
            chipKeys: _chipKeys,
            showFavoritesOnly: ref.watch(showFavoritesOnlyProvider),
            onFavoriteToggle: () {
              ref.read(showFavoritesOnlyProvider.notifier).state = !ref.read(showFavoritesOnlyProvider);
            },
            itemCount: ref.watch(filteredNotesProvider(currentSelectedCat)).length,
          ),
        if (!isSearching) const Divider(height: 1),
        Expanded(
          child: isSearching 
            ? _buildNotesPage('', allNotes, selectedNotes, isSelectionMode)
            : PageView.builder(
                controller: _categoryPageController,
                physics: const ClampingScrollPhysics(),
                itemCount: fullCategories.length,
                onPageChanged: (index) {
                  ref.read(selectedCategoryProvider.notifier).state = fullCategories[index];
                },
                itemBuilder: (context, catIndex) {
                  return _buildNotesPage(fullCategories[catIndex], allNotes, selectedNotes, isSelectionMode);
                },
              ),
        ),
      ],
    );
  }

  Widget _buildNotesPage(String category, List<Note> allNotes, Set<String> selectedNotes, bool isSelectionMode) {
    return Consumer(
      builder: (context, ref, child) {
        final filteredNotes = ref.watch(filteredNotesProvider(category));
        final sortOrder = ref.watch(sortOrderProvider);
        final isSearching = ref.watch(searchQueryProvider).isNotEmpty;


        if (filteredNotes.isEmpty) {
          return EmptyState(
            icon: Icons.note_alt_outlined,
            title: category.isEmpty ? 'No results found' : 'Empty Category',
            subtitle: category.isEmpty 
                ? 'Try searching for something else.' 
                : 'No notes in "$category". Tap + to create your first note here!',
            actionLabel: category.isEmpty ? null : 'Create Note',
            onAction: category.isEmpty ? null : () => createNewNote(context, ref),
          );
        }



        return ListView.builder(
          padding: const EdgeInsets.only(left: 8, right: 8, top: 12, bottom: 90),
          itemCount: filteredNotes.length,
          itemBuilder: (context, index) {
            final note = filteredNotes[index];
            final isSelected = selectedNotes.contains(note.id);
            return NoteCard(
              key: ValueKey(note.id),
              note: note,
              isSelected: isSelected,
              isSelectionMode: isSelectionMode,
              onTap: () {
                if (isSelectionMode) {
                  ref.read(selectedNotesProvider.notifier).toggle(note.id);
                } else if (note.isLocked) {
                  verifyPasscode(context, ref, onSuccess: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (context) => NoteEditor(note: note)),
                    );
                  });
                } else {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (context) => NoteEditor(note: note)),
                  );
                }
              },
              onLongPress: () {
                if (!isSelectionMode) {
                  ref.read(selectedNotesProvider.notifier).toggle(note.id);
                }
              },
              onCheckboxChanged: (val) => ref.read(selectedNotesProvider.notifier).toggle(note.id),
              onMorePressed: () => showNoteOptions(context, ref, note),
            );
          },
        );
      },
    );
  }
}
