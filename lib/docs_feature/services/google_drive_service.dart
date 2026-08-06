import 'dart:io';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive_io.dart';
import 'package:hive/hive.dart';

class GoogleDriveService {
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      drive.DriveApi.driveFileScope,
      drive.DriveApi.driveAppdataScope,
    ],
  );

  Future<drive.DriveApi?> _getDriveApi() async {
    var account = _googleSignIn.currentUser;
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

    // Add Hive DB directory
    // Hive defaults to the path provided in initFlutter() which is usually app doc dir / path
    // But since we used hive_flutter, it's typically the app doc dir.
    // Let's add the 'documentsBoxV3.hive' file directly.
    final hiveFile = File('${appDir.path}/documentsBoxV3.hive');
    if (await hiveFile.exists()) {
      encoder.addFile(hiveFile);
    }

    // Add images directory
    final imagesDir = Directory('${appDir.path}/images');
    if (await imagesDir.exists()) {
      encoder.addDirectory(imagesDir);
    }
    
    encoder.close();

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

    for (final file in archive) {
      final filename = file.name;
      if (file.isFile) {
        final data = file.content as List<int>;
        File('${appDir.path}/$filename')
          ..createSync(recursive: true)
          ..writeAsBytesSync(data);
      } else {
        Directory('${appDir.path}/$filename').createSync(recursive: true);
      }
    }

    // Cleanup
    await tempZipFile.delete();

    // Restart Hive - user must restart app ideally, but we can try to re-init
    // Note: It's best if the caller triggers a full app restart or reloads the provider.
  }
}
