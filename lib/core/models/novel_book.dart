import 'dart:convert';

class NovelChapter {
  final int index;
  final String title;
  final String content;
  final int wordCount;

  const NovelChapter({
    required this.index,
    required this.title,
    required this.content,
    required this.wordCount,
  });

  Map<String, dynamic> toJson() => {
        'index': index,
        'title': title,
        'content': content,
        'wordCount': wordCount,
      };

  factory NovelChapter.fromJson(Map<String, dynamic> json) {
    final content = (json['content'] ?? '').toString();
    return NovelChapter(
      index: ((json['index'] as num?) ?? 0).toInt(),
      title: (json['title'] ?? '未命名章节').toString(),
      content: content,
      wordCount: ((json['wordCount'] as num?) ?? content.length).toInt(),
    );
  }
}

class NovelBook {
  final String id;
  final String title;
  final String author;
  final String summary;
  final String source; // lan / webdav / local
  final List<NovelChapter> chapters;
  final int lastChapterIndex;
  final double lastScrollOffset;
  final int updatedAtMs;

  const NovelBook({
    required this.id,
    required this.title,
    this.author = '',
    this.summary = '',
    this.source = 'local',
    this.chapters = const [],
    this.lastChapterIndex = 0,
    this.lastScrollOffset = 0.0,
    required this.updatedAtMs,
  });

  int get totalWords =>
      chapters.fold(0, (sum, ch) => sum + ch.wordCount);

  String get formattedWords {
    if (totalWords >= 10000) {
      return '${(totalWords / 10000).toStringAsFixed(1)} 万字';
    }
    return '$totalWords 字';
  }

  String get sourceLabel => switch (source) {
        'lan' => '局域网直连',
        'webdav' => '坚果云/WebDAV',
        _ => '本地导入',
      };

  NovelBook copyWith({
    String? id,
    String? title,
    String? author,
    String? summary,
    String? source,
    List<NovelChapter>? chapters,
    int? lastChapterIndex,
    double? lastScrollOffset,
    int? updatedAtMs,
  }) {
    return NovelBook(
      id: id ?? this.id,
      title: title ?? this.title,
      author: author ?? this.author,
      summary: summary ?? this.summary,
      source: source ?? this.source,
      chapters: chapters ?? this.chapters,
      lastChapterIndex: lastChapterIndex ?? this.lastChapterIndex,
      lastScrollOffset: lastScrollOffset ?? this.lastScrollOffset,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'author': author,
        'summary': summary,
        'source': source,
        'chaptersJson':
            jsonEncode(chapters.map((c) => c.toJson()).toList()),
        'lastChapterIndex': lastChapterIndex,
        'lastScrollOffset': lastScrollOffset,
        'updatedAtMs': updatedAtMs,
      };

  factory NovelBook.fromMap(Map<String, dynamic> map) {
    final rawChapters = map['chaptersJson']?.toString() ?? '[]';
    final chapters = <NovelChapter>[];
    try {
      final list = jsonDecode(rawChapters);
      if (list is List) {
        for (final item in list) {
          if (item is Map) {
            chapters.add(
              NovelChapter.fromJson(Map<String, dynamic>.from(item)),
            );
          }
        }
      }
    } catch (_) {}

    return NovelBook(
      id: (map['id'] ?? '').toString(),
      title: (map['title'] ?? '未命名小说').toString(),
      author: (map['author'] ?? '').toString(),
      summary: (map['summary'] ?? '').toString(),
      source: (map['source'] ?? 'local').toString(),
      chapters: chapters,
      lastChapterIndex: ((map['lastChapterIndex'] as num?) ?? 0).toInt(),
      lastScrollOffset: ((map['lastScrollOffset'] as num?) ?? 0.0).toDouble(),
      updatedAtMs: ((map['updatedAtMs'] as num?) ?? 0).toInt(),
    );
  }

  factory NovelBook.fromSyncJson(
    Map<String, dynamic> json, {
    required String source,
  }) {
    final rawList = (json['chapters'] as List<dynamic>? ?? const []);
    final chapters = <NovelChapter>[];
    for (var i = 0; i < rawList.length; i++) {
      final item = rawList[i];
      if (item is Map) {
        final ch = NovelChapter.fromJson(Map<String, dynamic>.from(item));
        chapters.add(
          NovelChapter(
            index: i,
            title: ch.title,
            content: ch.content,
            wordCount: ch.wordCount,
          ),
        );
      }
    }
    return NovelBook(
      id: (json['id'] ?? 'novel_default').toString(),
      title: (json['title'] ?? '未命名小说').toString(),
      author: (json['author'] ?? '').toString(),
      summary: (json['summary'] ?? '').toString(),
      source: source,
      chapters: chapters,
      updatedAtMs: ((json['updatedAtMs'] as num?) ??
              DateTime.now().millisecondsSinceEpoch)
          .toInt(),
    );
  }

  /// 将整本 TXT / Markdown 文本自动按「第XXX章」或「# 标题」拆分为章节目录
  static List<NovelChapter> parseTextIntoChapters(
    String rawText, {
    String fallbackTitle = '正文',
  }) {
    final normalized =
        rawText.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
    if (normalized.isEmpty) return const [];

    final headingReg = RegExp(
      r'^(?:#{1,2}\s+.+|第[0-9零一二三四五六七八九十百千万]+[章回节卷][^\n]{0,40})$',
      multiLine: true,
    );
    final matches = headingReg.allMatches(normalized).toList();
    if (matches.isEmpty) {
      return [
        NovelChapter(
          index: 0,
          title: fallbackTitle,
          content: normalized,
          wordCount: normalized.replaceAll(RegExp(r'\s+'), '').length,
        ),
      ];
    }

    final chapters = <NovelChapter>[];
    // 如果第一章标题前有较长序言/楔子，保留为序章
    final preface = normalized.substring(0, matches.first.start).trim();
    if (preface.length >= 60) {
      chapters.add(
        NovelChapter(
          index: 0,
          title: '序章',
          content: preface,
          wordCount: preface.replaceAll(RegExp(r'\s+'), '').length,
        ),
      );
    }

    for (var i = 0; i < matches.length; i++) {
      final m = matches[i];
      final title = m.group(0)!.replaceFirst(RegExp(r'^#{1,2}\s+'), '').trim();
      final bodyStart = m.end;
      final bodyEnd =
          (i + 1 < matches.length) ? matches[i + 1].start : normalized.length;
      final body = normalized.substring(bodyStart, bodyEnd).trim();
      chapters.add(
        NovelChapter(
          index: chapters.length,
          title: title,
          content: body.isNotEmpty ? body : title,
          wordCount: body.replaceAll(RegExp(r'\s+'), '').length,
        ),
      );
    }
    return chapters;
  }
}
