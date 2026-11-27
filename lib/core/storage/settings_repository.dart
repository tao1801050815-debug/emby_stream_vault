import 'package:shared_preferences/shared_preferences.dart';
import '../models/site_config.dart';

/// 站点域名与播放器偏好的本地持久化
class SettingsRepository {
  static const _sitesKey = 'site_profiles_v1';
  static const _seekKey = 'pref_seek_seconds';
  static const _speedKey = 'pref_default_speed';
  static const _bgPlayKey = 'pref_bg_play';
  static const _sharpnessKey = 'pref_sharpness';
  static const _blockAdsKey = 'pref_block_ads';
  static const _uaKey = 'pref_custom_ua';
  static const _aiBaseUrlKey = 'pref_ai_base_url';
  static const _aiApiKey = 'pref_ai_api_key';
  static const _aiAsrModelKey = 'pref_ai_asr_model';
  static const _aiSourceLangKey = 'pref_ai_source_lang';
  static const _aiBilingualKey = 'pref_ai_bilingual';
  static const _updateFeedUrlKey = 'pref_update_feed_url';
  static const _autoCheckUpdateKey = 'pref_auto_check_update';

  Future<List<SiteProfile>> loadSites() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_sitesKey);
    if (raw == null || raw.isEmpty) {
      return SiteProfile.defaults();
    }
    try {
      return SiteProfile.decodeList(raw);
    } catch (_) {
      return SiteProfile.defaults();
    }
  }

  Future<void> saveSites(List<SiteProfile> sites) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sitesKey, SiteProfile.encodeList(sites));
  }

  Future<AppPreferences> loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    return AppPreferences(
      seekSeconds: prefs.getInt(_seekKey) ?? 10,
      defaultSpeed: prefs.getDouble(_speedKey) ?? 1.0,
      autoBackgroundPlay: prefs.getBool(_bgPlayKey) ?? true,
      enableSharpness: prefs.getBool(_sharpnessKey) ?? false,
      blockPopupAds: prefs.getBool(_blockAdsKey) ?? true,
      customUserAgent: prefs.getString(_uaKey) ?? '',
      aiApiBaseUrl:
          prefs.getString(_aiBaseUrlKey) ?? 'https://api.groq.com/openai/v1',
      aiApiKey: prefs.getString(_aiApiKey) ?? '',
      aiAsrModel:
          prefs.getString(_aiAsrModelKey) ?? 'whisper-large-v3-turbo',
      aiSourceLang: prefs.getString(_aiSourceLangKey) ?? 'ja',
      aiBilingual: prefs.getBool(_aiBilingualKey) ?? true,
      updateFeedUrl: prefs.getString(_updateFeedUrlKey) ??
          'https://github.com/tao1801050815-debug/emby_stream_vault/releases/download/latest/apps.json',
      autoCheckUpdate: prefs.getBool(_autoCheckUpdateKey) ?? true,
    );
  }

  Future<void> savePreferences(AppPreferences value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_seekKey, value.seekSeconds);
    await prefs.setDouble(_speedKey, value.defaultSpeed);
    await prefs.setBool(_bgPlayKey, value.autoBackgroundPlay);
    await prefs.setBool(_sharpnessKey, value.enableSharpness);
    await prefs.setBool(_blockAdsKey, value.blockPopupAds);
    await prefs.setString(_uaKey, value.customUserAgent);
    await prefs.setString(_aiBaseUrlKey, value.aiApiBaseUrl);
    await prefs.setString(_aiApiKey, value.aiApiKey);
    await prefs.setString(_aiAsrModelKey, value.aiAsrModel);
    await prefs.setString(_aiSourceLangKey, value.aiSourceLang);
    await prefs.setBool(_aiBilingualKey, value.aiBilingual);
    await prefs.setString(_updateFeedUrlKey, value.updateFeedUrl);
    await prefs.setBool(_autoCheckUpdateKey, value.autoCheckUpdate);
  }
}
