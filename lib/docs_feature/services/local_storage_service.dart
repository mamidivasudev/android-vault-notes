import 'package:hive_flutter/hive_flutter.dart';
import '../models/document_model.dart';

class LocalStorageService {
  static const String boxName = 'documentsBoxV3';

  static Future<void> init() async {
    await Hive.initFlutter();
    Hive.registerAdapter(DocumentModelAdapter());
    await Hive.openBox<DocumentModel>(boxName);
  }

  Future<void> addDocument(DocumentModel document) async {
    final box = Hive.box<DocumentModel>(boxName);
    await box.put(document.id, document);
  }

  Future<void> updateDocument(DocumentModel document) async {
    final box = Hive.box<DocumentModel>(boxName);
    await box.put(document.id, document);
  }

  List<DocumentModel> getAllDocuments() {
    final box = Hive.box<DocumentModel>(boxName);
    return box.values.toList();
  }

  Future<void> deleteDocument(String id) async {
    final box = Hive.box<DocumentModel>(boxName);
    await box.delete(id);
  }
}
