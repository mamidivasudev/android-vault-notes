import 'dart:io';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class SyncService {
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [drive.DriveApi.driveFileScope],
  );
  GoogleSignInAccount? _currentUser;

  Future<GoogleSignInAccount?> signIn() async {
    try {
      _currentUser = await _googleSignIn.signIn();
      return _currentUser;
    } catch (e) {
      print('Google Sign-In Error: $e');
      return null;
    }
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    _currentUser = null;
  }

  Future<drive.DriveApi?> _getDriveApi() async {
    final account = _currentUser ?? await _googleSignIn.signInSilently();
    if (account == null) return null;
    final http.Client? httpClient = await _googleSignIn.authenticatedClient();
    if (httpClient == null) return null;
    return drive.DriveApi(httpClient);
  }

  Future<String?> _getOrCreateFolder(drive.DriveApi api, String folderName) async {
    final folderList = await api.files.list(
      q: "name = '$folderName' and mimeType = 'application/vnd.google-apps.folder' and trashed = false",
      spaces: 'drive',
    );
    if (folderList.files != null && folderList.files!.isNotEmpty) {
      return folderList.files!.first.id;
    }
    final folder = drive.File()..name = folderName..mimeType = 'application/vnd.google-apps.folder';
    final createdFolder = await api.files.create(folder);
    return createdFolder.id;
  }

  Future<bool> backupDatabase() async {
    final api = await _getDriveApi();
    if (api == null) return false;
    try {
      final folderId = await _getOrCreateFolder(api, 'LifeVaultBackup');
      final dir = await getApplicationDocumentsDirectory();
      final dbFile = File('${dir.path}/documentsBox.hive');
      if (!dbFile.existsSync()) return false;
      
      final fileName = 'documentsBox.hive';
      final existingFiles = await api.files.list(
        q: "name = '$fileName' and '$folderId' in parents and trashed = false",
        spaces: 'drive',
      );
      final media = drive.Media(dbFile.openRead(), dbFile.lengthSync());
      final driveFile = drive.File()..name = fileName;

      if (existingFiles.files != null && existingFiles.files!.isNotEmpty) {
        await api.files.update(driveFile, existingFiles.files!.first.id!, uploadMedia: media);
      } else {
        driveFile.parents = [folderId!];
        await api.files.create(driveFile, uploadMedia: media);
      }
      return true;
    } catch (e) {
      print('Backup error: $e');
      return false;
    }
  }
}
