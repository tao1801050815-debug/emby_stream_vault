import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/media_item.dart';
import '../../core/providers/app_providers.dart';
import '../../core/theme/emby_theme.dart';
import '../browser/webview_sniffer_page.dart';
import 'media_detail_page.dart';

/// Emby 风格深色海报墙首页 + 本地网页书签收藏夹
class LibraryHomePage extends ConsumerStatefulWidget {
  const LibraryHomePage({super.key});

  @override
  ConsumerState<LibraryHomePage> createState() => _LibraryHomePageState();
}

class _LibraryHomePageState extends ConsumerState<LibraryHomePage> {
  bool _showBookmarks = false;

  @override
  Widget build(BuildContext context) {
    final libraryAsync = ref.watch(mediaLibraryProvider);
    final filter = ref.watch(libraryFilterProvider);
    final bookmarks = ref.watch(bookmarksProvider);
    final width = MediaQuery.sizeOf(context).width;
    final crossAxisCount = width >= 900
        ? 5
        : width >= 600
            ? 4
            : 2;

    return Scaffold(
      appBar: AppBar(
        title: Text(_showBookmarks ? '网页收藏夹（免登录）' : 'Emby 私人影库'),
        actions: [
          TextButton.icon(
            onPressed: () => setState(() => _showBookmarks = !_showBookmarks),
            icon: Icon(_showBookmarks ? Icons.movie_filter : Icons.bookmarks),
            label: Text(_showBookmarks ? '切回影库' : '网页收藏'),
          ),
          IconButton(
            tooltip: '手动录入影片',
            icon: const Icon(Icons.add_box_outlined),
            onPressed: () => _showAddManualDialog(context, ref),
          ),
        ],
      ),
      body: _showBookmarks
          ? (bookmarks.isEmpty
              ? const Center(
                  child: Text(
                    '暂无网页书签\n在「嗅探浏览」打开任意网站点右上角书签图标即可免登录收藏',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(color: EmbyTheme.textSecondary, height: 1.5),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: bookmarks.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, idx) {
                    final bm = bookmarks[idx];
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.bookmark_rounded,
                            color: EmbyTheme.warning),
                        title: Text(bm.title,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text('${bm.folder} · ${bm.url}',
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline_rounded),
                          onPressed: () => ref
                              .read(bookmarksProvider.notifier)
                              .remove(bm.id),
                        ),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => WebViewSnifferPage(
                                initialUrl: bm.url,
                                initialSiteKey: bm.siteKey,
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ))
          : Column(
        children: [
          // 搜索与筛选条
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                hintText: '搜索番号、演员、标签或个人笔记...',
                prefixIcon: Icon(Icons.search_rounded),
              ),
              onChanged: (val) => ref.read(libraryFilterProvider.notifier).state =
                  filter.copyWith(searchQuery: val),
            ),
          ),
          SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                FilterChip(
                  label: const Text('仅看收藏'),
                  selected: filter.onlyFavorites,
                  onSelected: (v) =>
                      ref.read(libraryFilterProvider.notifier).state =
                          filter.copyWith(onlyFavorites: v),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('4星以上'),
                  selected: filter.minRating >= 4.0,
                  onSelected: (v) =>
                      ref.read(libraryFilterProvider.notifier).state =
                          filter.copyWith(minRating: v ? 4.0 : 0.0),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('最近更新'),
                  selected: filter.sortBy == 'updatedAtMs',
                  onSelected: (_) =>
                      ref.read(libraryFilterProvider.notifier).state =
                          filter.copyWith(sortBy: 'updatedAtMs'),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('按评分排序'),
                  selected: filter.sortBy == 'rating',
                  onSelected: (_) =>
                      ref.read(libraryFilterProvider.notifier).state =
                          filter.copyWith(sortBy: 'rating'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: libraryAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(child: Text('读取影库失败: $err')),
              data: (items) {
                if (items.isEmpty) {
                  return _EmptyLibraryGuide(
                    onOpenBrowser: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const WebViewSnifferPage(
                            initialSiteKey: 'missav',
                          ),
                        ),
                      );
                    },
                    onAddManual: () => _showAddManualDialog(context, ref),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () =>
                      ref.read(mediaLibraryProvider.notifier).refresh(),
                  child: GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.68,
                    ),
                    itemCount: items.length,
                    itemBuilder: (_, idx) => _PosterCard(
                      item: items[idx],
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                MediaDetailPage(initialItem: items[idx]),
                          ),
                        );
                      },
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

  Future<void> _showAddManualDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final codeCtrl = TextEditingController();
    final titleCtrl = TextEditingController();
    final posterCtrl = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('手动录入到私人影库'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: codeCtrl,
              decoration: const InputDecoration(labelText: '番号（如 SSIS-001）'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(labelText: '影片标题'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: posterCtrl,
              decoration: const InputDecoration(labelText: '封面图 URL（可选）'),
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
    if (saved == true && codeCtrl.text.trim().isNotEmpty) {
      final code = codeCtrl.text.trim().toUpperCase();
      final item = MediaItem(
        id: 'manual_$code',
        code: code,
        title: titleCtrl.text.trim().isNotEmpty
            ? titleCtrl.text.trim()
            : code,
        posterUrl: posterCtrl.text.trim(),
        isFavorite: true,
        isMetadataLocked: true,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
      await ref.read(mediaLibraryProvider.notifier).saveItem(item);
    }
    codeCtrl.dispose();
    titleCtrl.dispose();
    posterCtrl.dispose();
  }
}

class _PosterCard extends StatelessWidget {
  final MediaItem item;
  final VoidCallback onTap;

  const _PosterCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: EmbyTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (item.posterUrl.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: item.posterUrl,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => const _PosterPlaceholder(),
                    )
                  else
                    const _PosterPlaceholder(),
                  // 番号徽章
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.72),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        item.code,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  // 个人评分徽章
                  if (item.personalRating > 0)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: EmbyTheme.warning.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star_rounded,
                                size: 12, color: Colors.black),
                            const SizedBox(width: 2),
                            Text(
                              item.personalRating.toStringAsFixed(1),
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.black,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  // 断点续播进度条
                  if (item.watchProgress > 0.01)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: LinearProgressIndicator(
                        value: item.watchProgress,
                        minHeight: 3,
                        backgroundColor: Colors.black54,
                        color: EmbyTheme.accent,
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                    ),
                  ),
                  if (item.actors.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      item.actors.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: EmbyTheme.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PosterPlaceholder extends StatelessWidget {
  const _PosterPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1E2634),
      child: const Center(
        child: Icon(
          Icons.movie_creation_outlined,
          size: 40,
          color: EmbyTheme.textSecondary,
        ),
      ),
    );
  }
}

class _EmptyLibraryGuide extends StatelessWidget {
  final VoidCallback onOpenBrowser;
  final VoidCallback onAddManual;

  const _EmptyLibraryGuide({
    required this.onOpenBrowser,
    required this.onAddManual,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.video_library_outlined,
                size: 64, color: EmbyTheme.accent),
            const SizedBox(height: 16),
            const Text(
              '私人海报墙还是空的',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              '去「嗅探浏览」登录 MissAV 或逛 JavDB，点击底部的「收藏到私人库」或「原生播放」，影片会自动沉淀到这里。',
              textAlign: TextAlign.center,
              style: TextStyle(color: EmbyTheme.textSecondary, height: 1.5),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: EmbyTheme.accent,
                    foregroundColor: Colors.black,
                  ),
                  onPressed: onOpenBrowser,
                  icon: const Icon(Icons.explore_rounded),
                  label: const Text('去登录 MissAV / 嗅探'),
                ),
                OutlinedButton.icon(
                  onPressed: onAddManual,
                  icon: const Icon(Icons.add),
                  label: const Text('手动录入番号'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
