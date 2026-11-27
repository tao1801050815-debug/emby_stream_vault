import 'package:dio/dio.dart';

/// 从 JavDB 等平台自动抓取番号的网上大众评分
class RatingFetcherService {
  RatingFetcherService._();
  static final RatingFetcherService instance = RatingFetcherService._();

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 12),
      headers: const {
        'User-Agent':
            'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1',
        'Accept-Language': 'zh-TW,zh;q=0.9,en;q=0.8',
      },
    ),
  );

  /// 仅对标准番号（如 SSIS-001 / MIMK-173 / FC2-PPV-123456）查询 JavDB 评分
  bool isStandardCode(String code) {
    return RegExp(r'^([A-Za-z]{2,6}-\d{2,5}|FC2-PPV-\d{5,7})$',
            caseSensitive: false)
        .hasMatch(code.trim());
  }

  Future<({double rating, String source})?> fetchPublicRating({
    required String code,
    String javdbBaseUrl = 'https://javdb.com',
  }) async {
    final cleanCode = code.trim().toUpperCase();
    if (!isStandardCode(cleanCode)) return null;

    final base = javdbBaseUrl.replaceAll(RegExp(r'/+$'), '');
    final searchUrl =
        '$base/search?q=${Uri.encodeComponent(cleanCode)}&f=all';

    try {
      final resp = await _dio.get<String>(
        searchUrl,
        options: Options(
          responseType: ResponseType.plain,
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      if (resp.statusCode != 200 || resp.data == null) return null;
      final html = resp.data!;

      // 尝试在包含该番号的上下文附近提取 JavDB 评分（例如 "4.52分, 由128人評價" 或 "4.52 / 5"）
      final idx = html.toUpperCase().indexOf(cleanCode);
      final snippet = idx >= 0
          ? html.substring(
              idx,
              (idx + 2400).clamp(0, html.length),
            )
          : html;

      final match = RegExp(r'([1-5]\.\d{1,2})\s*分')
              .firstMatch(snippet) ??
          RegExp(r'([1-5]\.\d{1,2})\s*/\s*5').firstMatch(snippet);
      if (match != null) {
        final score = double.tryParse(match.group(1) ?? '');
        if (score != null && score > 0 && score <= 5.0) {
          return (rating: score, source: 'JavDB');
        }
      }
    } catch (_) {
      // 网络波动或 Cloudflare 拦截时静默忽略，不影响主流程
    }
    return null;
  }
}
