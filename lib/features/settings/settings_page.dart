import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/site_config.dart';
import '../../core/providers/app_providers.dart';
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
        ],
      ),
    );
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
