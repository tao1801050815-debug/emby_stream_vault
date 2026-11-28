import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/bookmark.dart';
import '../models/download_task.dart';
import '../models/media_item.dart';
import '../models/site_config.dart';
import '../services/live_ai_subtitle_service.dart';
import '../services/m3u8_downloader_service.dart';
import '../services/rating_fetcher_service.dart';
import '../services/web_metadata_extractor_service.dart';
import '../storage/database_helper.dart';
import '../storage/settings_repository.dart';

final settingsRepositoryProvider = Provider((ref) => SettingsRepository());

/// 站点配置列表
final siteProfilesProvider =
    StateNotifierProvider<SiteProfilesNotifier, List<SiteProfile>>((ref) {
  return SiteProfilesNotifier(ref.read(settingsRepositoryProvider));
});

class SiteProfilesNotifier extends StateNotifier<List<SiteProfile>> {
  final SettingsRepository _repo;

  SiteProfilesNotifier(this._repo) : super(SiteProfile.defaults()) {
    _load();
  }

  Future<void> _load() async {
    final loaded = (await _repo.loadSites())
        .where((e) => e.key != 'ryxuxfoc')
        .toList();
    final existingKeys = loaded.map((e) => e.key).toSet();
    final missingDefaults = SiteProfile.defaults()
        .where((d) => !existingKeys.contains(d.key))
        .toList();
    state = [...loaded, ...missingDefaults];
  }

  Future<void> updateSite(SiteProfile updated) async {
    state = [
      for (final item in state)
        if (item.key == updated.key) updated else item,
    ];
    await _repo.saveSites(state);
  }

  Future<void> addSite(SiteProfile site) async {
    state = [
      ...state.where((e) => e.key != site.key),
      site,
    ];
    await _repo.saveSites(state);
  }

  Future<void> removeSite(String key) async {
    state = state.where((e) => e.key != key).toList();
    await _repo.saveSites(state);
  }

  Future<void> resetDefaults() async {
    state = SiteProfile.defaults();
    await _repo.saveSites(state);
  }
}

/// 播放器与浏览偏好
final appPreferencesProvider =
    StateNotifierProvider<AppPreferencesNotifier, AppPreferences>((ref) {
  return AppPreferencesNotifier(ref.read(settingsRepositoryProvider));
});

class AppPreferencesNotifier extends StateNotifier<AppPreferences> {
  final SettingsRepository _repo;

  AppPreferencesNotifier(this._repo) : super(const AppPreferences()) {
    _load();
  }

  Future<void> _load() async {
    state = await _repo.loadPreferences();
  }

  Future<void> update(AppPreferences next) async {
    state = next;
    await _repo.savePreferences(next);
  }
}

/// 媒体库筛选条件
class LibraryFilter {
  final bool onlyFavorites;
  final String searchQuery;
  final double minRating;
  final String sortBy;
  final Set<String> selectedSources; // 选中的来源标签（小写 key，如 missav / hanime1）
  final Set<String> selectedActors; // 选中的女优/演员标签
  final Set<String> selectedTags; // 选中的影片标签（如 中出 / 后宫 / 无码流出）

  const LibraryFilter({
    this.onlyFavorites = false,
    this.searchQuery = '',
    this.minRating = 0.0,
    this.sortBy = 'updatedAtMs',
    this.selectedSources = const {},
    this.selectedActors = const {},
    this.selectedTags = const {},
  });

  int get activeTagFilterCount =>
      selectedSources.length + selectedActors.length + selectedTags.length;

  /// 纯函数：按来源标签（OR）、女优标签（OR）与影片内容标签（AND）精确过滤列表
  List<MediaItem> applyTagFilters(List<MediaItem> items) {
    if (selectedSources.isEmpty &&
        selectedActors.isEmpty &&
        selectedTags.isEmpty) {
      return items;
    }
    final lowerSources = selectedSources.map((e) => e.toLowerCase()).toSet();
    final lowerActors = selectedActors.map((e) => e.toLowerCase()).toSet();
    final lowerTags = selectedTags.map((e) => e.toLowerCase()).toSet();

    return items.where((item) {
      if (lowerSources.isNotEmpty) {
        final site = item.sourceSite.trim().toLowerCase();
        final normalizedSite = site.isEmpty ? 'custom' : site;
        if (!lowerSources.contains(normalizedSite)) {
          return false;
        }
      }
      if (lowerActors.isNotEmpty) {
        final itemLowerActors =
            item.actors.map((a) => a.trim().toLowerCase()).toSet();
        final matchedAnyActor = lowerActors.any(itemLowerActors.contains);
        if (!matchedAnyActor) {
          return false;
        }
      }
      if (lowerTags.isNotEmpty) {
        final itemLowerTags =
            item.tags.map((t) => t.trim().toLowerCase()).toSet();
        for (final reqTag in lowerTags) {
          if (!itemLowerTags.contains(reqTag)) {
            return false;
          }
        }
      }
      return true;
    }).toList();
  }

  LibraryFilter copyWith({
    bool? onlyFavorites,
    String? searchQuery,
    double? minRating,
    String? sortBy,
    Set<String>? selectedSources,
    Set<String>? selectedActors,
    Set<String>? selectedTags,
  }) {
    return LibraryFilter(
      onlyFavorites: onlyFavorites ?? this.onlyFavorites,
      searchQuery: searchQuery ?? this.searchQuery,
      minRating: minRating ?? this.minRating,
      sortBy: sortBy ?? this.sortBy,
      selectedSources: selectedSources ?? this.selectedSources,
      selectedActors: selectedActors ?? this.selectedActors,
      selectedTags: selectedTags ?? this.selectedTags,
    );
  }
}

final libraryFilterProvider =
    StateProvider<LibraryFilter>((ref) => const LibraryFilter());

/// 全库来源、女优与内容标签聚合统计（不受当前筛选隐藏，方便随时切换）
class LibraryTagFacets {
  final List<MapEntry<String, int>> sourceTags; // (sourceKey, count)
  final List<MapEntry<String, int>> actorTags; // (actorName, count)
  final List<MapEntry<String, int>> contentTags; // (tagName, count)

  const LibraryTagFacets({
    this.sourceTags = const [],
    this.actorTags = const [],
    this.contentTags = const [],
  });
}

final libraryTagFacetsProvider = FutureProvider<LibraryTagFacets>((ref) async {
  // 监听影库变化以便增删影片后自动重新统计
  ref.watch(mediaLibraryProvider);
  final allItems = await DatabaseHelper.instance.getAllMediaItems();
  final sourceCounts = <String, int>{};
  final actorCounts = <String, int>{};
  final tagCounts = <String, int>{};

  for (final item in allItems) {
    final src = item.sourceSite.trim().toLowerCase();
    final key = src.isEmpty ? 'custom' : src;
    sourceCounts[key] = (sourceCounts[key] ?? 0) + 1;

    final seenActors = <String>{};
    for (final rawActor in item.actors) {
      final a = rawActor.trim();
      if (a.isNotEmpty && seenActors.add(a.toLowerCase())) {
        actorCounts[a] = (actorCounts[a] ?? 0) + 1;
      }
    }

    final seenTags = <String>{};
    for (final rawTag in item.tags) {
      final t = rawTag.trim();
      if (t.isNotEmpty && seenTags.add(t.toLowerCase())) {
        tagCounts[t] = (tagCounts[t] ?? 0) + 1;
      }
    }
  }

  final sortedSources = sourceCounts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final sortedActors = actorCounts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final sortedTags = tagCounts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  return LibraryTagFacets(
    sourceTags: sortedSources,
    actorTags: sortedActors,
    contentTags: sortedTags,
  );
});

/// 本地媒体库状态
final mediaLibraryProvider =
    StateNotifierProvider<MediaLibraryNotifier, AsyncValue<List<MediaItem>>>(
        (ref) {
  final filter = ref.watch(libraryFilterProvider);
  final sites = ref.watch(siteProfilesProvider);
  final javdbUrl = sites
      .where((s) => s.key == 'javdb')
      .map((s) => s.baseUrl)
      .firstOrNull;
  return MediaLibraryNotifier(
    filter,
    javdbBaseUrl: javdbUrl ?? 'https://javdb.com',
  );
});

class MediaLibraryNotifier extends StateNotifier<AsyncValue<List<MediaItem>>> {
  final LibraryFilter _filter;
  final String _javdbBaseUrl;
  bool _autoBackfilledRatings = false;

  MediaLibraryNotifier(
    this._filter, {
    required String javdbBaseUrl,
  })  : _javdbBaseUrl = javdbBaseUrl,
        super(const AsyncValue.loading()) {
    refresh();
  }

  Future<void> refresh() async {
    try {
      final rawItems = await DatabaseHelper.instance.getAllMediaItems(
        onlyFavorites: _filter.onlyFavorites,
        searchQuery: _filter.searchQuery,
        minRating: _filter.minRating,
        sortBy: _filter.sortBy,
      );
      final items = _filter.applyTagFilters(rawItems);
      state = AsyncValue.data(items);

      // 首次加载时自动为缺少网评的已收藏影片在后台静默补齐评分
      if (!_autoBackfilledRatings) {
        _autoBackfilledRatings = true;
        final missing = items
            .where((i) =>
                i.publicRating <= 0 &&
                RatingFetcherService.instance.isStandardCode(i.code))
            .take(16)
            .toList();
        if (missing.isNotEmpty) {
          _fetchPublicRatingInBackground(missing);
        }
      }
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// 手动一键批量刷新所有缺网评（或指定列表）的影片评分
  Future<int> refreshMissingRatings(List<MediaItem> targets) async {
    var successCount = 0;
    for (final item in targets) {
      if (!RatingFetcherService.instance.isStandardCode(item.code)) continue;
      final res = await RatingFetcherService.instance.fetchPublicRating(
        code: item.code,
        javdbBaseUrl: _javdbBaseUrl,
      );
      if (res != null) {
        await DatabaseHelper.instance.updatePublicRating(
          id: item.id,
          rating: res.rating,
          source: res.source,
        );
        successCount++;
      }
    }
    if (successCount > 0 && mounted) {
      await refresh();
    }
    return successCount;
  }

  Future<void> saveItem(MediaItem item) async {
    await DatabaseHelper.instance.upsertMediaItem(item);
    await refresh();
    if (item.publicRating <= 0 &&
        RatingFetcherService.instance.isStandardCode(item.code)) {
      _fetchPublicRatingInBackground([item]);
    }
    if (item.tags.isEmpty && item.sourceUrl.isNotEmpty) {
      _enrichTagsInBackground([item]);
    }
  }

  Future<void> saveItemsBatch(List<MediaItem> items) async {
    for (final item in items) {
      await DatabaseHelper.instance.upsertMediaItem(item);
    }
    await refresh();
    final needRating = items
        .where((i) =>
            i.publicRating <= 0 &&
            RatingFetcherService.instance.isStandardCode(i.code))
        .take(12)
        .toList();
    if (needRating.isNotEmpty) {
      _fetchPublicRatingInBackground(needRating);
    }
    final needTags = items
        .where((i) => i.tags.isEmpty && i.sourceUrl.isNotEmpty)
        .take(8)
        .toList();
    if (needTags.isNotEmpty) {
      _enrichTagsInBackground(needTags);
    }
  }

  Future<void> updateCumCount(String id, int count) async {
    await DatabaseHelper.instance.updateCumCount(id: id, cumCount: count);
    await refresh();
  }

  void _enrichTagsInBackground(List<MediaItem> items) {
    Future(() async {
      var updated = false;
      for (final item in items) {
        final meta = await WebMetadataExtractorService.instance
            .extractFromUrl(item.sourceUrl);
        if (meta.tags.isNotEmpty || meta.actors.isNotEmpty) {
          await DatabaseHelper.instance.updateTagsAndActors(
            id: item.id,
            tags: meta.tags,
            actors: meta.actors,
          );
          updated = true;
        }
      }
      if (updated && mounted) {
        await refresh();
      }
    });
  }

  Future<({double rating, String source})?> fetchPublicRatingNow(
    MediaItem item,
  ) async {
    final result = await RatingFetcherService.instance.fetchPublicRating(
      code: item.code,
      javdbBaseUrl: _javdbBaseUrl,
    );
    if (result != null) {
      await DatabaseHelper.instance.updatePublicRating(
        id: item.id,
        rating: result.rating,
        source: result.source,
      );
      await refresh();
    }
    return result;
  }

  void _fetchPublicRatingInBackground(List<MediaItem> items) {
    Future(() async {
      var updated = false;
      for (final item in items) {
        final result = await RatingFetcherService.instance.fetchPublicRating(
          code: item.code,
          javdbBaseUrl: _javdbBaseUrl,
        );
        if (result != null) {
          await DatabaseHelper.instance.updatePublicRating(
            id: item.id,
            rating: result.rating,
            source: result.source,
          );
          updated = true;
        }
      }
      if (updated && mounted) {
        await refresh();
      }
    });
  }

  Future<void> deleteItem(String id) async {
    await DatabaseHelper.instance.deleteMediaItem(id);
    await LiveAiSubtitleSession.deleteCachedSubtitle(id);
    await refresh();
  }

  Future<void> deleteItemsBatch(Iterable<String> ids) async {
    await DatabaseHelper.instance.deleteMediaItemsBatch(ids);
    for (final id in ids) {
      await LiveAiSubtitleSession.deleteCachedSubtitle(id);
    }
    await refresh();
  }

  Future<void> updateProgress(String id, int posSec, int durSec) async {
    await DatabaseHelper.instance.updateWatchProgress(
      id: id,
      positionSec: posSec,
      durationSec: durSec,
    );
    await refresh();
  }
}

/// 离线下载管理状态
final downloadTasksProvider =
    StateNotifierProvider<DownloadTasksNotifier, List<DownloadTask>>((ref) {
  return DownloadTasksNotifier();
});

class DownloadTasksNotifier extends StateNotifier<List<DownloadTask>> {
  DownloadTasksNotifier() : super(const []) {
    refresh();
  }

  Future<void> refresh() async {
    state = await DatabaseHelper.instance.getAllDownloadTasks();
  }

  Future<void> enqueue({
    required String code,
    required String title,
    required String posterUrl,
    required String streamUrl,
    String referer = '',
    String cookieHeader = '',
  }) async {
    await M3u8DownloaderService.instance.startDownload(
      code: code,
      title: title,
      posterUrl: posterUrl,
      streamUrl: streamUrl,
      referer: referer,
      cookieHeader: cookieHeader,
      onUpdate: (tasks) => state = tasks,
    );
  }

  Future<void> remove(String id) async {
    await M3u8DownloaderService.instance.deleteTask(id);
    await refresh();
  }
}

/// 本地网页书签收藏状态（用于无登录功能的站点）
final bookmarkFolderFilterProvider = StateProvider<String>((ref) => '全部');

final bookmarksProvider =
    StateNotifierProvider<BookmarksNotifier, List<BookmarkItem>>((ref) {
  final folder = ref.watch(bookmarkFolderFilterProvider);
  return BookmarksNotifier(folder);
});

class BookmarksNotifier extends StateNotifier<List<BookmarkItem>> {
  final String _folder;

  BookmarksNotifier(this._folder) : super(const []) {
    refresh();
  }

  Future<void> refresh() async {
    state = await DatabaseHelper.instance.getBookmarks(folder: _folder);
  }

  Future<void> save(BookmarkItem item) async {
    await DatabaseHelper.instance.upsertBookmark(item);
    await refresh();
  }

  Future<void> remove(String id) async {
    await DatabaseHelper.instance.deleteBookmark(id);
    await refresh();
  }
}
