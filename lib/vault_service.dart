import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';

class VaultService {
  static const String _vaultPathKey = 'vault_path';
  // Shared across all VaultService instances (the notification handler creates
  // its own instance) so a write from anywhere invalidates every reader.
  static Map<String, dynamic>? _cachedData;

  /// Every vault file that holds user data (backup, restore and local
  /// snapshots all use this list).
  static const List<String> dataFiles = [
    'notes_data.json',
    'expenses_data.json',
    'links_data.json',
    'tables_data.json',
    'reminders_data.json',
    'bills_data.json',
    'monthly_reports.json',
    'mileage_data.json',
    'service_data.json',
    'deleted_data.json',
    'profiles_data.json',
    'app_settings.json', // grocery list, budgets, docs categories, service odometer
  ];

  /// Folder (inside the vault) that holds automatic local snapshots.
  static const String backupFolderName = '.vault_backups';

  /// Files that existed but could not be parsed on the last load. Before such a
  /// file is overwritten, a copy is kept so its data is never lost.
  static final Set<String> _unreadableFiles = {};

  /// Marks a vault file as unreadable (e.g. a provider could not parse some of
  /// its records) so it is preserved before the next overwrite.
  static void markUnreadable(String fileName) => _unreadableFiles.add(fileName);

  /// Drops the in-memory cache so the next load re-reads the vault files.
  /// Must be called after files are replaced outside of the save methods
  /// (e.g. a Google Drive restore).
  void clearCache() {
    _cachedData = null;
  }

  /// SharedPreferences keys whose data is not stored in a vault JSON file.
  /// They are mirrored into app_settings.json so they are included in backups.
  static const List<String> _snapshotPrefKeys = [
    'grocery_items',
    'user_grocery_catalog',
    'expense_budgets',
    'custom_categories',
    'last_service_odo',
    'next_service_odo',
    'bike_tank_capacity',
    'enabled_tabs',
  ];

  /// Writes the SharedPreferences-only data into the vault as app_settings.json.
  Future<void> exportAppSettings() async {
    final path = await getVaultPath();
    if (path == null) return;
    final prefs = await SharedPreferences.getInstance();
    final Map<String, dynamic> values = {};
    for (final key in _snapshotPrefKeys) {
      final v = prefs.get(key);
      if (v != null) values[key] = v;
    }
    await _synchronized('app_settings', () async {
      await _atomicWrite(File('$path/app_settings.json'), json.encode({
        'settings': values,
        'savedAt': DateTime.now().toIso8601String(),
      }));
    });
  }

  /// Restores the SharedPreferences-only data from app_settings.json (if present).
  Future<void> importAppSettings() async {
    final path = await getVaultPath();
    if (path == null) return;
    final file = File('$path/app_settings.json');
    if (!await file.exists()) return;
    try {
      final decoded = json.decode(await file.readAsString());
      final values = (decoded is Map ? decoded['settings'] : null) as Map? ?? {};
      final prefs = await SharedPreferences.getInstance();
      for (final entry in values.entries) {
        final key = entry.key.toString();
        if (!_snapshotPrefKeys.contains(key)) continue;
        final v = entry.value;
        if (v is String) {
          await prefs.setString(key, v);
        } else if (v is bool) {
          await prefs.setBool(key, v);
        } else if (v is int) {
          await prefs.setInt(key, v);
        } else if (v is double) {
          await prefs.setDouble(key, v);
        } else if (v is List) {
          await prefs.setStringList(key, v.map((e) => e.toString()).toList());
        }
      }
    } catch (e) {
      print('Error importing app_settings.json: $e');
    }
  }

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
    final name = file.uri.pathSegments.isNotEmpty ? file.uri.pathSegments.last : file.path;
    if (_unreadableFiles.remove(name)) {
      await _preserveUnreadable(file);
    }
    final tempFile = File('${file.path}.tmp');
    await tempFile.writeAsString(content, flush: true);
    await tempFile.rename(file.path);
  }

  /// Keeps a copy of a file we could not parse, so overwriting it never
  /// destroys data that might still be recoverable by hand.
  Future<void> _preserveUnreadable(File file) async {
    try {
      if (!await file.exists()) return;
      final stamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      await file.copy('${file.path}.unreadable-$stamp');
    } catch (e) {
      print('Could not preserve unreadable ${file.path}: $e');
    }
  }

  /// Reads a JSON map that is about to be merged and re-written. If it can't be
  /// parsed, a copy is kept and an empty map is returned so the save still
  /// happens (previously the save was silently dropped).
  Future<Map<String, dynamic>> _readForMerge(File file) async {
    if (!await file.exists()) return {};
    try {
      final decoded = json.decode(await file.readAsString());
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (e) {
      print('Unreadable ${file.path} during save: $e');
    }
    await _preserveUnreadable(file);
    return {};
  }

  /// Copies every vault data file into `.vault_backups/<timestamp>_<reason>/`
  /// and keeps the newest [keep] snapshots. Returns the snapshot folder.
  Future<String?> createLocalBackup(String reason, {int keep = 14}) async {
    final path = await getVaultPath();
    if (path == null) return null;
    try {
      final now = DateTime.now();
      String two(int v) => v.toString().padLeft(2, '0');
      final stamp = '${now.year}-${two(now.month)}-${two(now.day)}_${two(now.hour)}${two(now.minute)}${two(now.second)}';
      final dir = Directory('$path/$backupFolderName/${stamp}_$reason');
      await dir.create(recursive: true);
      var copied = 0;
      for (final name in dataFiles) {
        final f = File('$path/$name');
        if (await f.exists()) {
          await f.copy('${dir.path}/$name');
          copied++;
        }
      }
      if (copied == 0) {
        await dir.delete(recursive: true);
        return null;
      }
      await _pruneBackups(Directory('$path/$backupFolderName'), keep);
      return dir.path;
    } catch (e) {
      print('Local backup failed: $e');
      return null;
    }
  }

  /// Takes one automatic snapshot per day.
  Future<void> dailyBackupIfNeeded() async {
    final path = await getVaultPath();
    if (path == null) return;
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final today = '${now.year}-${two(now.month)}-${two(now.day)}';
    final root = Directory('$path/$backupFolderName');
    if (await root.exists()) {
      await for (final e in root.list()) {
        final name = e.uri.pathSegments.where((p) => p.isNotEmpty).last;
        if (name.startsWith(today) && name.endsWith('_daily')) return;
      }
    }
    await createLocalBackup('daily');
  }

  Future<void> _pruneBackups(Directory root, int keep) async {
    if (!await root.exists()) return;
    final dirs = <Directory>[];
    await for (final e in root.list()) {
      if (e is Directory) dirs.add(e);
    }
    dirs.sort((a, b) => b.path.compareTo(a.path)); // names start with a sortable timestamp
    for (final d in dirs.skip(keep)) {
      try {
        await d.delete(recursive: true);
      } catch (_) {}
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
      final remindersFile = File('$path/reminders_data.json');
      final billsFile = File('$path/bills_data.json');
      
      Map<String, dynamic> combinedData = {
        'notes': [],
        'expenses': [],
        'links': [],
        'tables': [],
        'reminders': [],
        'bills': [],
        'monthlyReports': [],
        'fuelEntries': [],
        'serviceEntries': [],
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
          _unreadableFiles.add('notes_data.json');
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
          _unreadableFiles.add('expenses_data.json');
        }
      }

      // Load Links
      if (await linksFile.exists()) {
        try {
          final content = await linksFile.readAsString();
          final data = json.decode(content);
          combinedData['links'] = data['links'] ?? [];
          // Link categories are saved in notes_data.json; links_data.json only
          // has them from old app versions, so use those only as a fallback.
          final fromNotes = combinedData['linkCategories'];
          if (data['linkCategories'] != null && (fromNotes is! List || fromNotes.isEmpty)) {
            combinedData['linkCategories'] = data['linkCategories'];
          }
        } catch (e) {
          print('Error loading links_data.json: $e');
          _unreadableFiles.add('links_data.json');
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
          _unreadableFiles.add('tables_data.json');
        }
      }

      // Load Reminders
      if (await remindersFile.exists()) {
        try {
          final content = await remindersFile.readAsString();
          final data = json.decode(content);
          combinedData['reminders'] = data['reminders'] ?? [];
        } catch (e) {
          print('Error loading reminders_data.json: $e');
          _unreadableFiles.add('reminders_data.json');
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
          _unreadableFiles.add('bills_data.json');
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
          _unreadableFiles.add('monthly_reports.json');
        }
      }

      // Load Fuel Entries
      final mileageFile = File('$path/mileage_data.json');
      if (await mileageFile.exists()) {
        try {
          final content = await mileageFile.readAsString();
          final data = json.decode(content);
          if (data is List) {
            combinedData['fuelEntries'] = data;
          } else if (data is Map) {
            combinedData['fuelEntries'] = data['fuelEntries'] ?? [];
          }
        } catch (e) {
          print('Error loading mileage_data.json: $e');
          _unreadableFiles.add('mileage_data.json');
        }
      }

      // Load Service Entries
      final serviceFile = File('$path/service_data.json');
      if (await serviceFile.exists()) {
        try {
          final content = await serviceFile.readAsString();
          final data = json.decode(content);
          if (data is Map) {
            combinedData['serviceEntries'] = data['serviceEntries'] ?? [];
          } else if (data is List) {
            combinedData['serviceEntries'] = data;
          }
        } catch (e) {
          print('Error loading service_data.json: $e');
          _unreadableFiles.add('service_data.json');
        }
      }

      _cachedData = combinedData;
      return combinedData;
    });
  }


  Future<void> saveNotes(List<Note> notes, List<String> categories) async {
    _cachedData = null;
    await _synchronized('notes_data', () async {
      final path = await getVaultPath();
      if (path == null) return;
      final file = File('$path/notes_data.json');
      
      final currentData = await _readForMerge(file);

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
      _unreadableFiles.add('monthly_reports.json');
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

  Future<void> saveFuelEntries(List<FuelEntry> entries) async {
    _cachedData = null;
    await _synchronized('mileage_data', () async {
      final path = await getVaultPath();
      if (path == null) return;
      final file = File('$path/mileage_data.json');
      final data = {
        'fuelEntries': entries.map((e) => e.toJson()).toList(),
      };
      await _atomicWrite(file, json.encode(data));
    });
  }

  Future<void> saveServiceEntries(List<ServiceEntry> entries) async {
    _cachedData = null;
    await _synchronized('service_data', () async {
      final path = await getVaultPath();
      if (path == null) return;
      final file = File('$path/service_data.json');
      final data = {
        'serviceEntries': entries.map((e) => e.toJson()).toList(),
      };
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
      bool manual = false,
  }) async {
    final reports = await loadMonthlyReports();
    final keyExists = reports.indexWhere((r) => r['year'] == year && r['month'] == month);
    final entry = {
      if (manual) 'manual': true,
      'year': year,
      'month': month,
      'credit': credit,
      'loan': loan,
      'creditDetails': ?creditDetails,
      'loanDetails': ?loanDetails,
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
      
      final currentData = await _readForMerge(file);

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
      
      final currentData = await _readForMerge(file);

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


  Future<void> exportToFolders(
    String targetPath,
    List<Note> notes,
    List<String> categories,
    List<Expense> expenses,
    List<LinkItem> links,
    List<VaultTable> tables,
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
        content += "Last Modified: ${note.lastModified}\n";
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
          content += "Last Modified: ${note.lastModified}\n";
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

  Future<void> exportMileageToFolders(
    String targetPath,
    List<FuelEntry> fuel,
    List<ServiceEntry> service,
  ) async {
    final mileageDir = Directory('$targetPath/mileage_backup');
    if (!await mileageDir.exists()) {
      await mileageDir.create(recursive: true);
    }
    
    final fuelFile = File('${mileageDir.path}/fuel_data.json');
    await fuelFile.writeAsString(json.encode(fuel.map((e) => e.toJson()).toList()));
    
    final serviceFile = File('${mileageDir.path}/service_data.json');
    await serviceFile.writeAsString(json.encode(service.map((e) => e.toJson()).toList()));
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
      if (dirName == 'recycle_bin' || dirName == 'expense_backup' || dirName == 'links_backup' || dirName.startsWith('.')) return;

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
          _unreadableFiles.add('deleted_data.json');
      return {'notes': [], 'expenses': [], 'links': []};
    }
  }

  Future<void> _saveDeletedSection(String key, List<Map<String, dynamic>> items) async {
    await _synchronized('deleted_data', () async {
      final path = await getVaultPath();
      if (path == null) return;
      final file = File('$path/deleted_data.json');
      final currentData = await _readForMerge(file);
      await _atomicWrite(file, json.encode({...currentData, key: items}));
    });
  }

  Future<void> saveDeletedNotes(List<Note> notes) =>
      _saveDeletedSection('notes', notes.map((n) => n.toJson()).toList());

  Future<void> saveDeletedExpenses(List<Expense> expenses) =>
      _saveDeletedSection('expenses', expenses.map((e) => e.toJson()).toList());

  Future<void> saveDeletedLinks(List<LinkItem> links) =>
      _saveDeletedSection('links', links.map((l) => l.toJson()).toList());

  Future<void> saveLinkCategories(List<String> categories) async {
    _cachedData = null;
    await _synchronized('notes_data', () async {
      final path = await getVaultPath();
      if (path == null) return;
      final file = File('$path/notes_data.json');
      final currentData = await _readForMerge(file);
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
          _unreadableFiles.add('profiles_data.json');
      return [];
    }
  }

  Future<void> saveProfiles(List<dynamic> profiles) async {
    await _synchronized('profiles_data', () async {
      final path = await getVaultPath();
      if (path == null) return;
      final file = File('$path/profiles_data.json');
      final data = {
        'profiles': profiles,
        'lastSync': DateTime.now().toIso8601String(),
      };
      await _atomicWrite(file, json.encode(data));
    });
  }

  /// Permanently removes Recycle Bin items deleted more than 30 days ago.
  /// Age is measured from `deletedAt` (when the item was moved to the bin),
  /// never from the item's own creation/transaction date. Items from older app
  /// versions without `deletedAt` are stamped with "now" so they get a full
  /// 30 days instead of being purged immediately.
  Future<void> purgeOldDeletedItems() async {
    await _synchronized('deleted_data', () async {
      final path = await getVaultPath();
      if (path == null) return;
      final file = File('$path/deleted_data.json');
      if (!await file.exists()) return;

      try {
        final data = Map<String, dynamic>.from(json.decode(await file.readAsString()));
        final now = DateTime.now();
        bool changed = false;

        List<dynamic> filter(List<dynamic> items) {
          final kept = <dynamic>[];
          for (final raw in items) {
            if (raw is! Map) continue;
            final item = Map<String, dynamic>.from(raw);
            final deletedAt = DateTime.tryParse(item['deletedAt']?.toString() ?? '');
            if (deletedAt == null) {
              item['deletedAt'] = now.toIso8601String();
              changed = true;
              kept.add(item);
            } else if (now.difference(deletedAt).inDays < 30) {
              kept.add(item);
            } else {
              changed = true;
            }
          }
          return kept;
        }

        final newData = {
          ...data,
          'notes': filter(data['notes'] as List? ?? []),
          'expenses': filter(data['expenses'] as List? ?? []),
          'links': filter(data['links'] as List? ?? []),
        };
        if (changed) {
          await _atomicWrite(file, json.encode(newData));
        }
      } catch (e) {
        print('Error purging old deleted items: $e');
      }
    });
  }
}
