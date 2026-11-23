import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'models.dart';

class BackupDatabase {
  Database? _db;

  Future<Database> get _database async {
    if (_db != null) return _db!;
    _db = await openDatabase(
      p.join(await getDatabasesPath(), 'cloud_photo_vault_v1.db'),
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE backups (
            asset_id TEXT NOT NULL,
            account_id TEXT NOT NULL,
            drive_file_id TEXT NOT NULL,
            md5 TEXT NOT NULL,
            bytes INTEGER NOT NULL,
            original_name TEXT NOT NULL,
            verified_at INTEGER NOT NULL,
            moved_to_trash INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (asset_id, account_id)
          )
        ''');
        await db.execute('CREATE INDEX backups_account_idx ON backups(account_id, moved_to_trash)');
        await db.execute('''
          CREATE TABLE run_lock (
            lock_name TEXT PRIMARY KEY,
            holder TEXT NOT NULL,
            expires_at INTEGER NOT NULL
          )
        ''');
      },
    );
    return _db!;
  }

  Future<BackupRecord?> get(String assetId, String accountId) async {
    final results = await (await _database).query(
      'backups',
      where: 'asset_id = ? AND account_id = ?',
      whereArgs: [assetId, accountId],
      limit: 1,
    );
    return results.isEmpty ? null : BackupRecord.fromMap(results.first);
  }

  Future<void> save(BackupRecord record) async {
    await (await _database).insert(
      'backups', record.toMap(), conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> markTrashed(String assetId, String accountId) async {
    await (await _database).update(
      'backups', {'moved_to_trash': 1},
      where: 'asset_id = ? AND account_id = ?',
      whereArgs: [assetId, accountId],
    );
  }

  Future<List<BackupRecord>> pendingCleanup(String accountId, {int limit = 300}) async {
    final rows = await (await _database).query(
      'backups',
      where: 'account_id = ? AND moved_to_trash = 0',
      whereArgs: [accountId],
      orderBy: 'verified_at DESC',
      limit: limit,
    );
    return rows.map(BackupRecord.fromMap).toList();
  }

  Future<int> countVerified(String accountId) async {
    final result = await (await _database).rawQuery(
      'SELECT COUNT(*) AS n FROM backups WHERE account_id = ?', [accountId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<bool> acquireRunLock(String holder) async {
    final db = await _database;
    final now = DateTime.now().millisecondsSinceEpoch;
    return db.transaction((txn) async {
      await txn.delete('run_lock', where: 'expires_at < ?', whereArgs: [now]);
      final rows = await txn.query('run_lock', where: 'lock_name = ?', whereArgs: ['backup']);
      if (rows.isNotEmpty) return false;
      await txn.insert('run_lock', {
        'lock_name': 'backup', 'holder': holder,
        'expires_at': now + const Duration(minutes: 30).inMilliseconds,
      });
      return true;
    });
  }

  Future<void> refreshRunLock(String holder) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await (await _database).update('run_lock',
      {'expires_at': now + const Duration(minutes: 30).inMilliseconds},
      where: 'lock_name = ? AND holder = ?', whereArgs: ['backup', holder],
    );
  }

  Future<void> releaseRunLock(String holder) async {
    await (await _database).delete('run_lock',
      where: 'lock_name = ? AND holder = ?', whereArgs: ['backup', holder],
    );
  }
}
