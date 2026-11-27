import 'package:dio/dio.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// 从 JavDB 自动抓取番号的网上大众评分（含多域名兜底与 WebView Cookie 共享）
class RatingFetcherService {
  RatingFetcherService._();
  static final RatingFetcherService instance = RatingFetcherService._();

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 12),
      followRedirects: true,
      headers: const {
        'User-Agent':
            'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1',
        'Accept-Language': 'zh-TW,zh;q=0.9,en;q=0.8',
      },
    ),
  );

  /// 从任意番号文本（包括漏写横杠的如 mimk134、或带后缀的 MIMK-173-C）提取标准可查番号
  static String? normalizeLookupCode(String raw) {
    final trimmed = raw.trim().toUpperCase();
    if (trimmed.isEmpty) return null;

    // 1. 标准带横杠番号：SSIS-001 / MIMK-173 / FC2-PPV-1234567 / 259LUXU-1234
    final std = RegExp(
      r'([A-Z0-9]{2,7}-\d{2,6}|FC2-PPV-\d{5,7})',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (std != null) {
      final matched = std.group(1)!.toUpperCase();
      // 排除内部自动生成的占位前缀
      if (matched.startsWith('ITEM-') ||
          matched.startsWith('CUSTOM-') ||
          matched.startsWith('PH-') ||
          matched.startsWith('XH-') ||
          matched.startsWith('HN-')) {
        return null;
      }
      return matched;
    }

    // 2. 漏写横杠的纯字母+数字番号：如 mimk134 -> MIMK-134
    final noDash =
        RegExp(r'^([A-Z]{2,6})(\d{2,5})[A-Z]?$').firstMatch(trimmed);
    if (noDash != null) {
      return '${noDash.group(1)}-${noDash.group(2)}';
    }

    return null;
  }

  bool isStandardCode(String code) => normalizeLookupCode(code) != null;

  /// 解析 JavDB 搜索结果页 HTML，精准核对 `<a href="/v/...">` 卡片内的 `<strong>番号</strong>` 提取评分
  static double? parseJavdbSearchHtml(String html, String targetCode) {
    if (html.isEmpty) return null;
    final upperTarget = targetCode.trim().toUpperCase();
    final compactTarget = upperTarget.replaceAll('-', '');

    // 逐张视频卡片匹配：<a href="/v/xxx" class="box"> ... <strong>MIMK-134</strong> ... class="score" ... 4.3分 ... </a>
    final cardReg = RegExp(
      r'<a[^>]+href=["\x27]/v/[^"\x27]+["\x27][\s\S]{0,2200}?</a>',
      caseSensitive: false,
    );

    double? firstCardFallback;

    for (final cardMatch in cardReg.allMatches(html)) {
      final cardHtml = cardMatch.group(0)!;
      final codeMatch = RegExp(
        r'<strong>\s*([^<]+?)\s*</strong>',
        caseSensitive: false,
      ).firstMatch(cardHtml);
      final cardCode = (codeMatch?.group(1) ?? '').trim().toUpperCase();
      final compactCardCode = cardCode.replaceAll('-', '');

      final score = _extractScoreFromBlock(cardHtml);
      if (score == null) continue;

      firstCardFallback ??= score;

      if (cardCode == upperTarget ||
          compactCardCode == compactTarget ||
          cardCode.startsWith('$upperTarget ') ||
          cardCode.startsWith('$upperTarget-')) {
        return score;
      }
    }

    return firstCardFallback;
  }

  static double? _extractScoreFromBlock(String block) {
    // 兼容中文与英文界面：
    // "4.25分, 由750人評價" / "4.3分" / "4.25, by 750 users" / "4.25 / 5"
    final scoreSection = RegExp(
      r'class=["\x27][^"\x27]*score[^"\x27]*["\x27][\s\S]{0,420}?([0-5](?:\.\d{1,2})?)\s*(?:分|stars|,|\s*by|\s*/\s*5)',
      caseSensitive: false,
    ).firstMatch(block);

    if (scoreSection != null) {
      final val = double.tryParse(scoreSection.group(1) ?? '');
      if (val != null && val > 0 && val <= 5.0) {
        return val;
      }
    }
    return null;
  }

  Future<String> _buildCookieHeader(String baseUrl) async {
    final parts = <String>['over18=1', 'locale=zh'];
    try {
      final cookies =
          await CookieManager.instance().getCookies(url: WebUri(baseUrl));
      for (final c in cookies) {
        if (c.name != 'over18' && c.name != 'locale') {
          parts.add('${c.name}=${c.value}');
        }
      }
    } catch (_) {
      // 非移动端环境或 WebView 未初始化时静默忽略
    }
    return parts.join('; ');
  }

  Future<({double rating, String source})?> fetchPublicRating({
    required String code,
    String javdbBaseUrl = 'https://javdb.com',
  }) async {
    final cleanCode = normalizeLookupCode(code);
    if (cleanCode == null) return null;

    final primaryBase = javdbBaseUrl.replaceAll(RegExp(r'/+$'), '');
    final candidateBases = <String>{
      primaryBase,
      'https://javdb.com',
    }.toList();

    for (final base in candidateBases) {
      final searchUrl =
          '$base/search?q=${Uri.encodeComponent(cleanCode)}&f=all';
      final cookieHeader = await _buildCookieHeader(base);
      try {
        final resp = await _dio.get<String>(
          searchUrl,
          options: Options(
            responseType: ResponseType.plain,
            headers: {'Cookie': cookieHeader},
            validateStatus: (s) => s != null && s < 500,
          ),
        );
        if (resp.statusCode != 200 || resp.data == null) continue;
        final score = parseJavdbSearchHtml(resp.data!, cleanCode);
        if (score != null) {
          return (rating: score, source: 'JavDB');
        }
      } catch (_) {
        // 尝试下一个候选域名
      }
    }
    return null;
  }
}
