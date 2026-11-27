import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/site_config.dart';

/// 单条 AI 实时字幕条目
class AiSubtitleCue {
  final double startSec;
  final double endSec;
  final String originalText;
  final String translatedText;

  const AiSubtitleCue({
    required this.startSec,
    required this.endSec,
    required this.originalText,
    required this.translatedText,
  });

  Map<String, dynamic> toJson() => {
        'startSec': startSec,
        'endSec': endSec,
        'originalText': originalText,
        'translatedText': translatedText,
      };

  factory AiSubtitleCue.fromJson(Map<String, dynamic> json) => AiSubtitleCue(
        startSec: ((json['startSec'] as num?) ?? 0).toDouble(),
        endSec: ((json['endSec'] as num?) ?? 0).toDouble(),
        originalText: (json['originalText'] as String?) ?? '',
        translatedText: (json['translatedText'] as String?) ?? '',
      );
}

class _HlsSegment {
  final int index;
  final String urlOrPath;
  final bool isLocalFile;
  final double startSec;
  final double endSec;

  const _HlsSegment({
    required this.index,
    required this.urlOrPath,
    required this.isLocalFile,
    required this.startSec,
    required this.endSec,
  });
}

/// 纯手机端 AI 实时字幕会话：
/// 直接按播放进度抓取 .m3u8 对应时间点的 .ts 分片 -> 云端语音识别 -> 实时翻译成中文字幕
class LiveAiSubtitleSession {
  final String mediaId;
  final String streamUrl;
  final String referer;
  final String cookieHeader;
  final AppPreferences prefs;
  final void Function(List<AiSubtitleCue> cues) onCuesUpdated;
  final void Function(String status) onStatusChanged;

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 40),
    ),
  );

  bool _disposed = false;
  bool _processing = false;
  double _currentPosSec = 0.0;
  List<_HlsSegment> _segments = const [];
  final Set<int> _processedSegmentIndices = {};
  final List<AiSubtitleCue> _cues = [];
  Timer? _scheduler;

  LiveAiSubtitleSession({
    required this.mediaId,
    required this.streamUrl,
    required this.referer,
    required this.cookieHeader,
    required this.prefs,
    required this.onCuesUpdated,
    required this.onStatusChanged,
  });

  static Future<File> _cacheFileFor(String mediaId) async {
    final docDir = await getApplicationDocumentsDirectory();
    final safeName = mediaId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final dir = Directory(p.join(docDir.path, 'ai_subtitles'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File(p.join(dir.path, '$safeName.json'));
  }

  /// 读取某部影片本地已保存的 AI 字幕（播放时自动调用）
  static Future<List<AiSubtitleCue>> loadCachedCues(String mediaId) async {
    if (mediaId.trim().isEmpty) return const [];
    try {
      final file = await _cacheFileFor(mediaId);
      if (!await file.exists()) return const [];
      final raw = jsonDecode(await file.readAsString());
      if (raw is Map<String, dynamic> && raw['cues'] is List) {
        return (raw['cues'] as List)
            .whereType<Map<String, dynamic>>()
            .map(AiSubtitleCue.fromJson)
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  Future<void> _loadLocalCacheIntoSession() async {
    if (mediaId.trim().isEmpty) return;
    try {
      final file = await _cacheFileFor(mediaId);
      if (!await file.exists()) return;
      final raw = jsonDecode(await file.readAsString());
      if (raw is Map<String, dynamic>) {
        if (raw['cues'] is List) {
          _cues
            ..clear()
            ..addAll((raw['cues'] as List)
                .whereType<Map<String, dynamic>>()
                .map(AiSubtitleCue.fromJson));
        }
        if (raw['processedIndices'] is List) {
          _processedSegmentIndices
            ..clear()
            ..addAll((raw['processedIndices'] as List)
                .map((e) => (e as num).toInt()));
        }
        if (_cues.isNotEmpty) {
          onCuesUpdated(List<AiSubtitleCue>.unmodifiable(_cues));
        }
      }
    } catch (_) {}
  }

  Future<void> _persistCache() async {
    if (mediaId.trim().isEmpty) return;
    try {
      final file = await _cacheFileFor(mediaId);
      final payload = {
        'mediaId': mediaId,
        'processedIndices': _processedSegmentIndices.toList()..sort(),
        'cues': _cues.map((e) => e.toJson()).toList(),
      };
      await file.writeAsString(jsonEncode(payload));
    } catch (_) {}
  }

  Map<String, String> _streamHeaders() {
    final headers = <String, String>{};
    if (referer.isNotEmpty) headers['Referer'] = referer;
    if (cookieHeader.isNotEmpty) headers['Cookie'] = cookieHeader;
    return headers;
  }

  Future<void> start(double initialPositionSec) async {
    _currentPosSec = initialPositionSec;
    await _loadLocalCacheIntoSession();
    if (_disposed) return;

    if (prefs.aiApiKey.trim().isEmpty) {
      onStatusChanged('请先在「设置 → AI 实时字幕」中填写 API Key');
      return;
    }

    onStatusChanged('正在解析视频流分片...');
    try {
      _segments = await _parsePlaylist(streamUrl);
      if (_disposed) return;
      if (_segments.isEmpty) {
        onStatusChanged('当前视频不是分段流（m3u8），暂不支持实时分片识别');
        return;
      }
      onStatusChanged('AI 字幕已就绪，正在识别当前片段...');
      _scheduler = Timer.periodic(
        const Duration(seconds: 2),
        (_) => _tick(),
      );
      unawaited(_tick());
    } catch (e) {
      if (!_disposed) {
        onStatusChanged('流解析失败: $e');
      }
    }
  }

  void updatePosition(double positionSec) {
    _currentPosSec = positionSec;
  }

  void dispose() {
    _disposed = true;
    _scheduler?.cancel();
    _dio.close(force: true);
  }

  Future<void> _tick() async {
    if (_disposed || _processing || _segments.isEmpty) return;

    // 优先寻找覆盖当前播放位置及未来 24 秒内尚未识别的分片
    final target = _segments.where((seg) {
      if (_processedSegmentIndices.contains(seg.index)) return false;
      return seg.endSec >= _currentPosSec - 1.0 &&
          seg.startSec <= _currentPosSec + 24.0;
    }).take(2).toList();

    if (target.isEmpty) return;

    _processing = true;
    for (final s in target) {
      _processedSegmentIndices.add(s.index);
    }

    try {
      final startTime = target.first.startSec;
      final endTime = target.last.endSec;
      onStatusChanged('正在识别 ${_fmt(startTime)}...');

      final bytesBuilder = BytesBuilder(copy: false);
      for (final seg in target) {
        if (_disposed) return;
        final chunkBytes = await _loadSegmentBytes(seg);
        if (chunkBytes != null) {
          bytesBuilder.add(chunkBytes);
        }
      }
      final audioPayload = bytesBuilder.takeBytes();
      if (audioPayload.isEmpty || _disposed) return;

      final recognized = await _transcribeChunk(
        audioPayload,
        baseOffsetSec: startTime,
        fallbackEndSec: endTime,
      );
      if (_disposed) return;

      for (final seg in recognized) {
        if (seg.text.trim().isEmpty) continue;
        final zh = await _translateToChinese(seg.text);
        if (_disposed) return;
        _cues.add(
          AiSubtitleCue(
            startSec: seg.startSec,
            endSec: seg.endSec,
            originalText: seg.text.trim(),
            translatedText: zh.trim(),
          ),
        );
      }

      _cues.sort((a, b) => a.startSec.compareTo(b.startSec));
      await _persistCache();
      onCuesUpdated(List<AiSubtitleCue>.unmodifiable(_cues));
      onStatusChanged('AI 字幕运行中（已保存 ${_cues.length} 句）');
    } catch (e) {
      if (!_disposed) {
        onStatusChanged('识别出错: ${e.toString().split('\n').first}');
      }
    } finally {
      _processing = false;
    }
  }

  Future<List<_HlsSegment>> _parsePlaylist(String urlOrPath) async {
    final isLocal = !urlOrPath.startsWith('http://') &&
        !urlOrPath.startsWith('https://');
    String content;
    String baseUriOrDir;

    if (isLocal) {
      final f = File(urlOrPath);
      if (!await f.exists()) return const [];
      content = await f.readAsString();
      baseUriOrDir = p.dirname(urlOrPath);
    } else {
      final resolved = await _resolveLowestBandwidthPlaylist(urlOrPath);
      content = resolved.content;
      baseUriOrDir = resolved.url;
    }

    final lines = content.split(RegExp(r'\r?\n'));
    final result = <_HlsSegment>[];
    double cursor = 0.0;
    double pendingDur = 4.0;
    int idx = 0;

    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('#EXTINF:')) {
        final durStr = line.substring('#EXTINF:'.length).split(',').first.trim();
        pendingDur = double.tryParse(durStr) ?? 4.0;
        continue;
      }
      if (line.startsWith('#')) continue;

      final segTarget = isLocal
          ? p.join(baseUriOrDir, line)
          : Uri.parse(baseUriOrDir).resolve(line).toString();
      result.add(
        _HlsSegment(
          index: idx++,
          urlOrPath: segTarget,
          isLocalFile: isLocal,
          startSec: cursor,
          endSec: cursor + pendingDur,
        ),
      );
      cursor += pendingDur;
    }
    return result;
  }

  /// Master Playlist 优先挑选最低带宽流，体积最小、手机识别延迟最低
  Future<({String url, String content})> _resolveLowestBandwidthPlaylist(
    String url, [
    int depth = 0,
  ]) async {
    final resp = await _dio.get<String>(
      url,
      options: Options(
        headers: _streamHeaders(),
        responseType: ResponseType.plain,
      ),
    );
    final body = resp.data ?? '';
    if (body.contains('#EXT-X-STREAM-INF') && depth < 3) {
      final lines = body.split(RegExp(r'\r?\n'));
      int? minBw;
      String? chosenUrl;
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.startsWith('#EXT-X-STREAM-INF')) {
          final bw = int.tryParse(
                  RegExp(r'BANDWIDTH=(\d+)').firstMatch(line)?.group(1) ??
                      '0') ??
              0;
          if (i + 1 < lines.length) {
            final next = lines[i + 1].trim();
            if (next.isNotEmpty && !next.startsWith('#')) {
              if (minBw == null || (bw > 0 && bw < minBw)) {
                minBw = bw;
                chosenUrl = Uri.parse(url).resolve(next).toString();
              }
            }
          }
        }
      }
      if (chosenUrl != null) {
        return _resolveLowestBandwidthPlaylist(chosenUrl, depth + 1);
      }
    }
    return (url: url, content: body);
  }

  Future<Uint8List?> _loadSegmentBytes(_HlsSegment seg) async {
    if (seg.isLocalFile) {
      final f = File(seg.urlOrPath);
      if (await f.exists()) return f.readAsBytes();
      return null;
    }
    final resp = await _dio.get<List<int>>(
      seg.urlOrPath,
      options: Options(
        headers: _streamHeaders(),
        responseType: ResponseType.bytes,
      ),
    );
    final data = resp.data;
    return data == null ? null : Uint8List.fromList(data);
  }

  Future<List<({double startSec, double endSec, String text})>>
      _transcribeChunk(
    Uint8List bytes, {
    required double baseOffsetSec,
    required double fallbackEndSec,
  }) async {
    final base = prefs.aiApiBaseUrl.replaceAll(RegExp(r'/+$'), '');
    final endpoint = '$base/audio/transcriptions';

    final formMap = <String, dynamic>{
      'file': MultipartFile.fromBytes(bytes, filename: 'chunk.mp4'),
      'model': prefs.aiAsrModel.trim().isNotEmpty
          ? prefs.aiAsrModel.trim()
          : 'whisper-large-v3-turbo',
      'response_format': 'verbose_json',
    };
    if (prefs.aiSourceLang != 'auto' && prefs.aiSourceLang.isNotEmpty) {
      formMap['language'] = prefs.aiSourceLang;
    }

    final resp = await _dio.post<dynamic>(
      endpoint,
      data: FormData.fromMap(formMap),
      options: Options(
        headers: {
          'Authorization': 'Bearer ${prefs.aiApiKey.trim()}',
        },
      ),
    );

    final data = resp.data;
    final out = <({double startSec, double endSec, String text})>[];
    if (data is Map<String, dynamic>) {
      final segs = data['segments'];
      if (segs is List && segs.isNotEmpty) {
        for (final s in segs) {
          if (s is Map<String, dynamic>) {
            final t = (s['text'] as String? ?? '').trim();
            if (t.isEmpty) continue;
            final st = ((s['start'] as num?) ?? 0).toDouble();
            final en = ((s['end'] as num?) ?? (st + 3.0)).toDouble();
            out.add((
              startSec: baseOffsetSec + st,
              endSec: baseOffsetSec + en,
              text: t,
            ));
          }
        }
      } else {
        final text = (data['text'] as String? ?? '').trim();
        if (text.isNotEmpty) {
          out.add((
            startSec: baseOffsetSec,
            endSec: fallbackEndSec,
            text: text,
          ));
        }
      }
    }
    return out;
  }

  Future<String> _translateToChinese(String text) async {
    try {
      final resp = await _dio.get<dynamic>(
        'https://translate.googleapis.com/translate_a/single',
        queryParameters: {
          'client': 'gtx',
          'sl': 'auto',
          'tl': 'zh-CN',
          'dt': 't',
          'q': text,
        },
      );
      final data = resp.data;
      if (data is List && data.isNotEmpty && data.first is List) {
        final buf = StringBuffer();
        for (final part in data.first as List) {
          if (part is List && part.isNotEmpty && part.first is String) {
            buf.write(part.first);
          }
        }
        final translated = buf.toString().trim();
        if (translated.isNotEmpty) return translated;
      }
    } catch (_) {}
    return text;
  }

  String _fmt(double sec) {
    final total = sec.round();
    final m = (total ~/ 60).toString().padLeft(2, '0');
    final s = (total % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
