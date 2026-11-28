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
  static const _layoutModeKey = 'pref_library_layout_mode';
  static const _syncProviderKey = 'pref_sync_provider';
  static const _syncGistTokenKey = 'pref_sync_gist_token';
  static const _syncGistIdKey = 'pref_sync_gist_id';
  static const _syncWebDavUrlKey = 'pref_sync_webdav_url';
  static const _syncWebDavUserKey = 'pref_sync_webdav_user';
  static const _syncWebDavPassKey = 'pref_sync_webdav_pass';
  static const _lastSyncAtMsKey = 'pref_last_sync_at_ms';
  static const _novelLanUrlKey = 'pref_novel_lan_url';
  static const _readerFontSizeKey = 'pref_reader_font_size';
  static const _readerLineHeightKey = 'pref_reader_line_height';
  static const _readerThemeModeKey = 'pref_reader_theme_mode';
  static const _appLockEnabledKey = 'pref_app_lock_enabled';
  static const _appLockPinHashKey = 'pref_app_lock_pin_hash';
  static const _lockOnBgKey = 'pref_lock_on_background';

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
      libraryLayoutMode: prefs.getString(_layoutModeKey) ?? 'missav',
      syncProvider: prefs.getString(_syncProviderKey) ?? 'gist',
      syncGistToken: prefs.getString(_syncGistTokenKey) ?? '',
      syncGistId: prefs.getString(_syncGistIdKey) ?? '',
      syncWebDavUrl: prefs.getString(_syncWebDavUrlKey) ??
          'https://dav.jianguoyun.com/dav/EmbyStreamVault/sync.json',
      syncWebDavUser: prefs.getString(_syncWebDavUserKey) ?? '',
      syncWebDavPass: prefs.getString(_syncWebDavPassKey) ?? '',
      lastSyncAtMs: prefs.getInt(_lastSyncAtMsKey) ?? 0,
      novelLanServerUrl:
          prefs.getString(_novelLanUrlKey) ?? 'http://192.168.1.2:8765',
      readerFontSize: prefs.getDouble(_readerFontSizeKey) ?? 17.5,
      readerLineHeight: prefs.getDouble(_readerLineHeightKey) ?? 1.75,
      readerThemeMode: prefs.getString(_readerThemeModeKey) ?? 'dark',
      appLockEnabled: prefs.getBool(_appLockEnabledKey) ?? false,
      appLockPinHash: prefs.getString(_appLockPinHashKey) ?? '',
      lockOnBackground: prefs.getBool(_lockOnBgKey) ?? true,
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
    await prefs.setString(_layoutModeKey, value.libraryLayoutMode);
    await prefs.setString(_syncProviderKey, value.syncProvider);
    await prefs.setString(_syncGistTokenKey, value.syncGistToken);
    await prefs.setString(_syncGistIdKey, value.syncGistId);
    await prefs.setString(_syncWebDavUrlKey, value.syncWebDavUrl);
    await prefs.setString(_syncWebDavUserKey, value.syncWebDavUser);
    await prefs.setString(_syncWebDavPassKey, value.syncWebDavPass);
    await prefs.setInt(_lastSyncAtMsKey, value.lastSyncAtMs);
    await prefs.setString(_novelLanUrlKey, value.novelLanServerUrl);
    await prefs.setDouble(_readerFontSizeKey, value.readerFontSize);
    await prefs.setDouble(_readerLineHeightKey, value.readerLineHeight);
    await prefs.setString(_readerThemeModeKey, value.readerThemeMode);
    await prefs.setBool(_appLockEnabledKey, value.appLockEnabled);
    await prefs.setString(_appLockPinHashKey, value.appLockPinHash);
    await prefs.setBool(_lockOnBgKey, value.lockOnBackground);
  }
}
