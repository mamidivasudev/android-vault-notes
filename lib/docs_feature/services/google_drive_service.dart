import 'dart:io';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive_io.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'local_storage_service.dart';
import '../models/document_model.dart';

class GoogleDriveService {
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      drive.DriveApi.driveFileScope,
      drive.DriveApi.driveAppdataScope,
    ],
  );

  Future<drive.DriveApi?> _getDriveApi() async {
    var account = _googleSignIn.currentUser;
    // Reuse the existing session first so backup/restore doesn't pop the
    // account chooser every time it's called from the main sync.
    account ??= await _googleSignIn.signInSilently();
    account ??= await _googleSignIn.signIn();
    
    if (account == null) return null; // User cancelled
    
    final authClient = await _googleSignIn.authenticatedClient();
    if (authClient == null) return null;

    return drive.DriveApi(authClient);
  }

  Future<GoogleSignInAccount?> signIn() async {
    return await _googleSignIn.signIn();
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
  }

  Future<void> backupData() async {
    final api = await _getDriveApi();
    if (api == null) throw Exception("Authentication failed");

    // 1. Create a zip file containing the DB and images
    final appDir = await getApplicationDocumentsDirectory();
    final zipFile = File('${appDir.path}/backup.zip');
    
    final encoder = ZipFileEncoder();
    encoder.create(zipFile.path);

    // Add the Hive DB file. Hive lower-cases box names on disk
    // ('documentsboxv3.hive'), so the real path is taken from the open box
    // instead of being guessed -- the old hard-coded 'documentsBoxV3.hive'
    // never existed, which meant document records were never backed up.
    // The box is opened as Box<DocumentModel>; asking Hive for an untyped
    // Hive.box(...) throws "already open and of type Box<DocumentModel>",
    // which made every Docs backup fail.
    if (Hive.isBoxOpen(LocalStorageService.boxName)) {
      await Hive.box<DocumentModel>(LocalStorageService.boxName).flush();
    }
    final hivePath = LocalStorageService.boxFilePath ?? '${appDir.path}/${LocalStorageService.boxName.toLowerCase()}.hive';
    final hiveFile = File(hivePath);
    if (await hiveFile.exists()) {
      await encoder.addFile(hiveFile, p.basename(hivePath));
    }

    // Add images directory
    final imagesDir = Directory('${appDir.path}/images');
    if (await imagesDir.exists()) {
      await encoder.addDirectory(imagesDir);
    }

    // addFile/addDirectory/close are async; without awaiting them the zip
    // could be closed before the images were written into it.
    await encoder.close();

    // 2. Upload to Google Drive (appDataFolder)
    final driveFile = drive.File()
      ..name = 'lifevault_backup_${DateTime.now().millisecondsSinceEpoch}.zip'
      ..parents = ['appDataFolder'];
      
    final media = drive.Media(zipFile.openRead(), zipFile.lengthSync());
    
    await api.files.create(driveFile, uploadMedia: media);

    // Cleanup local zip
    if (await zipFile.exists()) {
      await zipFile.delete();
    }

    // Every backup is a new file; keep only the newest few so Drive storage
    // doesn't grow forever.
    await _pruneOldBackups(api, keep: 3);
  }

  Future<void> _pruneOldBackups(drive.DriveApi api, {required int keep}) async {
    try {
      final list = await api.files.list(
        spaces: 'appDataFolder',
        q: "name contains 'lifevault_backup_'",
        $fields: 'files(id, name, createdTime)',
        orderBy: 'createdTime desc',
      );
      final files = list.files ?? [];
      for (final f in files.skip(keep)) {
        if (f.id != null) await api.files.delete(f.id!);
      }
    } catch (e) {
      print('Could not prune old docs backups: $e');
    }
  }

  Future<void> restoreData() async {
    final api = await _getDriveApi();
    if (api == null) throw Exception("Authentication failed");

    // 1. Find the latest backup
    final fileList = await api.files.list(
      spaces: 'appDataFolder',
      $fields: 'files(id, name, createdTime)',
      orderBy: 'createdTime desc',
    );

    if (fileList.files == null || fileList.files!.isEmpty) {
      throw Exception("No backups found in Google Drive");
    }

    final latestBackup = fileList.files!.first;
    if (latestBackup.id == null) throw Exception("Backup file is invalid");

    // 2. Download it
    final drive.Media media = await api.files.get(
      latestBackup.id!, 
      downloadOptions: drive.DownloadOptions.fullMedia
    ) as drive.Media;
    
    final appDir = await getApplicationDocumentsDirectory();
    final tempZipFile = File('${appDir.path}/temp_restore.zip');
    
    List<int> dataStore = [];
    await for (var data in media.stream) {
      dataStore.addAll(data);
    }
    await tempZipFile.writeAsBytes(dataStore);

    // 3. Extract and overwrite local files
    // Close Hive first to safely overwrite
    await Hive.close();

    final bytes = tempZipFile.readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes);

    try {
      final root = p.normalize(appDir.path);
      for (final file in archive) {
        // Refuse entries that would escape the app directory ("../" paths).
        final target = p.normalize(p.join(root, file.name));
        if (!p.isWithin(root, target)) continue;
        if (file.isFile) {
          final data = file.content as List<int>;
          File(target)
            ..createSync(recursive: true)
            ..writeAsBytesSync(data);
        } else {
          Directory(target).createSync(recursive: true);
        }
      }
    } finally {
      // Cleanup and re-open the box we closed above, otherwise every later
      // Docs read/write throws until the app is restarted.
      if (await tempZipFile.exists()) await tempZipFile.delete();
      await LocalStorageService.reopen();
    }
  }
}
