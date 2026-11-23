import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:photo_manager/photo_manager.dart';

import 'backup_database.dart';
import 'drive_gateway.dart';
import 'models.dart';

const _pageSize = 80;

Future<bool> requestPhotoAccess({bool allowPrompt = true}) async {
  final state = allowPrompt
      ? await PhotoManager.requestPermissionExtend()
      : await PhotoManager.getPermissionState(
          requestOption: const PermissionRequestOption(),
        );
  return state == PermissionState.authorized || state == PermissionState.limited;
}

String guessMime(String fileName, AssetType type) {
  final extension = fileName.split('.').last.toLowerCase();
  switch (extension) {
    case 'jpg':
    case 'jpeg': return 'image/jpeg';
    case 'heic': return 'image/heic';
    case 'heif': return 'image/heif';
    case 'png': return 'image/png';
    case 'webp': return 'image/webp';
    case 'gif': return 'image/gif';
    case 'dng': return 'image/x-adobe-dng';
    case 'mp4': return 'video/mp4';
    case 'mov': return 'video/quicktime';
    case 'mkv': return 'video/x-matroska';
    default: return type == AssetType.video ? 'video/mp4' : 'application/octet-stream';
  }
}

Future<String> fileMd5(File file) async => (await md5.bind(file.openRead()).first).toString();

Future<bool> isOnUnmeteredNetwork() async {
  final modes = await Connectivity().checkConnectivity();
  return modes.contains(ConnectivityResult.wifi) || modes.contains(ConnectivityResult.ethernet);
}

class BackupEngine {
  final BackupDatabase database;
  final DriveGateway drive;

  BackupEngine({required this.database, required this.drive});

  Future<BackupRecord?> backupOne(AssetEntity asset) async {
    if (asset.type != AssetType.image && asset.type != AssetType.video) return null;
    final account = drive.account;
    if (account == null) throw StateError('Connect Google Drive first.');

    final original = await asset.originFile;
    if (original == null || !await original.exists()) {
      throw StateError('Cannot access the original file.');
    }
    final size = await original.length();
    if (size == 0) throw StateError('Empty file: skipped for safety.');
    final hash = await fileMd5(original);
    final previous = await database.get(asset.id, account.id);
    if (previous != null && previous.md5 == hash && previous.bytes == size) {
      // Reverify the remote file; never trust a stale local database entry.
      if (await drive.verifyRemote(previous.driveFileId, hash, size)) return null;
    }

    final name = await asset.titleAsync;
    final remoteId = await drive.uploadOrFind(
      original: original,
      bytes: size,
      md5: hash,
      name: name.isEmpty ? 'photo_${asset.id}' : name,
      mimeType: guessMime(name, asset.type),
      takenAt: asset.createDateTime,
    );
    // A second independent GET avoids relying solely on upload response metadata.
    if (!await drive.verifyRemote(remoteId, hash, size)) {
      throw StateError('Remote re-verification failed. The phone original was kept.');
    }
    final record = BackupRecord(
      assetId: asset.id, accountId: account.id, driveFileId: remoteId,
      md5: hash, bytes: size, originalName: name,
      verifiedAt: DateTime.now().toUtc(),
    );
    await database.save(record);
    return record;
  }

  /// Returns a summary. Errors on individual files never mark them as backed up.
  /// Only one engine (foreground or background) may run at a time.
  Future<BackupProgress> run({
    List<AssetEntity>? selected,
    int? maximum,
    int startPage = 0,
    bool wifiOnly = true,
    bool allowPermissionPrompt = true,
    bool Function()? cancelled,
    void Function(BackupProgress)? onProgress,
  }) async {
    if (drive.account == null) throw StateError('Connect Google Drive first.');
    if (wifiOnly && !await isOnUnmeteredNetwork()) {
      throw StateError('Wi-Fi only is on. Connect to Wi-Fi or change Settings.');
    }
    if (!await requestPhotoAccess(allowPrompt: allowPermissionPrompt)) {
      throw StateError('Please grant photo/video access in Android settings.');
    }
    final holder = '${DateTime.now().microsecondsSinceEpoch}';
    if (!await database.acquireRunLock(holder)) {
      throw StateError('A backup is already running.');
    }

    var done = 0, uploaded = 0, skipped = 0, errors = 0;
    try {
      final allCount = selected != null ? selected.length : await PhotoManager.getAssetCount();
      // Background worker visits the next 50-item page on each run, rather
      // than getting stuck rescanning the same first 50 images forever.
      final pageSize = maximum == null ? _pageSize : maximum.clamp(1, _pageSize);
      var total = selected?.length ?? (allCount - startPage * pageSize).clamp(0, allCount);
      if (maximum != null && maximum < total) total = maximum;
      var nextPage = (selected == null && total == 0) ? 0 : startPage;
      BackupProgress status(String name) => BackupProgress(
        done: done, total: total, uploaded: uploaded,
        skipped: skipped, errors: errors, currentFile: name,
        nextPage: nextPage,
      );

      onProgress?.call(status('Preparing files'));
      Future<void> process(AssetEntity asset) async {
        if (cancelled?.call() == true) return;
        await database.refreshRunLock(holder);
        final title = asset.title ?? asset.id;
        onProgress?.call(status(title));
        try {
          final record = await backupOne(asset);
          if (record == null) { skipped++; } else { uploaded++; }
        } catch (_) {
          // Individual file failures are kept safe for a future retry.
          errors++;
        } finally {
          done++;
          onProgress?.call(status(done == total ? 'Finishing backup' : title));
        }
      }

      if (selected != null) {
        for (final asset in selected) {
          if (cancelled?.call() == true || (maximum != null && done >= maximum)) break;
          await process(asset);
        }
      } else {
        var page = startPage;
        while (done < total && cancelled?.call() != true) {
          final assets = await PhotoManager.getAssetListPaged(
            page: page++, pageCount: pageSize,
          );
          if (assets.isEmpty) {
            nextPage = 0;
            break;
          }
          for (final asset in assets) {
            if (done >= total || cancelled?.call() == true) break;
            await process(asset);
          }
          nextPage = page * pageSize >= allCount ? 0 : page;
        }
      }
      return status('Completed');
    } finally {
      await database.releaseRunLock(holder);
    }
  }

  /// This is intentionally never called from background tasks.
  /// Verify BOTH the current original bytes and the remote Drive copy immediately
  /// before calling Android's system Move to Trash confirmation dialog.
  Future<List<String>> moveVerifiedToTrash(List<BackupRecord> records) async {
    final account = drive.account;
    if (account == null) throw StateError('Connect Google Drive first.');
    if (!await requestPhotoAccess()) throw StateError('Photo library access denied.');

    final approved = <AssetEntity>[];
    for (final record in records) {
      if (record.accountId != account.id || record.movedToTrash) continue;
      final asset = await AssetEntity.fromId(record.assetId);
      if (asset == null || asset.isTrashed) continue;
      final original = await asset.originFile;
      if (original == null || !await original.exists()) continue;
      if (await original.length() != record.bytes) continue;
      if (await fileMd5(original) != record.md5) continue;
      if (!await drive.verifyRemote(record.driveFileId, record.md5, record.bytes)) continue;
      approved.add(asset);
    }
    if (approved.isEmpty) return [];

    // Android 11+ system UI asks the user to approve moving these items to Bin.
    // No permanent delete API is used anywhere in this project.
    final movedIds = await PhotoManager.editor.android.moveToTrash(approved);
    for (final id in movedIds) {
      await database.markTrashed(id, account.id);
    }
    return movedIds;
  }
}
