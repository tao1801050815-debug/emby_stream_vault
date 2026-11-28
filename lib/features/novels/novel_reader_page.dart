import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/novel_book.dart';
import '../../core/models/site_config.dart';
import '../../core/providers/app_providers.dart';
import '../../core/theme/emby_theme.dart';

/// 沉浸式护眼小说阅读器：支持目录跳章、字号行距调节、3 套护眼配色与精准阅读进度自动保存
class NovelReaderPage extends ConsumerStatefulWidget {
  final NovelBook book;

  const NovelReaderPage({super.key, required this.book});

  @override
  ConsumerState<NovelReaderPage> createState() => _NovelReaderPageState();
}

class _NovelReaderPageState extends ConsumerState<NovelReaderPage> {
  late int _chapterIndex;
  late ScrollController _scrollController;
  bool _showChrome = true;

  @override
  void initState() {
    super.initState();
    final maxIdx =
        (widget.book.chapters.length - 1).clamp(0, 999999);
    _chapterIndex = widget.book.lastChapterIndex.clamp(0, maxIdx);
    _scrollController = ScrollController(
      initialScrollOffset: widget.book.lastScrollOffset.clamp(0.0, 999999.0),
    );
  }

  @override
  void dispose() {
    _saveProgress();
    _scrollController.dispose();
    super.dispose();
  }

  void _saveProgress() {
    final offset =
        _scrollController.hasClients ? _scrollController.offset : 0.0;
    ref
        .read(novelBooksProvider.notifier)
        .updateProgress(widget.book.id, _chapterIndex, offset);
  }

  void _goToChapter(int idx) {
    if (idx < 0 || idx >= widget.book.chapters.length) return;
    setState(() => _chapterIndex = idx);
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    ref
        .read(novelBooksProvider.notifier)
        .updateProgress(widget.book.id, _chapterIndex, 0.0);
  }

  ({Color bg, Color text, Color subText}) _palette(String mode) {
    return switch (mode) {
      'sepia' => (
          bg: const Color(0xFFF3E9D2),
          text: const Color(0xFF2D2418),
          subText: const Color(0xFF6B5B45),
        ),
      'green' => (
          bg: const Color(0xFFDCECD8),
          text: const Color(0xFF1F2D1E),
          subText: const Color(0xFF4F664D),
        ),
      _ => (
          bg: const Color(0xFF0E1117),
          text: const Color(0xFFDDE3EA),
          subText: const Color(0xFF8B949E),
        ),
    };
  }

  void _openChapterDrawer() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: EmbyTheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        minChildSize: 0.45,
        maxChildSize: 0.92,
        builder: (_, scrollCtrl) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '目录 · 共 ${widget.book.chapters.length} 章',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    widget.book.formattedWords,
                    style: const TextStyle(
                      fontSize: 12,
                      color: EmbyTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                controller: scrollCtrl,
                itemCount: widget.book.chapters.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final ch = widget.book.chapters[i];
                  final active = i == _chapterIndex;
                  return ListTile(
                    dense: true,
                    selected: active,
                    selectedTileColor:
                        EmbyTheme.accent.withValues(alpha: 0.14),
                    title: Text(
                      ch.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight:
                            active ? FontWeight.w800 : FontWeight.normal,
                        color: active
                            ? EmbyTheme.accent
                            : EmbyTheme.textPrimary,
                      ),
                    ),
                    trailing: Text(
                      '${ch.wordCount}字',
                      style: const TextStyle(
                        fontSize: 11,
                        color: EmbyTheme.textSecondary,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      _goToChapter(i);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openTypographySheet(AppPreferences prefs) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: EmbyTheme.surface,
      builder: (ctx) => Consumer(
        builder: (ctx, sheetRef, _) {
          final p = sheetRef.watch(appPreferencesProvider);
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '阅读排版与护眼配色',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text('字号'),
                      const SizedBox(width: 12),
                      OutlinedButton(
                        onPressed: () {
                          final next = (p.readerFontSize - 1).clamp(13.0, 28.0);
                          sheetRef
                              .read(appPreferencesProvider.notifier)
                              .update(p.copyWith(readerFontSize: next));
                        },
                        child: const Text('A-'),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Text(p.readerFontSize.toStringAsFixed(1)),
                      ),
                      OutlinedButton(
                        onPressed: () {
                          final next = (p.readerFontSize + 1).clamp(13.0, 28.0);
                          sheetRef
                              .read(appPreferencesProvider.notifier)
                              .update(p.copyWith(readerFontSize: next));
                        },
                        child: const Text('A+'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Text('行距'),
                      Expanded(
                        child: Slider(
                          value: p.readerLineHeight.clamp(1.3, 2.3),
                          min: 1.3,
                          max: 2.3,
                          divisions: 10,
                          label: p.readerLineHeight.toStringAsFixed(1),
                          onChanged: (v) {
                            sheetRef
                                .read(appPreferencesProvider.notifier)
                                .update(p.copyWith(readerLineHeight: v));
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    children: [
                      ChoiceChip(
                        label: const Text('深黑夜读'),
                        selected: p.readerThemeMode == 'dark',
                        onSelected: (_) => sheetRef
                            .read(appPreferencesProvider.notifier)
                            .update(p.copyWith(readerThemeMode: 'dark')),
                      ),
                      ChoiceChip(
                        label: const Text('羊皮纸护眼'),
                        selected: p.readerThemeMode == 'sepia',
                        onSelected: (_) => sheetRef
                            .read(appPreferencesProvider.notifier)
                            .update(p.copyWith(readerThemeMode: 'sepia')),
                      ),
                      ChoiceChip(
                        label: const Text('豆沙绿护眼'),
                        selected: p.readerThemeMode == 'green',
                        onSelected: (_) => sheetRef
                            .read(appPreferencesProvider.notifier)
                            .update(p.copyWith(readerThemeMode: 'green')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(appPreferencesProvider);
    final colors = _palette(prefs.readerThemeMode);

    if (widget.book.chapters.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.book.title)),
        body: const Center(child: Text('本书暂无可读章节')),
      );
    }

    final chapter = widget.book.chapters[_chapterIndex];
    final hasPrev = _chapterIndex > 0;
    final hasNext = _chapterIndex < widget.book.chapters.length - 1;

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: _showChrome
          ? AppBar(
              backgroundColor: colors.bg.withValues(alpha: 0.94),
              foregroundColor: colors.text,
              title: Text(
                chapter.title,
                style: TextStyle(fontSize: 15, color: colors.text),
              ),
              actions: [
                IconButton(
                  tooltip: '目录',
                  icon: const Icon(Icons.list_rounded),
                  onPressed: _openChapterDrawer,
                ),
                IconButton(
                  tooltip: '字号与配色',
                  icon: const Icon(Icons.text_fields_rounded),
                  onPressed: () => _openTypographySheet(prefs),
                ),
              ],
            )
          : null,
      body: GestureDetector(
        onTap: () => setState(() => _showChrome = !_showChrome),
        child: SafeArea(
          top: !_showChrome,
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 56),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  chapter.title,
                  style: TextStyle(
                    fontSize: prefs.readerFontSize + 4,
                    fontWeight: FontWeight.w800,
                    color: colors.text,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${widget.book.title} · 第 ${_chapterIndex + 1}/${widget.book.chapters.length} 章 · ${chapter.wordCount} 字',
                  style: TextStyle(fontSize: 12, color: colors.subText),
                ),
                const SizedBox(height: 18),
                SelectableText(
                  chapter.content,
                  style: TextStyle(
                    fontSize: prefs.readerFontSize,
                    height: prefs.readerLineHeight,
                    color: colors.text,
                  ),
                ),
                const SizedBox(height: 36),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed:
                            hasPrev ? () => _goToChapter(_chapterIndex - 1) : null,
                        icon: const Icon(Icons.chevron_left_rounded),
                        label: const Text('上一章'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: EmbyTheme.accent,
                          foregroundColor: Colors.black,
                        ),
                        onPressed:
                            hasNext ? () => _goToChapter(_chapterIndex + 1) : null,
                        icon: const Icon(Icons.chevron_right_rounded),
                        label: Text(hasNext ? '下一章' : '已是最新章'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: _showChrome
          ? Container(
              color: colors.bg.withValues(alpha: 0.96),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: SafeArea(
                top: false,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    TextButton.icon(
                      onPressed:
                          hasPrev ? () => _goToChapter(_chapterIndex - 1) : null,
                      icon: const Icon(Icons.skip_previous_rounded, size: 18),
                      label: const Text('上一章'),
                    ),
                    TextButton.icon(
                      onPressed: _openChapterDrawer,
                      icon: const Icon(Icons.menu_book_rounded, size: 18),
                      label: Text('${_chapterIndex + 1}/${widget.book.chapters.length}'),
                    ),
                    TextButton.icon(
                      onPressed: () => _openTypographySheet(prefs),
                      icon: const Icon(Icons.tune_rounded, size: 18),
                      label: const Text('排版'),
                    ),
                    TextButton.icon(
                      onPressed:
                          hasNext ? () => _goToChapter(_chapterIndex + 1) : null,
                      icon: const Icon(Icons.skip_next_rounded, size: 18),
                      label: const Text('下一章'),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }
}
