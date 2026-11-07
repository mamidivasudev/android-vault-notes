import 'dart:io';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'docs_vault_backup.dart';

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

    // 1. Zip the Docs database (real Hive path, typed box) and images.
    final appDir = await getApplicationDocumentsDirectory();
    final zipFile = await DocsVaultBackup.buildZip('${appDir.path}/backup.zip');

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

    // 3. Extract and overwrite local files, then keep the vault copy in step.
    try {
      await DocsVaultBackup.extractZip(tempZipFile);
    } finally {
      if (await tempZipFile.exists()) await tempZipFile.delete();
    }
    DocsVaultBackup.scheduleSave();
  }
}
