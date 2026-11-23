import 'dart:io';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

import 'models.dart';

const driveFileScope = 'https://www.googleapis.com/auth/drive.file';
const googleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

class _BearerClient extends http.BaseClient {
  final String accessToken;
  final http.Client _inner = http.Client();

  _BearerClient(this.accessToken);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer $accessToken';
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}

class DriveGateway {
  final GoogleSignIn _signIn = GoogleSignIn.instance;
  GoogleSignInAccount? _account;
  bool _initialized = false;

  GoogleSignInAccount? get account => _account;

  Future<void> initialize() async {
    if (_initialized) return;
    if (googleWebClientId.isEmpty) {
      throw StateError('Missing GOOGLE_WEB_CLIENT_ID. See README.md');
    }
    await _signIn.initialize(serverClientId: googleWebClientId);
    _initialized = true;
  }

  Future<GoogleSignInAccount?> restore() async {
    await initialize();
    _account = await _signIn.attemptLightweightAuthentication();
    return _account;
  }

  /// Only call this on a user button press: Android may show an OAuth screen.
  Future<GoogleSignInAccount> connectInteractively() async {
    await initialize();
    final account = await _signIn.authenticate();
    await account.authorizationClient.authorizeScopes([driveFileScope]);
    _account = account;
    return account;
  }

  Future<void> disconnect() async {
    await initialize();
    await _signIn.signOut();
    _account = null;
  }

  Future<T> _api<T>(Future<T> Function(drive.DriveApi api) callback) async {
    final user = _account;
    if (user == null) throw StateError('Connect your Google account first.');
    // No interactive OAuth dialogs are permitted during background work.
    final auth = await user.authorizationClient.authorizationForScopes([driveFileScope]);
    if (auth == null) {
      throw StateError('Google Drive needs permission. Open the app and reconnect.');
    }
    final client = _BearerClient(auth.accessToken);
    try {
      return await callback(drive.DriveApi(client));
    } finally {
      client.close();
    }
  }

  String _quote(String value) => value.replaceAll(r'\', r'\\').replaceAll("'", r"\'");

  Future<String> _ensureFolder(drive.DriveApi api, String name, String? parent) async {
    final qParent = parent == null ? "'root' in parents" : "'${_quote(parent)}' in parents";
    final result = await api.files.list(
      q: "mimeType = 'application/vnd.google-apps.folder' and name = '${_quote(name)}' and $qParent and trashed = false",
      $fields: 'files(id,name),nextPageToken', pageSize: 100,
    );
    for (final folder in result.files ?? <drive.File>[]) {
      if (folder.id != null) return folder.id!;
    }
    final created = await api.files.create(
      drive.File()
        ..name = name
        ..mimeType = 'application/vnd.google-apps.folder'
        ..parents = [parent ?? 'root'],
      $fields: 'id',
    );
    if (created.id == null) throw StateError('Unable to create Drive folder $name.');
    return created.id!;
  }

  Future<String> _destinationFolder(drive.DriveApi api, DateTime created) async {
    final root = await _ensureFolder(api, 'Cloud Photo Vault', null);
    final year = await _ensureFolder(api, '${created.year}', root);
    final month = created.month.toString().padLeft(2, '0');
    return _ensureFolder(api, month, year);
  }

  /// Drive appProperties make retries idempotent even if the phone crashes
  /// after successful upload but before SQLite gets updated.
  Future<drive.File?> _findExisting(drive.DriveApi api, String md5, int bytes) async {
    final files = await api.files.list(
      q: "appProperties has { key='sourceMd5' and value='${_quote(md5)}' } and trashed = false",
      $fields: 'nextPageToken,files(id,md5Checksum,size,trashed,name)',
      pageSize: 100,
    );
    for (final file in files.files ?? <drive.File>[]) {
      if (file.id != null && cloudCopyMatches(
        localMd5: md5,
        localBytes: bytes,
        remoteMd5: file.md5Checksum,
        remoteBytes: int.tryParse(file.size ?? ''),
        remoteTrashed: file.trashed,
      )) {
        return file;
      }
    }
    return null;
  }

  Future<String> uploadOrFind({
    required File original,
    required int bytes,
    required String md5,
    required String name,
    required String mimeType,
    required DateTime takenAt,
  }) async {
    return _api((api) async {
      final existing = await _findExisting(api, md5, bytes);
      if (existing != null) return existing.id!;

      final folderId = await _destinationFolder(api, takenAt);
      final uploaded = await api.files.create(
        drive.File()
          ..name = name
          ..parents = [folderId]
          ..mimeType = mimeType
          ..appProperties = {'sourceMd5': md5},
        uploadMedia: drive.Media(original.openRead(), bytes, contentType: mimeType),
        $fields: 'id,md5Checksum,size,trashed',
      );
      if (uploaded.id == null) throw StateError('Google Drive did not return a file ID.');
      if (!cloudCopyMatches(
        localMd5: md5,
        localBytes: bytes,
        remoteMd5: uploaded.md5Checksum,
        remoteBytes: int.tryParse(uploaded.size ?? ''),
        remoteTrashed: uploaded.trashed,
      )) {
        // Do not mark this asset as backed up; next run will recheck Drive.
        throw StateError('Uploaded file checksum/size did not match. Original is safe.');
      }
      return uploaded.id!;
    });
  }

  Future<bool> verifyRemote(String fileId, String md5, int bytes) async {
    try {
      return await _api((api) async {
        final remote = await api.files.get(
          fileId, $fields: 'id,md5Checksum,size,trashed',
        ) as drive.File;
        return cloudCopyMatches(
          localMd5: md5,
          localBytes: bytes,
          remoteMd5: remote.md5Checksum,
          remoteBytes: int.tryParse(remote.size ?? ''),
          remoteTrashed: remote.trashed,
        );
      });
    } on drive.DetailedApiRequestError catch (e) {
      if (e.status == 404) return false;
      rethrow;
    }
  }
}
