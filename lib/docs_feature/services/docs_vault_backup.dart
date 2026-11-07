import 'dart:async';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../vault_service.dart';
import '../models/document_model.dart';
import 'local_storage_service.dart';

/// Keeps a copy of all Docs (the document records + their photos/PDFs) in the
/// vault folder as `docs_backup.zip`, so Docs survive an uninstall or a new
/// phone the same way the other tabs do – not only through Drive.
///
/// - [scheduleSave] is called after every Docs change.
/// - [restoreIfEmpty] brings Docs back from the vault folder when the app has
///   none (fresh install / vault folder picked again).
class DocsVaultBackup {
  static const fileName = 'docs_backup.zip';

  static Timer? _debounce;
  static Future<void> _running = Future.value();

  /// Saves the vault copy shortly after a change (several quick changes → one save).
  static void scheduleSave() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), () {
      _running = _running.then((_) => saveNow()).catchError((_) {});
    });
  }

  /// Builds a zip with the documents database and the images folder.
  static Future<File> buildZip(String zipPath) async {
    final appDir = await getApplicationDocumentsDirectory();
    if (Hive.isBoxOpen(LocalStorageService.boxName)) {
      await Hive.box<DocumentModel>(LocalStorageService.boxName).flush();
    }
    final encoder = ZipFileEncoder();
    encoder.create(zipPath);
    final hivePath =
        LocalStorageService.boxFilePath ?? '${appDir.path}/${LocalStorageService.boxName.toLowerCase()}.hive';
    final hiveFile = File(hivePath);
    if (await hiveFile.exists()) {
      await encoder.addFile(hiveFile, p.basename(hivePath));
    }
    final imagesDir = Directory('${appDir.path}/images');
    if (await imagesDir.exists()) {
      await encoder.addDirectory(imagesDir);
    }
    await encoder.close();
    return File(zipPath);
  }

  /// Writes `docs_backup.zip` into the vault folder (via a temp file + rename,
  /// so a crash never leaves a half-written backup).
  static Future<void> saveNow() async {
    final vault = await VaultService().getVaultPath();
    if (vault == null) return;
    try {
      final target = File('$vault/$fileName');
      final tmp = await buildZip('$vault/$fileName.tmp');
      if (await target.exists()) await target.delete();
      await tmp.rename(target.path);
    } catch (e) {
      debugPrint('Docs vault backup failed: $e');
    }
  }

  /// Unpacks a Docs zip into the app folder, replacing the current Docs.
  static Future<void> extractZip(File zip) async {
    final appDir = await getApplicationDocumentsDirectory();
    final archive = ZipDecoder().decodeBytes(await zip.readAsBytes());
    await Hive.close();
    try {
      final root = p.normalize(appDir.path);
      for (final entry in archive) {
        // Refuse entries that would escape the app directory ("../" paths).
        final target = p.normalize(p.join(root, entry.name));
        if (!p.isWithin(root, target)) continue;
        if (entry.isFile) {
          File(target)
            ..createSync(recursive: true)
            ..writeAsBytesSync(entry.content as List<int>);
        } else {
          Directory(target).createSync(recursive: true);
        }
      }
    } finally {
      await LocalStorageService.reopen();
    }
  }

  /// Makes the first vault copy for people who already had Docs before this
  /// backup existed (or after the copy was removed).
  static Future<void> ensureCopyExists() async {
    try {
      final vault = await VaultService().getVaultPath();
      if (vault == null || await File('$vault/$fileName').exists()) return;
      if (Hive.isBoxOpen(LocalStorageService.boxName) &&
          Hive.box<DocumentModel>(LocalStorageService.boxName).isNotEmpty) {
        scheduleSave();
      }
    } catch (_) {}
  }

  /// If the app has no Docs but the vault folder has a Docs backup, restores it.
  /// Returns true when something was restored.
  static Future<bool> restoreIfEmpty() async {
    try {
      final vault = await VaultService().getVaultPath();
      if (vault == null) return false;
      final zip = File('$vault/$fileName');
      if (!await zip.exists()) return false;
      final box = Hive.isBoxOpen(LocalStorageService.boxName)
          ? Hive.box<DocumentModel>(LocalStorageService.boxName)
          : null;
      if (box != null && box.isNotEmpty) return false;
      await extractZip(zip);
      return Hive.box<DocumentModel>(LocalStorageService.boxName).isNotEmpty;
    } catch (e) {
      debugPrint('Docs restore from vault failed: $e');
      return false;
    }
  }
}
