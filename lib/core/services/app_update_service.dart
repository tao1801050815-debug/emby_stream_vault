import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/emby_theme.dart';

/// 编译期注入的版本号与构建号（由 GitHub Actions 自动递增）
const String kAppVersion =
    String.fromEnvironment('APP_VERSION', defaultValue: '1.1.02');
const int kAppBuildNumber =
    int.fromEnvironment('APP_BUILD', defaultValue: 0);

/// 默认软件源地址（兼容全能签 / 轻松签 / AltStore 与 App 内更新检测）
const String kDefaultUpdateFeedUrl =
    'https://github.com/tao1801050815-debug/emby_stream_vault/releases/download/latest/apps.json';

class AppReleaseInfo {
  final String version;
  final int buildNumber;
  final String versionDate;
  final String changelog;
  final String ipaDownloadUrl;
  final String apkDownloadUrl;
  final int sizeBytes;

  const AppReleaseInfo({
    required this.version,
    required this.buildNumber,
    required this.versionDate,
    required this.changelog,
    required this.ipaDownloadUrl,
    required this.apkDownloadUrl,
    required this.sizeBytes,
  });

  String get formattedSize {
    if (sizeBytes <= 0) return '未知大小';
    final mb = sizeBytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }
}

class AppUpdateCheckResult {
  final bool hasUpdate;
  final AppReleaseInfo? release;
  final String? error;

  const AppUpdateCheckResult({
    required this.hasUpdate,
    this.release,
    this.error,
  });
}

/// 基于 GitHub Release 软件源 (apps.json) 的轻量级更新检查服务
class AppUpdateService {
  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 12),
      followRedirects: true,
    ),
  );

  static Future<AppUpdateCheckResult> checkForUpdate({
    required String feedUrl,
  }) async {
    final trimmed = feedUrl.trim();
    if (trimmed.isEmpty) {
      return const AppUpdateCheckResult(
        hasUpdate: false,
        error: '更新源地址为空',
      );
    }

    try {
      final sep = trimmed.contains('?') ? '&' : '?';
      final url = '$trimmed${sep}_t=${DateTime.now().millisecondsSinceEpoch}';
      final resp = await _dio.get<dynamic>(
        url,
        options: Options(responseType: ResponseType.plain),
      );
      if (resp.statusCode != 200 || resp.data == null) {
        return AppUpdateCheckResult(
          hasUpdate: false,
          error: '拉取更新源失败（HTTP ${resp.statusCode}）',
        );
      }

      final decoded = jsonDecode(resp.data.toString());
      if (decoded is! Map<String, dynamic>) {
        return const AppUpdateCheckResult(
          hasUpdate: false,
          error: '软件源 JSON 格式无效',
        );
      }

      final apps = decoded['apps'];
      if (apps is! List || apps.isEmpty || apps.first is! Map) {
        return const AppUpdateCheckResult(
          hasUpdate: false,
          error: '软件源中未找到应用信息',
        );
      }

      final app = Map<String, dynamic>.from(apps.first as Map);
      final remoteVersion = (app['version'] ?? '').toString().trim();
      final remoteBuild = _parseBuildNumber(app['buildNumber'], remoteVersion);
      final release = AppReleaseInfo(
        version: remoteVersion.isEmpty ? '1.0.$remoteBuild' : remoteVersion,
        buildNumber: remoteBuild,
        versionDate: (app['versionDate'] ?? '').toString(),
        changelog: (app['versionDescription'] ?? '包含最新功能与修复').toString(),
        ipaDownloadUrl: (app['downloadURL'] ?? '').toString(),
        apkDownloadUrl: (app['androidDownloadURL'] ?? '').toString(),
        sizeBytes: (app['size'] is num) ? (app['size'] as num).toInt() : 0,
      );

      final hasUpdate = _isNewer(
        remoteBuild: release.buildNumber,
        remoteVersion: release.version,
      );
      return AppUpdateCheckResult(hasUpdate: hasUpdate, release: release);
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 404) {
        return const AppUpdateCheckResult(
          hasUpdate: false,
          error: '未找到 apps.json（请确认仓库已公开，且 GitHub Actions 已跑完最新一轮构建）',
        );
      }
      return AppUpdateCheckResult(
        hasUpdate: false,
        error: '网络请求失败：${e.message ?? '请检查网络或配置加速代理'}',
      );
    } catch (e) {
      return AppUpdateCheckResult(
        hasUpdate: false,
        error: '解析更新信息失败：$e',
      );
    }
  }

  static int _parseBuildNumber(dynamic rawBuild, String version) {
    if (rawBuild is num) return rawBuild.toInt();
    final parsed = int.tryParse(rawBuild?.toString() ?? '');
    if (parsed != null) return parsed;
    final parts = version.split('.');
    if (parts.isNotEmpty) {
      return int.tryParse(parts.last) ?? 0;
    }
    return 0;
  }

  static bool _isNewer({
    required int remoteBuild,
    required String remoteVersion,
  }) {
    if (remoteBuild > 0 && kAppBuildNumber > 0) {
      return remoteBuild > kAppBuildNumber;
    }
    if (remoteBuild > 0 && kAppBuildNumber == 0) {
      // 兼容旧版未注入 buildNumber 的安装包
      return remoteVersion.isNotEmpty && remoteVersion != kAppVersion;
    }
    return remoteVersion.isNotEmpty && remoteVersion != kAppVersion;
  }

  /// 弹出版本更新提示框（适配全能签一键覆盖更新）
  static Future<void> showUpdateDialog(
    BuildContext context, {
    required AppReleaseInfo release,
    required String feedUrl,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.system_update_rounded, color: EmbyTheme.accent),
            const SizedBox(width: 8),
            Expanded(child: Text('发现新版本 v${release.version}')),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '当前版本：v$kAppVersion (build $kAppBuildNumber)\n'
                '最新版本：v${release.version} · ${release.formattedSize}',
                style: const TextStyle(
                  fontSize: 12,
                  color: EmbyTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '更新内容：',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: EmbyTheme.surface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  release.changelog,
                  style: const TextStyle(fontSize: 12, height: 1.45),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '全能签用户直接打开「全能签 → 软件源 → 刷新并点击更新」即可原地覆盖安装，影库数据全部保留。',
                style: TextStyle(fontSize: 12, color: EmbyTheme.accent),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('稍后再说'),
          ),
          OutlinedButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: release.ipaDownloadUrl));
              if (ctx.mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已复制最新版 IPA 下载链接')),
                );
              }
            },
            child: const Text('复制 IPA 链接'),
          ),
          FilledButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: feedUrl));
              if (ctx.mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('已复制全能签软件源地址，打开全能签刷新即可更新'),
                  ),
                );
              }
            },
            child: const Text('复制全能签源'),
          ),
        ],
      ),
    );
  }
}
