import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'models.dart';
import 'vault_service.dart';
import 'services/google_drive_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'dart:convert';
import 'docs_feature/services/google_drive_service.dart' as docs_drive;
import 'package:google_sign_in/google_sign_in.dart';
import 'notification_service.dart';

final vaultServiceProvider = Provider((ref) => VaultService());

class LocalSyncingNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void setSyncing(bool value) {
    state = value;
  }
}

final localSyncingProvider = NotifierProvider<LocalSyncingNotifier, bool>(LocalSyncingNotifier.new);

void _triggerLocalSyncIndicator(Ref ref) {
  ref.read(localSyncingProvider.notifier).setSyncing(true);
  Future.delayed(const Duration(milliseconds: 800), () {
    ref.read(localSyncingProvider.notifier).setSyncing(false);
  });
}

final expenseBudgetProvider = NotifierProvider<ExpenseBudgetNotifier, Map<String, double>>(ExpenseBudgetNotifier.new);

class ExpenseBudgetNotifier extends Notifier<Map<String, double>> {
  @override
  Map<String, double> build() {
    _load();
    return {};
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('expense_budgets');
    if (jsonStr != null) {
      try {
        final Map<String, dynamic> decoded = json.decode(jsonStr);
        final Map<String, double> loaded = {};
        decoded.forEach((key, value) {
          if (value is num) {
            loaded[key] = value.toDouble();
          }
        });
        state = loaded;
      } catch (_) {}
    }
  }

  Future<void> setBudget(String category, double limit) async {
    final newState = {...state, category: limit};
    state = newState;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('expense_budgets', json.encode(newState));
  }

  Future<void> clearBudget(String category) async {
    final newState = {...state}..remove(category);
    state = newState;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('expense_budgets', json.encode(newState));
  }
}

enum NoteSortOrder { dateNewest, dateOldest, atoz, ztoa, manual }
enum ExpenseSortOrder { dateNewest, dateOldest, amountHighest, amountLowest, atoz, ztoa }

class SearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';
  @override
  set state(String value) => super.state = value;
}
final searchQueryProvider = NotifierProvider<SearchQueryNotifier, String>(SearchQueryNotifier.new);

class ShowFavoritesOnlyNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  @override
  set state(bool value) => super.state = value;
}
class ShowLinkPreviewsNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  @override
  set state(bool value) => super.state = value;
}
final showLinkPreviewsProvider = NotifierProvider<ShowLinkPreviewsNotifier, bool>(ShowLinkPreviewsNotifier.new);
final showFavoritesOnlyProvider = NotifierProvider<ShowFavoritesOnlyNotifier, bool>(ShowFavoritesOnlyNotifier.new);

class SortOrderNotifier extends Notifier<NoteSortOrder> {
  static const _key = 'note_sort_order';
  @override
  NoteSortOrder build() {
    _load();
    return NoteSortOrder.dateNewest;
  }
  
  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getInt(_key);
    if (index != null && index < NoteSortOrder.values.length) {
      state = NoteSortOrder.values[index];
    }
  }

  @override
  set state(NoteSortOrder value) {
    super.state = value;
    _save(value);
  }

  Future<void> _save(NoteSortOrder value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, value.index);
  }
}
final sortOrderProvider = NotifierProvider<SortOrderNotifier, NoteSortOrder>(SortOrderNotifier.new);

class ExpenseSortOrderNotifier extends Notifier<ExpenseSortOrder> {
  static const _key = 'expense_sort_order';
  @override
  ExpenseSortOrder build() {
    _load();
    return ExpenseSortOrder.dateNewest;
  }
  
  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getInt(_key);
    if (index != null && index < ExpenseSortOrder.values.length) {
      state = ExpenseSortOrder.values[index];
    }
  }

  @override
  set state(ExpenseSortOrder value) {
    super.state = value;
    _save(value);
  }

  Future<void> _save(ExpenseSortOrder value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, value.index);
  }
}
final expenseSortOrderProvider = NotifierProvider<ExpenseSortOrderNotifier, ExpenseSortOrder>(ExpenseSortOrderNotifier.new);

class FontSizeNotifier extends Notifier<double> {
  static const _key = 'app_font_size';
  @override
  double build() {
    _load();
    return 14.0;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final size = prefs.getDouble(_key);
    if (size != null) state = size;
  }

  @override
  set state(double value) {
    super.state = value;
    _save(value);
  }

  Future<void> _save(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_key, value);
  }
}
final fontSizeProvider = NotifierProvider<FontSizeNotifier, double>(FontSizeNotifier.new);

class DragAndDropNotifier extends Notifier<bool> {
  static const _key = 'drag_and_drop_enabled';
  @override
  bool build() {
    _load();
    return false;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_key);
    if (enabled != null) state = enabled;
  }

  @override
  set state(bool value) {
    super.state = value;
    _save(value);
  }

  Future<void> _save(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, value);
  }
}
final dragAndDropEnabledProvider = NotifierProvider<DragAndDropNotifier, bool>(DragAndDropNotifier.new);

class LockNotifier extends Notifier<String> {
  static const _key = 'vault_lock_password';

  @override
  String build() {
    _loadLock();
    return '1851421';
  }

  Future<void> _loadLock() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    if (saved != null) {
      state = saved;
    }
  }

  Future<void> setLock(String newPassword) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, newPassword);
    state = newPassword;
  }
}

final lockProvider = NotifierProvider<LockNotifier, String>(LockNotifier.new);

class GroupExpensesNotifier extends Notifier<bool> {
  static const _key = 'show_grouped_expenses';
  @override
  bool build() {
    _load();
    return false;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_key);
    if (enabled != null) state = enabled;
  }

  @override
  set state(bool value) {
    super.state = value;
    _save(value);
  }

  Future<void> _save(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, value);
  }
}
final showGroupedExpensesProvider = NotifierProvider<GroupExpensesNotifier, bool>(GroupExpensesNotifier.new);

class BiometricLockNotifier extends Notifier<bool> {
  static const _key = 'biometric_app_lock_enabled';

  @override
  bool build() {
    _load();
    return false;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_key);
    if (enabled != null) state = enabled;
  }

  @override
  set state(bool value) {
    super.state = value;
    _save(value);
  }

  Future<void> _save(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, value);
  }
}

final biometricLockEnabledProvider = NotifierProvider<BiometricLockNotifier, bool>(BiometricLockNotifier.new);

class SecurityLockEnabledNotifier extends Notifier<bool> {
  static const _key = 'security_lock_enabled';

  @override
  bool build() {
    _load();
    return false; // Disabled by default!
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_key);
    if (enabled != null) {
      state = enabled;
    }
  }

  @override
  set state(bool value) {
    super.state = value;
    _save(value);
  }

  Future<void> _save(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, value);
  }
}

final securityLockEnabledProvider = NotifierProvider<SecurityLockEnabledNotifier, bool>(SecurityLockEnabledNotifier.new);

class NotesNotifier extends Notifier<List<Note>> {
  Future<void>? _initFuture;

  @override
  List<Note> build() {
    ref.watch(vaultPathProvider);
    _initFuture = _load();
    return [];
  }

  Future<void> _load() async {
    final service = ref.read(vaultServiceProvider);
    final data = await service.loadVaultData();
    if (data['notes'] != null) {
      state = (data['notes'] as List).map((n) => Note.fromJson(n)).toList();
      // Ensure orderIndex is consistent if zero - initialize based on Date Newest
      if (state.isNotEmpty && state.every((n) => n.orderIndex == 0)) {
        final sorted = List<Note>.from(state)..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        state = [
          for (int i = 0; i < sorted.length; i++)
            sorted[i].copyWith(orderIndex: i)
        ];
      }
    }
  }

  Future<void> addNote(Note note) async {
    await _initFuture;
    // Deduplication: check if same title and content exists
    if (state.any((n) => n.title == note.title && n.content == note.content)) return;

    // Add to end of manual order
    final newOrder = state.isEmpty ? 0 : state.map((n) => n.orderIndex).reduce((a, b) => a > b ? a : b) + 1;
    state = [...state, note.copyWith(orderIndex: newOrder)];
    _save();
  }

  Future<void> updateNote(Note note) async {
    await _initFuture;
    state = [
      for (final n in state)
        if (n.id == note.id) note else n
    ];
    _save();
  }

  Future<void> deleteNote(String id) async {
    await deleteNotes([id]);
  }

  Future<void> deleteNotes(List<String> ids) async {
    await _initFuture;
    final deletedNotes = state.where((n) => ids.contains(n.id)).toList();
    state = state.where((n) => !ids.contains(n.id)).toList();
    
    // Add to recycle bin
    ref.read(deletedNotesProvider.notifier).addNotes(deletedNotes);
    
    _save();
  }

  Future<void> moveNote(String noteId, String newCategory) async {
    await moveNotes([noteId], newCategory);
  }

  Future<void> moveNotes(List<String> ids, String newCategory) async {
    await _initFuture;
    state = [
      for (final n in state)
        if (ids.contains(n.id)) n.copyWith(category: newCategory) else n
    ];
    _save();
  }
  Future<void> togglePin(String id) async {
    await _initFuture;
    state = [
      for (final n in state)
        if (n.id == id) n.copyWith(isPinned: !n.isPinned) else n
    ];
    _save();
  }

  Future<void> toggleLock(String id) async {
    await _initFuture;
    state = [
      for (final n in state)
        if (n.id == id) n.copyWith(isLocked: !n.isLocked) else n
    ];
    _save();
  }

  Future<void> toggleFavorite(String id) async {
    await _initFuture;
    state = [
      for (final n in state)
        if (n.id == id) n.copyWith(isFavorite: !n.isFavorite) else n
    ];
    _save();
  }

  Future<void> reorderNotes(List<Note> reorderedList) async {
    await _initFuture;
    state = [
      for (int i = 0; i < reorderedList.length; i++)
        reorderedList[i].copyWith(orderIndex: i)
    ];
    _save();
  }

  void _save() {
    final categories = ref.read(categoriesProvider);
    ref.read(vaultServiceProvider).saveNotes(state, categories);
    _triggerLocalSyncIndicator(ref);
  }
}

final notesProvider = NotifierProvider<NotesNotifier, List<Note>>(NotesNotifier.new);

final filteredNotesProvider = Provider.family<List<Note>, String>((ref, category) {
  final notes = ref.watch(notesProvider);
  final query = ref.watch(searchQueryProvider).toLowerCase();
  final sortOrder = ref.watch(sortOrderProvider);
  final showFavs = ref.watch(showFavoritesOnlyProvider);

  // If searching, we do global search (ignore category)
  var filtered = query.isNotEmpty
    ? notes.toList()
    : notes.where((n) => n.category == category).toList();

  // Filter by favorite
  if (showFavs) {
    filtered = filtered.where((n) => n.isFavorite).toList();
  }

  // Filter by search query
  if (query.isNotEmpty) {
    filtered = filtered.where((n) => 
      n.title.toLowerCase().contains(query) || 
      n.content.toLowerCase().contains(query)
    ).toList();
  }

  // Sort
  filtered.sort((a, b) {
    // Pinned notes always on top
    if (a.isPinned && !b.isPinned) return -1;
    if (!a.isPinned && b.isPinned) return 1;

    switch (sortOrder) {
      case NoteSortOrder.dateNewest:
        return b.createdAt.compareTo(a.createdAt);
      case NoteSortOrder.dateOldest:
        return a.createdAt.compareTo(b.createdAt);
      case NoteSortOrder.atoz:
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      case NoteSortOrder.ztoa:
        return b.title.toLowerCase().compareTo(a.title.toLowerCase());
      case NoteSortOrder.manual:
        return a.orderIndex.compareTo(b.orderIndex);
    }
  });

  return filtered;
});


class ExpensesNotifier extends Notifier<List<Expense>> {
  Future<void>? _initFuture;

  @override
  List<Expense> build() {
    ref.watch(vaultPathProvider);
    _initFuture = _load();
    return [];
  }

  Future<void> _load() async {
    final service = ref.read(vaultServiceProvider);
    final data = await service.loadVaultData();
    if (data['expenses'] != null) {
      final loadedExpenses = (data['expenses'] as List).map((e) => Expense.fromJson(e)).toList();
      state = loadedExpenses;
      
      // Ensure orderIndex consistency
      if (state.isNotEmpty && state.every((e) => e.orderIndex == 0)) {
        final sorted = List<Expense>.from(state)..sort((a, b) => b.date.compareTo(a.date));
        state = [
          for (int i = 0; i < sorted.length; i++)
            sorted[i].copyWith(orderIndex: i)
        ];
      }

      if (loadedExpenses.any((e) => e.category == 'Other' || e.category == 'Uncategorized')) {
        _save();
      }
    }
  }

  Future<void> addExpense(Expense expense) async {
    await _initFuture;
    // Deduplication: check if same title, amount and date exists
    if (state.any((e) => e.title == expense.title && e.amount == expense.amount && e.date == expense.date)) return;
    state = [...state, expense];
    _save();
  }

  Future<void> addExpenses(List<Expense> newExpenses) async {
    await _initFuture;
    // Avoid duplicates by ID or Content
    final existingIds = state.map((e) => e.id).toSet();
    final uniqueNew = newExpenses.where((newExp) {
      final idExists = existingIds.contains(newExp.id);
      final contentExists = state.any((e) => e.title == newExp.title && e.amount == newExp.amount && e.date == newExp.date);
      return !idExists && !contentExists;
    }).toList();
    
    state = [...state, ...uniqueNew];
    _save();
  }

  Future<void> deleteExpense(String id) async {
    await deleteExpenses([id]);
  }

  Future<void> deleteExpenses(List<String> ids) async {
    await _initFuture;
    final deletedExps = state.where((e) => ids.contains(e.id)).toList();
    state = state.where((e) => !ids.contains(e.id)).toList();
    
    // Add to recycle bin
    await ref.read(deletedExpensesProvider.notifier).addExpenses(deletedExps);
    
    _save();
  }

  Future<void> updateExpense(Expense expense) async {
    await _initFuture;
    state = [
      for (final e in state)
        if (e.id == expense.id) expense else e
    ];
    _save();
  }

  Future<void> toggleLock(String id) async {
    await _initFuture;
    state = [
      for (final e in state)
        if (e.id == id) e.copyWith(isLocked: !e.isLocked) else e
    ];
    _save();
  }

  Future<void> togglePin(String id) async {
    await _initFuture;
    state = [
      for (final e in state)
        if (e.id == id) e.copyWith(isPinned: !e.isPinned) else e
    ];
    _save();
  }

  Future<void> toggleFavorite(String id) async {
    await _initFuture;
    state = [
      for (final e in state)
        if (e.id == id) e.copyWith(isFavorite: !e.isFavorite) else e
    ];
    _save();
  }

  Future<void> moveExpense(String id, String newCategory) async {
    await moveExpenses([id], newCategory);
  }

  Future<void> moveExpenses(List<String> ids, String newCategory) async {
    await _initFuture;
    state = [
      for (final e in state)
        if (ids.contains(e.id)) e.copyWith(category: newCategory) else e
    ];
    _save();
  }

  void _save() {
    ref.read(vaultServiceProvider).saveExpenses(state);
    _triggerLocalSyncIndicator(ref);
  }

  Future<void> reorderExpenses(List<Expense> reorderedList) async {
    await _initFuture;
    state = [
      for (int i = 0; i < reorderedList.length; i++)
        reorderedList[i].copyWith(orderIndex: i)
    ];
    _save();
  }
}

final expensesProvider = NotifierProvider<ExpensesNotifier, List<Expense>>(ExpensesNotifier.new);

class ExpenseCategoriesNotifier extends Notifier<List<String>> {
  Future<void>? _initFuture;

  @override
  List<String> build() {
    ref.watch(vaultPathProvider);
    _initFuture = _load();
    return [];
  }

  Future<void> _load() async {
    final service = ref.read(vaultServiceProvider);
    final data = await service.loadVaultData();
    if (data['expenseCategories'] != null) {
      final loadedCats = List<String>.from(data['expenseCategories']);
      state = loadedCats;
      _save();
    }
  }

  Future<void> addCategory(String category) async {
    await _initFuture;
    if (!state.contains(category)) {
      state = [...state, category];
      _save();
    }
  }

  Future<void> renameCategory(String oldName, String newName) async {
    await _initFuture;
    if (oldName == 'All') return;
    state = [for (final c in state) if (c == oldName) newName else c];
    
    final expensesNotifier = ref.read(expensesProvider.notifier);
    final allExpenses = ref.read(expensesProvider);
    for (final exp in allExpenses) {
      if (exp.category == oldName) {
        await expensesNotifier.moveExpense(exp.id, newName);
      }
    }
    _save();
  }

  Future<void> deleteCategory(String category) async {
    await _initFuture;
    if (category == 'All') return;
    state = state.where((c) => c != category).toList();
    
    final defaultCat = state.isNotEmpty ? state.first : '';
    
    final allExpenses = ref.read(expensesProvider);
    for (final exp in allExpenses) {
      if (exp.category == category) {
        await ref.read(expensesProvider.notifier).moveExpense(exp.id, defaultCat);
      }
    }

    if (ref.read(selectedExpenseCategoryProvider) == category) {
      ref.read(selectedExpenseCategoryProvider.notifier).state = state.isNotEmpty ? state.first : '';
    }
    _save();
  }

  Future<void> deleteCategories(List<String> cats) async {
    for (final cat in cats) {
      await deleteCategory(cat);
    }
  }

  void _save() {
    ref.read(vaultServiceProvider).saveExpenseCategories(state);
  }
}

final expenseCategoriesProvider = NotifierProvider<ExpenseCategoriesNotifier, List<String>>(ExpenseCategoriesNotifier.new);

class SelectedExpenseCategoryNotifier extends Notifier<String> {
  static const _key = 'last_expense_category';

  @override
  String build() {
    // Asynchronously load the saved category and update state once ready
    _loadSaved();
    return '';
  }

  Future<void> _loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    // Wait for expense categories to fully load from disk first
    await ref.read(expenseCategoriesProvider.notifier)._initFuture;
    final saved = prefs.getString(_key);
    final categories = ref.read(expenseCategoriesProvider);
    if (saved != null && saved.isNotEmpty && categories.contains(saved)) {
      state = saved;
    } else if (categories.isNotEmpty) {
      state = categories.first;
    }
  }

  @override
  set state(String value) {
    super.state = value;
    // Persist in background
    SharedPreferences.getInstance().then((prefs) => prefs.setString(_key, value));
  }
}

final selectedExpenseCategoryProvider = NotifierProvider<SelectedExpenseCategoryNotifier, String>(SelectedExpenseCategoryNotifier.new);

class CategoriesNotifier extends Notifier<List<String>> {
  Future<void>? _initFuture;

  @override
  List<String> build() {
    ref.watch(vaultPathProvider);
    _initFuture = _load();
    return ['General'];
  }

  Future<void> _load() async {
    final service = ref.read(vaultServiceProvider);
    final data = await service.loadVaultData();
    if (data['categories'] != null) {
      final loaded = List<String>.from(data['categories']);
      state = loaded.where((c) => c != 'All').toList();
      if (state.isEmpty) state = ['General'];
    }
  }

  Future<void> addCategory(String category) async {
    await _initFuture;
    if (category == 'All') return;
    if (!state.contains(category)) {
      state = [...state, category];
      _save();
    }
  }

  Future<void> renameCategory(String oldName, String newName) async {
    await _initFuture;
    if (oldName == 'General') return; // Don't rename General
    if (newName == 'All') return;
    state = [for (final c in state) if (c == oldName) newName else c];
    
    // Update all notes in this category
    final notesNotifier = ref.read(notesProvider.notifier);
    final allNotes = ref.read(notesProvider);
    for (final note in allNotes) {
      if (note.category == oldName) {
        await notesNotifier.updateNote(note.copyWith(category: newName));
      }
    }
    _save();
  }

  Future<void> deleteCategory(String category) async {
    await _initFuture;
    if (category == 'General') return; // Don't delete General
    state = state.where((c) => c != category).toList();
    
    // Move all notes in this category to Recycle Bin
    final notesNotifier = ref.read(notesProvider.notifier);
    final allNotes = ref.read(notesProvider);
    final notesToDelete = allNotes.where((n) => n.category == category).toList();
    
    if (notesToDelete.isNotEmpty) {
      await notesNotifier.deleteNotes(notesToDelete.map((n) => n.id).toList());
    }

    if (ref.read(selectedCategoryProvider) == category) {
      ref.read(selectedCategoryProvider.notifier).state = 'General';
    }
    
    _save();
  }

  Future<void> deleteCategories(List<String> categoriesToDelete) async {
    await _initFuture;
    state = state.where((c) => !categoriesToDelete.contains(c) || c == 'General').toList();
    
    final notesNotifier = ref.read(notesProvider.notifier);
    final allNotes = ref.read(notesProvider);
    final notesToDelete = allNotes.where((n) => categoriesToDelete.contains(n.category) && n.category != 'General').toList();
    
    if (notesToDelete.isNotEmpty) {
      await notesNotifier.deleteNotes(notesToDelete.map((n) => n.id).toList());
    }

    if (categoriesToDelete.contains(ref.read(selectedCategoryProvider))) {
      ref.read(selectedCategoryProvider.notifier).state = 'General';
    }
    
    _save();
  }

  void _save() {
    final notes = ref.read(notesProvider);
    ref.read(vaultServiceProvider).saveNotes(notes, state);
    _triggerLocalSyncIndicator(ref);
  }
}

final categoriesProvider = NotifierProvider<CategoriesNotifier, List<String>>(CategoriesNotifier.new);

class SelectedCategoryNotifier extends Notifier<String> {
  @override
  String build() => 'General';
  
  @override
  set state(String value) => super.state = value;
}

final selectedCategoryProvider = NotifierProvider<SelectedCategoryNotifier, String>(SelectedCategoryNotifier.new);

class SelectedNotesNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => {};

  void toggle(String id) {
    if (state.contains(id)) {
      state = {for (final item in state) if (item != id) item};
    } else {
      state = {...state, id};
    }
  }

  void clear() => state = {};
  
  void selectAll(Set<String> ids) => state = ids;
}

final selectedNotesProvider = NotifierProvider<SelectedNotesNotifier, Set<String>>(SelectedNotesNotifier.new);

class DeletedNotesNotifier extends Notifier<List<Note>> {
  Future<void>? _initFuture;

  @override
  List<Note> build() {
    ref.watch(vaultPathProvider);
    _initFuture = _load();
    return [];
  }

  Future<void> _load() async {
    final data = await ref.read(vaultServiceProvider).loadDeletedData();
    if (data['notes'] != null) {
      state = (data['notes'] as List).map((n) => Note.fromJson(n)).toList();
    }
  }

  Future<void> addNotes(List<Note> notes) async {
    await _initFuture;
    // Basic deduplication: check if a note with same title and content exists
    final newNotes = notes.where((newNote) => !state.any((n) => n.title == newNote.title && n.content == newNote.content)).toList();
    state = [...state, ...newNotes];
    _save();
  }

  Future<void> restoreNote(String id) async {
    await _initFuture;
    final note = state.firstWhere((n) => n.id == id);
    state = state.where((n) => n.id != id).toList();
    
    // Auto-create category if missing
    await ref.read(categoriesProvider.notifier).addCategory(note.category);
    
    await ref.read(notesProvider.notifier).addNote(note);
    _save();
  }

  Future<void> restoreAll() async {
    await _initFuture;
    final allNotes = List<Note>.from(state);
    state = [];
    
    for (final note in allNotes) {
      // Auto-create category if missing
      await ref.read(categoriesProvider.notifier).addCategory(note.category);
      await ref.read(notesProvider.notifier).addNote(note);
    }
    _save();
  }

  Future<void> deletePermanently(String id) async {
    await _initFuture;
    state = state.where((n) => n.id != id).toList();
    _save();
  }

  Future<void> deleteAll() async {
    await _initFuture;
    state = [];
    _save();
  }

  void _save() {
    ref.read(vaultServiceProvider).saveDeletedNotes(state);
  }
}

final deletedNotesProvider = NotifierProvider<DeletedNotesNotifier, List<Note>>(DeletedNotesNotifier.new);

class DeletedExpensesNotifier extends Notifier<List<Expense>> {
  Future<void>? _initFuture;

  @override
  List<Expense> build() {
    ref.watch(vaultPathProvider);
    _initFuture = _load();
    return [];
  }

  Future<void> _load() async {
    final data = await ref.read(vaultServiceProvider).loadDeletedData();
    if (data['expenses'] != null) {
      state = (data['expenses'] as List).map((e) => Expense.fromJson(e)).toList();
    }
  }

  Future<void> addExpenses(List<Expense> expenses) async {
    await _initFuture;
    state = [...state, ...expenses];
    _save();
  }

  Future<void> restoreExpense(String id) async {
    await _initFuture;
    final exp = state.firstWhere((e) => e.id == id);
    state = state.where((e) => e.id != id).toList();
    await ref.read(expensesProvider.notifier).addExpense(exp);
    _save();
  }

  Future<void> deletePermanently(String id) async {
    await _initFuture;
    state = state.where((e) => e.id != id).toList();
    _save();
  }

  Future<void> restoreAll() async {
    await _initFuture;
    final allExps = List<Expense>.from(state);
    state = [];
    for (final exp in allExps) {
      await ref.read(expensesProvider.notifier).addExpense(exp);
    }
    _save();
  }

  Future<void> deleteAll() async {
    await _initFuture;
    state = [];
    _save();
  }

  void _save() {
    ref.read(vaultServiceProvider).saveDeletedExpenses(state);
  }
}

final deletedExpensesProvider = NotifierProvider<DeletedExpensesNotifier, List<Expense>>(DeletedExpensesNotifier.new);

class SelectedExpensesNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => {};

  void toggle(String id) {
    if (state.contains(id)) {
      state = {for (final item in state) if (item != id) item};
    } else {
      state = {...state, id};
    }
  }

  void clear() => state = {};
  
  void selectAll(Set<String> ids) => state = ids;
}

final selectedExpensesProvider = NotifierProvider<SelectedExpensesNotifier, Set<String>>(SelectedExpensesNotifier.new);

class LinkItemsNotifier extends Notifier<List<LinkItem>> {
  Future<void>? _initFuture;

  @override
  List<LinkItem> build() {
    ref.watch(vaultPathProvider);
    _initFuture = _load();
    return [];
  }

  Future<void> _load() async {
    final service = ref.read(vaultServiceProvider);
    final data = await service.loadVaultData();
    if (data['links'] != null) {
      state = (data['links'] as List).map((l) => LinkItem.fromJson(l)).toList();
      // Ensure orderIndex consistency
      if (state.isNotEmpty && state.every((l) => l.orderIndex == 0)) {
        final sorted = List<LinkItem>.from(state)..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        state = [
          for (int i = 0; i < sorted.length; i++)
            sorted[i].copyWith(orderIndex: i)
        ];
      }
    }
  }

  Future<void> addLink(LinkItem link) async {
    await _initFuture;
    // Deduplication by URL
    if (state.any((l) => l.url == link.url)) return;
    state = [...state, link];
    _save();
  }

  Future<void> updateLink(LinkItem link) async {
    await _initFuture;
    state = [
      for (final l in state)
        if (l.id == link.id) link else l
    ];
    _save();
  }

  Future<void> toggleLock(String id) async {
    await _initFuture;
    state = [
      for (final l in state)
        if (l.id == id) l.copyWith(isLocked: !l.isLocked) else l
    ];
    _save();
  }

  Future<void> togglePin(String id) async {
    await _initFuture;
    state = [
      for (final l in state)
        if (l.id == id) l.copyWith(isPinned: !l.isPinned) else l
    ];
    _save();
  }

  Future<void> toggleFavorite(String id) async {
    await _initFuture;
    state = [
      for (final l in state)
        if (l.id == id) l.copyWith(isFavorite: !l.isFavorite) else l
    ];
    _save();
  }

  Future<void> deleteLink(String id) async {
    await deleteLinks([id]);
  }

  Future<void> deleteLinks(List<String> ids) async {
    await _initFuture;
    final deletedLinks = state.where((l) => ids.contains(l.id)).toList();
    state = state.where((l) => !ids.contains(l.id)).toList();
    
    // Add to recycle bin
    ref.read(deletedLinksProvider.notifier).addLinks(deletedLinks);
    
    _save();
  }

  Future<void> reorderLinks(List<LinkItem> reorderedList) async {
    await _initFuture;
    state = [
      for (int i = 0; i < reorderedList.length; i++)
        reorderedList[i].copyWith(orderIndex: i)
    ];
    _save();
  }

  Future<void> moveLinks(List<String> ids, String newCategory) async {
    await _initFuture;
    state = [
      for (final l in state)
        if (ids.contains(l.id)) l.copyWith(category: newCategory) else l
    ];
    _save();
  }

  void _save() {
    ref.read(vaultServiceProvider).saveLinks(state);
    _triggerLocalSyncIndicator(ref);
  }
}

final linkItemsProvider = NotifierProvider<LinkItemsNotifier, List<LinkItem>>(LinkItemsNotifier.new);

class DeletedLinksNotifier extends Notifier<List<LinkItem>> {
  Future<void>? _initFuture;

  @override
  List<LinkItem> build() {
    ref.watch(vaultPathProvider);
    _initFuture = _load();
    return [];
  }

  Future<void> _load() async {
    final data = await ref.read(vaultServiceProvider).loadDeletedData();
    if (data['links'] != null) {
      state = (data['links'] as List).map((l) => LinkItem.fromJson(l)).toList();
    }
  }

  Future<void> addLinks(List<LinkItem> links) async {
    await _initFuture;
    state = [...state, ...links];
    _save();
  }

  Future<void> restoreLink(String id) async {
    await _initFuture;
    final link = state.firstWhere((l) => l.id == id);
    state = state.where((l) => l.id != id).toList();
    await ref.read(linkItemsProvider.notifier).addLink(link);
    _save();
  }

  Future<void> deletePermanently(String id) async {
    await _initFuture;
    state = state.where((l) => l.id != id).toList();
    _save();
  }

  Future<void> restoreAll() async {
    await _initFuture;
    final allLinks = List<LinkItem>.from(state);
    state = [];
    for (final link in allLinks) {
      await ref.read(linkItemsProvider.notifier).addLink(link);
    }
    _save();
  }

  Future<void> deleteAll() async {
    await _initFuture;
    state = [];
    _save();
  }

  void _save() {
    ref.read(vaultServiceProvider).saveDeletedLinks(state);
  }
}

final deletedLinksProvider = NotifierProvider<DeletedLinksNotifier, List<LinkItem>>(DeletedLinksNotifier.new);

class SelectedLinksNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => {};

  void toggle(String id) {
    if (state.contains(id)) {
      state = {for (final item in state) if (item != id) item};
    } else {
      state = {...state, id};
    }
  }

  void clear() => state = {};
  
  void selectAll(Set<String> ids) => state = ids;
}

final selectedLinksProvider = NotifierProvider<SelectedLinksNotifier, Set<String>>(SelectedLinksNotifier.new);

class LinkCategoriesNotifier extends Notifier<List<String>> {
  Future<void>? _initFuture;

  @override
  List<String> build() {
    ref.watch(vaultPathProvider);
    _initFuture = _load();
    return [];
  }

  Future<void> _load() async {
    final service = ref.read(vaultServiceProvider);
    final data = await service.loadVaultData();
    if (data['linkCategories'] != null) {
      state = List<String>.from(data['linkCategories'])
          .where((c) => c != 'All' && c != 'General')
          .toList();
    }
  }

  Future<void> addCategory(String category) async {
    await _initFuture;
    if (category == 'All' || category == 'General') return;
    if (!state.contains(category)) {
      state = [...state, category];
      _save();
    }
  }

  Future<void> renameCategory(String oldName, String newName) async {
    await _initFuture;
    if (oldName == 'All') return;
    state = [for (final c in state) if (c == oldName) newName else c];
    
    // Update links in this category
    final linksNotifier = ref.read(linkItemsProvider.notifier);
    final allLinks = ref.read(linkItemsProvider);
    for (final link in allLinks) {
      if (link.category == oldName) {
        await linksNotifier.updateLink(link.copyWith(category: newName));
      }
    }
    _save();
  }

  Future<void> deleteCategory(String category) async {
    await _initFuture;
    if (category == 'All') return;
    state = state.where((c) => c != category).toList();
    
    // Move links to All
    final allLinks = ref.read(linkItemsProvider);
    for (final link in allLinks) {
      if (link.category == category) {
        await ref.read(linkItemsProvider.notifier).updateLink(link.copyWith(category: 'All'));
      }
    }
    _save();
  }

  Future<void> deleteCategories(List<String> categoriesToDelete) async {
    await _initFuture;
    state = state.where((c) => !categoriesToDelete.contains(c) || c == 'All').toList();
    
    // Move all links in these categories to All
    final linksNotifier = ref.read(linkItemsProvider.notifier);
    final allLinks = ref.read(linkItemsProvider);
    for (final link in allLinks) {
      if (categoriesToDelete.contains(link.category)) {
        await linksNotifier.updateLink(link.copyWith(category: 'All'));
      }
    }
    _save();
  }

  void _save() {
    ref.read(vaultServiceProvider).saveLinkCategories(state);
  }
}

final linkCategoriesProvider = NotifierProvider<LinkCategoriesNotifier, List<String>>(LinkCategoriesNotifier.new);

class SelectedLinkCategoryNotifier extends Notifier<String> {
  @override
  String build() => 'All';
  @override
  set state(String value) => super.state = value;
}
final selectedLinkCategoryProvider = NotifierProvider<SelectedLinkCategoryNotifier, String>(SelectedLinkCategoryNotifier.new);

class TablesNotifier extends Notifier<List<VaultTable>> {
  Future<void>? _initFuture;

  @override
  List<VaultTable> build() {
    ref.watch(vaultPathProvider);
    _initFuture = _load();
    return [];
  }

  Future<void> _load() async {
    final service = ref.read(vaultServiceProvider);
    final data = await service.loadVaultData();
    if (data['tables'] != null) {
      state = (data['tables'] as List).map((t) => VaultTable.fromJson(t)).toList();
    }
  }

  Future<void> addTable(VaultTable table) async {
    await _initFuture;
    state = [...state, table];
    _save();
  }

  Future<void> updateTable(VaultTable table) async {
    await _initFuture;
    state = [for (final t in state) if (t.id == table.id) table else t];
    _save();
  }

  Future<void> deleteTable(String id) async {
    await _initFuture;
    state = state.where((t) => t.id != id).toList();
    _save();
  }

  Future<void> togglePin(String id) async {
    await _initFuture;
    state = [for (final t in state) if (t.id == id) t.copyWith(isPinned: !t.isPinned) else t];
    _save();
  }

  Future<void> toggleLock(String id) async {
    await _initFuture;
    state = [for (final t in state) if (t.id == id) t.copyWith(isLocked: !t.isLocked) else t];
    _save();
  }

  Future<void> toggleFavorite(String id) async {
    await _initFuture;
    state = [for (final t in state) if (t.id == id) t.copyWith(isFavorite: !t.isFavorite) else t];
    _save();
  }

  void _save() {
    ref.read(vaultServiceProvider).saveTables(state);
    _triggerLocalSyncIndicator(ref);
  }
}

final tablesProvider = NotifierProvider<TablesNotifier, List<VaultTable>>(TablesNotifier.new);

class EditingTableNotifier extends Notifier<VaultTable?> {
  @override
  VaultTable? build() => null;
  @override
  set state(VaultTable? value) => super.state = value;
}

final editingTableProvider = NotifierProvider<EditingTableNotifier, VaultTable?>(EditingTableNotifier.new);

class CopiedTableNotifier extends Notifier<VaultTable?> {
  @override
  VaultTable? build() => null;
  @override
  set state(VaultTable? value) => super.state = value;
}

final copiedTableProvider = NotifierProvider<CopiedTableNotifier, VaultTable?>(CopiedTableNotifier.new);

class TableCategoriesNotifier extends Notifier<List<String>> {
  Future<void>? _initFuture;

  @override
  List<String> build() {
    ref.watch(vaultPathProvider);
    _initFuture = _load();
    return ['General'];
  }

  Future<void> _load() async {
    final service = ref.read(vaultServiceProvider);
    final data = await service.loadVaultData();
    if (data['tableCategories'] != null) {
      final loaded = List<String>.from(data['tableCategories']);
      state = loaded.where((c) => c != 'All' && c != 'All Cards').toList();
      if (state.isEmpty) state = ['General'];
    }
  }

  Future<void> addCategory(String category) async {
    await _initFuture;
    if (category == 'All' || category == 'All Cards') return;
    if (!state.contains(category)) {
      state = [...state, category];
      _save();
    }
  }

  Future<void> renameCategory(String oldName, String newName) async {
    await _initFuture;
    if (oldName == 'General') return;
    if (newName == 'All' || newName == 'All Cards') return;
    state = [for (final c in state) if (c == oldName) newName else c];
    
    // Update tables in this category
    final tablesNotifier = ref.read(tablesProvider.notifier);
    final allTables = ref.read(tablesProvider);
    for (final table in allTables) {
      if (table.category == oldName) {
        await tablesNotifier.updateTable(table.copyWith(category: newName));
      }
    }
    _save();
  }

  Future<void> deleteCategory(String category) async {
    await _initFuture;
    if (category == 'General') return;
    state = state.where((c) => c != category).toList();
    
    // Move tables to General
    final tablesNotifier = ref.read(tablesProvider.notifier);
    final allTables = ref.read(tablesProvider);
    for (final table in allTables) {
      if (table.category == category) {
        await tablesNotifier.updateTable(table.copyWith(category: 'General'));
      }
    }
    _save();
  }

  Future<void> deleteCategories(List<String> categoriesToDelete) async {
    for (final cat in categoriesToDelete) {
      await deleteCategory(cat);
    }
  }

  void _save() {
    ref.read(vaultServiceProvider).saveTableCategories(state);
  }
}

final tableCategoriesProvider = NotifierProvider<TableCategoriesNotifier, List<String>>(TableCategoriesNotifier.new);

class SelectedTableCategoryNotifier extends Notifier<String> {
  @override
  String build() => 'General';
  @override
  set state(String value) => super.state = value;
}

final selectedTableCategoryProvider = NotifierProvider<SelectedTableCategoryNotifier, String>(SelectedTableCategoryNotifier.new);

final vaultPathProvider = FutureProvider<String?>((ref) => ref.watch(vaultServiceProvider).getVaultPath());

final googleDriveServiceProvider = Provider((ref) => GoogleDriveService());

final googleUserProvider = StreamProvider<GoogleSignInAccount?>((ref) {
  final service = ref.watch(googleDriveServiceProvider);
  return service.onCurrentUserChanged;
});

enum SyncStatus { idle, syncing, success, error }

class SyncNotifier extends Notifier<SyncStatus> {
  @override
  SyncStatus build() => SyncStatus.idle;

  Future<void> syncWithDrive({List<String>? selectedFiles}) async {
    state = SyncStatus.syncing;
    try {
      final driveService = ref.read(googleDriveServiceProvider);
      final vaultService = ref.read(vaultServiceProvider);
      final vaultPath = await vaultService.getVaultPath();

      if (vaultPath == null) throw Exception('Vault path not set');

      final account = await driveService.signIn();
      if (account == null) {
        state = SyncStatus.idle;
        return;
      }

      final filesToSync = selectedFiles ?? [
        'notes_data.json',
        'expenses_data.json',
        'links_data.json',
        'tables_data.json',
        'bills_data.json',
        'monthly_reports.json',
        'mileage_data.json',
        'docs_data',
      ];

      for (final fileName in filesToSync) {
        if (fileName == 'docs_data') {
          await docs_drive.GoogleDriveService().backupData();
        } else {
          final localFile = File('$vaultPath/$fileName');
          if (await localFile.exists()) {
            await driveService.uploadFile(localFile, 'vault_notes_backup');
          }
        }
      }

      state = SyncStatus.success;
      Future.delayed(const Duration(seconds: 3), () {
        if (state == SyncStatus.success) state = SyncStatus.idle;
      });
    } catch (e) {
      print('Sync Error: $e');
      state = SyncStatus.error;
    }
  }

  Future<void> downloadFromDrive() async {
     state = SyncStatus.syncing;
     try {
       final driveService = ref.read(googleDriveServiceProvider);
       final vaultService = ref.read(vaultServiceProvider);
       final vaultPath = await vaultService.getVaultPath();

       if (vaultPath == null) throw Exception('Vault path not set');

       final account = await driveService.signIn();
       if (account == null) {
         state = SyncStatus.idle;
         return;
       }

      final filesToSync = [
         'notes_data.json',
         'expenses_data.json',
         'links_data.json',
         'tables_data.json',
         'bills_data.json',
         'monthly_reports.json',
         'mileage_data.json',
         'docs_data',
       ];

       for (final fileName in filesToSync) {
         if (fileName == 'docs_data') {
           await docs_drive.GoogleDriveService().restoreData();
         } else {
           final localFile = File('$vaultPath/$fileName');
           await driveService.downloadFile(fileName, 'vault_notes_backup', localFile);
         }
       }

       // Refresh data
       ref.invalidate(notesProvider);
       ref.invalidate(expensesProvider);
       ref.invalidate(linkItemsProvider);
       ref.invalidate(categoriesProvider);
       ref.invalidate(expenseCategoriesProvider);
       ref.invalidate(linkCategoriesProvider);
       ref.invalidate(fuelEntriesProvider);
       ref.invalidate(tablesProvider);
       ref.invalidate(tableCategoriesProvider);
       ref.invalidate(billsProvider);

       state = SyncStatus.success;
       Future.delayed(const Duration(seconds: 3), () {
         if (state == SyncStatus.success) state = SyncStatus.idle;
       });
     } catch (e) {
       print('Download Error: $e');
       state = SyncStatus.error;
     }
  }
  Future<void> signOut() async {
    try {
      final driveService = ref.read(googleDriveServiceProvider);
      await driveService.signOut();
      state = SyncStatus.idle;
    } catch (e) {
      print('Sign Out Error: $e');
    }
  }
}

final syncProvider = NotifierProvider<SyncNotifier, SyncStatus>(SyncNotifier.new);

// --- Cards Vault Implementation ---

class CardsNotifier extends Notifier<List<VaultCard>> {
  Future<void>? _initFuture;

  @override
  List<VaultCard> build() {
    ref.watch(vaultPathProvider);
    _initFuture = _load();
    return [];
  }

  Future<void> _load() async {
    final path = await ref.read(vaultServiceProvider).getVaultPath();
    if (path == null) {
      state = [];
      return;
    }
    final service = ref.read(vaultServiceProvider);
    final passcode = ref.read(lockProvider);
    state = await service.loadCards(passcode);
  }

  Future<void> addCard(VaultCard card) async {
    await _initFuture;
    state = [card, ...state];
    await _save();
  }

  Future<void> updateCard(VaultCard card) async {
    await _initFuture;
    state = [for (final c in state) if (c.id == card.id) card else c];
    await _save();
  }

  Future<void> deleteCard(String id) async {
    await _initFuture;
    state = state.where((c) => c.id != id).toList();
    await _save();
  }

  Future<void> _save() async {
    final path = await ref.read(vaultServiceProvider).getVaultPath();
    if (path == null) return;
    final passcode = ref.read(lockProvider);
    await ref.read(vaultServiceProvider).saveCards(state, passcode);
    _triggerLocalSyncIndicator(ref);
  }
}

final cardsProvider = NotifierProvider<CardsNotifier, List<VaultCard>>(CardsNotifier.new);

final filteredCardsProvider = Provider<List<VaultCard>>((ref) {
  final cards = ref.watch(cardsProvider);
  final query = ref.watch(searchQueryProvider).toLowerCase();
  
  if (query.isEmpty) return cards;
  
  return cards.where((c) => 
    c.bankName.toLowerCase().contains(query) || 
    c.cardNumber.contains(query) || 
    c.holderName.toLowerCase().contains(query)
  ).toList();
});

class RevealedCardNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void setRevealed(String? id) => state = id;
}
final revealedCardIdProvider = NotifierProvider<RevealedCardNotifier, String?>(RevealedCardNotifier.new);

class RemindersNotifier extends Notifier<List<Reminder>> {
  Future<void>? _initFuture;

  @override
  List<Reminder> build() {
    ref.watch(vaultPathProvider);
    _initFuture = _load();
    return [];
  }

  Future<void> _load() async {
    final service = ref.read(vaultServiceProvider);
    final data = await service.loadVaultData();
    if (data['reminders'] != null) {
      state = (data['reminders'] as List).map((r) => Reminder.fromJson(r)).toList();
    }
  }

  Future<void> addReminder(Reminder reminder) async {
    await _initFuture;
    state = [...state, reminder];
    _save();
    if (!reminder.isDismissed) {
      NotificationService().scheduleReminderNotification(
        id: reminder.id,
        title: reminder.title,
        body: reminder.description.isNotEmpty ? reminder.description : 'You have a reminder!',
        dateTime: reminder.dateTime,
        repeatType: reminder.repeatType,
      );
    }
  }

  Future<void> updateReminder(Reminder reminder) async {
    await _initFuture;
    final oldReminder = state.firstWhere((r) => r.id == reminder.id, orElse: () => reminder);
    final newlyDismissed = !oldReminder.isDismissed && reminder.isDismissed;

    state = [
      for (final r in state)
        if (r.id == reminder.id) reminder else r
    ];

    if (newlyDismissed && reminder.repeatType != 'none') {
      DateTime nextDate = reminder.dateTime;
      if (reminder.repeatType == 'daily') {
        nextDate = nextDate.add(const Duration(days: 1));
      } else if (reminder.repeatType == 'weekly') {
        nextDate = nextDate.add(const Duration(days: 7));
      } else if (reminder.repeatType == 'monthly') {
        nextDate = DateTime(nextDate.year, nextDate.month + 1, nextDate.day);
      }
      final nextReminder = Reminder(
        title: reminder.title,
        description: reminder.description,
        dateTime: nextDate,
        isDismissed: false,
        repeatType: reminder.repeatType,
      );
      state = [...state, nextReminder];
      NotificationService().scheduleReminderNotification(
        id: nextReminder.id,
        title: nextReminder.title,
        body: nextReminder.description.isNotEmpty ? nextReminder.description : 'You have a reminder!',
        dateTime: nextReminder.dateTime,
        repeatType: nextReminder.repeatType,
      );
    }

    if (reminder.isDismissed) {
      NotificationService().cancelReminderNotification(reminder.id);
    } else {
      NotificationService().scheduleReminderNotification(
        id: reminder.id,
        title: reminder.title,
        body: reminder.description.isNotEmpty ? reminder.description : 'You have a reminder!',
        dateTime: reminder.dateTime,
        repeatType: reminder.repeatType,
      );
    }

    _save();
  }

  Future<void> deleteReminder(String id) async {
    await _initFuture;
    state = state.where((r) => r.id != id).toList();
    _save();
    NotificationService().cancelReminderNotification(id);
  }

  Future<void> deleteReminders(List<String> ids) async {
    await _initFuture;
    state = state.where((r) => !ids.contains(r.id)).toList();
    _save();
    for (final id in ids) {
      NotificationService().cancelReminderNotification(id);
    }
  }

  void _save() {
    ref.read(vaultServiceProvider).saveReminders(state);
  }
}

final remindersProvider = NotifierProvider<RemindersNotifier, List<Reminder>>(RemindersNotifier.new);

class BillsNotifier extends Notifier<List<Bill>> {
  late Future<void> _initFuture;

  @override
  List<Bill> build() {
    _initFuture = _load();
    return [];
  }

  Future<void> _load() async {
    final data = await ref.read(vaultServiceProvider).loadVaultData();
    final List<dynamic> jsonList = data['bills'] ?? [];
    List<Bill> loadedBills = jsonList.map((e) => Bill.fromJson(e)).toList();
    
    bool needsSave = false;
    final now = DateTime.now();
    for (int i = 0; i < loadedBills.length; i++) {
      var bill = loadedBills[i];
      if (bill.isPaid && bill.lastPaidDate != null) {
        if (bill.lastPaidDate!.month != now.month || bill.lastPaidDate!.year != now.year) {
          loadedBills[i] = bill.copyWith(isPaid: false);
          needsSave = true;
        }
      }
    }
    
    state = loadedBills;
    if (needsSave) {
      _save();
    }
  }

  Future<void> addBill(Bill bill) async {
    await _initFuture;
    state = [...state, bill];
    _save();
  }

  Future<void> updateBill(Bill bill) async {
    await _initFuture;
    state = [for (final b in state) if (b.id == bill.id) bill else b];
    _save();
  }

  Future<void> deleteBill(String id) async {
    await _initFuture;
    state = state.where((b) => b.id != id).toList();
    _save();
  }

  Future<void> deleteBills(Iterable<String> ids) async {
    await _initFuture;
    state = state.where((b) => !ids.contains(b.id)).toList();
    _save();
  }

  Future<void> markAsPaid(String id) async {
    await _initFuture;
    final now = DateTime.now();
    final currentMonth = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    state = [
      for (final b in state)
        if (b.id == id)
          b.copyWith(
            isPaid: true,
            lastPaidDate: now,
            // Increment paidEmis for any bill if not already counted this month
            paidEmis: (b.lastEmiPaidMonth != currentMonth)
                ? (b.paidEmis ?? 0) + 1
                : b.paidEmis,
            lastEmiPaidMonth: (b.lastEmiPaidMonth != currentMonth)
                ? currentMonth
                : b.lastEmiPaidMonth,
          )
        else b
    ];
    _save();
  }

  void _save() {
    ref.read(vaultServiceProvider).saveBills(state);
  }
}

final billsProvider = NotifierProvider<BillsNotifier, List<Bill>>(BillsNotifier.new);

class SelectedRemindersNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => {};

  void toggle(String id) {
    if (state.contains(id)) {
      state = {for (final item in state) if (item != id) item};
    } else {
      state = {...state, id};
    }
  }

  void clear() => state = {};
  
  void selectAll(Set<String> ids) => state = ids;
}

final selectedRemindersProvider = NotifierProvider<SelectedRemindersNotifier, Set<String>>(SelectedRemindersNotifier.new);

class SelectedBillsNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => {};

  void toggle(String id) {
    if (state.contains(id)) {
      state = {for (final item in state) if (item != id) item};
    } else {
      state = {...state, id};
    }
  }

  void clear() => state = {};
  
  void selectAll(Set<String> ids) => state = ids;
}

final selectedBillsProvider = NotifierProvider<SelectedBillsNotifier, Set<String>>(SelectedBillsNotifier.new);

final currentTimeProvider = StreamProvider<DateTime>((ref) {
  return Stream.periodic(const Duration(seconds: 1), (_) => DateTime.now());
});

final activeRemindersProvider = Provider<List<Reminder>>((ref) {
  final reminders = ref.watch(remindersProvider);
  final now = ref.watch(currentTimeProvider).value ?? DateTime.now();
  return reminders.where((r) => !r.isDismissed && r.dateTime.isBefore(now)).toList();
});

class FuelEntriesNotifier extends Notifier<List<FuelEntry>> {
  Future<void>? _initFuture;

  @override
  List<FuelEntry> build() {
    state = [];
    _initFuture = _load();
    return state;
  }

  Future<void> _load() async {
    final data = await ref.read(vaultServiceProvider).loadVaultData();
    final list = data['fuelEntries'] as List? ?? [];
    state = list.map((e) => FuelEntry.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<void> refresh() async {
    await _load();
  }

  Future<void> addEntry(FuelEntry entry) async {
    await _initFuture;
    state = [...state, entry]..sort((a, b) => a.date.compareTo(b.date));
    _save();
  }

  Future<void> updateEntry(FuelEntry oldEntry, FuelEntry newEntry) async {
    await _initFuture;
    final index = state.indexOf(oldEntry);
    if (index != -1) {
      final newState = [...state];
      newState[index] = newEntry;
      newState.sort((a, b) => a.date.compareTo(b.date));
      state = newState;
      _save();
    }
  }

  Future<void> deleteEntry(FuelEntry entry) async {
    await _initFuture;
    state = state.where((e) => e != entry).toList();
    _save();
  }

  Future<void> setEntries(List<FuelEntry> entries) async {
    state = entries;
    _save();
  }

  void _save() {
    ref.read(vaultServiceProvider).saveFuelEntries(state);
  }
}

final fuelEntriesProvider = NotifierProvider<FuelEntriesNotifier, List<FuelEntry>>(FuelEntriesNotifier.new);
