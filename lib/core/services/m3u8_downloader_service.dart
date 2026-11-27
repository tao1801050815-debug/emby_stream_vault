import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/download_task.dart';
import '../storage/database_helper.dart';

/// m3u8 解析与分片并发离线缓存服务
class M3u8DownloaderService {
  M3u8DownloaderService._();
  static final M3u8DownloaderService instance = M3u8DownloaderService._();

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );

  Map<String, String> _buildHeaders(String referer, String cookieHeader) {
    final headers = <String, String>{};
    if (referer.isNotEmpty) headers['Referer'] = referer;
    if (cookieHeader.isNotEmpty) headers['Cookie'] = cookieHeader;
    return headers;
  }

  Future<void> startDownload({
    required String code,
    required String title,
    required String posterUrl,
    required String streamUrl,
    String referer = '',
    String cookieHeader = '',
    required void Function(List<DownloadTask>) onUpdate,
  }) async {
    final docDir = await getApplicationDocumentsDirectory();
    final id = 'dl_${code}_${DateTime.now().millisecondsSinceEpoch}';
    final taskDir = Directory(p.join(docDir.path, 'offline_videos', id));
    await taskDir.create(recursive: true);

    var task = DownloadTask(
      id: id,
      code: code,
      title: title,
      posterUrl: posterUrl,
      streamUrl: streamUrl,
      referer: referer,
      cookieHeader: cookieHeader,
      status: DownloadStatus.downloading,
      localDir: taskDir.path,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    );

    await DatabaseHelper.instance.upsertDownloadTask(task);
    onUpdate(await DatabaseHelper.instance.getAllDownloadTasks());

    try {
      final headers = _buildHeaders(referer, cookieHeader);
      final resolved = await _resolveMediaPlaylist(streamUrl, headers);
      final lines = resolved.content.split(RegExp(r'\r?\n'));
      final segmentIndices = <int>[];
      final segmentUrls = <String>[];

      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.isEmpty || line.startsWith('#')) continue;
        segmentIndices.add(i);
        segmentUrls.add(Uri.parse(resolved.url).resolve(line).toString());
      }

      if (segmentUrls.isEmpty) {
        throw Exception('未在 m3u8 中解析到有效的视频分片');
      }

      task = task.copyWith(totalSegments: segmentUrls.length);
      await DatabaseHelper.instance.upsertDownloadTask(task);
      onUpdate(await DatabaseHelper.instance.getAllDownloadTasks());

      // 分批并发下载（每批 4 个分片，兼顾速度与手机内存）
      var completedCount = 0;
      const batchSize = 4;
      for (var start = 0; start < segmentUrls.length; start += batchSize) {
        final end = (start + batchSize).clamp(0, segmentUrls.length);
        await Future.wait([
          for (var idx = start; idx < end; idx++)
            _downloadSegment(
              url: segmentUrls[idx],
              savePath: p.join(taskDir.path, 'seg_$idx.ts'),
              headers: headers,
            ).then((_) {
              completedCount++;
            }),
        ]);

        // 改写 m3u8 对应行到本地文件
        for (var idx = start; idx < end; idx++) {
          lines[segmentIndices[idx]] = 'seg_$idx.ts';
        }

        task = task.copyWith(downloadedSegments: completedCount);
        await DatabaseHelper.instance.upsertDownloadTask(task);
        onUpdate(await DatabaseHelper.instance.getAllDownloadTasks());
      }

      final localPlaylist = File(p.join(taskDir.path, 'local.m3u8'));
      await localPlaylist.writeAsString(lines.join('\n'));

      task = task.copyWith(
        status: DownloadStatus.completed,
        localPlaylistPath: localPlaylist.path,
      );
      await DatabaseHelper.instance.upsertDownloadTask(task);
      onUpdate(await DatabaseHelper.instance.getAllDownloadTasks());
    } catch (e) {
      task = task.copyWith(
        status: DownloadStatus.failed,
        errorMessage: e.toString(),
      );
      await DatabaseHelper.instance.upsertDownloadTask(task);
      onUpdate(await DatabaseHelper.instance.getAllDownloadTasks());
    }
  }

  Future<({String url, String content})> _resolveMediaPlaylist(
    String url,
    Map<String, String> headers,
  ) async {
    final resp = await _dio.get<String>(
      url,
      options: Options(headers: headers, responseType: ResponseType.plain),
    );
    final body = resp.data ?? '';
    final lines = body.split(RegExp(r'\r?\n'));

    // 若为 Master Playlist，自动挑选最高带宽的 Sub-Playlist
    if (body.contains('#EXT-X-STREAM-INF')) {
      int bestBandwidth = -1;
      String? bestUrl;
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.startsWith('#EXT-X-STREAM-INF')) {
          final bwMatch = RegExp(r'BANDWIDTH=(\d+)').firstMatch(line);
          final bw = int.tryParse(bwMatch?.group(1) ?? '0') ?? 0;
          if (i + 1 < lines.length) {
            final nextLine = lines[i + 1].trim();
            if (nextLine.isNotEmpty && !nextLine.startsWith('#') && bw >= bestBandwidth) {
              bestBandwidth = bw;
              bestUrl = Uri.parse(url).resolve(nextLine).toString();
            }
          }
        }
      }
      if (bestUrl != null) {
        return _resolveMediaPlaylist(bestUrl, headers);
      }
    }

    return (url: url, content: body);
  }

  Future<void> _downloadSegment({
    required String url,
    required String savePath,
    required Map<String, String> headers,
  }) async {
    await _dio.download(
      url,
      savePath,
      options: Options(headers: headers),
    );
  }

  Future<void> deleteTask(String id) async {
    final tasks = await DatabaseHelper.instance.getAllDownloadTasks();
    final target = tasks.where((t) => t.id == id).firstOrNull;
    if (target != null && target.localDir.isNotEmpty) {
      final dir = Directory(target.localDir);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    }
    await DatabaseHelper.instance.deleteDownloadTask(id);
  }
}
