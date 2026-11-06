import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/document_model.dart';
import '../services/local_storage_service.dart';
import '../services/notification_service.dart';

class DocumentProvider with ChangeNotifier {
  final LocalStorageService _storageService = LocalStorageService();
  List<DocumentModel> _documents = [];

  List<String> _categories = [
    'ID / Passport',
    'Medical',
    'Financial',
    'Vehicle',
    'Education',
    'Insurance',
    'Other',
  ];

  List<DocumentModel> get documents => _documents;
  List<String> get categories => _categories;

  /// The live instance, so code outside the widget tree (Drive restore) can reload it.
  static DocumentProvider? current;

  DocumentProvider() {
    current = this;
    loadDocuments();
    loadCategories();
  }

  /// Re-reads documents and categories, e.g. after a Drive restore replaced them.
  Future<void> reload() async {
    await LocalStorageService.reopen();
    loadDocuments();
    await loadCategories();
  }

  void loadDocuments() {
    _documents = _storageService.getAllDocuments();
    notifyListeners();
  }

  Future<void> loadCategories() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('custom_categories');
    if (saved != null && saved.isNotEmpty) {
      _categories = saved;
    }
    notifyListeners();
  }

  Future<void> addCategory(String category) async {
    if (!_categories.contains(category)) {
      _categories.add(category);
      await _saveCategories();
      notifyListeners();
    }
  }

  /// Renames a category. Returns false if [newName] is empty or already used.
  Future<bool> editCategory(String oldName, String newName) async {
    newName = newName.trim();
    if (newName.isEmpty || (newName != oldName && _categories.contains(newName))) return false;
    final index = _categories.indexOf(oldName);
    if (index != -1) {
      _categories[index] = newName;
      await _saveCategories();
      
      // Update all documents that had this category
      for (var doc in _documents) {
        if (doc.category == oldName) {
          doc.category = newName;
          await updateDocument(doc);
        }
      }
      notifyListeners();
    }
    return true;
  }

  /// Removes a category. Its documents move to "Other" (created if needed)
  /// so they never end up in a category that no screen shows.
  Future<void> deleteCategory(String category) async {
    _categories.remove(category);
    final orphans = _documents.where((d) => d.category == category).toList();
    if (orphans.isNotEmpty) {
      const fallback = 'Other';
      if (!_categories.contains(fallback)) _categories.add(fallback);
      for (final doc in orphans) {
        doc.category = fallback;
        await updateDocument(doc);
      }
    }
    await _saveCategories();
    notifyListeners();
  }

  Future<void> resetCategories() async {
    _categories = [
      'ID / Passport',
      'Medical',
      'Financial',
      'Vehicle',
      'Education',
      'Insurance',
      'Other',
    ];
    await _saveCategories();
    notifyListeners();
  }

  Future<void> _saveCategories() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('custom_categories', _categories);
  }

  Future<void> addDocument(DocumentModel doc) async {
    await _storageService.addDocument(doc);
    _documents.add(doc);
    notifyListeners();
  }

  Future<void> updateDocument(DocumentModel doc) async {
    await _storageService.updateDocument(doc);
    final index = _documents.indexWhere((d) => d.id == doc.id);
    if (index != -1) {
      _documents[index] = doc;
      notifyListeners();
    }
  }

  Future<void> deleteDocument(String id) async {
    final index = _documents.indexWhere((d) => d.id == id);
    final doc = index != -1 ? _documents[index] : null;
    await _storageService.deleteDocument(id);
    _documents.removeWhere((d) => d.id == id);
    notifyListeners();

    // Clean up what the document owned: its expiry alerts and attached files.
    await NotificationService().cancelReminders(id);
    if (doc != null) {
      for (final path in doc.imagePaths) {
        try {
          final file = File(path);
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
    }
  }
}
