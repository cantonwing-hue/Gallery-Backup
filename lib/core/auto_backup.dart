import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'backup_database.dart';
import 'drive_gateway.dart';
import 'media_backup.dart';

const _taskName = 'photoVaultPeriodicBackup';
const _uniqueName = 'photoVaultAuto';

class VaultPreferences {
  final SharedPreferencesAsync _prefs = SharedPreferencesAsync();

  Future<bool> get autoEnabled async => await _prefs.getBool('auto_enabled') ?? false;
  Future<bool> get wifiOnly async => await _prefs.getBool('wifi_only') ?? true;
  Future<String> get lastRun async => await _prefs.getString('last_run') ?? 'Never';
  Future<int> get nextAutoPage async => await _prefs.getInt('next_auto_page') ?? 0;
  Future<void> setNextAutoPage(int page) => _prefs.setInt('next_auto_page', page);

  Future<void> setAuto(bool enabled) => _prefs.setBool('auto_enabled', enabled);
  Future<void> setWifiOnly(bool enabled) => _prefs.setBool('wifi_only', enabled);
  Future<void> setLastRun(String value) => _prefs.setString('last_run', value);
}

@pragma('vm:entry-point')
void photoVaultDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    if (taskName != _taskName) return true;

    final settings = VaultPreferences();
    if (!await settings.autoEnabled) return true;
    try {
      final drive = DriveGateway();
      final account = await drive.restore();
      if (account == null) {
        await settings.setLastRun('Reconnect Google in the app to resume auto backup');
        return true; // User action is required: no background login dialog.
      }
      final result = await BackupEngine(database: BackupDatabase(), drive: drive).run(
        maximum: 50,
        startPage: await settings.nextAutoPage,
        wifiOnly: await settings.wifiOnly,
        allowPermissionPrompt: false,
      );
      await settings.setNextAutoPage(result.nextPage);
      await settings.setLastRun(
        'Background: ${result.uploaded} uploaded, ${result.errors} failed • ${DateTime.now().toLocal()}',
      );
      return result.errors == 0;
    } catch (error) {
      await settings.setLastRun('Auto backup paused: $error');
      // Retrying on temporary failures is best effort, not guaranteed timing.
      return false;
    }
  });
}

Future<void> configureBackgroundBackup({
  required bool enabled,
  required bool wifiOnly,
}) async {
  if (!enabled) {
    await Workmanager().cancelByUniqueName(_uniqueName);
    return;
  }
  await Workmanager().registerPeriodicTask(
    _uniqueName,
    _taskName,
    frequency: const Duration(hours: 6),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    constraints: Constraints(
      networkType: wifiOnly ? NetworkType.unmetered : NetworkType.connected,
      requiresBatteryNotLow: true,
    ),
  );
}
