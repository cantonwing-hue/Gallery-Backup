import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';

import 'auto_backup.dart';
import 'backup_database.dart';
import 'drive_gateway.dart';
import 'media_backup.dart';
import 'models.dart';

class VaultController extends ChangeNotifier {
  final DriveGateway drive = DriveGateway();
  final BackupDatabase database = BackupDatabase();
  final VaultPreferences settings = VaultPreferences();
  late final BackupEngine engine = BackupEngine(database: database, drive: drive);

  bool busy = false;
  bool backingUp = false;
  bool autoEnabled = false;
  bool wifiOnly = true;
  String notice = '';
  BackupProgress? progress;
  int totalPhotos = 0;
  int matchingPhotos = 0;
  bool oldestFirst = false;
  DateTime? galleryDate;
  bool loadingPhotos = false;
  Set<String> lastSelectedBatch = const {};
  int backedUp = 0;
  List<AssetEntity> assets = [];
  List<BackupRecord> readyForCleanup = [];
  final Map<String, AssetEntity> _selectedAssets = {};
  Iterable<String> get selected => _selectedAssets.keys;
  bool _cancel = false;
  int _page = 0;
  bool _hasMore = true;

  String? get email => drive.account?.email;
  bool get connected => drive.account != null;
  bool get canLoadMore => _hasMore && !loadingPhotos;
  String get backupFolder => drive.backupFolder;

  FilterOptionGroup get _galleryFilter {
    final date = galleryDate;
    return FilterOptionGroup(
      orders: [OrderOption(asc: oldestFirst)],
      createTimeCond: date == null ? null : DateTimeCond(
        min: DateTime(date.year, date.month),
        max: DateTime(date.year, date.month + 1).subtract(const Duration(milliseconds: 1)),
      ),
    );
  }

  Future<void> changeGallery({required bool oldest, DateTime? month}) async {
    if (busy || loadingPhotos || backingUp) return;
    oldestFirst = oldest;
    galleryDate = month;
    await scanPhotos();
  }

  Future<void> changeBackupFolder(String name) async {
    if (busy || backingUp || name.trim().isEmpty) return;
    busy = true;
    notifyListeners();
    try {
      final folder = name.trim();
      await settings.setBackupFolder(folder);
      drive.backupFolder = folder;
      notice = 'New uploads will go to My Drive / $folder';
    } catch (error) {
      notice = 'Could not save the Drive folder: $error';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> initialize() async {
    busy = true;
    notifyListeners();
    try {
      autoEnabled = await settings.autoEnabled;
      wifiOnly = await settings.wifiOnly;
      drive.backupFolder = await settings.backupFolder;
      try {
        await drive.restore();
      } catch (error) {
        notice = 'Google sign-in setup needed: $error';
      }
      if (connected) await refreshCounts();
      if (autoEnabled) {
        await configureBackgroundBackup(enabled: true, wifiOnly: wifiOnly);
      }
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> connect() async {
    busy = true;
    notifyListeners();
    try {
      await drive.connectInteractively();
      notice = 'Connected to ${drive.account!.email}';
      await refreshCounts();
    } catch (error) {
      notice = 'Google connection failed: $error';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    await drive.disconnect();
    _selectedAssets.clear();
    lastSelectedBatch = const {};
    readyForCleanup.clear();
    backedUp = 0;
    autoEnabled = false;
    await settings.setAuto(false);
    await configureBackgroundBackup(enabled: false, wifiOnly: wifiOnly);
    notifyListeners();
  }

  Future<void> scanPhotos() async {
    if (busy || loadingPhotos || backingUp) return;
    busy = true;
    notice = '';
    notifyListeners();
    try {
      if (!await requestPhotoAccess()) {
        notice = 'Please allow photos and videos access to scan your gallery.';
        return;
      }
      totalPhotos = await PhotoManager.getAssetCount();
      matchingPhotos = galleryDate == null ? totalPhotos :
          await PhotoManager.getAssetCount(filterOption: _galleryFilter);
      assets.clear();
      _page = 0;
      _hasMore = true;
      await loadMore();
      if (notice.isEmpty) notice = '$matchingPhotos photos/videos match this view';
    } catch (error) {
      notice = 'Unable to scan photos: $error';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> loadMore() async {
    if (!_hasMore || loadingPhotos) return;
    loadingPhotos = true;
    notifyListeners();
    try {
      final next = await PhotoManager.getAssetListPaged(
        page: _page, pageCount: 80, filterOption: _galleryFilter,
      );
      _page++;
      assets.addAll(next);
      _hasMore = next.isNotEmpty && assets.length < matchingPhotos;
    } catch (error) {
      _hasMore = false;
      notice = 'Photo loading issue: $error';
    } finally {
      loadingPhotos = false;
      notifyListeners();
    }
  }

  void toggleSelect(AssetEntity asset) {
    if (_selectedAssets.remove(asset.id) == null) {
      _selectedAssets[asset.id] = asset;
    }
    notifyListeners();
  }

  void selectVisible() {
    _selectedAssets.addEntries(assets.map((asset) => MapEntry(asset.id, asset)));
    notifyListeners();
  }

  void clearSelected() {
    _selectedAssets.clear();
    notifyListeners();
  }

  void cancelBackup() {
    _cancel = true;
    notice = 'Stopping after the current file…';
    notifyListeners();
  }

  Future<void> startBackup({bool selectedOnly = false}) async {
    if (backingUp || busy) return;
    backingUp = true;
    _cancel = false;
    progress = null;
    notice = '';
    notifyListeners();
    try {
      final list = selectedOnly
          ? _selectedAssets.values.toList()
          : null;
      if (selectedOnly && list!.isEmpty) {
        notice = 'Select photos in the Photos tab first.';
        return;
      }
      lastSelectedBatch = const {};
      final result = await engine.run(
        selected: list,
        wifiOnly: wifiOnly,
        cancelled: () => _cancel,
        onProgress: (p) { progress = p; notifyListeners(); },
      );
      if (list != null) {
        lastSelectedBatch = list.take(result.done).map((asset) => asset.id).toSet();
      }
      notice = 'Finished: ${result.uploaded} uploaded, ${result.skipped} already safe, ${result.errors} errors';
      await settings.setLastRun(notice);
      _selectedAssets.clear();
      await refreshCounts();
    } catch (error) {
      notice = 'Backup stopped: $error';
    } finally {
      backingUp = false;
      notifyListeners();
    }
  }

  Future<void> refreshCounts() async {
    final id = drive.account?.id;
    if (id == null) return;
    backedUp = await database.countVerified(id);
    readyForCleanup = await database.pendingCleanup(id);
    notifyListeners();
  }

  Future<int> trashRecords(List<BackupRecord> records) async {
    if (busy || backingUp) return 0;
    busy = true;
    notifyListeners();
    try {
      // 40 at a time avoids an enormous native permission confirmation request.
      var moved = 0;
      for (var offset = 0; offset < records.length; offset += 40) {
        final chunk = records.skip(offset).take(40).toList();
        moved += (await engine.moveVerifiedToTrash(chunk)).length;
      }
      notice = '$moved verified items moved to Android Bin';
      await refreshCounts();
      return moved;
    } catch (error) {
      notice = 'No further items moved: $error';
      await refreshCounts();
      return 0;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> changeAuto(bool enabled) async {
    autoEnabled = enabled;
    await settings.setAuto(enabled);
    await configureBackgroundBackup(enabled: enabled, wifiOnly: wifiOnly);
    notice = enabled ? 'Auto backup is scheduled. Android decides the actual run time.' : 'Automatic backup disabled';
    notifyListeners();
  }

  Future<void> changeWifi(bool enabled) async {
    wifiOnly = enabled;
    await settings.setWifiOnly(enabled);
    if (autoEnabled) {
      await configureBackgroundBackup(enabled: true, wifiOnly: enabled);
    }
    notifyListeners();
  }
}
