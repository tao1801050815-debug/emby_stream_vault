import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/novel_book.dart';
import '../../core/models/site_config.dart';
import '../../core/providers/app_providers.dart';
import '../../core/services/novel_sync_service.dart';
import '../../core/theme/emby_theme.dart';
import 'novel_reader_page.dart';

/// 私人小说书架：支持局域网 Wi-Fi 直连、坚果云/WebDAV 云端同步与手机本地 TXT/MD 导入
class NovelShelfPage extends ConsumerStatefulWidget {
  const NovelShelfPage({super.key});

  @override
  ConsumerState<NovelShelfPage> createState() => _NovelShelfPageState();
}

class _NovelShelfPageState extends ConsumerState<NovelShelfPage> {
  bool _syncing = false;

  Future<void> _syncLan(AppPreferences prefs) async {
    final ctrl = TextEditingController(text: prefs.novelLanServerUrl);
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('局域网 Wi-Fi 直连同步'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '在电脑上双击「启动小说局域网同步服务.bat」，把窗口显示的局域网地址填在下面即可秒拉最新章节（手机与电脑需在同一 Wi-Fi）：',
              style: TextStyle(fontSize: 12, color: EmbyTheme.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(
                labelText: '电脑局域网地址',
                hintText: 'http://192.168.1.5:8765',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('立即拉取'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (url == null || url.isEmpty) return;

    await ref
        .read(appPreferencesProvider.notifier)
        .update(prefs.copyWith(novelLanServerUrl: url));
    setState(() => _syncing = true);
    final res = await NovelSyncService.instance.syncFromLan(url);
    if (res.success) {
      await ref.read(novelBooksProvider.notifier).refresh();
    }
    if (mounted) {
      setState(() => _syncing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.message)),
      );
    }
  }

  Future<void> _syncWebDav(AppPreferences prefs) async {
    setState(() => _syncing = true);
    final res = await NovelSyncService.instance.syncFromWebDav(prefs);
    if (res.success) {
      await ref.read(novelBooksProvider.notifier).refresh();
    }
    if (mounted) {
      setState(() => _syncing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.message)),
      );
    }
  }

  Future<void> _importLocal() async {
    setState(() => _syncing = true);
    final res = await NovelSyncService.instance.importLocalFile();
    if (res.success) {
      await ref.read(novelBooksProvider.notifier).refresh();
    }
    if (mounted) {
      setState(() => _syncing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.message)),
      );
    }
  }

  Future<void> _confirmDelete(NovelBook book) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('移出书架'),
        content: Text('确定从手机书架删除《${book.title}》吗？（不会影响电脑原稿）'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(novelBooksProvider.notifier).remove(book.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final books = ref.watch(novelBooksProvider);
    final prefs = ref.watch(appPreferencesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('私人书架'),
        actions: [
          if (_syncing)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else ...[
            IconButton(
              tooltip: '局域网 Wi-Fi 直连拉取',
              icon: const Icon(Icons.wifi_tethering_rounded,
                  color: EmbyTheme.accent),
              onPressed: () => _syncLan(prefs),
            ),
            IconButton(
              tooltip: '从坚果云 / WebDAV 拉取',
              icon: const Icon(Icons.cloud_download_outlined,
                  color: EmbyTheme.accentSecondary),
              onPressed: () => _syncWebDav(prefs),
            ),
            IconButton(
              tooltip: '导入手机本地 TXT / MD',
              icon: const Icon(Icons.file_open_outlined),
              onPressed: _importLocal,
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          // 顶部三通道同步快捷条
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _syncing ? null : () => _syncLan(prefs),
                    icon: const Icon(Icons.wifi_rounded, size: 16),
                    label: const Text('局域网拉取',
                        style: TextStyle(fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _syncing ? null : () => _syncWebDav(prefs),
                    icon: const Icon(Icons.cloud_sync_rounded, size: 16),
                    label: const Text('坚果云同步',
                        style: TextStyle(fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _syncing ? null : _importLocal,
                    icon: const Icon(Icons.upload_file_rounded, size: 16),
                    label: const Text('本地导入',
                        style: TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: books.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.auto_stories_outlined,
                              size: 64, color: EmbyTheme.accent),
                          const SizedBox(height: 14),
                          const Text(
                            '书架还是空的',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            '支持 3 种方式把你在电脑写的小说同步到手机追更：\n1. 局域网 Wi-Fi 直连电脑脚本\n2. 坚果云 WebDAV 云端同步\n3. 直接导入本地 .txt / .md 文件（自动拆章）',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: EmbyTheme.textSecondary,
                              height: 1.55,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
                    itemCount: books.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, idx) {
                      final book = books[idx];
                      final currentIdx = book.chapters.isEmpty
                          ? 0
                          : book.lastChapterIndex
                              .clamp(0, book.chapters.length - 1);
                      final currentTitle = book.chapters.isNotEmpty
                          ? book.chapters[currentIdx].title
                          : '暂无章节';
                      final latestTitle = book.chapters.isNotEmpty
                          ? book.chapters.last.title
                          : '';

                      return Card(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => NovelReaderPage(book: book),
                              ),
                            );
                          },
                          onLongPress: () => _confirmDelete(book),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                Container(
                                  width: 56,
                                  height: 76,
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Color(0xFF2B3A55),
                                        Color(0xFF151C2C),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: EmbyTheme.accent
                                          .withValues(alpha: 0.45),
                                    ),
                                  ),
                                  alignment: Alignment.center,
                                  padding: const EdgeInsets.all(4),
                                  child: Text(
                                    book.title.characters.take(4).toString(),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      height: 1.2,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              book.title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 15.5,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: EmbyTheme.accentSecondary
                                                  .withValues(alpha: 0.18),
                                              borderRadius:
                                                  BorderRadius.circular(5),
                                            ),
                                            child: Text(
                                              book.sourceLabel,
                                              style: const TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w700,
                                                color:
                                                    EmbyTheme.accentSecondary,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 5),
                                      Text(
                                        '共 ${book.chapters.length} 章 · ${book.formattedWords}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: EmbyTheme.accent,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '读至：$currentTitle',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: EmbyTheme.textPrimary,
                                        ),
                                      ),
                                      if (latestTitle.isNotEmpty)
                                        Text(
                                          '最新：$latestTitle',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 11.5,
                                            color: EmbyTheme.textSecondary,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    color: EmbyTheme.textSecondary,
                                  ),
                                  onPressed: () => _confirmDelete(book),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
