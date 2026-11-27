import 'package:emby_stream_vault/core/models/download_task.dart';
import 'package:emby_stream_vault/core/models/media_item.dart';
import 'package:emby_stream_vault/core/models/site_config.dart';
import 'package:emby_stream_vault/core/services/web_metadata_extractor_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MediaItem', () {
    test('toMap and fromMap preserve fields including cumCount and uncensored',
        () {
      const item = MediaItem(
        id: 'missav_SSIS-001_uncensored',
        code: 'SSIS-001',
        title: 'Demo Title 无码流出',
        actors: ['Actor A', 'Actor B'],
        tags: ['中出', '无码流出'],
        personalRating: 4.5,
        publicRating: 4.3,
        publicRatingSource: 'JavDB',
        cumCount: 6,
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
      expect(restored.tags, ['中出', '无码流出']);
      expect(restored.cumCount, 6);
      expect(restored.isUncensored, isTrue);
      expect(restored.isFavorite, isTrue);
      expect(restored.isMetadataLocked, isTrue);
      expect(restored.watchProgress, closeTo(0.25, 0.001));
    });
  });

  group('WebMetadataExtractorService', () {
    test('buildMediaId distinguishes uncensored edition from standard edition',
        () {
      final normalId = WebMetadataExtractorService.buildMediaId(
        siteKey: 'missav',
        code: 'MIMK-173',
        sourceUrl: 'https://missav.ws/cn/mimk-173',
      );
      final uncId = WebMetadataExtractorService.buildMediaId(
        siteKey: 'missav',
        code: 'MIMK-173',
        sourceUrl: 'https://missav.ws/dm18/cn/mimk-173-uncensored-leak',
      );

      expect(normalId, 'missav_MIMK-173');
      expect(uncId, 'missav_MIMK-173_uncensored');
      expect(normalId == uncId, isFalse);
    });

    test('extractTagsFromHtml parses MissAV genre links', () {
      const html = '''
        <div>
          <a href="https://missav.ws/cn/genres/%E4%B8%AD%E5%87%BA">中出</a>
          <a href="https://missav.ws/cn/genres/%E5%B7%A8%E4%B9%B3">巨乳</a>
          <a href="/categories/creampie">#Creampie</a>
        </div>
      ''';
      final tags = WebMetadataExtractorService.extractTagsFromHtml(html);
      expect(tags, containsAll(['中出', '巨乳', 'Creampie']));
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
