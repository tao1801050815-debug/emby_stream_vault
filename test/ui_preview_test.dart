import 'dart:io';
import 'package:emby_stream_vault/core/models/media_item.dart';
import 'package:emby_stream_vault/core/models/site_config.dart';
import 'package:emby_stream_vault/core/providers/app_providers.dart';
import 'package:emby_stream_vault/core/storage/settings_repository.dart';
import 'package:emby_stream_vault/core/theme/emby_theme.dart';
import 'package:emby_stream_vault/features/library/library_home_page.dart';
import 'package:emby_stream_vault/features/library/media_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 真实 UI 预览截图生成测试（在 GitHub Actions 中自动渲染高清 PNG 并附到 Release 说明里）
Future<void> _loadRealFonts() async {
  // 1. 加载 Material Icons 字体，保证所有图标真实渲染
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null) {
    final iconFont = File(
      '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (iconFont.existsSync()) {
      final loader = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.sublistView(iconFont.readAsBytesSync())));
      await loader.load();
    }
  }

  // 2. 加载系统真实中文字体（Ubuntu 安装 fonts-noto-cjk 后可用），避免出现方块字
  const candidateFontPaths = [
    '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
    '/usr/share/fonts/noto-cjk/NotoSansCJK-Regular.ttc',
    '/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc',
    '/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc',
  ];
  for (final p in candidateFontPaths) {
    final f = File(p);
    if (f.existsSync()) {
      final bytes = ByteData.sublistView(f.readAsBytesSync());
      final robotoLoader = FontLoader('Roboto')..addFont(Future.value(bytes));
      await robotoLoader.load();
      break;
    }
  }
}

List<MediaItem> _demoItems() => const [
      MediaItem(
        id: 'missav_MIMK-173_uncensored',
        code: 'MIMK-173',
        title: '真人版超级作弊任务：你能成功完成吗？无码流出特别版',
        actors: ['三上悠亚', '深田咏美'],
        tags: ['无码流出', '中出', '巨乳', '中文字幕'],
        studio: 'Moodyz',
        personalRating: 5.0,
        publicRating: 4.25,
        publicRatingSource: 'JavDB',
        cumCount: 6,
        isFavorite: true,
        sourceSite: 'missav',
        sourceUrl: 'https://missav.ws/dm18/cn/mimk-173-uncensored-leak',
        lastPositionSec: 1800,
        durationSec: 4200,
        updatedAtMs: 1700000010000,
      ),
      MediaItem(
        id: 'missav_MIMK-134',
        code: 'MIMK-134',
        title: '实写版 邻家大姐姐的秘密诱惑 中文字幕',
        actors: ['河北彩花'],
        tags: ['中出', '单体作品', '中文字幕'],
        studio: 'Moodyz',
        personalRating: 4.5,
        publicRating: 4.30,
        publicRatingSource: 'JavDB',
        cumCount: 4,
        isFavorite: true,
        sourceSite: 'missav',
        sourceUrl: 'https://missav.ws/cn/mimk-134',
        updatedAtMs: 1700000009000,
      ),
      MediaItem(
        id: 'hanime1_HN-8821',
        code: 'HN-8821',
        title: '异世界后宫学院 第 02 集 无修高清版',
        actors: ['声优A'],
        tags: ['后宫', '中出', '无码'],
        personalRating: 4.0,
        publicRating: 4.60,
        publicRatingSource: 'JavDB',
        cumCount: 3,
        isFavorite: true,
        sourceSite: 'hanime1',
        sourceUrl: 'https://hanime1.me/watch?v=8821',
        updatedAtMs: 1700000008000,
      ),
      MediaItem(
        id: 'missav_SSIS-001',
        code: 'SSIS-001',
        title: '极上美少女 4K 超清限定版',
        actors: ['三上悠亚'],
        tags: ['单体作品', '巨乳'],
        personalRating: 4.5,
        publicRating: 4.42,
        publicRatingSource: 'JavDB',
        cumCount: 2,
        isFavorite: true,
        sourceSite: 'missav',
        updatedAtMs: 1700000007000,
      ),
      MediaItem(
        id: 'pornhub_PH-9A2B1C',
        code: 'PH-9A2B1C',
        title: '4K Private Studio Session',
        actors: ['Eva Elfie'],
        tags: ['欧美', '4K'],
        personalRating: 4.0,
        cumCount: 1,
        isFavorite: true,
        sourceSite: 'pornhub',
        updatedAtMs: 1700000006000,
      ),
      MediaItem(
        id: 'missav_IPX-811',
        code: 'IPX-811',
        title: '温泉旅行独占纪录 无码流出',
        actors: ['相泽南'],
        tags: ['无码流出', '温泉', '中出'],
        personalRating: 5.0,
        publicRating: 4.55,
        publicRatingSource: 'JavDB',
        cumCount: 5,
        isFavorite: true,
        sourceSite: 'missav',
        updatedAtMs: 1700000005000,
      ),
      MediaItem(
        id: 'hanime1_HN-9012',
        code: 'HN-9012',
        title: '纯爱后宫物语 OVA 完结篇',
        tags: ['后宫', '纯爱'],
        personalRating: 4.0,
        cumCount: 2,
        isFavorite: true,
        sourceSite: 'hanime1',
        updatedAtMs: 1700000004000,
      ),
      MediaItem(
        id: 'xhamster_XH-7788',
        code: 'XH-7788',
        title: 'Late Night Exclusive Collection',
        tags: ['欧美', '后宫'],
        personalRating: 3.5,
        cumCount: 0,
        isFavorite: true,
        sourceSite: 'xhamster',
        updatedAtMs: 1700000003000,
      ),
      MediaItem(
        id: 'missav_PRED-556',
        code: 'PRED-556',
        title: '第 2 页演示影片 · 职场秘密',
        actors: ['山岸逢花'],
        tags: ['中出', 'OL'],
        personalRating: 4.5,
        publicRating: 4.18,
        publicRatingSource: 'JavDB',
        cumCount: 1,
        isFavorite: true,
        sourceSite: 'missav',
        updatedAtMs: 1700000002000,
      ),
    ];

LibraryTagFacets _demoFacets() => const LibraryTagFacets(
      sourceTags: [
        MapEntry('missav', 5),
        MapEntry('hanime1', 2),
        MapEntry('pornhub', 1),
        MapEntry('xhamster', 1),
      ],
      actorTags: [
        MapEntry('三上悠亚', 2),
        MapEntry('深田咏美', 1),
        MapEntry('河北彩花', 1),
        MapEntry('相泽南', 1),
      ],
      contentTags: [
        MapEntry('中出', 5),
        MapEntry('后宫', 3),
        MapEntry('无码流出', 2),
        MapEntry('巨乳', 2),
        MapEntry('中文字幕', 2),
        MapEntry('单体作品', 2),
      ],
    );

Widget _wrapPreviewApp({
  required Widget home,
  required String layoutMode,
}) {
  final demoItems = _demoItems();
  final repo = SettingsRepository();
  return ProviderScope(
    overrides: [
      siteProfilesProvider.overrideWith(
        (_) => SiteProfilesNotifier(repo, autoLoad: false),
      ),
      appPreferencesProvider.overrideWith(
        (_) => AppPreferencesNotifier(
          repo,
          initial: AppPreferences(libraryLayoutMode: layoutMode),
          autoLoad: false,
        ),
      ),
      mediaLibraryProvider.overrideWith(
        (ref) => MediaLibraryNotifier(
          ref.watch(libraryFilterProvider),
          javdbBaseUrl: 'https://javdb.com',
          initialState: AsyncValue.data(demoItems),
          autoLoad: false,
        ),
      ),
      bookmarksProvider.overrideWith(
        (_) => BookmarksNotifier('全部', autoLoad: false),
      ),
      libraryTagFacetsProvider.overrideWith((_) async => _demoFacets()),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: EmbyTheme.darkTheme(),
      home: home,
    ),
  );
}

void main() {
  setUpAll(() async {
    await _loadRealFonts();
  });

  testWidgets('render UI previews for GitHub Release', (tester) async {
    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // 1. MissAV 双列并排主页（8 部分页 + 四象限徽章 + 计数微缩图标）
    await tester.pumpWidget(
      _wrapPreviewApp(home: const LibraryHomePage(), layoutMode: 'missav'),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/preview_1_home_missav_grid.png'),
    );

    // 2. Pornhub 单列宽卡主页
    await tester.pumpWidget(
      _wrapPreviewApp(home: const LibraryHomePage(), layoutMode: 'pornhub'),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/preview_2_home_pornhub_wide.png'),
    );

    // 3. 点击「标签筛选」弹出三合一筛选面板（来源 + 女优 + 标签）
    await tester.tap(find.text('标签筛选'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/preview_3_tag_filter_sheet.png'),
    );

    // 4. 影片详情页（来源徽章、无码角标、射过次数微缩图标、可点女优与标签）
    await tester.pumpWidget(
      _wrapPreviewApp(
        home: MediaDetailPage(initialItem: _demoItems().first),
        layoutMode: 'missav',
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/preview_4_media_detail.png'),
    );
  });
}
