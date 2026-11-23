import 'package:cloud_photo_vault/core/media_backup.dart';
import 'package:cloud_photo_vault/core/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_manager/photo_manager.dart';

void main() {
  group('remote verification gating trash', () {
    test('valid same size and MD5 is allowed', () {
      expect(cloudCopyMatches(
        localMd5: 'ABC', localBytes: 1024, remoteMd5: 'abc',
        remoteBytes: 1024, remoteTrashed: false,
      ), isTrue);
    });
    test('size mismatch blocks', () {
      expect(cloudCopyMatches(
        localMd5: 'abc', localBytes: 1024, remoteMd5: 'abc',
        remoteBytes: 1000, remoteTrashed: false,
      ), isFalse);
    });
    test('checksum mismatch blocks', () {
      expect(cloudCopyMatches(
        localMd5: 'abc', localBytes: 1024, remoteMd5: 'bad',
        remoteBytes: 1024, remoteTrashed: false,
      ), isFalse);
    });
    test('missing checksum blocks', () {
      expect(cloudCopyMatches(
        localMd5: 'abc', localBytes: 1024, remoteMd5: null,
        remoteBytes: 1024, remoteTrashed: false,
      ), isFalse);
    });
    test('missing trashed flag blocks', () {
      expect(cloudCopyMatches(
        localMd5: 'abc', localBytes: 1024, remoteMd5: 'abc',
        remoteBytes: 1024, remoteTrashed: null,
      ), isFalse);
    });
    test('trashed Drive copy blocks', () {
      expect(cloudCopyMatches(
        localMd5: 'abc', localBytes: 1024, remoteMd5: 'abc',
        remoteBytes: 1024, remoteTrashed: true,
      ), isFalse);
    });
  });
  test('file MIME mapping', () {
    expect(guessMime('holiday.heic', AssetType.image), 'image/heic');
    expect(guessMime('reel.mp4', AssetType.video), 'video/mp4');
  });
}
