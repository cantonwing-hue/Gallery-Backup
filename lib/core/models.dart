class BackupRecord {
  final String assetId;
  final String accountId;
  final String driveFileId;
  final String md5;
  final int bytes;
  final String originalName;
  final DateTime verifiedAt;
  final bool movedToTrash;

  const BackupRecord({
    required this.assetId,
    required this.accountId,
    required this.driveFileId,
    required this.md5,
    required this.bytes,
    required this.originalName,
    required this.verifiedAt,
    this.movedToTrash = false,
  });

  Map<String, Object?> toMap() => {
    'asset_id': assetId,
    'account_id': accountId,
    'drive_file_id': driveFileId,
    'md5': md5,
    'bytes': bytes,
    'original_name': originalName,
    'verified_at': verifiedAt.toUtc().millisecondsSinceEpoch,
    'moved_to_trash': movedToTrash ? 1 : 0,
  };

  factory BackupRecord.fromMap(Map<String, Object?> map) => BackupRecord(
    assetId: map['asset_id']! as String,
    accountId: map['account_id']! as String,
    driveFileId: map['drive_file_id']! as String,
    md5: map['md5']! as String,
    bytes: map['bytes']! as int,
    originalName: map['original_name']! as String,
    verifiedAt: DateTime.fromMillisecondsSinceEpoch(map['verified_at']! as int, isUtc: true),
    movedToTrash: (map['moved_to_trash']! as int) == 1,
  );
}

class BackupProgress {
  final int done;
  final int total;
  final int uploaded;
  final int skipped;
  final int errors;
  final String currentFile;
  final int nextPage;

  const BackupProgress({
    required this.done,
    required this.total,
    required this.uploaded,
    required this.skipped,
    required this.errors,
    required this.currentFile,
    this.nextPage = 0,
  });

  double get fraction => total == 0 ? 0 : done / total;
}

bool cloudCopyMatches({
  required String localMd5,
  required int localBytes,
  required String? remoteMd5,
  required int? remoteBytes,
  required bool? remoteTrashed,
}) =>
    remoteTrashed == false &&
    remoteMd5 != null &&
    remoteMd5.toLowerCase() == localMd5.toLowerCase() &&
    remoteBytes != null &&
    remoteBytes == localBytes;
