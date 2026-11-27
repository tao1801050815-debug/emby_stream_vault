import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/site_config.dart';
import '../../core/providers/app_providers.dart';
import '../../core/services/app_update_service.dart';
import '../../core/services/live_ai_subtitle_service.dart';
import '../../core/theme/emby_theme.dart';
import '../browser/webview_sniffer_page.dart';

/// 站点域名热配置、账号登录入口与播放器偏好设置
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sites = ref.watch(siteProfilesProvider);
    final prefs = ref.watch(appPreferencesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('站点与播放设置'),
        actions: [
          IconButton(
            tooltip: '添加自定义站点',
            icon: const Icon(Icons.add_circle_outline_rounded),
            onPressed: () => _addSiteDialog(context, ref),
          ),
          TextButton(
            onPressed: () =>
                ref.read(siteProfilesProvider.notifier).resetDefaults(),
            child: const Text('恢复默认'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              const Expanded(child: _SectionHeader('站点域名配置与账号登录')),
              FilledButton.tonalIcon(
                onPressed: () => _addSiteDialog(context, ref),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('添加片源网站'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...sites.map(
            (site) => Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                title: Text(site.name),
                subtitle: Text(
                  site.baseUrl,
                  style: const TextStyle(color: EmbyTheme.textSecondary),
                ),
                trailing: Wrap(
                  spacing: 4,
                  children: [
                    IconButton(
                      tooltip: '打开登录页',
                      icon: const Icon(Icons.login_rounded,
                          color: EmbyTheme.accent),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => WebViewSnifferPage(
                              initialUrl: site.loginUrl,
                              initialSiteKey: site.key,
                            ),
                          ),
                        );
                      },
                    ),
                    IconButton(
                      tooltip: '修改域名',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => _editSiteDialog(context, ref, site),
                    ),
                    IconButton(
                      tooltip: '删除站点',
                      icon: const Icon(Icons.delete_outline_rounded,
                          color: EmbyTheme.danger),
                      onPressed: () => ref
                          .read(siteProfilesProvider.notifier)
                          .removeSite(site.key),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const _SectionHeader('增强播放器默认参数'),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  title: const Text('快进/快退步长'),
                  subtitle: Text('${prefs.seekSeconds} 秒'),
                  trailing: DropdownButton<int>(
                    value: prefs.seekSeconds,
                    items: const [5, 10, 15, 30, 60]
                        .map((s) => DropdownMenuItem(
                              value: s,
                              child: Text('${s}s'),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      ref
                          .read(appPreferencesProvider.notifier)
                          .update(prefs.copyWith(seekSeconds: v));
                    },
                  ),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('默认开启画面锐化增强'),
                  subtitle: const Text('基于 libmpv sharpen 滤镜'),
                  value: prefs.enableSharpness,
                  onChanged: (v) => ref
                      .read(appPreferencesProvider.notifier)
                      .update(prefs.copyWith(enableSharpness: v)),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('拦截常见弹窗广告域名'),
                  value: prefs.blockPopupAds,
                  onChanged: (v) => ref
                      .read(appPreferencesProvider.notifier)
                      .update(prefs.copyWith(blockPopupAds: v)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const _SectionHeader('AI 实时中文字幕（纯手机端）'),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  title: const Text('语音识别接口与 API Key'),
                  subtitle: Text(
                    prefs.aiApiKey.isNotEmpty
                        ? '${prefs.aiAsrModel} · Key 已配置'
                        : '未配置（点此选择 Groq 免费 / 硅基流动 / OpenAI 预设）',
                    style: const TextStyle(color: EmbyTheme.textSecondary),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _editAiSubtitleDialog(context, ref, prefs),
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('视频原声语言'),
                  trailing: DropdownButton<String>(
                    value: prefs.aiSourceLang,
                    items: const [
                      DropdownMenuItem(value: 'ja', child: Text('日语 (ja)')),
                      DropdownMenuItem(value: 'en', child: Text('英语 (en)')),
                      DropdownMenuItem(value: 'auto', child: Text('自动识别')),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      ref
                          .read(appPreferencesProvider.notifier)
                          .update(prefs.copyWith(aiSourceLang: v));
                    },
                  ),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('显示双语字幕（中文 + 原文）'),
                  value: prefs.aiBilingual,
                  onChanged: (v) => ref
                      .read(appPreferencesProvider.notifier)
                      .update(prefs.copyWith(aiBilingual: v)),
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('管理本地 AI 字幕缓存'),
                  subtitle: const Text('查看占用空间或一键清空全部已保存字幕'),
                  trailing: const Icon(Icons.cleaning_services_outlined,
                      color: EmbyTheme.danger),
                  onTap: () => _manageSubtitleCacheDialog(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const _SectionHeader('应用更新与全能签软件源'),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  title: const Text('检查新版本'),
                  subtitle: Text(
                    '当前版本：v$kAppVersion (build $kAppBuildNumber)',
                    style: const TextStyle(color: EmbyTheme.textSecondary),
                  ),
                  trailing: const Icon(Icons.system_update_rounded,
                      color: EmbyTheme.accent),
                  onTap: () => _checkUpdateNow(context, prefs),
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('复制全能签软件源地址'),
                  subtitle: const Text(
                    '粘贴到全能签 → 软件源，以后 GitHub 构建完即可一键原地更新',
                    style: TextStyle(color: EmbyTheme.textSecondary),
                  ),
                  trailing: const Icon(Icons.copy_rounded),
                  onTap: () async {
                    await Clipboard.setData(
                      ClipboardData(text: prefs.updateFeedUrl),
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('已复制全能签软件源地址，直接粘贴到全能签即可'),
                        ),
                      );
                    }
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('启动时自动检查更新'),
                  subtitle: const Text('检测到 GitHub 发布新版时自动弹窗提醒'),
                  value: prefs.autoCheckUpdate,
                  onChanged: (v) => ref
                      .read(appPreferencesProvider.notifier)
                      .update(prefs.copyWith(autoCheckUpdate: v)),
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('自定义更新源地址 / 加速代理'),
                  subtitle: Text(
                    prefs.updateFeedUrl,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: EmbyTheme.textSecondary),
                  ),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () => _editUpdateFeedDialog(context, ref, prefs),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editAiSubtitleDialog(
    BuildContext context,
    WidgetRef ref,
    AppPreferences prefs,
  ) async {
    final baseCtrl = TextEditingController(text: prefs.aiApiBaseUrl);
    final keyCtrl = TextEditingController(text: prefs.aiApiKey);
    final modelCtrl = TextEditingController(text: prefs.aiAsrModel);

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('配置 AI 实时字幕'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '一键填充预设：',
                style: TextStyle(fontSize: 12, color: EmbyTheme.textSecondary),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  ActionChip(
                    label: const Text('Groq 免费极速'),
                    onPressed: () {
                      baseCtrl.text = 'https://api.groq.com/openai/v1';
                      modelCtrl.text = 'whisper-large-v3-turbo';
                    },
                  ),
                  ActionChip(
                    label: const Text('硅基流动 国内直连'),
                    onPressed: () {
                      baseCtrl.text = 'https://api.siliconflow.cn/v1';
                      modelCtrl.text = 'FunAudioLLM/SenseVoiceSmall';
                    },
                  ),
                  ActionChip(
                    label: const Text('OpenAI'),
                    onPressed: () {
                      baseCtrl.text = 'https://api.openai.com/v1';
                      modelCtrl.text = 'whisper-1';
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: baseCtrl,
                decoration: const InputDecoration(labelText: 'API Base URL'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: modelCtrl,
                decoration: const InputDecoration(labelText: '语音识别模型名'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: keyCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'API Key (sk-... / gsk_...)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );

    if (saved == true) {
      await ref.read(appPreferencesProvider.notifier).update(
            prefs.copyWith(
              aiApiBaseUrl: baseCtrl.text.trim(),
              aiApiKey: keyCtrl.text.trim(),
              aiAsrModel: modelCtrl.text.trim(),
            ),
          );
    }
    baseCtrl.dispose();
    keyCtrl.dispose();
    modelCtrl.dispose();
  }

  Future<void> _manageSubtitleCacheDialog(BuildContext context) async {
    final stats = await LiveAiSubtitleSession.getCacheStats();
    if (!context.mounted) return;
    final kb = (stats.totalBytes / 1024).toStringAsFixed(1);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('本地 AI 字幕缓存'),
        content: Text(
          stats.count == 0
              ? '当前没有本地 AI 字幕缓存。'
              : '当前共缓存了 ${stats.count} 部影片的 AI 字幕，仅占用 $kb KB 空间。\n是否一键清空全部本地字幕缓存？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('关闭'),
          ),
          if (stats.count > 0)
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('全部清空'),
            ),
        ],
      ),
    );
    if (confirmed == true) {
      final deleted = await LiveAiSubtitleSession.clearAllCachedSubtitles();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已清空 $deleted 份本地 AI 字幕缓存')),
        );
      }
    }
  }

  Future<void> _checkUpdateNow(
    BuildContext context,
    AppPreferences prefs,
  ) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('正在检查 GitHub 最新版本...'),
        duration: Duration(seconds: 1),
      ),
    );
    final res = await AppUpdateService.checkForUpdate(
      feedUrl: prefs.updateFeedUrl,
    );
    if (!context.mounted) return;
    if (res.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.error!)),
      );
      return;
    }
    if (res.hasUpdate && res.release != null) {
      await AppUpdateService.showUpdateDialog(
        context,
        release: res.release!,
        feedUrl: prefs.updateFeedUrl,
      );
    } else {
      final remoteVer = res.release?.version ?? kAppVersion;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('当前已是最新版本（v$remoteVer）')),
      );
    }
  }

  Future<void> _editUpdateFeedDialog(
    BuildContext context,
    WidgetRef ref,
    AppPreferences prefs,
  ) async {
    final ctrl = TextEditingController(text: prefs.updateFeedUrl);
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('自定义更新源地址'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '默认指向 GitHub Releases 的 apps.json；如直连较慢可加上加速代理前缀。',
              style: TextStyle(fontSize: 12, color: EmbyTheme.textSecondary),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'apps.json 订阅地址'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => ctrl.text = kDefaultUpdateFeedUrl,
              child: const Text('恢复默认 GitHub 地址'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (saved == true && ctrl.text.trim().isNotEmpty) {
      await ref
          .read(appPreferencesProvider.notifier)
          .update(prefs.copyWith(updateFeedUrl: ctrl.text.trim()));
    }
    ctrl.dispose();
  }

  Future<void> _editSiteDialog(
    BuildContext context,
    WidgetRef ref,
    SiteProfile site,
  ) async {
    final baseCtrl = TextEditingController(text: site.baseUrl);
    final searchCtrl = TextEditingController(text: site.searchTemplate);
    final loginCtrl = TextEditingController(text: site.loginUrl);
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('编辑 ${site.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: baseCtrl,
              decoration: const InputDecoration(labelText: '主域名 (含 https://)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: searchCtrl,
              decoration:
                  const InputDecoration(labelText: '搜索模板 ({base}, {query})'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: loginCtrl,
              decoration: const InputDecoration(labelText: '登录页 URL'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (saved == true) {
      await ref.read(siteProfilesProvider.notifier).updateSite(
            site.copyWith(
              baseUrl: baseCtrl.text.trim(),
              searchTemplate: searchCtrl.text.trim(),
              loginUrl: loginCtrl.text.trim(),
            ),
          );
    }
    baseCtrl.dispose();
    searchCtrl.dispose();
    loginCtrl.dispose();
  }

  Future<void> _addSiteDialog(BuildContext context, WidgetRef ref) async {
    final nameCtrl = TextEditingController();
    final baseCtrl = TextEditingController();
    final searchCtrl = TextEditingController(text: '{base}/search/{query}');
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加自定义片源网站'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: '网站名称（如 新站点）'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: baseCtrl,
                decoration:
                    const InputDecoration(labelText: '网站地址（如 https://xxx.com）'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: searchCtrl,
                decoration: const InputDecoration(
                    labelText: '搜索模板（可选，默认即可）'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    if (saved == true && baseCtrl.text.trim().isNotEmpty) {
      var raw = baseCtrl.text.trim();
      if (!raw.startsWith('http://') && !raw.startsWith('https://')) {
        raw = 'https://$raw';
      }
      final base = raw.replaceAll(RegExp(r'/+$'), '');
      final uri = Uri.tryParse(base);
      final hostSlug = (uri?.host ?? 'site')
          .replaceAll(RegExp(r'^www\.'), '')
          .split('.')
          .first
          .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '')
          .toLowerCase();
      final key = hostSlug.isNotEmpty
          ? hostSlug
          : 'site_${DateTime.now().millisecondsSinceEpoch % 10000}';
      await ref.read(siteProfilesProvider.notifier).addSite(
            SiteProfile(
              key: key,
              name: nameCtrl.text.trim().isNotEmpty
                  ? nameCtrl.text.trim()
                  : (uri?.host ?? key),
              baseUrl: base,
              searchTemplate: searchCtrl.text.trim().isNotEmpty
                  ? searchCtrl.text.trim()
                  : '{base}/search/{query}',
              loginUrl: base,
            ),
          );
    }
    nameCtrl.dispose();
    baseCtrl.dispose();
    searchCtrl.dispose();
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: EmbyTheme.accent,
      ),
    );
  }
}
