import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/media_item.dart';
import '../../core/providers/app_providers.dart';
import '../../core/services/live_ai_subtitle_service.dart';
import '../../core/services/web_metadata_extractor_service.dart';
import '../../core/theme/emby_theme.dart';
import '../../core/widgets/cum_count_badge.dart';
import '../browser/webview_sniffer_page.dart';
import 'media_detail_page.dart';

/// 私人影库主页：支持 Pornhub 单列宽屏卡片 / MissAV 双列并排切换 + 每页固定 8 部分页 + 自定义网址自动提取添加
class LibraryHomePage extends ConsumerStatefulWidget {
  const LibraryHomePage({super.key});

  @override
  ConsumerState<LibraryHomePage> createState() => _LibraryHomePageState();
}

class _LibraryHomePageState extends ConsumerState<LibraryHomePage> {
  static const int _pageSize = 8;

  bool _showBookmarks = false;
  bool _selectionMode = false;
  final Set<String> _selectedIds = {};
  int _currentPage = 1;
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _jumpToPage(int page, int totalPages) {
    final target = page.clamp(1, totalPages);
    if (target == _currentPage) return;
    setState(() => _currentPage = target);
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _toggleSelect(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        if (_selectedIds.isEmpty) _selectionMode = false;
      } else {
        _selectedIds.add(id);
      }
    });
  }

  Future<void> _confirmBatchDelete() async {
    if (_selectedIds.isEmpty) return;
    final count = _selectedIds.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('批量删除收藏'),
        content: Text('确定从私人影库删除选中的 $count 部影片吗？'),
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
      await ref
          .read(mediaLibraryProvider.notifier)
          .deleteItemsBatch(_selectedIds.toList());
      setState(() {
        _selectedIds.clear();
        _selectionMode = false;
      });
    }
  }

  Future<void> _showCardActions(MediaItem item) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: EmbyTheme.surface,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const EjaculationMiniIcon(size: 22),
              title: Text('射过次数 +1（当前 ${item.cumCount} 次）'),
              onTap: () async {
                Navigator.pop(ctx);
                await ref
                    .read(mediaLibraryProvider.notifier)
                    .updateCumCount(item.id, item.cumCount + 1);
              },
            ),
            ListTile(
              leading: const Icon(Icons.star_half_rounded,
                  color: EmbyTheme.accentSecondary),
              title: const Text('从 JavDB 获取/刷新网上评分'),
              onTap: () async {
                Navigator.pop(ctx);
                final res = await ref
                    .read(mediaLibraryProvider.notifier)
                    .fetchPublicRatingNow(item);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        res != null
                            ? '${item.code} 获取成功：${res.source} ${res.rating.toStringAsFixed(2)} 分'
                            : '未能在 JavDB 找到 ${item.code} 的评分（可能非标准番号或触发验证）',
                      ),
                    ),
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.checklist_rounded),
              title: const Text('进入批量选择删除模式'),
              onTap: () {
                Navigator.pop(ctx);
                setState(() {
                  _selectionMode = true;
                  _selectedIds.add(item.id);
                });
              },
            ),
            ListTile(
              leading: const Icon(Icons.subtitles_off_outlined),
              title: const Text('删除该片本地 AI 字幕缓存'),
              onTap: () async {
                Navigator.pop(ctx);
                final removed =
                    await LiveAiSubtitleSession.deleteCachedSubtitle(item.id);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        removed
                            ? '已清除 ${item.code} 的本地 AI 字幕缓存'
                            : '${item.code} 暂无本地 AI 字幕缓存',
                      ),
                    ),
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded,
                  color: EmbyTheme.danger),
              title: const Text('删除此收藏',
                  style: TextStyle(color: EmbyTheme.danger)),
              onTap: () async {
                Navigator.pop(ctx);
                await ref
                    .read(mediaLibraryProvider.notifier)
                    .deleteItem(item.id);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final libraryAsync = ref.watch(mediaLibraryProvider);
    final filter = ref.watch(libraryFilterProvider);
    final prefs = ref.watch(appPreferencesProvider);
    final bookmarks = ref.watch(bookmarksProvider);
    final isPornhubSingleCol = prefs.libraryLayoutMode == 'pornhub';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _selectionMode
              ? '已选 ${_selectedIds.length} 项'
              : (_showBookmarks ? '网页收藏夹（免登录）' : '私人影库'),
        ),
        actions: _selectionMode
            ? [
                TextButton(
                  onPressed: () => setState(() {
                    _selectionMode = false;
                    _selectedIds.clear();
                  }),
                  child: const Text('取消'),
                ),
                IconButton(
                  tooltip: '删除选中项',
                  icon: const Icon(Icons.delete_forever_rounded,
                      color: EmbyTheme.danger),
                  onPressed: _confirmBatchDelete,
                ),
              ]
            : [
                if (!_showBookmarks)
                  IconButton(
                    tooltip: isPornhubSingleCol
                        ? '切换为 MissAV 双列并排'
                        : '切换为 Pornhub 单列宽卡',
                    icon: Icon(
                      isPornhubSingleCol
                          ? Icons.grid_view_rounded
                          : Icons.view_agenda_rounded,
                      color: isPornhubSingleCol
                          ? const Color(0xFFFF9900)
                          : const Color(0xFFFF4D8D),
                    ),
                    onPressed: () {
                      final nextMode =
                          isPornhubSingleCol ? 'missav' : 'pornhub';
                      ref.read(appPreferencesProvider.notifier).update(
                            prefs.copyWith(libraryLayoutMode: nextMode),
                          );
                    },
                  ),
                TextButton.icon(
                  onPressed: () =>
                      setState(() => _showBookmarks = !_showBookmarks),
                  icon: Icon(
                    _showBookmarks ? Icons.movie_filter : Icons.bookmarks,
                    size: 18,
                  ),
                  label: Text(_showBookmarks ? '影库' : '书签'),
                ),
                if (!_showBookmarks)
                  IconButton(
                    tooltip: '刷新本页网评',
                    icon: const Icon(
                      Icons.stars_rounded,
                      color: EmbyTheme.accentSecondary,
                    ),
                    onPressed: () async {
                      final items = libraryAsync.valueOrNull ?? const [];
                      if (items.isEmpty) return;
                      final totalPages =
                          ((items.length - 1) ~/ _pageSize) + 1;
                      final safePage = _currentPage.clamp(1, totalPages);
                      final pageItems = items
                          .skip((safePage - 1) * _pageSize)
                          .take(_pageSize)
                          .toList();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('正在从 JavDB 批量获取本页影片评分...'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                      final updated = await ref
                          .read(mediaLibraryProvider.notifier)
                          .refreshMissingRatings(pageItems);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              updated > 0
                                  ? '已成功更新本页 $updated 部影片的 JavDB 网评！'
                                  : '未获取到新评分（请确认番号格式正确且网络可访问 JavDB）',
                            ),
                          ),
                        );
                      }
                    },
                  ),
                if (!_showBookmarks)
                  IconButton(
                    tooltip: '批量删除管理',
                    icon: const Icon(Icons.delete_sweep_outlined),
                    onPressed: () => setState(() => _selectionMode = true),
                  ),
                IconButton(
                  tooltip: '自定义添加收藏（支持网址自动提取）',
                  icon: const Icon(Icons.add_box_outlined),
                  onPressed: () => _showCustomAddDialog(context, ref),
                ),
              ],
      ),
      body: _showBookmarks
          ? _buildBookmarksView(bookmarks)
          : Column(
              children: [
                // 搜索框 + 布局模式快捷切换胶囊
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 40,
                          child: TextField(
                            decoration: const InputDecoration(
                              hintText: '搜番号、名称、中出/无码标签、女优...',
                              prefixIcon: Icon(Icons.search_rounded, size: 20),
                              contentPadding:
                                  EdgeInsets.symmetric(horizontal: 12),
                            ),
                            onChanged: (val) {
                              setState(() => _currentPage = 1);
                              ref.read(libraryFilterProvider.notifier).state =
                                  filter.copyWith(searchQuery: val);
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _LayoutTogglePill(
                        isSingleCol: isPornhubSingleCol,
                        onToggle: (mode) {
                          ref.read(appPreferencesProvider.notifier).update(
                                prefs.copyWith(libraryLayoutMode: mode),
                              );
                        },
                      ),
                    ],
                  ),
                ),
                // 排序与过滤条
                SizedBox(
                  height: 38,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    children: [
                      ChoiceChip(
                        label: const Text('最近收藏'),
                        selected: filter.sortBy == 'updatedAtMs',
                        onSelected: (_) {
                          setState(() => _currentPage = 1);
                          ref.read(libraryFilterProvider.notifier).state =
                              filter.copyWith(sortBy: 'updatedAtMs');
                        },
                      ),
                      const SizedBox(width: 6),
                      ChoiceChip(
                        label: const Text('撸过最多'),
                        selected: filter.sortBy == 'cumCount',
                        onSelected: (_) {
                          setState(() => _currentPage = 1);
                          ref.read(libraryFilterProvider.notifier).state =
                              filter.copyWith(sortBy: 'cumCount');
                        },
                      ),
                      const SizedBox(width: 6),
                      ChoiceChip(
                        label: const Text('个人高分'),
                        selected: filter.sortBy == 'rating',
                        onSelected: (_) {
                          setState(() => _currentPage = 1);
                          ref.read(libraryFilterProvider.notifier).state =
                              filter.copyWith(sortBy: 'rating');
                        },
                      ),
                      const SizedBox(width: 6),
                      ChoiceChip(
                        label: const Text('网上高分'),
                        selected: filter.sortBy == 'publicRating',
                        onSelected: (_) {
                          setState(() => _currentPage = 1);
                          ref.read(libraryFilterProvider.notifier).state =
                              filter.copyWith(sortBy: 'publicRating');
                        },
                      ),
                      const SizedBox(width: 6),
                      ChoiceChip(
                        label: const Text('番号排序'),
                        selected: filter.sortBy == 'code',
                        onSelected: (_) {
                          setState(() => _currentPage = 1);
                          ref.read(libraryFilterProvider.notifier).state =
                              filter.copyWith(sortBy: 'code');
                        },
                      ),
                      const SizedBox(width: 6),
                      FilterChip(
                        label: const Text('4星+'),
                        selected: filter.minRating >= 4.0,
                        onSelected: (v) {
                          setState(() => _currentPage = 1);
                          ref.read(libraryFilterProvider.notifier).state =
                              filter.copyWith(minRating: v ? 4.0 : 0.0);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                // 主体卡片列表 + 底部分页器（每页严格 8 部）
                Expanded(
                  child: libraryAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
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
                          onAddManual: () =>
                              _showCustomAddDialog(context, ref),
                        );
                      }

                      final totalPages =
                          ((items.length - 1) ~/ _pageSize) + 1;
                      final safePage = _currentPage.clamp(1, totalPages);
                      final startIdx = (safePage - 1) * _pageSize;
                      final pageItems = items
                          .skip(startIdx)
                          .take(_pageSize)
                          .toList();

                      return Column(
                        children: [
                          Expanded(
                            child: RefreshIndicator(
                              onRefresh: () => ref
                                  .read(mediaLibraryProvider.notifier)
                                  .refresh(),
                              child: isPornhubSingleCol
                                  ? ListView.separated(
                                      controller: _scrollController,
                                      padding: const EdgeInsets.fromLTRB(
                                          14, 4, 14, 16),
                                      itemCount: pageItems.length,
                                      separatorBuilder: (_, __) =>
                                          const SizedBox(height: 16),
                                      itemBuilder: (_, idx) =>
                                          _buildCardItem(pageItems[idx], true),
                                    )
                                  : GridView.builder(
                                      controller: _scrollController,
                                      padding: const EdgeInsets.fromLTRB(
                                          12, 4, 12, 16),
                                      gridDelegate:
                                          const SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: 2,
                                        mainAxisSpacing: 12,
                                        crossAxisSpacing: 10,
                                        childAspectRatio: 0.96,
                                      ),
                                      itemCount: pageItems.length,
                                      itemBuilder: (_, idx) =>
                                          _buildCardItem(pageItems[idx], false),
                                    ),
                            ),
                          ),
                          _PaginationBar(
                            currentPage: safePage,
                            totalPages: totalPages,
                            totalItems: items.length,
                            accentColor: isPornhubSingleCol
                                ? const Color(0xFFFF9900)
                                : const Color(0xFFFF4D8D),
                            onPageSelected: (p) => _jumpToPage(p, totalPages),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildCardItem(MediaItem item, bool isSingleColumn) {
    final isSelected = _selectedIds.contains(item.id);
    void handleTap() {
      if (_selectionMode) {
        _toggleSelect(item.id);
        return;
      }
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MediaDetailPage(initialItem: item),
        ),
      );
    }

    if (isSingleColumn) {
      return _PornhubWideCard(
        item: item,
        selectionMode: _selectionMode,
        selected: isSelected,
        onTap: handleTap,
        onLongPress: () => _showCardActions(item),
        onMoreTap: () => _showCardActions(item),
        onCumCountChanged: (next) => ref
            .read(mediaLibraryProvider.notifier)
            .updateCumCount(item.id, next),
      );
    }

    return _MissavGridCard(
      item: item,
      selectionMode: _selectionMode,
      selected: isSelected,
      onTap: handleTap,
      onLongPress: () => _showCardActions(item),
      onCumCountChanged: (next) =>
          ref.read(mediaLibraryProvider.notifier).updateCumCount(item.id, next),
    );
  }

  Widget _buildBookmarksView(List<dynamic> bookmarks) {
    if (bookmarks.isEmpty) {
      return const Center(
        child: Text(
          '暂无网页书签\n在「嗅探浏览」打开任意网站点右上角书签图标即可免登录收藏',
          textAlign: TextAlign.center,
          style: TextStyle(color: EmbyTheme.textSecondary, height: 1.5),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: bookmarks.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, idx) {
        final bm = bookmarks[idx];
        return Card(
          child: ListTile(
            leading:
                const Icon(Icons.bookmark_rounded, color: EmbyTheme.warning),
            title:
                Text(bm.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${bm.folder} · ${bm.url}',
                maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () =>
                  ref.read(bookmarksProvider.notifier).remove(bm.id),
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
    );
  }

  /// 主页自定义添加收藏（支持网址一键提取名称、封面、番号与标签，也可全手动填写）
  Future<void> _showCustomAddDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final urlCtrl = TextEditingController();
    final titleCtrl = TextEditingController();
    final posterCtrl = TextEditingController();
    final codeCtrl = TextEditingController();
    final tagsCtrl = TextEditingController();
    var extracting = false;
    var previewPoster = '';
    var detectedSite = 'custom';
    var extractedActors = <String>[];

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          Future<void> doExtract() async {
            final rawUrl = urlCtrl.text.trim();
            if (rawUrl.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('请先输入或粘贴影片网址')),
              );
              return;
            }
            setModalState(() => extracting = true);
            final meta = await WebMetadataExtractorService.instance
                .extractFromUrl(rawUrl);
            if (!ctx.mounted) return;
            setModalState(() {
              extracting = false;
              urlCtrl.text = meta.url;
              detectedSite = meta.sourceSite;
              extractedActors = meta.actors;
              if (meta.code.isNotEmpty) {
                codeCtrl.text = meta.code;
              }
              if (meta.title.isNotEmpty) {
                titleCtrl.text = meta.title;
              }
              if (meta.posterUrl.isNotEmpty) {
                posterCtrl.text = meta.posterUrl;
                previewPoster = meta.posterUrl;
              }
              if (meta.tags.isNotEmpty && tagsCtrl.text.trim().isEmpty) {
                tagsCtrl.text = meta.tags.join(', ');
              }
            });
          }

          return AlertDialog(
            title: const Text('自定义添加收藏'),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 380,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: urlCtrl,
                            decoration: InputDecoration(
                              labelText: '影片网址 URL',
                              hintText: 'https://missav.ws/...',
                              suffixIcon: IconButton(
                                tooltip: '粘贴剪贴板',
                                icon: const Icon(Icons.content_paste_rounded,
                                    size: 18),
                                onPressed: () async {
                                  final data =
                                      await Clipboard.getData('text/plain');
                                  final txt = data?.text?.trim() ?? '';
                                  if (txt.isNotEmpty) {
                                    urlCtrl.text = txt;
                                    await doExtract();
                                  }
                                },
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.tonal(
                          onPressed: extracting ? null : doExtract,
                          child: extracting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('自动提取'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: titleCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: '影片名称（可自动提取或手填）',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: posterCtrl,
                      decoration: const InputDecoration(
                        labelText: '封面图片 URL（可自动提取或填任意图链）',
                      ),
                      onChanged: (v) =>
                          setModalState(() => previewPoster = v.trim()),
                    ),
                    if (previewPoster.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: AspectRatio(
                          aspectRatio: 16 / 9,
                          child: CachedNetworkImage(
                            imageUrl: previewPoster,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) =>
                                const _PosterPlaceholder(),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: codeCtrl,
                            decoration: const InputDecoration(
                              labelText: '番号 / 标识（选填）',
                              hintText: '如 MIMK-173',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: tagsCtrl,
                      decoration: const InputDecoration(
                        labelText: '标签（逗号分隔，如 中出, 无码, 巨乳）',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('加入影库'),
              ),
            ],
          );
        },
      ),
    );

    if (saved == true) {
      final rawUrl = urlCtrl.text.trim();
      final rawTitle = titleCtrl.text.trim();
      final rawCode = codeCtrl.text.trim().toUpperCase();
      if (rawUrl.isEmpty && rawTitle.isEmpty && rawCode.isEmpty) {
        urlCtrl.dispose();
        titleCtrl.dispose();
        posterCtrl.dispose();
        codeCtrl.dispose();
        tagsCtrl.dispose();
        return;
      }

      final inferredCode = rawCode.isNotEmpty
          ? rawCode
          : WebMetadataExtractorService.extractCodeFromText(
              '$rawUrl $rawTitle',
            );
      final finalCode = inferredCode.isNotEmpty
          ? inferredCode
          : 'CUSTOM-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}';
      final uri = Uri.tryParse(rawUrl);
      final siteKey = (uri != null && uri.host.isNotEmpty)
          ? WebMetadataExtractorService.inferSiteKey(uri.host)
          : detectedSite;
      final tags = tagsCtrl.text
          .split(RegExp(r'[,，]'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      final id = WebMetadataExtractorService.buildMediaId(
        siteKey: siteKey,
        code: finalCode,
        sourceUrl: rawUrl,
        tags: tags,
      );

      final item = MediaItem(
        id: id,
        code: finalCode,
        title: rawTitle.isNotEmpty ? rawTitle : finalCode,
        posterUrl: posterCtrl.text.trim(),
        actors: extractedActors,
        tags: tags,
        isFavorite: true,
        sourceSite: siteKey,
        sourceUrl: rawUrl,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
      await ref.read(mediaLibraryProvider.notifier).saveItem(item);
    }

    urlCtrl.dispose();
    titleCtrl.dispose();
    posterCtrl.dispose();
    codeCtrl.dispose();
    tagsCtrl.dispose();
  }
}

/// 顶部紧凑双模式切换胶囊（仿 Pornhub 单列 / 仿 MissAV 双列）
class _LayoutTogglePill extends StatelessWidget {
  final bool isSingleCol;
  final ValueChanged<String> onToggle;

  const _LayoutTogglePill({
    required this.isSingleCol,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: EmbyTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTab(
            label: '单列',
            icon: Icons.view_agenda_rounded,
            selected: isSingleCol,
            activeColor: const Color(0xFFFF9900),
            onTap: () => onToggle('pornhub'),
          ),
          _buildTab(
            label: '双列',
            icon: Icons.grid_view_rounded,
            selected: !isSingleCol,
            activeColor: const Color(0xFFFF4D8D),
            onTap: () => onToggle('missav'),
          ),
        ],
      ),
    );
  }

  Widget _buildTab({
    required String label,
    required IconData icon,
    required bool selected,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? activeColor : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 14,
              color: selected ? Colors.black : EmbyTheme.textSecondary,
            ),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: selected ? Colors.black : EmbyTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 仿 Pornhub 风格：单列全宽 16:9 大卡片（竖着一部片占一栏）
class _PornhubWideCard extends StatelessWidget {
  final MediaItem item;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onMoreTap;
  final ValueChanged<int> onCumCountChanged;

  const _PornhubWideCard({
    required this.item,
    required this.selectionMode,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onMoreTap,
    required this.onCumCountChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF15171C),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? EmbyTheme.danger
                : Colors.white.withValues(alpha: 0.08),
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: _CoverOverlayStack(
                item: item,
                selectionMode: selectionMode,
                selected: selected,
                compact: false,
                progressColor: const Color(0xFFFF9900),
                onCumCountChanged: onCumCountChanged,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            height: 1.3,
                          ),
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.more_vert_rounded,
                            size: 20, color: EmbyTheme.textSecondary),
                        onPressed: onMoreTap,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.actors.isNotEmpty
                        ? '${item.sourceSite.toUpperCase()} · ${item.actors.join(' / ')}'
                        : '来源: ${item.sourceSite.toUpperCase()}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: EmbyTheme.textSecondary,
                    ),
                  ),
                  if (item.tags.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 5,
                      children: item.tags.take(6).map((tag) {
                        final isUnc = tag.contains('无码') || tag.contains('無碼');
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: isUnc
                                ? const Color(0x33FF4D8D)
                                : Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            tag,
                            style: TextStyle(
                              fontSize: 11,
                              color: isUnc
                                  ? const Color(0xFFFF7AA8)
                                  : EmbyTheme.textPrimary,
                            ),
                          ),
                        );
                      }).toList(),
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

/// 仿 MissAV 风格：两部片并列紧凑横版封面卡
class _MissavGridCard extends StatelessWidget {
  final MediaItem item;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final ValueChanged<int> onCumCountChanged;

  const _MissavGridCard({
    required this.item,
    required this.selectionMode,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onCumCountChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        decoration: BoxDecoration(
          color: EmbyTheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? EmbyTheme.danger
                : Colors.white.withValues(alpha: 0.08),
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9.4,
              child: _CoverOverlayStack(
                item: item,
                selectionMode: selectionMode,
                selected: selected,
                compact: true,
                progressColor: const Color(0xFFFF4D8D),
                onCumCountChanged: onCumCountChanged,
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        Text(
                          item.sourceSite.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFFF7AA8),
                          ),
                        ),
                        if (item.tags.isNotEmpty) ...[
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              item.tags.take(3).join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10.5,
                                color: EmbyTheme.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 封面四象限徽章叠层：左上番号(+无码) / 右上网评+自评 / 右下射过次数微缩图标 / 底部进度条
class _CoverOverlayStack extends StatelessWidget {
  final MediaItem item;
  final bool selectionMode;
  final bool selected;
  final bool compact;
  final Color progressColor;
  final ValueChanged<int> onCumCountChanged;

  const _CoverOverlayStack({
    required this.item,
    required this.selectionMode,
    required this.selected,
    required this.compact,
    required this.progressColor,
    required this.onCumCountChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
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
        // 底部微暗渐变衬底，保证右下角计数徽章清晰可见
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 36,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.65),
                  ],
                ),
              ),
            ),
          ),
        ),
        // 左上角：番号 + 无码标记
        Positioned(
          top: 6,
          left: 6,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 6 : 8,
                  vertical: 2.5,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.78),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  item.code,
                  style: TextStyle(
                    fontSize: compact ? 10.5 : 12,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
              if (item.isUncensored) ...[
                const SizedBox(width: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE91E63),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    '无码',
                    style: TextStyle(
                      fontSize: compact ? 9.5 : 11,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        // 右上角：多选框 或 网络评分 + 自我评分
        if (selectionMode)
          Positioned(
            top: 6,
            right: 6,
            child: Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: selected ? EmbyTheme.danger : Colors.white,
              size: 24,
            ),
          )
        else
          Positioned(
            top: 6,
            right: 6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (item.publicRating > 0)
                  Container(
                    margin: const EdgeInsets.only(bottom: 3),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: EmbyTheme.accentSecondary.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      '网 ${item.publicRating.toStringAsFixed(1)}',
                      style: TextStyle(
                        fontSize: compact ? 9.5 : 11,
                        fontWeight: FontWeight.w800,
                        color: Colors.black,
                      ),
                    ),
                  ),
                if (item.personalRating > 0)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: EmbyTheme.warning.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.star_rounded,
                            size: 11, color: Colors.black),
                        const SizedBox(width: 1),
                        Text(
                          '自 ${item.personalRating.toStringAsFixed(1)}',
                          style: TextStyle(
                            fontSize: compact ? 9.5 : 11,
                            fontWeight: FontWeight.w800,
                            color: Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        // 右下角：包茎微露龟头喷射微缩图标 + 自定义射过次数
        if (!selectionMode)
          Positioned(
            right: 6,
            bottom: item.watchProgress > 0.01 ? 7 : 5,
            child: CumCountBadge(
              count: item.cumCount,
              compact: compact,
              onChanged: onCumCountChanged,
            ),
          ),
        // 底部播放进度条
        if (item.watchProgress > 0.01)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: LinearProgressIndicator(
              value: item.watchProgress,
              minHeight: 3,
              backgroundColor: Colors.black54,
              color: progressColor,
            ),
          ),
      ],
    );
  }
}

/// 仿 Pornhub / MissAV 风格底部分页条（每页固定 8 部）
class _PaginationBar extends StatelessWidget {
  final int currentPage;
  final int totalPages;
  final int totalItems;
  final Color accentColor;
  final ValueChanged<int> onPageSelected;

  const _PaginationBar({
    required this.currentPage,
    required this.totalPages,
    required this.totalItems,
    required this.accentColor,
    required this.onPageSelected,
  });

  List<int> _visiblePages() {
    if (totalPages <= 5) {
      return List.generate(totalPages, (i) => i + 1);
    }
    var start = (currentPage - 2).clamp(1, totalPages - 4);
    return List.generate(5, (i) => start + i);
  }

  @override
  Widget build(BuildContext context) {
    final pages = _visiblePages();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: EmbyTheme.surface,
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: Row(
        children: [
          Text(
            '共 $totalItems 部',
            style: const TextStyle(
              fontSize: 11.5,
              color: EmbyTheme.textSecondary,
            ),
          ),
          const Spacer(),
          _PageBtn(
            label: '上一页',
            enabled: currentPage > 1,
            onTap: () => onPageSelected(currentPage - 1),
          ),
          const SizedBox(width: 4),
          ...pages.map(
            (p) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: _PageNumberBtn(
                page: p,
                selected: p == currentPage,
                accentColor: accentColor,
                onTap: () => onPageSelected(p),
              ),
            ),
          ),
          const SizedBox(width: 4),
          _PageBtn(
            label: '下一页',
            enabled: currentPage < totalPages,
            onTap: () => onPageSelected(currentPage + 1),
          ),
        ],
      ),
    );
  }
}

class _PageBtn extends StatelessWidget {
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  const _PageBtn({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: enabled ? 0.08 : 0.03),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            color: enabled ? Colors.white : Colors.white30,
          ),
        ),
      ),
    );
  }
}

class _PageNumberBtn extends StatelessWidget {
  final int page;
  final bool selected;
  final Color accentColor;
  final VoidCallback onTap;

  const _PageNumberBtn({
    required this.page,
    required this.selected,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        constraints: const BoxConstraints(minWidth: 28),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? accentColor : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          '$page',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: selected ? Colors.black : Colors.white,
          ),
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
          size: 36,
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
              '私人影库还是空的',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              '去「嗅探浏览」打开片源精准勾选收藏，或点下方「自定义网址添加」自动抓取封面与标题。',
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
                  label: const Text('去嗅探浏览选片'),
                ),
                OutlinedButton.icon(
                  onPressed: onAddManual,
                  icon: const Icon(Icons.add_link_rounded),
                  label: const Text('自定义网址添加'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
