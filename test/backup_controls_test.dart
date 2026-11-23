import 'package:cloud_photo_vault/core/auto_backup.dart';
import 'package:cloud_photo_vault/core/models.dart';
import 'package:cloud_photo_vault/core/vault_controller.dart';
import 'package:cloud_photo_vault/ui/vault_home.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _TestPreferences extends VaultPreferences {
  @override
  Future<String> get lastRun async => 'Never';
}

class _TestController extends VaultController {
  @override
  VaultPreferences get settings => _preferences;

  final _preferences = _TestPreferences();
}

void main() {
  testWidgets('cleanup shortcut only selects the last selected batch', (
    tester,
  ) async {
    final controller = _TestController()
      ..lastSelectedBatch = {'recent'}
      ..readyForCleanup = ['recent', 'older', 'oldest']
          .map(
            (id) => BackupRecord(
              assetId: id,
              accountId: 'account',
              driveFileId: 'drive-$id',
              md5: 'example',
              bytes: 1024,
              originalName: '$id.jpg',
              verifiedAt: DateTime.utc(2026),
            ),
          )
          .toList();

    await tester.pumpWidget(
      MaterialApp(home: VaultHome(controller: controller)),
    );
    await tester.tap(find.text('Clean up'));
    await tester.pumpAndSettle();
    expect(find.text('0 selected · 3 available for review'), findsOneWidget);

    await tester.tap(find.text('Select last backup batch (1)'));
    await tester.pumpAndSettle();
    expect(find.text('1 selected · 3 available for review'), findsOneWidget);

    await tester.tap(find.text('Review & move 1 to Bin'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 items selected.'), findsOneWidget);
    expect(find.text('Keep originals'), findsOneWidget);
  });

  testWidgets('Photos keeps a determinate progress bar for selected backup', (
    tester,
  ) async {
    final controller = _TestController()
      ..backingUp = true
      ..progress = const BackupProgress(
        done: 14,
        total: 104,
        uploaded: 12,
        skipped: 2,
        errors: 0,
        currentFile: 'older-photo.jpg',
      );

    await tester.pumpWidget(
      MaterialApp(home: VaultHome(controller: controller)),
    );
    await tester.tap(find.text('Photos'));
    await tester.pumpAndSettle();

    expect(find.text('14 of 104 checked · 12 uploaded'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      14 / 104,
    );
  });
}
