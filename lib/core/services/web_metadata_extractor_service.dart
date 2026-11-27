import 'package:dio/dio.dart';

class ExtractedWebMetadata {
  final String url;
  final String code;
  final String title;
  final String posterUrl;
  final String sourceSite;
  final List<String> tags;
  final List<String> actors;

  const ExtractedWebMetadata({
    required this.url,
    required this.code,
    required this.title,
    required this.posterUrl,
    required this.sourceSite,
    this.tags = const [],
    this.actors = const [],
  });
}

/// 从任意视频网页 URL 自动提取名称、封面、番号、站点来源与自带标签（支持 MissAV / JavDB / Pornhub / xHamster 等）
class WebMetadataExtractorService {
  WebMetadataExtractorService._();
  static final WebMetadataExtractorService instance =
      WebMetadataExtractorService._();

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 12),
      followRedirects: true,
      headers: const {
        'User-Agent':
            'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1',
        'Accept-Language': 'zh-CN,zh-TW;q=0.9,zh;q=0.8,en;q=0.7',
      },
    ),
  );

  /// 根据 URL + 页面 HTML 提取元数据；即使目标站开启了 CF 盾也能从 URL 智能兜底提取番号与站点
  Future<ExtractedWebMetadata> extractFromUrl(String rawUrl) async {
    var normalized = rawUrl.trim();
    if (!normalized.startsWith('http://') &&
        !normalized.startsWith('https://')) {
      normalized = 'https://$normalized';
    }
    final uri = Uri.tryParse(normalized);
    final siteKey = inferSiteKey(uri?.host ?? '');
    var fallbackCode = extractCodeFromText(normalized);
    var title = '';
    var posterUrl = '';
    final tags = <String>{};
    final actors = <String>{};

    if (normalized.toLowerCase().contains('uncensored-leak')) {
      tags.add('无码流出');
    } else if (normalized.toLowerCase().contains('uncensored')) {
      tags.add('无码');
    }
    if (normalized.toLowerCase().contains('chinese-subtitle')) {
      tags.add('中文字幕');
    }

    try {
      final resp = await _dio.get<String>(
        normalized,
        options: Options(
          responseType: ResponseType.plain,
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      final html = resp.data ?? '';
      if (resp.statusCode == 200 && html.isNotEmpty) {
        title = _matchMetaContent(html, 'og:title') ??
            _matchMetaContent(html, 'twitter:title') ??
            _matchTitleTag(html) ??
            '';
        title = _decodeHtmlEntities(title).trim();
        // 清理常见站点后缀
        title = title
            .replaceAll(RegExp(r'\s*[-|]\s*(MissAV|Pornhub|xHamster|JavDB|Jable).*$', caseSensitive: false), '')
            .trim();

        posterUrl = _matchMetaContent(html, 'og:image') ??
            _matchMetaContent(html, 'twitter:image') ??
            '';
        posterUrl = _resolveUrl(uri, _decodeHtmlEntities(posterUrl).trim());

        if (fallbackCode.isEmpty) {
          fallbackCode = extractCodeFromText('$normalized $title');
        }

        tags.addAll(extractTagsFromHtml(html));
        actors.addAll(extractActorsFromHtml(html));
      }
    } catch (_) {
      // 网络失败或 CF 盾阻拦时走下方 URL 规则兜底
    }

    // MissAV 若遇到 CF 盾未拿到封面，但 URL 有标准番号，可智能推导高清封面兜底
    if (posterUrl.isEmpty &&
        siteKey == 'missav' &&
        RegExp(r'^[A-Za-z]{2,6}-\d{2,5}$').hasMatch(fallbackCode)) {
      final lowerCode = fallbackCode.toLowerCase();
      posterUrl = 'https://fourhoi.com/$lowerCode/cover-n.jpg';
    }

    final finalCode = fallbackCode.isNotEmpty
        ? fallbackCode
        : 'ITEM-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';

    return ExtractedWebMetadata(
      url: normalized,
      code: finalCode,
      title: title.isNotEmpty ? title : finalCode,
      posterUrl: posterUrl,
      sourceSite: siteKey,
      tags: tags.take(20).toList(),
      actors: actors.take(12).toList(),
    );
  }

  /// 构建唯一媒体库 ID（区分同一番号的普通版与无码版，确保播放精准对应用户收藏版本）
  static String buildMediaId({
    required String siteKey,
    required String code,
    required String sourceUrl,
    List<String> tags = const [],
  }) {
    final lowerUrl = sourceUrl.toLowerCase();
    final isUncensored = lowerUrl.contains('uncensored') ||
        tags.any((t) => t.contains('无码') || t.contains('無碼'));
    if (isUncensored) {
      return '${siteKey}_${code}_uncensored';
    }
    return '${siteKey}_$code';
  }

  static String inferSiteKey(String host) {
    final h = host.toLowerCase().replaceAll(RegExp(r'^www\.'), '');
    if (h.isEmpty) return 'custom';
    if (h.contains('missav')) return 'missav';
    if (h.contains('javdb')) return 'javdb';
    if (h.contains('jable')) return 'jable';
    if (h.contains('pornhub')) return 'pornhub';
    if (h.contains('xhamster')) return 'xhamster';
    if (h.contains('hanime')) return 'hanime1';
    if (h.contains('motv')) return 'motv';
    if (h.contains('tangxin')) return 'tangxinvlog';
    if (h.contains('didktiekw')) return 'didktiekw';
    return h.split('.').first;
  }

  static String extractCodeFromText(String text) {
    final std = RegExp(r'([A-Za-z]{2,6}-\d{2,5}|FC2-PPV-\d{5,7})',
            caseSensitive: false)
        .firstMatch(text);
    if (std != null) {
      return std.group(1)!.toUpperCase();
    }
    final ph =
        RegExp(r'viewkey=([a-zA-Z0-9]+)', caseSensitive: false).firstMatch(text);
    if (ph != null) {
      final key = ph.group(1)!;
      return 'PH-${key.substring(0, key.length.clamp(0, 10)).toUpperCase()}';
    }
    final xh = RegExp(r'xhamster\.com/videos/.*-([a-zA-Z0-9]+)(?:$|[/?])',
            caseSensitive: false)
        .firstMatch(text);
    if (xh != null) {
      final key = xh.group(1)!;
      final start = key.length > 8 ? key.length - 8 : 0;
      return 'XH-${key.substring(start).toUpperCase()}';
    }
    return '';
  }

  static List<String> extractTagsFromHtml(String html) {
    final found = <String>{};
    // 匹配 MissAV (/genres/...), JavDB (/tags...), Pornhub/xHamster (/categories/...) 的锚点文字
    final reg = RegExp(
      r'<a[^>]+href=["\x27][^"\x27]*(?:/genres/|/tags(?:/|\?)|/categories/|genre=)[^"\x27]*["\x27][^>]*>([\s\S]*?)</a>',
      caseSensitive: false,
    );
    const ignore = {
      '全部',
      '更多',
      '首页',
      '首頁',
      '类型',
      '類型',
      '标签',
      '標籤',
      'categories',
      'tags',
      'all',
      'more',
    };
    for (final m in reg.allMatches(html)) {
      final raw = m
          .group(1)!
          .replaceAll(RegExp(r'<[^>]+>'), '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      final clean = _decodeHtmlEntities(raw).replaceAll(RegExp(r'^#'), '').trim();
      if (clean.isNotEmpty &&
          clean.length <= 18 &&
          !ignore.contains(clean.toLowerCase())) {
        found.add(clean);
      }
    }
    return found.toList();
  }

  static List<String> extractActorsFromHtml(String html) {
    final found = <String>{};
    final reg = RegExp(
      r'<a[^>]+href=["\x27][^"\x27]*(?:/actors/|/actresses/|/pornstars/|/star/)[^"\x27]*["\x27][^>]*>([\s\S]*?)</a>',
      caseSensitive: false,
    );
    const ignore = {'女优', '女優', '演员', '演員', 'actors', 'actresses', 'pornstars'};
    for (final m in reg.allMatches(html)) {
      final raw = m
          .group(1)!
          .replaceAll(RegExp(r'<[^>]+>'), '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      final clean = _decodeHtmlEntities(raw).trim();
      if (clean.isNotEmpty &&
          clean.length <= 24 &&
          !ignore.contains(clean.toLowerCase())) {
        found.add(clean);
      }
    }
    return found.toList();
  }

  static String? _matchMetaContent(String html, String propName) {
    final r1 = RegExp(
      '<meta[^>]+(?:property|name)=["\']$propName["\'][^>]+content=["\']([^"\']+)["\']',
      caseSensitive: false,
    ).firstMatch(html);
    if (r1 != null) return r1.group(1);
    final r2 = RegExp(
      '<meta[^>]+content=["\']([^"\']+)["\'][^>]+(?:property|name)=["\']$propName["\']',
      caseSensitive: false,
    ).firstMatch(html);
    return r2?.group(1);
  }

  static String? _matchTitleTag(String html) {
    final m =
        RegExp(r'<title[^>]*>([\s\S]*?)</title>', caseSensitive: false)
            .firstMatch(html);
    return m?.group(1);
  }

  static String _resolveUrl(Uri? base, String raw) {
    if (raw.isEmpty) return '';
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    if (raw.startsWith('//')) return 'https:$raw';
    if (base == null) return raw;
    return base.resolve(raw).toString();
  }

  static String _decodeHtmlEntities(String input) {
    return input
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#039;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&nbsp;', ' ');
  }
}
