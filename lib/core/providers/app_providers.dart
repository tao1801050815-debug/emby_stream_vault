import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/bookmark.dart';
import '../models/download_task.dart';
import '../models/media_item.dart';
import '../models/site_config.dart';
import '../services/m3u8_downloader_service.dart';
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
    final loaded = await _repo.loadSites();
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

  const LibraryFilter({
    this.onlyFavorites = false,
    this.searchQuery = '',
    this.minRating = 0.0,
    this.sortBy = 'updatedAtMs',
  });

  LibraryFilter copyWith({
    bool? onlyFavorites,
    String? searchQuery,
    double? minRating,
    String? sortBy,
  }) {
    return LibraryFilter(
      onlyFavorites: onlyFavorites ?? this.onlyFavorites,
      searchQuery: searchQuery ?? this.searchQuery,
      minRating: minRating ?? this.minRating,
      sortBy: sortBy ?? this.sortBy,
    );
  }
}

final libraryFilterProvider =
    StateProvider<LibraryFilter>((ref) => const LibraryFilter());

/// 本地媒体库状态
final mediaLibraryProvider =
    StateNotifierProvider<MediaLibraryNotifier, AsyncValue<List<MediaItem>>>(
        (ref) {
  final filter = ref.watch(libraryFilterProvider);
  return MediaLibraryNotifier(filter);
});

class MediaLibraryNotifier extends StateNotifier<AsyncValue<List<MediaItem>>> {
  final LibraryFilter _filter;

  MediaLibraryNotifier(this._filter) : super(const AsyncValue.loading()) {
    refresh();
  }

  Future<void> refresh() async {
    try {
      final items = await DatabaseHelper.instance.getAllMediaItems(
        onlyFavorites: _filter.onlyFavorites,
        searchQuery: _filter.searchQuery,
        minRating: _filter.minRating,
        sortBy: _filter.sortBy,
      );
      state = AsyncValue.data(items);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> saveItem(MediaItem item) async {
    await DatabaseHelper.instance.upsertMediaItem(item);
    await refresh();
  }

  Future<void> deleteItem(String id) async {
    await DatabaseHelper.instance.deleteMediaItem(id);
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
