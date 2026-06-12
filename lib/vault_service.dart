import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:crypto/crypto.dart';
import 'dart:typed_data';

class VaultService {
  static const String _vaultPathKey = 'vault_path';
  Map<String, dynamic>? _cachedData;

  Future<String?> getVaultPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_vaultPathKey);
  }

  Future<void> setVaultPath(String path) async {
    _cachedData = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_vaultPathKey, path);
  }
  
  static final Map<String, Future<void>> _locks = {};

  Future<T> _synchronized<T>(String key, Future<T> Function() action) async {
    final previous = _locks[key] ?? Future.value();
    final completer = Completer<void>();
    _locks[key] = completer.future;
    
    try {
      await previous;
    } catch (_) {}

    try {
      return await action();
    } finally {
      completer.complete();
    }
  }

  Future<void> _atomicWrite(File file, String content) async {
    final tempFile = File('${file.path}.tmp');
    await tempFile.writeAsString(content);
    await tempFile.rename(file.path);
  }

  String _encryptData(String plainText, String passcode) {
    if (passcode.isEmpty) passcode = 'default_vault_key'; // Fallback
    try {
      final keyBytes = sha256.convert(utf8.encode(passcode)).bytes;
      final key = encrypt.Key(Uint8List.fromList(keyBytes));
      final iv = encrypt.IV.fromSecureRandom(16);
      final encrypter = encrypt.Encrypter(encrypt.AES(key));
      final encrypted = encrypter.encrypt(plainText, iv: iv);
      return '${iv.base64}:${encrypted.base64}';
    } catch (e) {
      print('Encryption error: $e');
      return plainText;
    }
  }

  String _decryptData(String cipherText, String passcode) {
    if (passcode.isEmpty) passcode = 'default_vault_key'; // Fallback
    try {
      if (!cipherText.contains(':')) return cipherText; // Unencrypted JSON
      final parts = cipherText.split(':');
      if (parts.length != 2) return cipherText;
      
      final keyBytes = sha256.convert(utf8.encode(passcode)).bytes;
      final key = encrypt.Key(Uint8List.fromList(keyBytes));
      final iv = encrypt.IV.fromBase64(parts[0]);
      final encrypter = encrypt.Encrypter(encrypt.AES(key));
      return encrypter.decrypt64(parts[1], iv: iv);
    } catch (e) {
      print('Decryption error: $e');
      return cipherText;
    }
  }

  Future<Map<String, dynamic>> loadVaultData() async {
    if (_cachedData != null) return _cachedData!;
    return _synchronized('all', () async {
      if (_cachedData != null) return _cachedData!;
      final path = await getVaultPath();
      if (path == null) return {'notes': [], 'expenses': [], 'links': [], 'tables': [], 'reminders': [], 'categories': ['General'], 'expenseCategories': ['All'], 'linkCategories': [], 'tableCategories': ['General']};

      final notesFile = File('$path/notes_data.json');
      final expensesFile = File('$path/expenses_data.json');
      final linksFile = File('$path/links_data.json');
      final tablesFile = File('$path/tables_data.json');
      final cardsFile = File('$path/cards_data.json');
      final remindersFile = File('$path/reminders_data.json');
      final billsFile = File('$path/bills_data.json');
      
      Map<String, dynamic> combinedData = {
        'notes': [],
        'expenses': [],
        'links': [],
        'tables': [],
        'cards': [],
        'reminders': [],
        'bills': [],
        'monthlyReports': [],
        'categories': ['General'],
        'expenseCategories': ['All'],
        'linkCategories': [],
        'tableCategories': ['General'],
      };

      // Load Notes
      if (await notesFile.exists()) {
        try {
          final content = await notesFile.readAsString();
          final data = json.decode(content);
          combinedData['notes'] = data['notes'] ?? [];
          combinedData['categories'] = data['categories'] ?? ['General'];
          combinedData['expenseCategories'] = data['expenseCategories'] ?? ['All'];
          combinedData['linkCategories'] = data['linkCategories'] ?? [];
          combinedData['tableCategories'] = data['tableCategories'] ?? ['General'];
          combinedData['lastSync'] = data['lastSync'];
        } catch (e) {
          print('Error loading notes_data.json: $e');
        }
      }

      // Load Expenses
      if (await expensesFile.exists()) {
        try {
          final content = await expensesFile.readAsString();
          final data = json.decode(content);
          if (data is List) {
            combinedData['expenses'] = data;
          } else if (data is Map) {
            combinedData['expenses'] = data['expenses'] ?? [];
          }
        } catch (e) {
          print('Error loading expenses_data.json: $e');
        }
      }

      // Load Links
      if (await linksFile.exists()) {
        try {
          final content = await linksFile.readAsString();
          final data = json.decode(content);
          combinedData['links'] = data['links'] ?? [];
          if (data['linkCategories'] != null) {
            combinedData['linkCategories'] = data['linkCategories'];
          }
        } catch (e) {
          print('Error loading links_data.json: $e');
        }
      }

      // Load Tables
      if (await tablesFile.exists()) {
        try {
          final content = await tablesFile.readAsString();
          final data = json.decode(content);
          combinedData['tables'] = data['tables'] ?? [];
        } catch (e) {
          print('Error loading tables_data.json: $e');
        }
      }

      // Cards are encrypted in cards_data.json — use loadCards(passcode), not loadVaultData.
      // Load Reminders
      if (await remindersFile.exists()) {
        try {
          final content = await remindersFile.readAsString();
          final data = json.decode(content);
          combinedData['reminders'] = data['reminders'] ?? [];
        } catch (e) {
          print('Error loading reminders_data.json: $e');
        }
      }

      // Load Bills
      if (await billsFile.exists()) {
        try {
          final content = await billsFile.readAsString();
          final data = json.decode(content);
          combinedData['bills'] = data['bills'] ?? [];
        } catch (e) {
          print('Error loading bills_data.json: $e');
        }
      }

      // Load Monthly Reports
      final monthlyFile = File('$path/monthly_reports.json');
      if (await monthlyFile.exists()) {
        try {
          final content = await monthlyFile.readAsString();
          final data = json.decode(content);
          combinedData['monthlyReports'] = data['monthlyReports'] ?? [];
        } catch (e) {
          print('Error loading monthly_reports.json: $e');
        }
      }

      _cachedData = combinedData;
      return combinedData;
    });
  }

  Future<List<VaultCard>> loadCards(String passcode) async {
    return _synchronized('cards_data', () async {
      final path = await getVaultPath();
      if (path == null) return [];
      final cardsFile = File('$path/cards_data.json');
      if (!await cardsFile.exists()) return [];

      try {
        final content = await cardsFile.readAsString();
        final decrypted = _decryptData(content, passcode);
        final data = json.decode(decrypted);
        final cardsList = data['cards'] as List?;
        if (cardsList == null) return [];
        return cardsList.map((e) => VaultCard.fromJson(e)).toList();
      } catch (e) {
        print('Error loading cards_data.json: $e');
        return [];
      }
    });
  }

  Future<void> saveNotes(List<Note> notes, List<String> categories) async {
    _cachedData = null;
    await _synchronized('notes_data', () async {
      final path = await getVaultPath();
      if (path == null) return;
      final file = File('$path/notes_data.json');
      
      Map<String, dynamic> currentData = {};
      if (await file.exists()) {
        try {
          currentData = json.decode(await file.readAsString());
        } catch (e) {
          throw Exception('Failed to read notes_data.json during saveNotes (aborting to prevent data loss): $e');
        }
      }

      final data = {
        ...currentData,
        'notes': notes.map((n) => n.toJson()).toList(),
        'categories': categories,
        'lastSync': DateTime.now().toIso8601String(),
      };
      await _atomicWrite(file, json.encode(data));
    });
  }

  Future<void> saveExpenses(List<Expense> expenses) async {
    _cachedData = null;
    await _synchronized('expenses_data', () async {
      final path = await getVaultPath();
      if (path == null) return;
      final file = File('$path/expenses_data.json');
      final data = {
        'expenses': expenses.map((e) => e.toJson()).toList(),
      };
      await _atomicWrite(file, json.encode(data));
    });
  }

  Future<void> saveBills(List<Bill> bills) async {
    _cachedData = null;
    await _synchronized('bills_data', () async {
      final path = await getVaultPath();
      if (path == null) return;
      final file = File('$path/bills_data.json');
      final data = {
        'bills': bills.map((b) => b.toJson()).toList(),
      };
      await _atomicWrite(file, json.encode(data));
    });
  }

  Future<List<Map<String, dynamic>>> loadMonthlyReports() async {
    final path = await getVaultPath();
    if (path == null) return [];
    final monthlyFile = File('$path/monthly_reports.json');
    if (!await monthlyFile.exists()) return [];
    try {
      final content = await monthlyFile.readAsString();
      final data = json.decode(content);
      final list = data['monthlyReports'] as List<dynamic>? ?? [];
      return List<Map<String, dynamic>>.from(list.map((e) => Map<String, dynamic>.from(e)));
    } catch (e) {
      print('Error reading monthly_reports.json: $e');
      return [];
    }
  }

  Future<void> saveMonthlyReports(List<Map<String, dynamic>> reports) async {
    _cachedData = null;
    await _synchronized('monthly_reports', () async {
      final path = await getVaultPath();
      if (path == null) return;
      final file = File('$path/monthly_reports.json');
      final data = {'monthlyReports': reports};
      await _atomicWrite(file, json.encode(data));
    });
  }

  Future<void> addOrUpdateMonthlySnapshot(
      int year,
      int month,
      double credit,
      double loan, {
      List<Map<String, dynamic>>? creditDetails,
      List<Map<String, dynamic>>? loanDetails,
  }) async {
    final reports = await loadMonthlyReports();
    final keyExists = reports.indexWhere((r) => r['year'] == year && r['month'] == month);
    final entry = {
      'year': year,
      'month': month,
      'credit': credit,
      'loan': loan,
      if (creditDetails != null) 'creditDetails': creditDetails,
      if (loanDetails != null) 'loanDetails': loanDetails,
      'savedAt': DateTime.now().toIso8601String(),
    };
    if (keyExists >= 0) {
      reports[keyExists] = entry;
    } else {
      reports.add(entry);
    }
    await saveMonthlyReports(reports);
  }

  Future<void> saveExpenseCategories(List<String> categories) async {
    _cachedData = null;
    await _synchronized('notes_data', () async {
      final path = await getVaultPath();
      if (path == null) return;
      final file = File('$path/notes_data.json');
      
      Map<String, dynamic> currentData = {};
      if (await file.exists()) {
        try {
          currentData = json.decode(await file.readAsString());
        } catch (e) {
          throw Exception('Failed to read notes_data.json during saveExpenseCategories: $e');
        }
      }

      final data = {
        ...currentData,
        'expenseCategories': categories,
      };
      await _atomicWrite(file, json.encode(data));
    });
  }

  Future<void> saveLinks(List<LinkItem> links) async {
    _cachedData = null;
    await _synchronized('links_data', () async {
      final path = await getVaultPath();
      if (path == null) return;
      final file = File('$path/links_data.json');
      final data = {
        'links': links.map((l) => l.toJson()).toList(),
        'lastSync': DateTime.now().toIso8601String(),
      };
      await _atomicWrite(file, json.encode(data));
    });
  }

  Future<void> saveTableCategories(List<String> categories) async {
    _cachedData = null;
    await _synchronized('notes_data', () async {
      final path = await getVaultPath();
      if (path == null) return;
      final file = File('$path/notes_data.json');
      
      Map<String, dynamic> currentData = {};
      if (await file.exists()) {
        try {
          currentData = json.decode(await file.readAsString());
        } catch (e) {
          throw Exception('Failed to read notes_data.json during saveTableCategories: $e');
        }
      }

      final data = {
        ...currentData,
        'tableCategories': categories,
      };
      await _atomicWrite(file, json.encode(data));
    });
  }

  Future<void> saveTables(List<VaultTable> tables) async {
    _cachedData = null;
    await _synchronized('tables_data', () async {
      final path = await getVaultPath();
      if (path == null) return;
      final file = File('$path/tables_data.json');
      final data = {
        'tables': tables.map((t) => t.toJson()).toList(),
        'lastSync': DateTime.now().toIso8601String(),
      };
      await _atomicWrite(file, json.encode(data));
    });
  }

  Future<void> saveReminders(List<Reminder> reminders) async {
    _cachedData = null;
    await _synchronized('reminders_data', () async {
      final path = await getVaultPath();
      if (path == null) return;
      final file = File('$path/reminders_data.json');
      final data = {
        'reminders': reminders.map((r) => r.toJson()).toList(),
        'lastSync': DateTime.now().toIso8601String(),
      };
      await _atomicWrite(file, json.encode(data));
    });
  }

  Future<void> saveCards(List<VaultCard> cards, String passcode) async {
    _cachedData = null;
    await _synchronized('cards_data', () async {
      final path = await getVaultPath();
      if (path == null) return;
      final file = File('$path/cards_data.json');
      final data = {
        'cards': cards.map((c) => c.toJson()).toList(),
        'lastSync': DateTime.now().toIso8601String(),
      };
      final jsonString = json.encode(data);
      final encryptedString = _encryptData(jsonString, passcode);
      await _atomicWrite(file, encryptedString);
    });
  }

  Future<void> exportToFolders(
    String targetPath,
    List<Note> notes,
    List<String> categories,
    List<Expense> expenses,
    List<LinkItem> links,
    List<VaultTable> tables,
    List<VaultCard> cards,
    String passcode,
  ) async {
    final notesDir = Directory('$targetPath/notes_backup');
    if (!await notesDir.exists()) {
      await notesDir.create(recursive: true);
    }

    for (final cat in categories) {
      final catDir = Directory('${notesDir.path}/$cat');
      
      if (await catDir.exists()) {
        await catDir.delete(recursive: true);
      }
      await catDir.create(recursive: true);

      final catNotes = notes.where((n) => n.category == cat);
      for (final note in catNotes) {
        String safeTitle = note.title.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
        if (safeTitle.isEmpty) safeTitle = 'Untitled';
        // Add short ID to avoid collisions
        final shortId = note.id.length >= 4 ? note.id.substring(note.id.length - 4) : note.id;
        final fileName = "${safeTitle}_$shortId.txt";
        
        final file = File('${catDir.path}/$fileName');
        String content = "Title: ${note.title}\n";
        content += "Category: ${note.category}\n";
        content += "Last Modified: ${note.createdAt}\n";
        content += "--------------------------------\n\n";
        content += note.content;
        
        await file.writeAsString(content);
      }
    }

    // Export Recycle Bin
    final deletedData = await loadDeletedData();
    final deletedNotesRaw = deletedData['notes'] as List? ?? [];
    final deletedNotes = deletedNotesRaw.map((n) => Note.fromJson(n)).toList();
    
    if (deletedNotes.isNotEmpty) {
      final binDir = Directory('$targetPath/notes_backup/Recycle_Bin');
      if (await binDir.exists()) await binDir.delete(recursive: true);
      await binDir.create(recursive: true);

      // Group by category
      final categories = deletedNotes.map((n) => n.category).toSet();
      for (final cat in categories) {
        final catDir = Directory('${binDir.path}/$cat');
        await catDir.create(recursive: true);
        
        final catNotes = deletedNotes.where((n) => n.category == cat);
        for (final note in catNotes) {
          String safeTitle = note.title.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
          if (safeTitle.isEmpty) safeTitle = 'Deleted';
          final shortId = note.id.length >= 4 ? note.id.substring(note.id.length - 4) : note.id;
          final fileName = "${safeTitle}_$shortId.txt";
          
          final file = File('${binDir.path}/$cat/$fileName');
          String content = "Title: ${note.title}\n";
          content += "Category: ${note.category} (DELETED)\n";
          content += "Last Modified: ${note.createdAt}\n";
          content += "--------------------------------\n\n";
          content += note.content;
          
          await file.writeAsString(content);
        }
      }

      // Also export deleted expenses
      final deletedExpsRaw = deletedData['expenses'] as List? ?? [];
      if (deletedExpsRaw.isNotEmpty) {
        final expBinFile = File('${binDir.path}/deleted_expenses.json');
        await expBinFile.writeAsString(json.encode(deletedExpsRaw));
      }
    }

    // Export Expenses
    if (expenses.isNotEmpty) {
      final expDir = Directory('$targetPath/expense_backup');
      await expDir.create(recursive: true);
      final expFile = File('${expDir.path}/expenses_backup.json');
      await expFile.writeAsString(json.encode(expenses.map((e) => e.toJson()).toList()));
    }

    // Export Tables
    if (tables.isNotEmpty) {
      final tablesDir = Directory('$targetPath/tables_backup');
      await tablesDir.create(recursive: true);
      final tablesFile = File('${tablesDir.path}/tables_backup.json');
      await tablesFile.writeAsString(json.encode(tables.map((t) => t.toJson()).toList()));
    }

    // Export Secure Cards — persist encrypted file in vault + readable backup copy
    if (cards.isNotEmpty) {
      await saveCards(cards, passcode);
      final cardsDir = Directory('$targetPath/cards_backup');
      await cardsDir.create(recursive: true);
      final cardsFile = File('${cardsDir.path}/cards_backup.json');
      await cardsFile.writeAsString(json.encode(cards.map((c) => c.toJson()).toList()));
    }

    // Export Monthly Reports (human-readable backup)
    try {
      final reports = await loadMonthlyReports();
      if (reports.isNotEmpty) {
        final monthlyFile = File('$targetPath/monthly_reports.json');
        await monthlyFile.writeAsString(json.encode({'monthlyReports': reports}));
      }
    } catch (e) {
      print('Error exporting monthly_reports.json: $e');
    }
  }

  Future<Map<String, dynamic>> importFromFolders(String sourcePath) async {
    final List<Note> importedNotes = [];
    final List<dynamic> importedExpenses = [];
    final List<dynamic> importedLinks = [];
    final List<String> importedCategories = ['General'];
    final List<String> linkCategoryNamesFromJson = [];
    final rootDir = Directory(sourcePath);

    if (!await rootDir.exists()) return {'notes': [], 'categories': []};

    // Helper to process a directory
    Future<void> processDirectory(Directory dir, String categoryName) async {
      // Ignore internal system folders during recursive scan
      final dirName = dir.path.split(Platform.pathSeparator).last.toLowerCase();
      if (dirName == 'recycle_bin' || dirName == 'expense_backup' || dirName == 'links_backup') return;

      if (!importedCategories.contains(categoryName)) {
        importedCategories.add(categoryName);
      }

      final entities = await dir.list().toList();
      for (final entity in entities) {
        if (entity is File && entity.path.toLowerCase().endsWith('.txt')) {
          var title = entity.path.split(Platform.pathSeparator).last.replaceAll(RegExp(r'\.txt$', caseSensitive: false), '');
          final content = await entity.readAsString();
          
          String cleanContent = content;
          if (content.startsWith('Title:')) {
            final lines = content.split('\n');
            title = lines.first.substring(6).trim();
            final separatorIndex = lines.indexWhere((l) => l.startsWith('---'));
            if (separatorIndex != -1) {
              cleanContent = lines.skip(separatorIndex + 1).join('\n').trim();
            }
          }

          importedNotes.add(Note(
            title: title,
            content: cleanContent,
            category: categoryName,
            createdAt: (await entity.lastModified()),
          ));
        } else if (entity is Directory) {
          // Process subfolder as a new category
          final subCatName = entity.path.split(Platform.pathSeparator).last;
          await processDirectory(entity, subCatName);
        }
      }
    }

    // Start with the root folder
    await processDirectory(rootDir, 'General');

    // Search for expenses in multiple locations and names
    final possibleExpPaths = [
      '$sourcePath/expense_backup/expenses_backup.json',
      '$sourcePath/Expenses/expenses_backup.json',
      '$sourcePath/Expenses/expenses_data.json',
      '$sourcePath/Expenses/expenses.json',
      '$sourcePath/expense_backup.json',
      '$sourcePath/expenses_backup.json',
      '$sourcePath/expenses_data.json',
      '$sourcePath/expenses.json',
    ];

    for (final expPath in possibleExpPaths) {
      final expFile = File(expPath);
      if (await expFile.exists()) {
        try {
          final content = await expFile.readAsString();
          final decoded = json.decode(content);
          if (decoded is List) {
            importedExpenses.addAll(decoded);
          } else if (decoded is Map) {
            if (decoded['expenses'] != null) {
              importedExpenses.addAll(decoded['expenses']);
            } else if (decoded['data'] != null && decoded['data'] is List) {
              importedExpenses.addAll(decoded['data']);
            }
          }
          if (importedExpenses.isNotEmpty) break; 
        } catch (e) {
          print('Error importing expenses from $expPath: $e');
        }
      }
    }

    // Search for links in multiple locations and names
    final possibleLinkPaths = [
      '$sourcePath/links_backup/links_backup.json',
      '$sourcePath/Links/links_backup.json',
      '$sourcePath/Links/links_data.json',
      '$sourcePath/Links/links.json',
      '$sourcePath/links_backup.json',
      '$sourcePath/links_data.json',
      '$sourcePath/links.json',
    ];

    for (final linkPath in possibleLinkPaths) {
      final linkFile = File(linkPath);
      if (await linkFile.exists()) {
        try {
          final content = await linkFile.readAsString();
          final decoded = json.decode(content);
          List<dynamic>? linksList;
          List<dynamic>? categoriesList;

          if (decoded is List) {
            linksList = decoded;
          } else if (decoded is Map) {
            linksList = (decoded['links'] ?? decoded['data']) as List?;
            categoriesList = (decoded['categories'] ?? decoded['linkCategories']) as List?;
          }

          if (linksList != null) {
            final catMap = categoriesList != null ? {
              for (var cat in categoriesList)
                if (cat is Map) cat['id']?.toString(): cat['name']?.toString()
            } : <String, String>{};

            if (categoriesList != null) {
              for (var cat in categoriesList) {
                if (cat is Map && cat['name'] != null) {
                  linkCategoryNamesFromJson.add(cat['name'].toString());
                }
              }
            }

            final processedLinks = linksList.map((l) {
              if (l is Map && l['category'] == null && l['categoryId'] != null) {
                final catId = l['categoryId'].toString();
                if (catMap.containsKey(catId)) {
                  final newLink = Map<String, dynamic>.from(l);
                  newLink['category'] = catMap[catId];
                  return newLink;
                }
              }
              return l;
            }).toList();
            importedLinks.addAll(processedLinks);
            break;
          }
        } catch (e) {
          print('Error importing links from $linkPath: $e');
        }
      }
    }

    // Search for deleted data
    final Map<String, dynamic> importedDeletedData = {'notes': [], 'expenses': [], 'links': []};
    final possibleDeletedPaths = [
      '$sourcePath/deleted_data.json',
      '$sourcePath/Recycle_Bin/deleted_data.json',
      '$sourcePath/recycle_bin.json',
    ];

    for (final delPath in possibleDeletedPaths) {
      final delFile = File(delPath);
      if (await delFile.exists()) {
        try {
          final content = await delFile.readAsString();
          final decoded = json.decode(content);
          if (decoded is Map) {
            if (decoded['notes'] != null) importedDeletedData['notes'].addAll(decoded['notes']);
            if (decoded['expenses'] != null) importedDeletedData['expenses'].addAll(decoded['expenses']);
            if (decoded['links'] != null) importedDeletedData['links'].addAll(decoded['links']);
            break;
          }
        } catch (e) {
          print('Error importing deleted data from $delPath: $e');
        }
      }
    }

    // Also look for Recycle_Bin folder for text notes
    final recycleBinDir = Directory('$sourcePath/Recycle_Bin');
    if (await recycleBinDir.exists()) {
      final entities = await recycleBinDir.list().toList();
      for (final entity in entities) {
        if (entity is File && entity.path.toLowerCase().endsWith('.txt')) {
           var title = entity.path.split(Platform.pathSeparator).last.replaceAll(RegExp(r'\.txt$', caseSensitive: false), '');
           final content = await entity.readAsString();
           
           String cleanContent = content;
           if (content.startsWith('Title:')) {
             final lines = content.split('\n');
             title = lines.first.substring(6).trim();
             final separatorIndex = lines.indexWhere((l) => l.startsWith('---'));
             if (separatorIndex != -1) {
               cleanContent = lines.skip(separatorIndex + 1).join('\n').trim();
             }
           }
           
           importedDeletedData['notes'].add({
             'title': title,
             'content': cleanContent,
             'category': 'Recycle Bin',
             'createdAt': (await entity.lastModified()).toIso8601String(),
           });
        }
      }
    }

    // Collect categories from expenses and links
    final List<String> importedExpenseCategories = importedExpenses
        .map((e) => (e is Map ? e['category']?.toString() : null))
        .whereType<String>()
        .toSet()
        .toList();
        
    final List<String> importedLinkCategories = {
      ...linkCategoryNamesFromJson,
      ...importedLinks
          .map((l) => (l is Map ? l['category']?.toString() : null))
          .whereType<String>()
    }.toList();

    return {
      'notes': importedNotes,
      'categories': importedCategories,
      'expenses': importedExpenses,
      'expenseCategories': importedExpenseCategories,
      'links': importedLinks,
      'linkCategories': importedLinkCategories,
      'deletedData': importedDeletedData,
    };
  }

  Future<Map<String, dynamic>> loadDeletedData() async {
    final path = await getVaultPath();
    if (path == null) return {'notes': [], 'expenses': [], 'links': []};

    final file = File('$path/deleted_data.json');
    if (!await file.exists()) return {'notes': [], 'expenses': [], 'links': []};

    try {
      final content = await file.readAsString();
      final data = json.decode(content);
      return {
        'notes': data['notes'] ?? [],
        'expenses': data['expenses'] ?? [],
        'links': data['links'] ?? [],
      };
    } catch (e) {
      print('Error loading deleted_data.json: $e');
      return {'notes': [], 'expenses': [], 'links': []};
    }
  }

  Future<void> saveDeletedNotes(List<Note> notes) async {
    final path = await getVaultPath();
    if (path == null) return;
    final file = File('$path/deleted_data.json');
    Map<String, dynamic> currentData = {};
    if (await file.exists()) {
      try {
        currentData = json.decode(await file.readAsString());
      } catch (_) {}
    }
    final data = {
      ...currentData,
      'notes': notes.map((n) => n.toJson()).toList(),
    };
    await _atomicWrite(file, json.encode(data));
  }

  Future<void> saveDeletedExpenses(List<Expense> expenses) async {
    final path = await getVaultPath();
    if (path == null) return;
    final file = File('$path/deleted_data.json');
    Map<String, dynamic> currentData = {};
    if (await file.exists()) {
      try {
        currentData = json.decode(await file.readAsString());
      } catch (_) {}
    }
    final data = {
      ...currentData,
      'expenses': expenses.map((e) => e.toJson()).toList(),
    };
    await _atomicWrite(file, json.encode(data));
  }

  Future<void> saveDeletedLinks(List<LinkItem> links) async {
    final path = await getVaultPath();
    if (path == null) return;
    final file = File('$path/deleted_data.json');
    Map<String, dynamic> currentData = {};
    if (await file.exists()) {
      try {
        currentData = json.decode(await file.readAsString());
      } catch (_) {}
    }
    final data = {
      ...currentData,
      'links': links.map((l) => l.toJson()).toList(),
    };
    await _atomicWrite(file, json.encode(data));
  }

  Future<void> saveLinkCategories(List<String> categories) async {
    _cachedData = null;
    await _synchronized('notes_data', () async {
      final path = await getVaultPath();
      if (path == null) return;
      final file = File('$path/notes_data.json');
      Map<String, dynamic> currentData = {};
      if (await file.exists()) {
        try {
          currentData = json.decode(await file.readAsString());
        } catch (_) {}
      }
      final data = {...currentData, 'linkCategories': categories};
      await _atomicWrite(file, json.encode(data));
    });
  }

  Future<List<dynamic>> loadProfiles() async {
    final path = await getVaultPath();
    if (path == null) return [];
    final file = File('$path/profiles_data.json');
    if (!await file.exists()) return [];
    try {
      final content = await file.readAsString();
      final decoded = json.decode(content);
      if (decoded is Map && decoded['profiles'] != null) {
        return decoded['profiles'] as List;
      } else if (decoded is List) {
        return decoded;
      }
      return [];
    } catch (e) {
      print('Error loading profiles_data.json: $e');
      return [];
    }
  }

  Future<void> saveProfiles(List<dynamic> profiles) async {
    final path = await getVaultPath();
    if (path == null) return;
    final file = File('$path/profiles_data.json');
    final data = {
      'profiles': profiles,
      'lastSync': DateTime.now().toIso8601String(),
    };
    await _atomicWrite(file, json.encode(data));
  }

  Future<void> purgeOldDeletedItems() async {
    final path = await getVaultPath();
    if (path == null) return;
    final file = File('$path/deleted_data.json');
    if (!await file.exists()) return;

    try {
      final content = await file.readAsString();
      final data = json.decode(content);
      final now = DateTime.now();

      final List<dynamic> notes = data['notes'] ?? [];
      final List<dynamic> expenses = data['expenses'] ?? [];
      final List<dynamic> links = data['links'] ?? [];

      final filteredNotes = notes.where((n) {
        final dateStr = n['createdAt'] ?? n['updatedAt'];
        if (dateStr == null) return true;
        final date = DateTime.tryParse(dateStr.toString());
        if (date == null) return true;
        return now.difference(date).inDays < 30;
      }).toList();

      final filteredExpenses = expenses.where((e) {
        final dateStr = e['date'];
        if (dateStr == null) return true;
        final date = DateTime.tryParse(dateStr.toString());
        if (date == null) return true;
        return now.difference(date).inDays < 30;
      }).toList();

      final filteredLinks = links.where((l) {
        final dateStr = l['createdAt'];
        if (dateStr == null) return true;
        final date = DateTime.tryParse(dateStr.toString());
        if (date == null) return true;
        return now.difference(date).inDays < 30;
      }).toList();

      if (filteredNotes.length != notes.length ||
          filteredExpenses.length != expenses.length ||
          filteredLinks.length != links.length) {
        final newData = {
          ...data,
          'notes': filteredNotes,
          'expenses': filteredExpenses,
          'links': filteredLinks,
        };
        await _atomicWrite(file, json.encode(newData));
      }
    } catch (e) {
      print('Error purging old deleted items: $e');
    }
  }

}


