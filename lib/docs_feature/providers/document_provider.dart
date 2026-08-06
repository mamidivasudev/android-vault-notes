import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/document_model.dart';
import '../services/local_storage_service.dart';

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

  DocumentProvider() {
    loadDocuments();
    loadCategories();
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

  Future<void> editCategory(String oldName, String newName) async {
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
  }

  Future<void> deleteCategory(String category) async {
    _categories.remove(category);
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
    await _storageService.deleteDocument(id);
    _documents.removeWhere((d) => d.id == id);
    notifyListeners();
  }
}
