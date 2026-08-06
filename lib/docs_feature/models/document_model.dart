import 'package:hive/hive.dart';

class DocumentModel {
  String id;
  String title;
  String category;
  DateTime? issueDate;
  DateTime? expiryDate;
  List<String> imagePaths;
  bool isSynced;
  String personName;
  String notes;

  DocumentModel({
    required this.id,
    required this.title,
    required this.category,
    this.issueDate,
    this.expiryDate,
    this.imagePaths = const [],
    this.isSynced = false,
    this.personName = 'Me',
    this.notes = '',
  });
}

class DocumentModelAdapter extends TypeAdapter<DocumentModel> {
  @override
  final int typeId = 0;

  @override
  DocumentModel read(BinaryReader reader) {
    String id = reader.readString();
    String title = reader.readString();
    String category = reader.readString();
    DateTime? issueDate = reader.readBool() ? DateTime.fromMillisecondsSinceEpoch(reader.readInt()) : null;
    DateTime? expiryDate = reader.readBool() ? DateTime.fromMillisecondsSinceEpoch(reader.readInt()) : null;
    List<String> imagePaths = reader.readStringList();
    bool isSynced = reader.readBool();
    String personName = reader.readString();
    
    String notes = '';
    try {
      if (reader.availableBytes > 0) {
        notes = reader.readString();
      }
    } catch (_) {}

    return DocumentModel(
      id: id,
      title: title,
      category: category,
      issueDate: issueDate,
      expiryDate: expiryDate,
      imagePaths: imagePaths,
      isSynced: isSynced,
      personName: personName,
      notes: notes,
    );
  }

  @override
  void write(BinaryWriter writer, DocumentModel obj) {
    writer.writeString(obj.id);
    writer.writeString(obj.title);
    writer.writeString(obj.category);
    
    writer.writeBool(obj.issueDate != null);
    if (obj.issueDate != null) {
      writer.writeInt(obj.issueDate!.millisecondsSinceEpoch);
    }
    
    writer.writeBool(obj.expiryDate != null);
    if (obj.expiryDate != null) {
      writer.writeInt(obj.expiryDate!.millisecondsSinceEpoch);
    }
    
    writer.writeStringList(obj.imagePaths);
    writer.writeBool(obj.isSynced);
    writer.writeString(obj.personName);
    writer.writeString(obj.notes);
  }
}
