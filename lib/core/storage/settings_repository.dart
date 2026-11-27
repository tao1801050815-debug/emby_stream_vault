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
  }
}
