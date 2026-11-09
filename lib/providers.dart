import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'models.dart';
import 'profiles/providers/profile_provider.dart' show profilesProvider;
import 'utils/grocery_catalog.dart';
import 'vault_service.dart';
import 'services/google_drive_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'docs_feature/services/google_drive_service.dart' as docs_drive;
import 'package:google_sign_in/google_sign_in.dart';
import 'notification_service.dart';
import 'docs_feature/providers/document_provider.dart';

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
    await _persist({...state, category: limit});
  }

  Future<void> clearBudget(String category) async {
    await _persist({...state}..remove(category));
  }

  /// Keeps a category's budget when the category is renamed.
  Future<void> renameCategory(String oldName, String newName) async {
    if (!state.containsKey(oldName)) return;
    final next = {...state};
    final limit = next.remove(oldName)!;
    next[newName] = limit;
    await _persist(next);
  }

  Future<void> _persist(Map<String, double> newState) async {
    state = newState;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('expense_budgets', json.encode(newState));
    // Budgets live in SharedPreferences; mirror them into the vault right away
    // so local folder sync and Drive backups always carry the latest values.
    await ref.read(vaultServiceProvider).exportAppSettings();
  }
}

enum NoteSortOrder { dateNewest, dateOldest, atoz, ztoa, manual, modifiedNewest }

/// Small persisted bool setting backed by SharedPreferences.
abstract class _PersistedBoolNotifier extends Notifier<bool> {
  String get prefsKey;
  bool get defaultValue => false;

  @override
  bool build() {
    _load();
    return defaultValue;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getBool(prefsKey);
    if (v != null && v != state) super.state = v;
  }

  @override
  set state(bool value) {
    super.state = value;
    SharedPreferences.getInstance().then((p) => p.setBool(prefsKey, value));
  }
}

class NotesGridViewNotifier extends _PersistedBoolNotifier {
  @override
  String get prefsKey => 'notes_grid_view';
}
final notesGridViewProvider = NotifierProvider<NotesGridViewNotifier, bool>(NotesGridViewNotifier.new);

class NotesSearchInCategoryNotifier extends _PersistedBoolNotifier {
  @override
  String get prefsKey => 'notes_search_current_category';
}
final notesSearchInCategoryProvider = NotifierProvider<NotesSearchInCategoryNotifier, bool>(NotesSearchInCategoryNotifier.new);

/// Swipe a note card right to pin / left to delete. While on, swiping
/// sideways no longer switches categories (the gestures would clash).
class NotesSwipeActionsNotifier extends _PersistedBoolNotifier {
  @override
  String get prefsKey => 'notes_swipe_actions';
}
final notesSwipeActionsProvider = NotifierProvider<NotesSwipeActionsNotifier, bool>(NotesSwipeActionsNotifier.new);

/// Reminder id used for the reminder attached to a note.
String noteReminderId(String noteId) => 'note_$noteId';
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

class EnabledTabsNotifier extends Notifier<List<String>> {
  static const _key = 'enabled_tabs';

  @override
  List<String> build() {
    _load();
    // Default all tabs enabled
    return ['notes', 'expenses', 'links', 'tables', 'bills', 'docs', 'mileage', 'grocery'];
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_key);
    if (saved != null) {
      state = saved;
    }
  }

  Future<void> toggleTab(String tabId, bool isEnabled) async {
    List<String> newState = List.from(state);
    if (isEnabled && !newState.contains(tabId)) {
      newState.add(tabId);
    } else if (!isEnabled && newState.contains(tabId)) {
      newState.remove(tabId);
    }
    // Keep order
    final ordered = ['notes', 'expenses', 'links', 'tables', 'bills', 'docs', 'mileage', 'grocery'].where((t) => newState.contains(t)).toList();
    state = ordered;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, ordered);
  }
}

final enabledTabsProvider = NotifierProvider<EnabledTabsNotifier, List<String>>(EnabledTabsNotifier.new);

final biometricLockEnabledProvider = NotifierProvider<BiometricLockNotifier, bool>(BiometricLockNotifier.new);

class SecurityLockEnabledNotifier extends Notifier<bool> {
  static const _key = 'security_lock_enabled';

  @override
  bool build() {
    _load();
    // Must match verifyPasscode(), which treats a missing value as enabled.
    return true;
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

  /// Adds [note]. Returns false if it was skipped.
  /// A note whose id already exists is always skipped. With [dedupe] (used by
  /// imports) a note with identical title and content is skipped as well.
  Future<bool> addNote(Note note, {bool dedupe = false}) async {
    await _initFuture;
    if (state.any((n) => n.id == note.id)) return false;
    if (dedupe && state.any((n) => n.title == note.title && n.content == note.content)) return false;

    // Add to end of manual order
    final newOrder = state.isEmpty ? 0 : state.map((n) => n.orderIndex).reduce((a, b) => a > b ? a : b) + 1;
    state = [...state, note.copyWith(orderIndex: newOrder)];
    _save();
    return true;
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
    final now = DateTime.now();
    final deletedNotes = state.where((n) => ids.contains(n.id)).map((n) => n.copyWith(deletedAt: now)).toList();
    state = state.where((n) => !ids.contains(n.id)).toList();
    
    // Add to recycle bin
    ref.read(deletedNotesProvider.notifier).addNotes(deletedNotes);

    // Drop any reminders attached to these notes
    final reminderIds = ids.map(noteReminderId).toSet();
    final attached = ref.read(remindersProvider).where((r) => reminderIds.contains(r.id)).map((r) => r.id).toList();
    if (attached.isNotEmpty) ref.read(remindersProvider.notifier).deleteReminders(attached);

    _save();
  }

  /// Renames a category on every note in it with a single save.
  Future<void> renameCategoryInNotes(String oldName, String newName) async {
    await _initFuture;
    if (!state.any((n) => n.category == oldName)) return;
    state = [
      for (final n in state)
        if (n.category == oldName) n.copyWith(category: newName) else n
    ];
    _save();
  }

  /// Puts notes back from the Recycle Bin. Unlike [addNote] this does not apply
  /// the title/content de-duplication, so a restored note is never silently dropped.
  Future<void> restoreNotes(List<Note> notes) async {
    await _initFuture;
    final existingIds = state.map((n) => n.id).toSet();
    final usedOrders = state.map((n) => n.orderIndex).toSet();
    var nextOrder = usedOrders.isEmpty ? 0 : usedOrders.reduce((a, b) => a > b ? a : b) + 1;
    final toAdd = <Note>[];
    for (final n in notes) {
      if (existingIds.contains(n.id)) continue;
      // Keep the note's old manual position if nothing has taken it since.
      final order = usedOrders.contains(n.orderIndex) ? nextOrder++ : n.orderIndex;
      usedOrders.add(order);
      toAdd.add(n.copyWith(deletedAt: null, orderIndex: order));
    }
    if (toAdd.isEmpty) return;
    state = [...state, ...toAdd];
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

  /// Applies a new manual order for a subset of notes (e.g. one category),
  /// keeping every other note in the slots it already had.
  Future<void> reorderSubset(List<Note> reorderedSubset) async {
    await _initFuture;
    final subsetIds = reorderedSubset.map((n) => n.id).toSet();
    final byOrder = List<Note>.from(state)..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    final queue = reorderedSubset.iterator;
    final merged = <Note>[
      for (final n in byOrder)
        if (subsetIds.contains(n.id)) (queue..moveNext()).current else n
    ];
    await reorderNotes(merged);
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

  // An empty category means "all categories" (used for global search).
  var filtered = category.isEmpty
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
      // Locked notes are only matched by title so their content isn't revealed
      (!n.isLocked && n.content.toLowerCase().contains(query))
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
      case NoteSortOrder.modifiedNewest:
        return b.lastModified.compareTo(a.lastModified);
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

  /// Adds [expense]. Returns false if an identical one (same title, amount
  /// and date) already exists, so the caller can tell the user.
  Future<bool> addExpense(Expense expense) async {
    await _initFuture;
    if (state.any((e) => e.id == expense.id ||
        (e.title == expense.title && e.amount == expense.amount && e.date == expense.date))) {
      return false;
    }
    state = [...state, expense];
    _save();
    return true;
  }

  /// Renames a category on every expense in it with a single save.
  Future<void> renameCategoryInExpenses(String oldName, String newName) async {
    await _initFuture;
    if (!state.any((e) => e.category == oldName)) return;
    state = [for (final e in state) if (e.category == oldName) e.copyWith(category: newName) else e];
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
    final now = DateTime.now();
    final deletedExps = state.where((e) => ids.contains(e.id)).map((e) => e.copyWith(deletedAt: now)).toList();
    state = state.where((e) => !ids.contains(e.id)).toList();
    
    // Add to recycle bin
    await ref.read(deletedExpensesProvider.notifier).addExpenses(deletedExps);
    
    _save();
  }

  /// Puts expenses back from the Recycle Bin without the title/amount/date
  /// de-duplication used by [addExpense].
  Future<void> restoreExpenses(List<Expense> expenses) async {
    await _initFuture;
    final existingIds = state.map((e) => e.id).toSet();
    final toAdd = expenses.where((e) => !existingIds.contains(e.id)).map((e) => e.copyWith(deletedAt: null)).toList();
    if (toAdd.isEmpty) return;
    state = [...state, ...toAdd];
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
    newName = newName.trim();
    if (oldName == 'All' || newName.isEmpty || newName == 'All' || newName == oldName) return;
    if (state.contains(newName)) return; // would create a duplicate
    state = [for (final c in state) if (c == oldName) newName else c];

    await ref.read(expensesProvider.notifier).renameCategoryInExpenses(oldName, newName);
    await ref.read(expenseBudgetProvider.notifier).renameCategory(oldName, newName);
    if (ref.read(selectedExpenseCategoryProvider) == oldName) {
      ref.read(selectedExpenseCategoryProvider.notifier).state = newName;
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
    newName = newName.trim();
    if (oldName == 'General') return; // Don't rename General
    if (newName.isEmpty || newName == 'All' || newName == oldName) return;
    if (state.contains(newName)) return; // Would create a duplicate category
    state = [for (final c in state) if (c == oldName) newName else c];

    // Update all notes in this category (single save)
    await ref.read(notesProvider.notifier).renameCategoryInNotes(oldName, newName);

    if (ref.read(selectedCategoryProvider) == oldName) {
      ref.read(selectedCategoryProvider.notifier).state = newName;
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
    final now = DateTime.now();
    final existingIds = state.map((n) => n.id).toSet();
    final newNotes = notes
        .where((n) => !existingIds.contains(n.id))
        .map((n) => n.deletedAt == null ? n.copyWith(deletedAt: now) : n)
        .toList();
    state = [...state, ...newNotes];
    _save();
  }

  Future<void> restoreNote(String id) async {
    await _initFuture;
    final idx = state.indexWhere((n) => n.id == id);
    if (idx == -1) return; // already restored or permanently deleted
    final note = state[idx];
    // Auto-create category if missing
    await ref.read(categoriesProvider.notifier).addCategory(note.category);
    await ref.read(notesProvider.notifier).restoreNotes([note]);
    state = state.where((n) => n.id != id).toList();
    _save();
  }

  Future<void> restoreAll() async {
    await _initFuture;
    final allNotes = List<Note>.from(state);
    for (final cat in allNotes.map((n) => n.category).toSet()) {
      await ref.read(categoriesProvider.notifier).addCategory(cat);
    }
    await ref.read(notesProvider.notifier).restoreNotes(allNotes);
    state = [];
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
    final now = DateTime.now();
    final existingIds = state.map((e) => e.id).toSet();
    state = [
      ...state,
      ...expenses
          .where((e) => !existingIds.contains(e.id))
          .map((e) => e.deletedAt == null ? e.copyWith(deletedAt: now) : e),
    ];
    _save();
  }

  Future<void> restoreExpense(String id) async {
    await _initFuture;
    final exp = state.firstWhere((e) => e.id == id);
    await ref.read(expensesProvider.notifier).restoreExpenses([exp]);
    state = state.where((e) => e.id != id).toList();
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
    await ref.read(expensesProvider.notifier).restoreExpenses(allExps);
    state = [];
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

  /// Adds [link]. Returns false if the same URL is already saved.
  Future<bool> addLink(LinkItem link) async {
    await _initFuture;
    if (state.any((l) => l.id == link.id || l.url == link.url)) return false;
    state = [...state, link];
    _save();
    return true;
  }

  /// Moves every link in [oldName] to [newName] with a single save.
  Future<void> renameCategoryInLinks(String oldName, String newName) async {
    await _initFuture;
    if (!state.any((l) => l.category == oldName)) return;
    state = [for (final l in state) if (l.category == oldName) l.copyWith(category: newName) else l];
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
    final now = DateTime.now();
    final deletedLinks = state.where((l) => ids.contains(l.id)).map((l) => l.copyWith(deletedAt: now)).toList();
    state = state.where((l) => !ids.contains(l.id)).toList();
    
    // Add to recycle bin
    ref.read(deletedLinksProvider.notifier).addLinks(deletedLinks);
    
    _save();
  }

  /// Puts links back from the Recycle Bin without the URL de-duplication used by [addLink].
  Future<void> restoreLinks(List<LinkItem> links) async {
    await _initFuture;
    final existingIds = state.map((l) => l.id).toSet();
    final toAdd = links.where((l) => !existingIds.contains(l.id)).map((l) => l.copyWith(deletedAt: null)).toList();
    if (toAdd.isEmpty) return;
    state = [...state, ...toAdd];
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
    final now = DateTime.now();
    final existingIds = state.map((l) => l.id).toSet();
    state = [
      ...state,
      ...links
          .where((l) => !existingIds.contains(l.id))
          .map((l) => l.deletedAt == null ? l.copyWith(deletedAt: now) : l),
    ];
    _save();
  }

  Future<void> restoreLink(String id) async {
    await _initFuture;
    final link = state.firstWhere((l) => l.id == id);
    await ref.read(linkItemsProvider.notifier).restoreLinks([link]);
    state = state.where((l) => l.id != id).toList();
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
    await ref.read(linkItemsProvider.notifier).restoreLinks(allLinks);
    state = [];
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
    newName = newName.trim();
    if (oldName == 'All' || newName.isEmpty || newName == 'All' || newName == 'General' || newName == oldName) return;
    if (state.contains(newName)) return; // would create a duplicate
    state = [for (final c in state) if (c == oldName) newName else c];

    await ref.read(linkItemsProvider.notifier).renameCategoryInLinks(oldName, newName);
    if (ref.read(selectedLinkCategoryProvider) == oldName) {
      ref.read(selectedLinkCategoryProvider.notifier).state = newName;
    }
    _save();
  }

  Future<void> deleteCategory(String category) async {
    await deleteCategories([category]);
  }

  Future<void> deleteCategories(List<String> categoriesToDelete) async {
    await _initFuture;
    final toDelete = categoriesToDelete.where((c) => c != 'All').toList();
    if (toDelete.isEmpty) return;
    state = state.where((c) => !toDelete.contains(c)).toList();

    // Links in deleted categories stay visible under "All" (single save).
    final linksNotifier = ref.read(linkItemsProvider.notifier);
    for (final cat in toDelete) {
      await linksNotifier.renameCategoryInLinks(cat, 'All');
    }
    if (toDelete.contains(ref.read(selectedLinkCategoryProvider))) {
      ref.read(selectedLinkCategoryProvider.notifier).state = 'All';
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

  /// Puts a deleted table back (used by Undo). No-op if it already exists.
  Future<void> restoreTable(VaultTable table) async {
    await _initFuture;
    if (state.any((t) => t.id == table.id)) return;
    state = [...state, table];
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

// Calls trySilentSignIn() on first build so any previously signed-in session
// is restored automatically — no button click required on every app open.
final googleDriveServiceProvider = Provider((ref) {
  final service = GoogleDriveService();
  // Silently restore the last session in the background.
  // If the user was signed in before, this re-authenticates them with no UI.
  service.trySilentSignIn();
  return service;
});

final googleUserProvider = StreamProvider<GoogleSignInAccount?>((ref) {
  final service = ref.watch(googleDriveServiceProvider);
  // Create a StreamController that immediately emits the current user
  // (resolved by trySilentSignIn on startup), then forwards all future changes.
  // This ensures the UI reflects the signed-in state as soon as possible
  // instead of waiting for the next change event.
  final controller = StreamController<GoogleSignInAccount?>.broadcast();

  // Emit the current user right away (may be null if silent sign-in not done yet)
  Future.microtask(() async {
    if (!controller.isClosed) {
      controller.add(service.currentUser);
    }
  });

  // Forward all subsequent user change events
  final sub = service.onCurrentUserChanged.listen(
    (user) { if (!controller.isClosed) controller.add(user); },
    onError: (e) { if (!controller.isClosed) controller.addError(e); },
  );

  ref.onDispose(() {
    sub.cancel();
    controller.close();
  });

  return controller.stream;
});

/// Every vault file that holds user data. Backup and restore both use this list
/// so they can never drift apart (previously reminders, recycle bin, service
/// history and monthly reports were silently left out of one or the other).
const List<String> kVaultDataFiles = VaultService.dataFiles;

/// Pseudo file name for the Docs vault (Hive DB + attached images, zipped).
const String kDocsBackupKey = 'docs_data';

const String kDriveBackupFolder = 'vault_notes_backup';

enum SyncStatus { idle, syncing, success, error }

class SyncNotifier extends Notifier<SyncStatus> {
  /// Human readable details about the last sync (e.g. which items failed).
  String? lastMessage;

  @override
  SyncStatus build() => SyncStatus.idle;

  /// First line of an error, without the "Exception: " prefix, kept short so
  /// it fits in the snackbar but still says what went wrong.
  static String _shortError(Object e) {
    var text = e.toString().split('\n').first.replaceFirst(RegExp(r'^(Exception|HiveError|PlatformException):\s*'), '');
    if (text.length > 80) text = '${text.substring(0, 80)}…';
    return text;
  }

  void _finish(List<String> failed, String successMessage) {
    if (failed.isEmpty) {
      lastMessage = successMessage;
      state = SyncStatus.success;
      Future.delayed(const Duration(seconds: 3), () {
        if (state == SyncStatus.success) state = SyncStatus.idle;
      });
    } else {
      lastMessage = 'Failed: ${failed.join(', ')}';
      state = SyncStatus.error;
    }
  }

  Future<void> syncWithDrive({List<String>? selectedFiles}) async {
    state = SyncStatus.syncing;
    lastMessage = null;
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

      final filesToSync = selectedFiles ?? [...kVaultDataFiles, kDocsBackupKey];

      // Data that only lives in SharedPreferences is mirrored into the vault first.
      if (filesToSync.contains('app_settings.json')) {
        await vaultService.exportAppSettings();
      }

      final failed = <String>[];
      int uploaded = 0;
      for (final fileName in filesToSync) {
        try {
          if (fileName == kDocsBackupKey) {
            await docs_drive.GoogleDriveService().backupData();
            uploaded++;
          } else {
            final localFile = File('$vaultPath/$fileName');
            if (await localFile.exists()) {
              await driveService.uploadFile(localFile, kDriveBackupFolder);
              uploaded++;
            }
          }
        } catch (e) {
          print('Backup error for $fileName: $e');
          failed.add('$fileName (${_shortError(e)})');
        }
      }

      _finish(failed, 'Backed up $uploaded item${uploaded == 1 ? '' : 's'} to Google Drive');
    } catch (e) {
      print('Sync Error: $e');
      lastMessage = e.toString();
      state = SyncStatus.error;
    }
  }

  Future<void> downloadFromDrive() async {
    state = SyncStatus.syncing;
    lastMessage = null;
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

      // Snapshot the current local data first: a restore replaces every file,
      // and the Drive copy may be older than what is on this device.
      final snapshot = await vaultService.createLocalBackup('before_restore', keep: 20);

      final failed = <String>[];
      int restored = 0;
      for (final fileName in kVaultDataFiles) {
        // Download into a temp file first so a failed/partial download never
        // replaces a good local file.
        final localFile = File('$vaultPath/$fileName');
        final tempFile = File('$vaultPath/$fileName.download');
        try {
          final found = await driveService.downloadFile(fileName, kDriveBackupFolder, tempFile);
          if (found) {
            await tempFile.rename(localFile.path);
            restored++;
          }
        } catch (e) {
          print('Restore error for $fileName: $e');
          failed.add('$fileName (${_shortError(e)})');
          if (await tempFile.exists()) await tempFile.delete();
        }
      }

      try {
        await docs_drive.GoogleDriveService().restoreData();
        DocumentProvider.current?.reload();
        restored++;
      } catch (e) {
        // "No backups found" is not fatal: the rest of the vault is restored.
        print('Docs restore: $e');
        if (!e.toString().contains('No backups found')) failed.add('Docs (${_shortError(e)})');
      }

      // The files were replaced behind VaultService's back: drop its cache,
      // otherwise every provider below would reload the pre-restore data and the
      // next save would write it over the restored files.
      vaultService.clearCache();
      await vaultService.importAppSettings();

      ref.invalidate(notesProvider);
      ref.invalidate(categoriesProvider);
      ref.invalidate(expensesProvider);
      ref.invalidate(expenseCategoriesProvider);
      ref.invalidate(expenseBudgetProvider);
      ref.invalidate(linkItemsProvider);
      ref.invalidate(linkCategoriesProvider);
      ref.invalidate(tablesProvider);
      ref.invalidate(tableCategoriesProvider);
      ref.invalidate(remindersProvider);
      ref.invalidate(billsProvider);
      ref.invalidate(fuelEntriesProvider);
      ref.invalidate(serviceEntriesProvider);
      ref.invalidate(deletedNotesProvider);
      ref.invalidate(deletedExpensesProvider);
      ref.invalidate(deletedLinksProvider);
      ref.invalidate(groceryProvider);
      ref.invalidate(groceryHistoryProvider);
      ref.invalidate(groceryCatalogProvider);
      ref.invalidate(enabledTabsProvider);
      ref.invalidate(profilesProvider); // profiles_data.json was replaced too

      await rescheduleAllNotifications(vaultService);

      _finish(
        failed,
        'Restored $restored item${restored == 1 ? '' : 's'} from Google Drive'
        '${snapshot != null ? ' (previous data kept in ${VaultService.backupFolderName})' : ''}',
      );
    } catch (e) {
      print('Download Error: $e');
      lastMessage = e.toString();
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

/// Re-creates every bill and reminder notification from the vault files.
/// Used after a Drive restore and once at app start (bill reminders are
/// scheduled a couple of cycles ahead, so this keeps them topped up).
Future<void> rescheduleAllNotifications(VaultService vaultService, {bool askPermission = true}) async {
  try {
    final data = await vaultService.loadVaultData();
    for (final raw in (data['bills'] as List? ?? [])) {
      try {
        final bill = Bill.fromJson(Map<String, dynamic>.from(raw));
        await NotificationService().scheduleBillNotificationsFor(bill, askPermission: askPermission);
      } catch (e) {
        print('Skipping bill reminder: $e');
      }
    }
    for (final raw in (data['reminders'] as List? ?? [])) {
      try {
        final r = Reminder.fromJson(Map<String, dynamic>.from(raw));
        if (r.isDismissed) {
          await NotificationService().cancelReminderNotification(r.id);
        } else {
          await NotificationService().scheduleReminderFor(r);
        }
      } catch (e) {
        print('Skipping reminder: $e');
      }
    }
  } catch (e) {
    print('Error rescheduling notifications: $e');
  }
}



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

  /// Completes once the reminders have been loaded from the vault.
  Future<void> get ready => _initFuture ?? Future.value();

  Future<void> addReminder(Reminder reminder) async {
    await _initFuture;
    state = [...state, reminder];
    _save();
    if (!reminder.isDismissed) {
      NotificationService().scheduleReminderFor(reminder);
    }
  }

  Future<void> updateReminder(Reminder reminder) async {
    await _initFuture;
    final oldReminder = state.firstWhere((r) => r.id == reminder.id, orElse: () => reminder);
    final newlyDismissed = !oldReminder.isDismissed && reminder.isDismissed;

    Reminder finalReminder = reminder;

    if (newlyDismissed && reminder.repeatType != 'none') {
      // Jump to the next occurrence after *now* (a daily reminder missed for
      // several days must not stay overdue), keeping the original schedule.
      final anchor = reminder.referenceDate ?? oldReminder.referenceDate ?? oldReminder.dateTime;
      final after = reminder.dateTime.isAfter(DateTime.now()) ? reminder.dateTime : DateTime.now();
      finalReminder = reminder.copyWith(
        dateTime: reminderOccurrenceAfter(anchor, reminder.repeatType, after),
        isDismissed: false, // Keep it active for the next occurrence
        referenceDate: anchor,
      );
    }

    state = [
      for (final r in state)
        if (r.id == reminder.id) finalReminder else r
    ];

    if (finalReminder.isDismissed) {
      NotificationService().cancelReminderNotification(finalReminder.id);
    } else {
      NotificationService().scheduleReminderFor(finalReminder);
    }

    _save();
  }

  Future<void> deleteReminder(String id) async {
    await _initFuture;
    state = state.where((r) => r.id != id).toList();
    _save();
    NotificationService().cancelReminderNotification(id);
  }

  /// Puts back reminders removed by [deleteReminders] (used by Undo).
  Future<void> restoreReminders(List<Reminder> reminders) async {
    await _initFuture;
    final existing = state.map((r) => r.id).toSet();
    final toAdd = reminders.where((r) => !existing.contains(r.id)).toList();
    if (toAdd.isEmpty) return;
    state = [...state, ...toAdd];
    _save();
    for (final r in toAdd) {
      if (!r.isDismissed) NotificationService().scheduleReminderFor(r);
    }
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
    ref.watch(vaultPathProvider);
    _initFuture = _load();
    return [];
  }

  Future<void> _load() async {
    final data = await ref.read(vaultServiceProvider).loadVaultData();
    final List<dynamic> jsonList = data['bills'] ?? [];
    List<Bill> loadedBills = jsonList.map((e) => Bill.fromJson(e)).toList();
    
    state = loadedBills;
    refreshPaidStatus();
  }

  /// A bill only stays "paid" for the billing cycle the payment covered.
  /// Cycles follow the due date, not the calendar month, so paying a bill due
  /// on the 2nd on the 30th of the month before still counts as paid.
  void refreshPaidStatus() {
    final now = DateTime.now();
    var changed = false;
    final next = [
      for (final b in state)
        if (b.isPaid && b.paidCycle != b.currentCycle(now))
          () {
            changed = true;
            return b.copyWith(isPaid: false);
          }()
        else
          b
    ];
    if (changed) {
      state = next;
      _save();
      for (final b in next) {
        NotificationService().scheduleBillNotificationsFor(b, askPermission: false);
      }
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
    await deleteBills([id]);
  }

  /// Deletes bills and cancels their scheduled reminders, so a deleted bill
  /// never keeps notifying every month.
  Future<void> deleteBills(Iterable<String> ids) async {
    await _initFuture;
    final idSet = ids.toSet();
    state = state.where((b) => !idSet.contains(b.id)).toList();
    _save();
    for (final id in idSet) {
      await NotificationService().cancelBillNotifications(id);
    }
  }

  /// Reverts [markAsPaid]: clears the paid date and, if this month's payment
  /// was counted as an EMI, takes that count back.
  Future<void> markAsUnpaid(String id) async {
    await _initFuture;
    final now = DateTime.now();
    state = [
      for (final b in state)
        if (b.id == id)
          () {
            final cycle = b.currentCycle(now);
            final countedThisCycle = b.lastEmiPaidMonth == cycle || b.paidCycle == cycle;
            return b.copyWith(
              isPaid: false,
              lastPaidDate: null,
              paidEmis: countedThisCycle && (b.paidEmis ?? 0) > 0 ? b.paidEmis! - 1 : b.paidEmis,
              lastEmiPaidMonth: countedThisCycle ? null : b.lastEmiPaidMonth,
            );
          }()
        else b
    ];
    _save();
    final bill = state.where((b) => b.id == id).firstOrNull;
    if (bill != null) NotificationService().scheduleBillNotificationsFor(bill, askPermission: false);
  }

  Future<void> markAsPaid(String id) async {
    await _initFuture;
    final now = DateTime.now();
    state = [
      for (final b in state)
        if (b.id == id)
          () {
            final cycle = b.currentCycle(now);
            final alreadyCounted = b.lastEmiPaidMonth == cycle;
            var paid = alreadyCounted ? b.paidEmis : (b.paidEmis ?? 0) + 1;
            // Never count more EMIs than the loan has.
            if (paid != null && b.totalEmis != null && b.totalEmis! > 0 && paid > b.totalEmis!) paid = b.totalEmis;
            return b.copyWith(
              isPaid: true,
              lastPaidDate: now,
              paidEmis: paid,
              lastEmiPaidMonth: cycle,
            );
          }()
        else b
    ];
    _save();
    // No more "due in 2 days" reminders for a cycle that is already paid.
    final bill = state.where((b) => b.id == id).firstOrNull;
    if (bill != null) NotificationService().scheduleBillNotificationsFor(bill, askPermission: false);
  }

  /// Puts back bills removed by [deleteBills] (used by Undo).
  Future<void> restoreBills(List<Bill> bills) async {
    await _initFuture;
    final existing = state.map((b) => b.id).toSet();
    final toAdd = bills.where((b) => !existing.contains(b.id)).toList();
    if (toAdd.isEmpty) return;
    state = [...state, ...toAdd];
    _save();
    for (final b in toAdd) {
      await NotificationService().scheduleBillNotificationsFor(b, askPermission: false);
    }
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
  return Stream.periodic(const Duration(seconds: 15), (_) => DateTime.now());
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
    ref.watch(vaultPathProvider);
    _initFuture = _load();
    return [];
  }

  /// Completes once the fuel entries have been loaded from the vault.
  Future<void> get ready => _initFuture ?? Future.value();

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
    state = [...state, entry]..sort(_compareFuel);
    _save();
  }

  /// Date first, then odometer, so several fills on one day keep their order
  /// (Dart's sort is not stable, which could swap them and break mileage maths).
  static int _compareFuel(FuelEntry a, FuelEntry b) {
    final byDate = a.date.compareTo(b.date);
    if (byDate != 0) return byDate;
    if (!a.hasOdometer || !b.hasOdometer) return 0;
    return a.odometer.compareTo(b.odometer);
  }

  Future<void> updateEntry(FuelEntry oldEntry, FuelEntry newEntry) async {
    await _initFuture;
    final index = state.indexOf(oldEntry);
    if (index != -1) {
      final newState = [...state];
      newState[index] = newEntry;
      newState.sort(_compareFuel);
      state = newState;
      _save();
    }
  }

  Future<void> deleteEntry(FuelEntry entry) async {
    await _initFuture;
    state = state.where((e) => e != entry).toList();
    _save();
  }

  /// Puts a deleted fill back (used by Undo).
  Future<void> restoreEntry(FuelEntry entry) async {
    await _initFuture;
    if (state.contains(entry)) return;
    state = [...state, entry]..sort(_compareFuel);
    _save();
  }

  Future<void> setEntries(List<FuelEntry> entries) async {
    await _initFuture;
    state = entries;
    _save();
  }

  void _save() {
    ref.read(vaultServiceProvider).saveFuelEntries(state);
    _triggerLocalSyncIndicator(ref);
  }
}

final fuelEntriesProvider = NotifierProvider<FuelEntriesNotifier, List<FuelEntry>>(FuelEntriesNotifier.new);

class ServiceEntriesNotifier extends Notifier<List<ServiceEntry>> {
  Future<void>? _initFuture;

  @override
  List<ServiceEntry> build() {
    ref.watch(vaultPathProvider);
    _initFuture = _load();
    return [];
  }

  Future<void> _load() async {
    final data = await ref.read(vaultServiceProvider).loadVaultData();
    final list = data['serviceEntries'] as List? ?? [];
    state = list.map((e) => ServiceEntry.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<void> refresh() async {
    await _load();
  }

  Future<void> addEntry(ServiceEntry entry) async {
    await _initFuture;
    state = [...state, entry]..sort((a, b) => a.date.compareTo(b.date));
    _save();
  }

  Future<void> updateEntry(ServiceEntry updated) async {
    await _initFuture;
    state = [
      for (final e in state)
        if (e.id == updated.id) updated else e
    ]..sort((a, b) => a.date.compareTo(b.date));
    _save();
  }

  Future<void> deleteEntry(String id) async {
    await _initFuture;
    state = state.where((e) => e.id != id).toList();
    _save();
  }

  /// Puts a deleted service entry back (used by Undo).
  Future<void> restoreEntry(ServiceEntry entry) async {
    await _initFuture;
    if (state.any((e) => e.id == entry.id)) return;
    state = [...state, entry]..sort((a, b) => a.date.compareTo(b.date));
    _save();
  }

  void _save() {
    ref.read(vaultServiceProvider).saveServiceEntries(state);
    _triggerLocalSyncIndicator(ref);
  }

  Future<void> setEntries(List<ServiceEntry> entries) async {
    await _initFuture;
    state = entries;
    _save();
  }
}

final serviceEntriesProvider = NotifierProvider<ServiceEntriesNotifier, List<ServiceEntry>>(ServiceEntriesNotifier.new);



class GroceryNotifier extends Notifier<List<GroceryItem>> {
  Future<void>? _initFuture;

  @override
  List<GroceryItem> build() {
    _initFuture = _loadItems();
    return [];
  }

  Future<void> _loadItems() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getStringList('grocery_items') ?? [];
    final items = <GroceryItem>[];
    var migrated = false;
    for (final raw in data) {
      try {
        final map = Map<String, dynamic>.from(jsonDecode(raw));
        if (!map.containsKey('quantity')) migrated = true;
        items.add(GroceryItem.fromJson(map));
      } catch (e) {
        print('Skipping unreadable grocery item: $e');
      }
    }
    state = items;
    // Old "Rice (2 kg)" names were split into fields; store the new format once.
    if (migrated) await _saveItems();
  }

  Future<void> _saveItems() async {
    final prefs = await SharedPreferences.getInstance();
    final data = state.map((e) => jsonEncode(e.toJson())).toList();
    await prefs.setStringList('grocery_items', data);
    // The list lives in SharedPreferences; mirror it into the vault so local
    // folder sync and Drive backups always include the latest list.
    await ref.read(vaultServiceProvider).exportAppSettings();
  }

  static String _key(String name) => name.trim().toLowerCase();

  /// Adds an item. If it is already on the list it is not duplicated: an item
  /// already bought is moved back to "to buy" (with the new quantity, if given).
  Future<GroceryAddResult> addItem(
    String name, {
    String quantity = '',
    String unit = '',
    String category = '',
    String localName = '',
  }) async {
    await _initFuture;
    final trimmed = name.trim();
    if (trimmed.isEmpty) return GroceryAddResult.ignored;
    final existing = state.where((i) => _key(i.name) == _key(trimmed)).firstOrNull;
    if (existing != null) {
      if (!existing.isPurchased) return GroceryAddResult.alreadyOnList;
      // Comes back to the top of the list, like a newly added item.
      state = [
        existing.copyWith(
          isPurchased: false,
          purchasedAt: null,
          price: null,
          quantity: quantity.isNotEmpty ? quantity : null,
          unit: unit.isNotEmpty ? unit : null,
        ),
        for (final i in state)
          if (i.id != existing.id) i,
      ];
      await _saveItems();
      return GroceryAddResult.movedBack;
    }
    // Newest first, so what was just added is at the top of the list.
    state = [
      GroceryItem(name: trimmed, quantity: quantity, unit: unit, category: category, localName: localName),
      ...state,
    ];
    await _saveItems();
    return GroceryAddResult.added;
  }

  Future<void> updateItem(GroceryItem updated) async {
    await _initFuture;
    state = [for (final i in state) if (i.id == updated.id) updated else i];
    await _saveItems();
  }

  Future<void> toggleItem(String id, {double? price}) async {
    await _initFuture;
    GroceryItem? bought;
    state = [
      for (final item in state)
        if (item.id == id)
          () {
            final next = item.copyWith(
              isPurchased: !item.isPurchased,
              purchasedAt: item.isPurchased ? null : DateTime.now(),
              price: item.isPurchased ? null : price,
            );
            if (next.isPurchased) bought = next;
            return next;
          }()
        else
          item
    ];
    await _saveItems();
    final b = bought;
    if (b != null) await ref.read(groceryHistoryProvider.notifier).record(b);
  }

  Future<void> editItem(String id, String newName) async {
    await _initFuture;
    if (newName.trim().isEmpty) return;
    state = [
      for (final item in state)
        if (item.id == id) item.copyWith(name: newName.trim()) else item
    ];
    await _saveItems();
  }

  Future<void> deleteItem(String id) async {
    await _initFuture;
    state = state.where((item) => item.id != id).toList();
    await _saveItems();
  }

  Future<void> clearPurchased() async {
    await _initFuture;
    state = state.where((item) => !item.isPurchased).toList();
    await _saveItems();
  }

  /// "Shop again": every bought item goes back to the to-buy list.
  Future<void> uncheckAll() async {
    await _initFuture;
    state = [for (final i in state) i.isPurchased ? i.copyWith(isPurchased: false, purchasedAt: null, price: null) : i];
    await _saveItems();
  }

  Future<void> clearToBuy() async {
    await _initFuture;
    state = state.where((item) => item.isPurchased).toList();
    await _saveItems();
  }

  Future<void> clearAll() async {
    await _initFuture;
    state = [];
    await _saveItems();
  }

  Future<void> deleteMultiple(Set<String> ids) async {
    await _initFuture;
    state = state.where((item) => !ids.contains(item.id)).toList();
    await _saveItems();
  }

  /// Puts back items removed by a delete/clear (used by Undo), in their old order.
  Future<void> restoreItems(List<GroceryItem> items) async {
    await _initFuture;
    final existing = state.map((i) => i.id).toSet();
    final toAdd = items.where((i) => !existing.contains(i.id)).toList();
    if (toAdd.isEmpty) return;
    state = [...state, ...toAdd]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    await _saveItems();
  }
}

enum GroceryAddResult { added, alreadyOnList, movedBack, ignored }

final groceryProvider = NotifierProvider<GroceryNotifier, List<GroceryItem>>(GroceryNotifier.new);

/// What has been bought before, for the "Buy again" suggestions.
class GroceryHistoryEntry {
  final String name;
  final String quantity;
  final String unit;
  final String category;
  final String localName;
  final int count;
  final DateTime lastBought;

  const GroceryHistoryEntry({
    required this.name,
    required this.quantity,
    required this.unit,
    required this.category,
    required this.localName,
    required this.count,
    required this.lastBought,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'quantity': quantity,
        'unit': unit,
        'category': category,
        'localName': localName,
        'count': count,
        'lastBought': lastBought.toIso8601String(),
      };

  factory GroceryHistoryEntry.fromJson(Map<String, dynamic> j) => GroceryHistoryEntry(
        name: j['name']?.toString() ?? '',
        quantity: j['quantity']?.toString() ?? '',
        unit: j['unit']?.toString() ?? '',
        category: j['category']?.toString() ?? '',
        localName: j['localName']?.toString() ?? '',
        count: (j['count'] as num?)?.toInt() ?? 1,
        lastBought: DateTime.tryParse(j['lastBought']?.toString() ?? '') ?? DateTime.now(),
      );
}

class GroceryHistoryNotifier extends Notifier<List<GroceryHistoryEntry>> {
  static const _prefsKey = 'grocery_history';
  static const _maxEntries = 200;

  @override
  List<GroceryHistoryEntry> build() {
    _load();
    return [];
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return;
    try {
      state = (jsonDecode(raw) as List).map((e) => GroceryHistoryEntry.fromJson(Map<String, dynamic>.from(e))).toList();
    } catch (e) {
      print('Unreadable grocery history: $e');
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(state.map((h) => h.toJson()).toList()));
    await ref.read(vaultServiceProvider).exportAppSettings();
  }

  Future<void> record(GroceryItem item) async {
    final key = item.name.trim().toLowerCase();
    final old = state.where((h) => h.name.toLowerCase() == key).firstOrNull;
    final entry = GroceryHistoryEntry(
      name: item.name.trim(),
      quantity: item.quantity,
      unit: item.unit,
      category: item.category,
      localName: item.localName,
      count: (old?.count ?? 0) + 1,
      lastBought: DateTime.now(),
    );
    final next = [entry, ...state.where((h) => h.name.toLowerCase() != key)];
    if (next.length > _maxEntries) next.removeRange(_maxEntries, next.length);
    state = next;
    await _persist();
  }

  Future<void> forget(String name) async {
    final key = name.trim().toLowerCase();
    state = state.where((h) => h.name.toLowerCase() != key).toList();
    await _persist();
  }
}

final groceryHistoryProvider = NotifierProvider<GroceryHistoryNotifier, List<GroceryHistoryEntry>>(GroceryHistoryNotifier.new);

/// "Buy again": most often / most recently bought items not already on the to-buy list.
final groceryBuyAgainProvider = Provider<List<GroceryHistoryEntry>>((ref) {
  final history = ref.watch(groceryHistoryProvider);
  final toBuy = ref.watch(groceryProvider).where((i) => !i.isPurchased).map((i) => i.name.toLowerCase()).toSet();
  final candidates = history.where((h) => !toBuy.contains(h.name.toLowerCase())).toList();
  final now = DateTime.now();
  double score(GroceryHistoryEntry h) => h.count - now.difference(h.lastBought).inDays / 30.0;
  candidates.sort((a, b) => score(b).compareTo(score(a)));
  return candidates.take(15).toList();
});

// Grocery Master Catalog Provider
/// Bundled catalog + the user's changes on top of it:
/// - `user_grocery_catalog`  items the user saved (ids start with "U")
/// - `grocery_catalog_edits` built-in items the user edited (id → item json)
/// - `grocery_catalog_hidden` built-in items the user deleted (ids)
/// "Reset" clears all three, giving back the original catalog.
class GroceryMasterCatalogNotifier extends AsyncNotifier<List<dynamic>> {
  static const _userKey = 'user_grocery_catalog';
  static const _editsKey = 'grocery_catalog_edits';
  static const _hiddenKey = 'grocery_catalog_hidden';

  List<dynamic> _base = const [];

  @override
  Future<List<dynamic>> build() async {
    if (_base.isEmpty) {
      try {
        final String response = await rootBundle.loadString('assets/indian_grocery_master_v2_multilingual_search.json');
        _base = List<dynamic>.from(json.decode(response)['items']);
      } catch (e) {
        print('Error loading catalog: $e');
      }
    }
    final prefs = await SharedPreferences.getInstance();
    final hidden = _readList(prefs, _hiddenKey).map((e) => e.toString()).toSet();
    final edits = _readMap(prefs, _editsKey);
    return [
      for (final item in _base)
        if (item is Map && !hidden.contains(item['id']?.toString())) edits[item['id']?.toString()] ?? item,
      ..._readList(prefs, _userKey),
    ];
  }

  static List<dynamic> _readList(SharedPreferences prefs, String key) {
    try {
      final raw = prefs.getString(key);
      if (raw != null) return List<dynamic>.from(json.decode(raw));
    } catch (_) {}
    return [];
  }

  static Map<String, dynamic> _readMap(SharedPreferences prefs, String key) {
    try {
      final raw = prefs.getString(key);
      if (raw != null) return Map<String, dynamic>.from(json.decode(raw));
    } catch (_) {}
    return {};
  }

  static bool isUserItem(String id) => id.startsWith('U');

  Future<void> _saved() async {
    ref.invalidateSelf();
    await ref.read(vaultServiceProvider).exportAppSettings();
  }

  static List<String> _keywords(String text) =>
      text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  Future<void> addCustomItem(String englishName, String localName, String searchKeywords,
      {String category = 'Other', String unit = ''}) async {
    final prefs = await SharedPreferences.getInstance();
    final userItems = _readList(prefs, _userKey);
    userItems.add({
      "id": "U${DateTime.now().millisecondsSinceEpoch}",
      "names": {"en": englishName, "local": localName},
      "search_terms": {"en": _keywords(searchKeywords)},
      "category": category,
      if (unit.isNotEmpty) "default_unit": unit,
      if (unit.isNotEmpty) "common_units": [unit],
    });
    await prefs.setString(_userKey, json.encode(userItems));
    await _saved();
  }

  /// Changes a product's name, local name, extra search words, category or unit.
  /// The local name is only replaced when it was changed, so built-in
  /// Telugu/Hindi names stay as they are otherwise.
  Future<void> editItem(
    String id, {
    required String englishName,
    required String localName,
    required String searchKeywords,
    required String category,
    required String unit,
    required String oldLocalName,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final current = (state.value ?? const []).whereType<Map>().where((m) => m['id']?.toString() == id).firstOrNull;
    if (current == null) return;
    final item = Map<String, dynamic>.from(json.decode(json.encode(current)));
    final names = Map<String, dynamic>.from((item['names'] as Map?) ?? {});
    names['en'] = englishName;
    if (localName != oldLocalName) {
      names
        ..remove('te')
        ..remove('hi')
        ..['local'] = localName;
    }
    item['names'] = names;
    final terms = Map<String, dynamic>.from((item['search_terms'] as Map?) ?? {});
    final extra = _keywords(searchKeywords);
    if (extra.isNotEmpty) terms['user'] = extra; else terms.remove('user');
    item['search_terms'] = terms;
    item['category'] = category;
    if (unit.isNotEmpty) {
      item['default_unit'] = unit;
      final units = List<dynamic>.from((item['common_units'] as List?) ?? []);
      if (!units.contains(unit)) units.insert(0, unit);
      item['common_units'] = units;
    }

    if (isUserItem(id)) {
      final userItems = _readList(prefs, _userKey);
      await prefs.setString(
          _userKey, json.encode([for (final u in userItems) (u is Map && u['id']?.toString() == id) ? item : u]));
    } else {
      final edits = _readMap(prefs, _editsKey)..[id] = item;
      await prefs.setString(_editsKey, json.encode(edits));
    }
    await _saved();
  }

  /// Removes a product from the catalog (saved items are deleted, built-in ones hidden).
  Future<void> deleteItem(String id) async {
    final prefs = await SharedPreferences.getInstance();
    if (isUserItem(id)) {
      final userItems = _readList(prefs, _userKey)..removeWhere((u) => u is Map && u['id']?.toString() == id);
      await prefs.setString(_userKey, json.encode(userItems));
    } else {
      final hidden = _readList(prefs, _hiddenKey).map((e) => e.toString()).toSet()..add(id);
      await prefs.setString(_hiddenKey, json.encode(hidden.toList()));
      final edits = _readMap(prefs, _editsKey)..remove(id);
      await prefs.setString(_editsKey, json.encode(edits));
    }
    await _saved();
  }

  /// Back to the original catalog: drops saved items, edits and deletions.
  /// Written as empty values (not removed) so a sync to other devices resets them too.
  Future<void> resetCatalog() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey, '[]');
    await prefs.setString(_editsKey, '{}');
    await prefs.setString(_hiddenKey, '[]');
    await _saved();
  }
}

final groceryCatalogProvider = AsyncNotifierProvider<GroceryMasterCatalogNotifier, List<dynamic>>(GroceryMasterCatalogNotifier.new);

/// The catalog as typed entries (empty while it is still loading).
final groceryCatalogItemsProvider = Provider<List<CatalogItem>>((ref) {
  final raw = ref.watch(groceryCatalogProvider).value ?? const [];
  final items = <CatalogItem>[];
  for (final e in raw) {
    if (e is Map) {
      try {
        final item = CatalogItem.fromJson(e);
        if (item.name.isNotEmpty) items.add(item);
      } catch (_) {}
    }
  }
  return items;
});


class IsSelectionModeNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void setState(bool value) => state = value;
}
final isSelectionModeProvider = NotifierProvider<IsSelectionModeNotifier, bool>(IsSelectionModeNotifier.new);

class GrocerySelectBoughtNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool value) => state = value;
}

/// Which Grocery tab selection mode was started on (true = Bought), so
/// "select all" only picks the items that tab shows.
final grocerySelectBoughtProvider = NotifierProvider<GrocerySelectBoughtNotifier, bool>(GrocerySelectBoughtNotifier.new);

class SelectedGroceryNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => {};
  void toggle(String id) {
    if (state.contains(id)) {
      state = {...state}..remove(id);
    } else {
      state = {...state, id};
    }
  }
  void selectAll(Set<String> ids) => state = ids;
  void clear() => state = {};
}
final selectedGroceryProvider = NotifierProvider<SelectedGroceryNotifier, Set<String>>(SelectedGroceryNotifier.new);
