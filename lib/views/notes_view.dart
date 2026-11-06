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
    final query = ref.watch(searchQueryProvider);
    final isSearching = query.isNotEmpty;
    final searchInCategory = ref.watch(notesSearchInCategoryProvider);
    final swipeActions = ref.watch(notesSwipeActionsProvider);

    final currentSelectedCat = (categories.isNotEmpty && (selectedCat.isEmpty || !categories.contains(selectedCat)))
        ? categories.first
        : selectedCat;

    // Sync PageController if category changes externally
    ref.listen(selectedCategoryProvider, (prev, next) {
      final index = categories.indexOf(next);
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

    final searchScope = searchInCategory ? currentSelectedCat : '';

    return Column(
      children: [
        if (!isSearching)
          CategoryChipBar(
            categories: categories,
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
        if (isSearching) _buildSearchScopeBar(currentSelectedCat, searchScope),
        const Divider(height: 1),
        Expanded(
          child: isSearching
              ? _buildNotesPage(searchScope)
              : PageView.builder(
                  controller: _categoryPageController,
                  // Swipe actions on cards take over horizontal drags; use the chips to switch.
                  physics: swipeActions ? const NeverScrollableScrollPhysics() : const ClampingScrollPhysics(),
                  itemCount: categories.length,
                  onPageChanged: (index) {
                    ref.read(selectedCategoryProvider.notifier).state = categories[index];
                  },
                  itemBuilder: (context, catIndex) => _buildNotesPage(categories[catIndex]),
                ),
        ),
      ],
    );
  }

  /// "N results · [All categories] [This category]" shown while searching.
  Widget _buildSearchScopeBar(String currentCat, String scope) {
    final count = ref.watch(filteredNotesProvider(scope)).length;
    final inCategory = ref.watch(notesSearchInCategoryProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Row(
        children: [
          Text(
            '$count ${count == 1 ? 'result' : 'results'}',
            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
          ),
          const Spacer(),
          ChoiceChip(
            label: const Text('All categories', style: TextStyle(fontSize: 11)),
            selected: !inCategory,
            visualDensity: VisualDensity.compact,
            onSelected: (_) => ref.read(notesSearchInCategoryProvider.notifier).state = false,
          ),
          const SizedBox(width: 6),
          ChoiceChip(
            label: Text(currentCat, style: const TextStyle(fontSize: 11)),
            selected: inCategory,
            visualDensity: VisualDensity.compact,
            onSelected: (_) => ref.read(notesSearchInCategoryProvider.notifier).state = true,
          ),
        ],
      ),
    );
  }

  Widget _buildNotesPage(String category) {
    return Consumer(
      builder: (context, ref, child) {
        final filteredNotes = ref.watch(filteredNotesProvider(category));
        final query = ref.watch(searchQueryProvider);
        final isSearching = query.isNotEmpty;
        final isGrid = ref.watch(notesGridViewProvider);
        final sortOrder = ref.watch(sortOrderProvider);
        final selectedNotes = ref.watch(selectedNotesProvider);
        final isSelectionMode = selectedNotes.isNotEmpty || ref.watch(isSelectionModeProvider);
        final reminderIds = ref
            .watch(remindersProvider)
            .where((r) => !r.isDismissed && r.id.startsWith('note_'))
            .map((r) => r.id)
            .toSet();

        if (filteredNotes.isEmpty) {
          return EmptyState(
            icon: Icons.note_alt_outlined,
            title: isSearching ? 'No results found' : 'Empty Category',
            subtitle: isSearching
                ? 'Try searching for something else.'
                : 'No notes in "$category". Tap + to create your first note here!',
            actionLabel: isSearching ? null : 'Create Note',
            onAction: isSearching ? null : () => createNewNote(context, ref),
          );
        }

        Widget card(Note note, {Widget? leading, required bool grid}) => NoteCard(
              key: ValueKey('card_${note.id}'),
              note: note,
              isGrid: grid,
              highlight: query,
              hasReminder: reminderIds.contains(noteReminderId(note.id)),
              leading: leading,
              isSelected: selectedNotes.contains(note.id),
              isSelectionMode: isSelectionMode,
              onTap: () => _openNote(note, isSelectionMode),
              onLongPress: () {
                if (!isSelectionMode) {
                  ref.read(isSelectionModeProvider.notifier).setState(true);
                  ref.read(selectedNotesProvider.notifier).toggle(note.id);
                }
              },
              onCheckboxChanged: (val) => ref.read(selectedNotesProvider.notifier).toggle(note.id),
              onMorePressed: () => showNoteOptions(context, ref, note),
            );

        const padding = EdgeInsets.only(left: 8, right: 8, top: 12, bottom: 90);

        // ── Grid (two staggered columns) ──
        if (isGrid) {
          final left = <Note>[], right = <Note>[];
          for (int i = 0; i < filteredNotes.length; i++) {
            (i.isEven ? left : right).add(filteredNotes[i]);
          }
          return SingleChildScrollView(
            padding: padding,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Column(children: [for (final n in left) card(n, grid: true)])),
                Expanded(child: Column(children: [for (final n in right) card(n, grid: true)])),
              ],
            ),
          );
        }

        // ── Manual order: drag handles to reorder ──
        final canReorder = sortOrder == NoteSortOrder.manual && !isSearching && !isSelectionMode && category.isNotEmpty;
        if (canReorder) {
          return ReorderableListView.builder(
            padding: padding,
            buildDefaultDragHandles: false,
            itemCount: filteredNotes.length,
            onReorder: (oldIndex, newIndex) {
              if (newIndex > oldIndex) newIndex -= 1;
              final reordered = List<Note>.from(filteredNotes);
              final moved = reordered.removeAt(oldIndex);
              reordered.insert(newIndex, moved);
              ref.read(notesProvider.notifier).reorderSubset(reordered);
            },
            itemBuilder: (context, index) {
              final note = filteredNotes[index];
              return KeyedSubtree(
                key: ValueKey(note.id),
                child: card(
                  note,
                  grid: false,
                  leading: ReorderableDragStartListener(
                    index: index,
                    child: const Padding(
                      padding: EdgeInsets.only(right: 8, top: 2),
                      child: Icon(Icons.drag_indicator, size: 20, color: Colors.grey),
                    ),
                  ),
                ),
              );
            },
          );
        }

        // ── Plain list with swipe actions ──
        return ListView.builder(
          padding: padding,
          itemCount: filteredNotes.length,
          itemBuilder: (context, index) {
            final note = filteredNotes[index];
            final child = card(note, grid: false);
            if (!ref.watch(notesSwipeActionsProvider) || isSelectionMode || note.isLocked) return child;
            return Dismissible(
              key: ValueKey('swipe_${note.id}'),
              background: _swipeBackground(
                alignment: Alignment.centerLeft,
                color: const Color(0xFF1D63D2),
                icon: note.isPinned ? Icons.push_pin_outlined : Icons.push_pin,
                label: note.isPinned ? 'Unpin' : 'Pin',
              ),
              secondaryBackground: _swipeBackground(
                alignment: Alignment.centerRight,
                color: Colors.red,
                icon: Icons.delete_outline,
                label: 'Delete',
              ),
              confirmDismiss: (direction) async {
                if (direction == DismissDirection.startToEnd) {
                  // Pin/unpin without removing the card
                  ref.read(notesProvider.notifier).togglePin(note.id);
                  return false;
                }
                return true;
              },
              onDismissed: (_) => deleteNotesWithUndo(context, ref, [note.id]),
              child: child,
            );
          },
        );
      },
    );
  }

  Widget _swipeBackground({required Alignment alignment, required Color color, required IconData icon, required String label}) {
    final isLeft = alignment == Alignment.centerLeft;
    return Container(
      margin: const EdgeInsets.only(bottom: 10, left: 2, right: 2),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
      alignment: alignment,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isLeft) Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          if (!isLeft) const SizedBox(width: 8),
          Icon(icon, color: Colors.white),
          if (isLeft) const SizedBox(width: 8),
          if (isLeft) Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  void _openNote(Note note, bool isSelectionMode, {bool ocr = false}) {
    if (isSelectionMode) {
      ref.read(selectedNotesProvider.notifier).toggle(note.id);
      return;
    }
    void open() => Navigator.of(context).push(
          MaterialPageRoute(builder: (context) => NoteEditor(note: note, openOcrOnStart: ocr)),
        );
    if (note.isLocked) {
      verifyPasscode(context, ref, onSuccess: open);
    } else {
      open();
    }
  }
}
