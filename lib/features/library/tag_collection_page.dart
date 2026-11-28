import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/media_item.dart';
import '../../core/providers/app_providers.dart';
import '../../core/storage/database_helper.dart';
import '../../core/theme/emby_theme.dart';
import '../../core/widgets/cum_count_badge.dart';
import 'media_detail_page.dart';

enum CollectionKind { actor, tag, source }

/// 点击详情页中的女优、标签或来源后进入的专属作品汇总页（支持继续点击任意作品无缝探索）
class TagCollectionPage extends ConsumerStatefulWidget {
  final CollectionKind kind;
  final String value;

  const TagCollectionPage({
    super.key,
    required this.kind,
    required this.value,
  });

  @override
  ConsumerState<TagCollectionPage> createState() => _TagCollectionPageState();
}

class _TagCollectionPageState extends ConsumerState<TagCollectionPage> {
  List<MediaItem> _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String get _titlePrefix => switch (widget.kind) {
        CollectionKind.actor => '女优',
        CollectionKind.tag => '标签 #',
        CollectionKind.source => '来源',
      };

  Future<void> _load() async {
    final all = await DatabaseHelper.instance.getAllMediaItems();
    final filter = switch (widget.kind) {
      CollectionKind.actor => LibraryFilter(selectedActors: {widget.value}),
      CollectionKind.tag => LibraryFilter(selectedTags: {widget.value}),
      CollectionKind.source => LibraryFilter(selectedSources: {widget.value}),
    };
    final matched = filter.applyTagFilters(all);
    if (mounted) {
      setState(() {
        _items = matched;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayValue = widget.kind == CollectionKind.source
        ? widget.value.toUpperCase()
        : widget.value;

    return Scaffold(
      appBar: AppBar(
        title: Text('$_titlePrefix$displayValue (${_items.length})'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(
                  child: Text(
                    '私人影库中暂无其他「$displayValue」相关作品',
                    style: const TextStyle(color: EmbyTheme.textSecondary),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.96,
                  ),
                  itemCount: _items.length,
                  itemBuilder: (_, idx) {
                    final item = _items[idx];
                    return GestureDetector(
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => MediaDetailPage(initialItem: item),
                          ),
                        );
                        _load();
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: EmbyTheme.surface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AspectRatio(
                              aspectRatio: 16 / 9.4,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  if (item.posterUrl.isNotEmpty)
                                    CachedNetworkImage(
                                      imageUrl: item.posterUrl,
                                      fit: BoxFit.cover,
                                      errorWidget: (_, __, ___) => Container(
                                        color: const Color(0xFF1E2634),
                                        child: const Icon(
                                            Icons.movie_creation_outlined),
                                      ),
                                    )
                                  else
                                    Container(
                                      color: const Color(0xFF1E2634),
                                      child: const Icon(
                                          Icons.movie_creation_outlined),
                                    ),
                                  Positioned(
                                    top: 6,
                                    left: 6,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color:
                                            Colors.black.withValues(alpha: 0.78),
                                        borderRadius: BorderRadius.circular(5),
                                      ),
                                      child: Text(
                                        item.code,
                                        style: const TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    right: 6,
                                    bottom: 5,
                                    child: CumCountBadge(
                                      count: item.cumCount,
                                      compact: true,
                                      onChanged: (next) async {
                                        await ref
                                            .read(mediaLibraryProvider.notifier)
                                            .updateCumCount(item.id, next);
                                        _load();
                                      },
                                    ),
                                  ),
                                ],
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
                                    Text(
                                      item.tags.isNotEmpty
                                          ? '${item.sourceTagLabel} · ${item.tags.take(2).join(' · ')}'
                                          : item.sourceTagLabel,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 10.5,
                                        color: EmbyTheme.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
