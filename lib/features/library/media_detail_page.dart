import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/media_item.dart';
import '../../core/providers/app_providers.dart';
import '../../core/theme/emby_theme.dart';
import '../browser/webview_sniffer_page.dart';
import '../player/enhanced_player_page.dart';

/// 仿 Emby 详情页：毛玻璃背景 + 个人评分/笔记 + 元数据纠错锁定 + 多源一键跳转
class MediaDetailPage extends ConsumerStatefulWidget {
  final MediaItem initialItem;

  const MediaDetailPage({super.key, required this.initialItem});

  @override
  ConsumerState<MediaDetailPage> createState() => _MediaDetailPageState();
}

class _MediaDetailPageState extends ConsumerState<MediaDetailPage> {
  late MediaItem _item;

  @override
  void initState() {
    super.initState();
    _item = widget.initialItem;
  }

  Future<void> _saveChanges(MediaItem next) async {
    setState(() => _item = next);
    await ref.read(mediaLibraryProvider.notifier).saveItem(next);
  }

  Future<void> _editMetadataDialog() async {
    final titleCtrl = TextEditingController(text: _item.title);
    final actorsCtrl = TextEditingController(text: _item.actors.join(', '));
    final tagsCtrl = TextEditingController(text: _item.tags.join(', '));
    final studioCtrl = TextEditingController(text: _item.studio);
    final notesCtrl = TextEditingController(text: _item.notes);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('元数据纠错与锁定'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(labelText: '影片标题'),
                maxLines: 2,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: actorsCtrl,
                decoration: const InputDecoration(labelText: '演员（逗号分隔）'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: tagsCtrl,
                decoration: const InputDecoration(labelText: '标签（逗号分隔）'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: studioCtrl,
                decoration: const InputDecoration(labelText: '片商'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: notesCtrl,
                decoration: const InputDecoration(labelText: '个人备注'),
                maxLines: 3,
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
            child: const Text('保存并锁定'),
          ),
        ],
      ),
    );

    if (ok == true) {
      List<String> splitCsv(String raw) => raw
          .split(RegExp(r'[,，]'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      await _saveChanges(
        _item.copyWith(
          title: titleCtrl.text.trim(),
          actors: splitCsv(actorsCtrl.text),
          tags: splitCsv(tagsCtrl.text),
          studio: studioCtrl.text.trim(),
          notes: notesCtrl.text.trim(),
          isMetadataLocked: true,
          updatedAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    }

    titleCtrl.dispose();
    actorsCtrl.dispose();
    tagsCtrl.dispose();
    studioCtrl.dispose();
    notesCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sites = ref.watch(siteProfilesProvider);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: _item.isFavorite ? '取消收藏' : '加入收藏',
            icon: Icon(
              _item.isFavorite
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              color: _item.isFavorite ? EmbyTheme.danger : Colors.white,
            ),
            onPressed: () =>
                _saveChanges(_item.copyWith(isFavorite: !_item.isFavorite)),
          ),
          IconButton(
            tooltip: '元数据纠错',
            icon: const Icon(Icons.edit_note_rounded),
            onPressed: _editMetadataDialog,
          ),
          IconButton(
            tooltip: '删除此条目',
            icon: const Icon(Icons.delete_outline_rounded,
                color: EmbyTheme.danger),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('删除影片'),
                  content: Text('确定从私人影库删除「${_item.code}」吗？'),
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
              if (confirm == true) {
                await ref
                    .read(mediaLibraryProvider.notifier)
                    .deleteItem(_item.id);
                if (context.mounted) Navigator.of(context).pop();
              }
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          if (_item.posterUrl.isNotEmpty)
            Positioned.fill(
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                child: CachedNetworkImage(
                  imageUrl: _item.posterUrl,
                  fit: BoxFit.cover,
                  color: Colors.black.withValues(alpha: 0.72),
                  colorBlendMode: BlendMode.darken,
                  errorWidget: (_, __, ___) =>
                      Container(color: EmbyTheme.background),
                ),
              ),
            ),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: 120,
                        height: 170,
                        child: _item.posterUrl.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: _item.posterUrl,
                                fit: BoxFit.cover,
                              )
                            : Container(
                                color: EmbyTheme.surface,
                                child: const Icon(Icons.movie, size: 42),
                              ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: EmbyTheme.accent.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  _item.code,
                                  style: const TextStyle(
                                    color: EmbyTheme.accent,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              if (_item.sourceSite.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '来源: ${_item.sourceSite.toUpperCase()}',
                                    style: const TextStyle(
                                      color: EmbyTheme.textPrimary,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _item.title,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              height: 1.3,
                            ),
                          ),
                          if (_item.studio.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              '片商: ${_item.studio}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: EmbyTheme.textSecondary,
                              ),
                            ),
                          ],
                          if (_item.isMetadataLocked)
                            const Padding(
                              padding: EdgeInsets.only(top: 6),
                              child: Row(
                                children: [
                                  Icon(Icons.lock_outline,
                                      size: 13, color: EmbyTheme.warning),
                                  SizedBox(width: 4),
                                  Text(
                                    '元数据已手动纠错锁定',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: EmbyTheme.warning,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                // 主播放按钮（如果已有嗅探流则直接断点续播）
                if (_item.lastStreamUrl != null &&
                    _item.lastStreamUrl!.isNotEmpty)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: EmbyTheme.accent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => EnhancedPlayerPage(
                            mediaItem: _item,
                            streamUrl: _item.lastStreamUrl!,
                            referer: _item.sourceUrl,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: Text(
                      _item.lastPositionSec > 0
                          ? '断点续播（已看 ${_item.lastPositionSec ~/ 60} 分钟）'
                          : '立即原生播放',
                    ),
                  )
                else if (_item.sourceUrl.isNotEmpty)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: EmbyTheme.accent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => WebViewSnifferPage(
                            initialUrl: _item.sourceUrl,
                            initialSiteKey: _item.sourceSite,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.play_circle_outline_rounded),
                    label: const Text('打开原片页自动抓流播放'),
                  ),
                const SizedBox(height: 14),
                // 多站点一键直达嗅探
                const Text(
                  '多源搜索与嗅探直达',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: sites.map((site) {
                    return ActionChip(
                      avatar: const Icon(Icons.open_in_browser_rounded,
                          size: 16),
                      label: Text('去 ${site.key.toUpperCase()} 找流'),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => WebViewSnifferPage(
                              initialSiteKey: site.key,
                              initialUrl: site.buildSearchUrl(_item.code),
                            ),
                          ),
                        );
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
                // 网上大众评分（自动从 JavDB 获取，支持手动刷新）
                Row(
                  children: [
                    const Text(
                      '网上评分',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(width: 10),
                    if (_item.publicRating > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: EmbyTheme.accentSecondary
                              .withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${_item.publicRatingSource.isNotEmpty ? _item.publicRatingSource : 'JavDB'} ${_item.publicRating.toStringAsFixed(2)} / 5.0',
                          style: const TextStyle(
                            color: EmbyTheme.accentSecondary,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      )
                    else
                      const Text(
                        '暂无',
                        style: TextStyle(
                            fontSize: 12, color: EmbyTheme.textSecondary),
                      ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () async {
                        final res = await ref
                            .read(mediaLibraryProvider.notifier)
                            .fetchPublicRatingNow(_item);
                        if (res != null && mounted) {
                          setState(() {
                            _item = _item.copyWith(
                              publicRating: res.rating,
                              publicRatingSource: res.source,
                            );
                          });
                        } else if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content:
                                  Text('未获取到 JavDB 评分（可能非标准番号或暂时被拦截）'),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('刷新网评'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // 个人 1~5 星评分
                const Text(
                  '个人评分',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Row(
                  children: List.generate(5, (idx) {
                    final starValue = (idx + 1).toDouble();
                    final filled = _item.personalRating >= starValue;
                    return IconButton(
                      onPressed: () => _saveChanges(
                        _item.copyWith(personalRating: starValue),
                      ),
                      icon: Icon(
                        filled ? Icons.star_rounded : Icons.star_border_rounded,
                        color: EmbyTheme.warning,
                        size: 30,
                      ),
                    );
                  }),
                ),
                if (_item.actors.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const Text(
                    '演员',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _item.actors
                        .map((a) => Chip(label: Text(a)))
                        .toList(),
                  ),
                ],
                if (_item.tags.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const Text(
                    '标签',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children:
                        _item.tags.map((t) => Chip(label: Text(t))).toList(),
                  ),
                ],
                if (_item.notes.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const Text(
                    '个人笔记',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(_item.notes),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
