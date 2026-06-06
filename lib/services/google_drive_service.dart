import 'dart:io';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

class GoogleDriveService {
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      drive.DriveApi.driveFileScope,
    ],
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

    final folder = drive.File()
      ..name = folderName
      ..mimeType = 'application/vnd.google-apps.folder';

    final createdFolder = await api.files.create(folder);
    return createdFolder.id;
  }

  Future<void> uploadFile(File localFile, String remoteFolderName) async {
    final api = await _getDriveApi();
    if (api == null) throw Exception('Not signed in to Google');

    final folderId = await _getOrCreateFolder(api, remoteFolderName);
    final fileName = p.basename(localFile.path);

    // Check if file exists
    final existingFiles = await api.files.list(
      q: "name = '$fileName' and '$folderId' in parents and trashed = false",
      spaces: 'drive',
    );

    final media = drive.Media(localFile.openRead(), localFile.lengthSync());
    final driveFile = drive.File()..name = fileName;

    if (existingFiles.files != null && existingFiles.files!.isNotEmpty) {
      // Update existing
      await api.files.update(driveFile, existingFiles.files!.first.id!, uploadMedia: media);
    } else {
      // Create new
      driveFile.parents = [folderId!];
      await api.files.create(driveFile, uploadMedia: media);
    }
  }

  Future<bool> downloadFile(String remoteFileName, String remoteFolderName, File localFile) async {
    final api = await _getDriveApi();
    if (api == null) throw Exception('Not signed in to Google');

    final folderId = await _getOrCreateFolder(api, remoteFolderName);

    final existingFiles = await api.files.list(
      q: "name = '$remoteFileName' and '$folderId' in parents and trashed = false",
      spaces: 'drive',
      $fields: 'files(id, name)',
    );

    if (existingFiles.files == null || existingFiles.files!.isEmpty) {
      return false;
    }

    final fileId = existingFiles.files!.first.id!;
    final drive.Media response = await api.files.get(fileId, downloadOptions: drive.DownloadOptions.fullMedia) as drive.Media;

    final List<int> dataStore = [];
    await for (final data in response.stream) {
      dataStore.addAll(data);
    }
    await localFile.writeAsBytes(dataStore);
    return true;
  }

  Future<List<String>> listFilesInFolder(String folderName) async {
    final api = await _getDriveApi();
    if (api == null) return [];

    final folderId = await _getOrCreateFolder(api, folderName);
    final files = await api.files.list(
      q: "'$folderId' in parents and trashed = false",
      spaces: 'drive',
    );

    return files.files?.map((f) => f.name ?? '').toList() ?? [];
  }
}
