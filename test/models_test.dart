import 'package:emby_stream_vault/core/models/download_task.dart';
import 'package:emby_stream_vault/core/models/media_item.dart';
import 'package:emby_stream_vault/core/models/site_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MediaItem', () {
    test('toMap and fromMap preserve fields and watchProgress clamps safely', () {
      const item = MediaItem(
        id: 'missav_SSIS-001',
        code: 'SSIS-001',
        title: 'Demo Title',
        actors: ['Actor A', 'Actor B'],
        tags: ['HD', 'Subtitle'],
        personalRating: 4.5,
        isFavorite: true,
        isMetadataLocked: true,
        lastPositionSec: 300,
        durationSec: 1200,
        updatedAtMs: 1700000000000,
      );

      final restored = MediaItem.fromMap(item.toMap());
      expect(restored.id, item.id);
      expect(restored.code, 'SSIS-001');
      expect(restored.actors, ['Actor A', 'Actor B']);
      expect(restored.tags, ['HD', 'Subtitle']);
      expect(restored.isFavorite, isTrue);
      expect(restored.isMetadataLocked, isTrue);
      expect(restored.watchProgress, closeTo(0.25, 0.001));
    });
  });

  group('SiteProfile', () {
    test('buildSearchUrl normalizes trailing slash and encodes query', () {
      const site = SiteProfile(
        key: 'missav',
        name: 'MissAV',
        baseUrl: 'https://missav.ws/',
        searchTemplate: '{base}/cn/search/{query}',
        loginUrl: 'https://missav.ws/cn/login',
      );

      expect(
        site.buildSearchUrl('SSIS-001 中文'),
        'https://missav.ws/cn/search/SSIS-001%20%E4%B8%AD%E6%96%87',
      );
    });
  });

  group('DownloadTask', () {
    test('progress calculation and map roundtrip work as expected', () {
      const task = DownloadTask(
        id: 'dl_1',
        code: 'SSIS-001',
        title: 'Demo',
        streamUrl: 'https://example.com/playlist.m3u8',
        totalSegments: 100,
        downloadedSegments: 40,
        status: DownloadStatus.downloading,
        localDir: '/tmp/dl_1',
        createdAtMs: 1700000000000,
      );

      final restored = DownloadTask.fromMap(task.toMap());
      expect(restored.status, DownloadStatus.downloading);
      expect(restored.progress, closeTo(0.4, 0.001));
    });
  });
}
