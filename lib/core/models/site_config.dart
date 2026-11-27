import 'dart:convert';

/// 站点配置（支持用户热更新最新可用域名）
class SiteProfile {
  final String key;
  final String name;
  final String baseUrl;
  final String searchTemplate; // 例如 {base}/search/{query}
  final String loginUrl;
  final bool enabled;

  const SiteProfile({
    required this.key,
    required this.name,
    required this.baseUrl,
    required this.searchTemplate,
    required this.loginUrl,
    this.enabled = true,
  });

  String buildSearchUrl(String query) {
    final encoded = Uri.encodeComponent(query.trim());
    return searchTemplate
        .replaceAll('{base}', baseUrl.replaceAll(RegExp(r'/+$'), ''))
        .replaceAll('{query}', encoded);
  }

  SiteProfile copyWith({
    String? baseUrl,
    String? searchTemplate,
    String? loginUrl,
    bool? enabled,
  }) {
    return SiteProfile(
      key: key,
      name: name,
      baseUrl: baseUrl ?? this.baseUrl,
      searchTemplate: searchTemplate ?? this.searchTemplate,
      loginUrl: loginUrl ?? this.loginUrl,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() => {
        'key': key,
        'name': name,
        'baseUrl': baseUrl,
        'searchTemplate': searchTemplate,
        'loginUrl': loginUrl,
        'enabled': enabled,
      };

  factory SiteProfile.fromJson(Map<String, dynamic> json) => SiteProfile(
        key: json['key'] as String,
        name: json['name'] as String,
        baseUrl: json['baseUrl'] as String,
        searchTemplate: json['searchTemplate'] as String,
        loginUrl: json['loginUrl'] as String,
        enabled: (json['enabled'] as bool?) ?? true,
      );

  static List<SiteProfile> defaults() => const [
        SiteProfile(
          key: 'missav',
          name: 'MissAV（在线播放 & 账号）',
          baseUrl: 'https://missav.ws',
          searchTemplate: '{base}/cn/search/{query}',
          loginUrl: 'https://missav.ws/cn/login',
        ),
        SiteProfile(
          key: 'javdb',
          name: 'JavDB（找片 & 元数据）',
          baseUrl: 'https://javdb.com',
          searchTemplate: '{base}/search?q={query}&f=all',
          loginUrl: 'https://javdb.com/login',
        ),
        SiteProfile(
          key: 'jable',
          name: 'Jable（备用流媒体）',
          baseUrl: 'https://jable.tv',
          searchTemplate: '{base}/search/{query}/',
          loginUrl: 'https://jable.tv',
        ),
        SiteProfile(
          key: 'pornhub',
          name: 'Pornhub',
          baseUrl: 'https://www.pornhub.com',
          searchTemplate: '{base}/video/search?search={query}',
          loginUrl: 'https://www.pornhub.com/login',
        ),
        SiteProfile(
          key: 'xhamster',
          name: 'xHamster',
          baseUrl: 'https://xhamster.com',
          searchTemplate: '{base}/search/{query}',
          loginUrl: 'https://xhamster.com',
        ),
        SiteProfile(
          key: 'hanime1',
          name: 'Hanime1（里番/动漫）',
          baseUrl: 'https://hanime1.me',
          searchTemplate: '{base}/search?query={query}',
          loginUrl: 'https://hanime1.me/login',
        ),
        SiteProfile(
          key: 'motv',
          name: 'MoTV',
          baseUrl: 'https://motv.app',
          searchTemplate: '{base}/search/{query}',
          loginUrl: 'https://motv.app',
        ),
        SiteProfile(
          key: 'tangxinvlog',
          name: '糖心Vlog',
          baseUrl: 'https://tangxinvlog.app',
          searchTemplate: '{base}/search/{query}',
          loginUrl: 'https://tangxinvlog.app',
        ),
        SiteProfile(
          key: 'didktiekw',
          name: 'Active1 (didktiekw)',
          baseUrl: 'https://active1.didktiekw.cc',
          searchTemplate: '{base}/search/{query}',
          loginUrl: 'https://active1.didktiekw.cc',
        ),
      ];

  static String encodeList(List<SiteProfile> items) =>
      jsonEncode(items.map((e) => e.toJson()).toList());

  static List<SiteProfile> decodeList(String raw) {
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => SiteProfile.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

/// 播放器与浏览偏好设置
class AppPreferences {
  final int seekSeconds;
  final double defaultSpeed;
  final bool autoBackgroundPlay;
  final bool enableSharpness;
  final bool blockPopupAds;
  final String customUserAgent;
  // 纯手机端 AI 实时字幕配置（支持 Groq / 硅基流动 / OpenAI 兼容接口）
  final String aiApiBaseUrl;
  final String aiApiKey;
  final String aiAsrModel;
  final String aiSourceLang; // auto / ja / en
  final bool aiBilingual;
  // 应用自动更新与全能签软件源配置
  final String updateFeedUrl;
  final bool autoCheckUpdate;
  // 主页排版模式：'missav'（两部并列）或 'pornhub'（单列整屏宽横卡）
  final String libraryLayoutMode;

  const AppPreferences({
    this.seekSeconds = 10,
    this.defaultSpeed = 1.0,
    this.autoBackgroundPlay = true,
    this.enableSharpness = false,
    this.blockPopupAds = true,
    this.customUserAgent = '',
    this.aiApiBaseUrl = 'https://api.groq.com/openai/v1',
    this.aiApiKey = '',
    this.aiAsrModel = 'whisper-large-v3-turbo',
    this.aiSourceLang = 'ja',
    this.aiBilingual = true,
    this.updateFeedUrl =
        'https://github.com/tao1801050815-debug/emby_stream_vault/releases/download/latest/apps.json',
    this.autoCheckUpdate = true,
    this.libraryLayoutMode = 'missav',
  });

  AppPreferences copyWith({
    int? seekSeconds,
    double? defaultSpeed,
    bool? autoBackgroundPlay,
    bool? enableSharpness,
    bool? blockPopupAds,
    String? customUserAgent,
    String? aiApiBaseUrl,
    String? aiApiKey,
    String? aiAsrModel,
    String? aiSourceLang,
    bool? aiBilingual,
    String? updateFeedUrl,
    bool? autoCheckUpdate,
    String? libraryLayoutMode,
  }) {
    return AppPreferences(
      seekSeconds: seekSeconds ?? this.seekSeconds,
      defaultSpeed: defaultSpeed ?? this.defaultSpeed,
      autoBackgroundPlay: autoBackgroundPlay ?? this.autoBackgroundPlay,
      enableSharpness: enableSharpness ?? this.enableSharpness,
      blockPopupAds: blockPopupAds ?? this.blockPopupAds,
      customUserAgent: customUserAgent ?? this.customUserAgent,
      aiApiBaseUrl: aiApiBaseUrl ?? this.aiApiBaseUrl,
      aiApiKey: aiApiKey ?? this.aiApiKey,
      aiAsrModel: aiAsrModel ?? this.aiAsrModel,
      aiSourceLang: aiSourceLang ?? this.aiSourceLang,
      aiBilingual: aiBilingual ?? this.aiBilingual,
      updateFeedUrl: updateFeedUrl ?? this.updateFeedUrl,
      autoCheckUpdate: autoCheckUpdate ?? this.autoCheckUpdate,
      libraryLayoutMode: libraryLayoutMode ?? this.libraryLayoutMode,
    );
  }
}
