import 'dart:convert';
import 'package:dio/dio.dart';
import '../models/bookmark.dart';
import '../models/media_item.dart';
import '../models/site_config.dart';
import '../storage/database_helper.dart';
import '../storage/settings_repository.dart';

class CloudSyncResult {
  final bool success;
  final String message;
  final int mediaCount;
  final int bookmarkCount;
  final int siteCount;
  final String? resolvedGistId;

  const CloudSyncResult({
    required this.success,
    required this.message,
    this.mediaCount = 0,
    this.bookmarkCount = 0,
    this.siteCount = 0,
    this.resolvedGistId,
  });
}

/// 跨平台云同步与离线备份服务：
/// 1. GitHub 私有 Gist（免费私密，自动跨 iOS / iPadOS / Android 认领同步）
/// 2. WebDAV（坚果云 / Alist / 自建 NAS，国内直连）
/// 3. 离线 JSON 导出/导入
class CloudSyncService {
  CloudSyncService._();
  static final CloudSyncService instance = CloudSyncService._();

  static const String syncFileName = 'embystreamvault_sync.json';

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      followRedirects: true,
    ),
  );

  /// 纯函数：合并本机与云端影片列表（按 updatedAtMs 择新 + 标签取并集 + 保护非零评分与次数）
  static List<MediaItem> mergeMediaItems(
    List<MediaItem> local,
    List<MediaItem> remote,
  ) {
    final map = <String, MediaItem>{
      for (final item in local) item.id: item,
    };

    for (final r in remote) {
      final l = map[r.id];
      if (l == null) {
        map[r.id] = r;
        continue;
      }

      final primary = r.updatedAtMs >= l.updatedAtMs ? r : l;
      final secondary = r.updatedAtMs >= l.updatedAtMs ? l : r;
      final mergedTags = {...primary.tags, ...secondary.tags}.toList();

      map[r.id] = primary.copyWith(
        posterUrl: primary.posterUrl.isNotEmpty
            ? primary.posterUrl
            : secondary.posterUrl,
        actors: primary.actors.isNotEmpty ? primary.actors : secondary.actors,
        tags: mergedTags,
        studio: primary.studio.isNotEmpty ? primary.studio : secondary.studio,
        personalRating: primary.personalRating > 0
            ? primary.personalRating
            : secondary.personalRating,
        publicRating: primary.publicRating > 0
            ? primary.publicRating
            : secondary.publicRating,
        publicRatingSource: primary.publicRatingSource.isNotEmpty
            ? primary.publicRatingSource
            : secondary.publicRatingSource,
        cumCount: primary.cumCount > 0 ? primary.cumCount : secondary.cumCount,
        notes: primary.notes.isNotEmpty ? primary.notes : secondary.notes,
        lastStreamUrl: primary.lastStreamUrl ?? secondary.lastStreamUrl,
        lastPositionSec: primary.lastPositionSec > secondary.lastPositionSec
            ? primary.lastPositionSec
            : secondary.lastPositionSec,
        durationSec: primary.durationSec > 0
            ? primary.durationSec
            : secondary.durationSec,
      );
    }

    final merged = map.values.toList()
      ..sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
    return merged;
  }

  static List<BookmarkItem> mergeBookmarks(
    List<BookmarkItem> local,
    List<BookmarkItem> remote,
  ) {
    final map = <String, BookmarkItem>{
      for (final bm in local) bm.url: bm,
    };
    for (final r in remote) {
      map.putIfAbsent(r.url, () => r);
    }
    return map.values.toList()
      ..sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
  }

  static List<SiteProfile> mergeSites(
    List<SiteProfile> local,
    List<SiteProfile> remote,
  ) {
    final map = <String, SiteProfile>{
      for (final s in local) s.key: s,
    };
    for (final r in remote) {
      map.putIfAbsent(r.key, () => r);
    }
    return map.values.toList();
  }

  /// 导出当前本机完整数据快照（JSON 字符串）
  Future<String> exportLocalSnapshotJson() async {
    final media = await DatabaseHelper.instance.getAllMediaItems();
    final bookmarks = await DatabaseHelper.instance.getBookmarks();
    final sites = await SettingsRepository().loadSites();

    return const JsonEncoder.withIndent('  ').convert({
      'schemaVersion': 1,
      'exportedAtMs': DateTime.now().millisecondsSinceEpoch,
      'mediaItems': media.map((e) => e.toMap()).toList(),
      'bookmarks': bookmarks.map((e) => e.toMap()).toList(),
      'sites': sites.map((e) => e.toJson()).toList(),
    });
  }

  /// 解析外部 JSON 快照并与本机合并落库
  Future<CloudSyncResult> importAndMergeJson(String rawJson) async {
    try {
      final parsed = _parseSnapshot(rawJson);
      final localMedia = await DatabaseHelper.instance.getAllMediaItems();
      final localBookmarks = await DatabaseHelper.instance.getBookmarks();
      final settingsRepo = SettingsRepository();
      final localSites = await settingsRepo.loadSites();

      final mergedMedia = mergeMediaItems(localMedia, parsed.mediaItems);
      final mergedBookmarks =
          mergeBookmarks(localBookmarks, parsed.bookmarks);
      final mergedSites = mergeSites(localSites, parsed.sites);

      for (final item in mergedMedia) {
        await DatabaseHelper.instance.upsertMediaItem(item);
      }
      for (final bm in mergedBookmarks) {
        await DatabaseHelper.instance.upsertBookmark(bm);
      }
      await settingsRepo.saveSites(mergedSites);

      return CloudSyncResult(
        success: true,
        message:
            '导入合并成功：影库 ${mergedMedia.length} 部，书签 ${mergedBookmarks.length} 条，站点 ${mergedSites.length} 个',
        mediaCount: mergedMedia.length,
        bookmarkCount: mergedBookmarks.length,
        siteCount: mergedSites.length,
      );
    } catch (e) {
      return CloudSyncResult(
        success: false,
        message: '备份 JSON 解析失败：$e',
      );
    }
  }

  /// 执行云端同步（forcePushLocal = true 时以本机为准覆盖云端，用于同步删除操作）
  Future<CloudSyncResult> syncNow(
    AppPreferences prefs, {
    bool forcePushLocal = false,
  }) async {
    if (prefs.syncProvider == 'webdav') {
      return _syncViaWebDav(prefs, forcePushLocal: forcePushLocal);
    }
    return _syncViaGitHubGist(prefs, forcePushLocal: forcePushLocal);
  }

  Future<CloudSyncResult> _syncViaGitHubGist(
    AppPreferences prefs, {
    required bool forcePushLocal,
  }) async {
    final token = prefs.syncGistToken.trim();
    if (token.isEmpty) {
      return const CloudSyncResult(
        success: false,
        message: '请先配置 GitHub Token（仅需勾选 gist 权限）',
      );
    }

    final headers = {
      'Authorization': 'Bearer $token',
      'Accept': 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
    };

    try {
      var gistId = prefs.syncGistId.trim();
      String? remoteContent;

      // 1. 如果未填写 Gist ID，自动扫描当前账号下是否已有同步 Gist（换新设备时自动认领！）
      if (gistId.isEmpty) {
        final listResp = await _dio.get<List<dynamic>>(
          'https://api.github.com/gists?per_page=50',
          options: Options(headers: headers),
        );
        final list = listResp.data ?? const [];
        for (final entry in list) {
          if (entry is Map &&
              entry['files'] is Map &&
              (entry['files'] as Map).containsKey(syncFileName)) {
            gistId = (entry['id'] ?? '').toString();
            break;
          }
        }
      }

      // 2. 如果找到了 Gist 且不是强制覆盖模式，先拉取云端快照并合并到本地
      if (gistId.isNotEmpty && !forcePushLocal) {
        final getResp = await _dio.get<Map<String, dynamic>>(
          'https://api.github.com/gists/$gistId',
          options: Options(headers: headers),
        );
        final files = getResp.data?['files'];
        if (files is Map && files[syncFileName] is Map) {
          final fileObj = files[syncFileName] as Map;
          if (fileObj['truncated'] == true && fileObj['raw_url'] != null) {
            final rawResp = await _dio.get<String>(
              fileObj['raw_url'].toString(),
              options: Options(responseType: ResponseType.plain),
            );
            remoteContent = rawResp.data;
          } else {
            remoteContent = fileObj['content']?.toString();
          }
        }
        if (remoteContent != null && remoteContent.trim().isNotEmpty) {
          final mergedRes = await importAndMergeJson(remoteContent);
          if (!mergedRes.success) return mergedRes;
        }
      }

      // 3. 打包最新完整快照并回写到私有 Gist
      final latestJson = await exportLocalSnapshotJson();
      final decodedStats = _parseSnapshot(latestJson);

      if (gistId.isEmpty) {
        final createResp = await _dio.post<Map<String, dynamic>>(
          'https://api.github.com/gists',
          options: Options(headers: headers),
          data: {
            'description': 'EmbyStreamVault Private Cloud Sync Data',
            'public': false,
            'files': {
              syncFileName: {'content': latestJson},
            },
          },
        );
        gistId = (createResp.data?['id'] ?? '').toString();
      } else {
        await _dio.patch<Map<String, dynamic>>(
          'https://api.github.com/gists/$gistId',
          options: Options(headers: headers),
          data: {
            'files': {
              syncFileName: {'content': latestJson},
            },
          },
        );
      }

      return CloudSyncResult(
        success: true,
        message: forcePushLocal
            ? '已用本机数据覆盖私有 Gist（${decodedStats.mediaItems.length} 部影片）'
            : 'GitHub 私有 Gist 双向同步成功（影库 ${decodedStats.mediaItems.length} 部 · 书签 ${decodedStats.bookmarks.length} 条）',
        mediaCount: decodedStats.mediaItems.length,
        bookmarkCount: decodedStats.bookmarks.length,
        siteCount: decodedStats.sites.length,
        resolvedGistId: gistId,
      );
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 401 || code == 403) {
        return const CloudSyncResult(
          success: false,
          message: 'GitHub Token 无效或缺少 gist 权限，请检查后重试',
        );
      }
      return CloudSyncResult(
        success: false,
        message: 'GitHub 同步失败：${e.message ?? '网络异常'}',
      );
    } catch (e) {
      return CloudSyncResult(success: false, message: '同步异常：$e');
    }
  }

  Future<CloudSyncResult> _syncViaWebDav(
    AppPreferences prefs, {
    required bool forcePushLocal,
  }) async {
    final url = prefs.syncWebDavUrl.trim();
    final user = prefs.syncWebDavUser.trim();
    final pass = prefs.syncWebDavPass.trim();
    if (url.isEmpty || user.isEmpty || pass.isEmpty) {
      return const CloudSyncResult(
        success: false,
        message: '请先填写完整的 WebDAV 地址、账号和应用密码',
      );
    }

    final auth = 'Basic ${base64Encode(utf8.encode('$user:$pass'))}';
    final headers = {'Authorization': auth};

    try {
      if (!forcePushLocal) {
        final getResp = await _dio.get<String>(
          url,
          options: Options(
            headers: headers,
            responseType: ResponseType.plain,
            validateStatus: (s) => s != null && (s < 300 || s == 404),
          ),
        );
        if (getResp.statusCode == 200 &&
            getResp.data != null &&
            getResp.data!.trim().isNotEmpty) {
          final mergedRes = await importAndMergeJson(getResp.data!);
          if (!mergedRes.success) return mergedRes;
        }
      }

      // 确保父目录存在（对坚果云/标准 WebDAV 友好，若已存在会返回 405 直接忽略）
      final uri = Uri.tryParse(url);
      if (uri != null && uri.pathSegments.length >= 2) {
        final parentPath =
            uri.pathSegments.sublist(0, uri.pathSegments.length - 1).join('/');
        final parentUrl = '${uri.scheme}://${uri.authority}/$parentPath/';
        try {
          await _dio.request<void>(
            parentUrl,
            options: Options(
              method: 'MKCOL',
              headers: headers,
              validateStatus: (s) => s != null && s < 500,
            ),
          );
        } catch (_) {}
      }

      final latestJson = await exportLocalSnapshotJson();
      final stats = _parseSnapshot(latestJson);
      await _dio.put<void>(
        url,
        data: latestJson,
        options: Options(
          headers: {
            ...headers,
            'Content-Type': 'application/json; charset=utf-8',
          },
        ),
      );

      return CloudSyncResult(
        success: true,
        message: forcePushLocal
            ? '已用本机数据覆盖 WebDAV（${stats.mediaItems.length} 部影片）'
            : 'WebDAV 双向同步成功（影库 ${stats.mediaItems.length} 部 · 书签 ${stats.bookmarks.length} 条）',
        mediaCount: stats.mediaItems.length,
        bookmarkCount: stats.bookmarks.length,
        siteCount: stats.sites.length,
      );
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 401 || code == 403) {
        return const CloudSyncResult(
          success: false,
          message: 'WebDAV 账号或应用密码不正确（坚果云需使用专用应用密码）',
        );
      }
      return CloudSyncResult(
        success: false,
        message: 'WebDAV 同步失败（HTTP ${code ?? '?'}）：${e.message ?? ''}',
      );
    } catch (e) {
      return CloudSyncResult(success: false, message: 'WebDAV 同步异常：$e');
    }
  }

  ({
    List<MediaItem> mediaItems,
    List<BookmarkItem> bookmarks,
    List<SiteProfile> sites,
  }) _parseSnapshot(String rawJson) {
    final root = jsonDecode(rawJson) as Map<String, dynamic>;
    final mediaRaw = (root['mediaItems'] as List<dynamic>? ?? const []);
    final bmRaw = (root['bookmarks'] as List<dynamic>? ?? const []);
    final siteRaw = (root['sites'] as List<dynamic>? ?? const []);

    return (
      mediaItems: mediaRaw
          .whereType<Map>()
          .map((e) => MediaItem.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
      bookmarks: bmRaw
          .whereType<Map>()
          .map((e) => BookmarkItem.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
      sites: siteRaw
          .whereType<Map>()
          .map((e) => SiteProfile.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}
