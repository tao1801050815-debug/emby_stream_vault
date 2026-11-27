import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/bookmark.dart';
import '../../core/models/media_item.dart';
import '../../core/models/site_config.dart';
import '../../core/providers/app_providers.dart';
import '../../core/services/web_metadata_extractor_service.dart';
import '../../core/theme/emby_theme.dart';
import '../player/enhanced_player_page.dart';

/// 嗅探到的页面媒体信息
class SniffedMediaInfo {
  final String code;
  final String title;
  final String posterUrl;
  final String studio;
  final List<String> actors;
  final List<String> tags;
  final String pageUrl;
  final List<String> streamUrls;
  final List<String> subtitleUrls;

  const SniffedMediaInfo({
    this.code = '',
    this.title = '',
    this.posterUrl = '',
    this.studio = '',
    this.actors = const [],
    this.tags = const [],
    this.pageUrl = '',
    this.streamUrls = const [],
    this.subtitleUrls = const [],
  });

  SniffedMediaInfo copyWith({
    String? code,
    String? title,
    String? posterUrl,
    String? studio,
    List<String>? actors,
    List<String>? tags,
    String? pageUrl,
    List<String>? streamUrls,
    List<String>? subtitleUrls,
  }) {
    return SniffedMediaInfo(
      code: code ?? this.code,
      title: title ?? this.title,
      posterUrl: posterUrl ?? this.posterUrl,
      studio: studio ?? this.studio,
      actors: actors ?? this.actors,
      tags: tags ?? this.tags,
      pageUrl: pageUrl ?? this.pageUrl,
      streamUrls: streamUrls ?? this.streamUrls,
      subtitleUrls: subtitleUrls ?? this.subtitleUrls,
    );
  }
}

class _RecognizedCandidate {
  final String code;
  final String title;
  final String posterUrl;
  final String sourceUrl;
  final String studio;
  final List<String> actors;
  final List<String> tags;
  final String? streamUrl;
  final bool isCurrentMain;

  const _RecognizedCandidate({
    required this.code,
    required this.title,
    required this.posterUrl,
    required this.sourceUrl,
    this.studio = '',
    this.actors = const [],
    this.tags = const [],
    this.streamUrl,
    this.isCurrentMain = false,
  });
}

/// 内置浏览器：支持 MissAV/JavDB 登录、m3u8 嗅探、MissAV 标签/无码版本识别与可视化选片收藏
class WebViewSnifferPage extends ConsumerStatefulWidget {
  final String? initialUrl;
  final String? initialSiteKey;

  const WebViewSnifferPage({
    super.key,
    this.initialUrl,
    this.initialSiteKey,
  });

  @override
  ConsumerState<WebViewSnifferPage> createState() => _WebViewSnifferPageState();
}

class _WebViewSnifferPageState extends ConsumerState<WebViewSnifferPage> {
  InAppWebViewController? _controller;
  final TextEditingController _urlController = TextEditingController();
  late String _activeSiteKey;
  double _progress = 0;
  bool _canGoBack = false;
  SniffedMediaInfo _sniffed = const SniffedMediaInfo();
  Offset? _snifferPos; // 可自由拖动的位置
  bool _snifferCollapsed = false; // 是否折叠成迷你悬浮球

  static const _adHostKeywords = [
    'doubleclick.net',
    'googlesyndication.com',
    'popads.net',
    'popcash.net',
    'exoclick.com',
    'juicyads.com',
    'trafficjunky.net',
    'adsterra.com',
    'tsyndicate.com',
  ];

  @override
  void initState() {
    super.initState();
    _activeSiteKey = widget.initialSiteKey ?? 'missav';
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  SiteProfile _currentSite(List<SiteProfile> sites) {
    return sites.firstWhere(
      (s) => s.key == _activeSiteKey,
      orElse: () => sites.first,
    );
  }

  Future<void> _loadUrl(String url) async {
    if (_controller == null) return;
    final normalized = url.startsWith('http') ? url : 'https://$url';
    setState(() {
      _sniffed = SniffedMediaInfo(pageUrl: normalized);
    });
    await _controller!.loadUrl(urlRequest: URLRequest(url: WebUri(normalized)));
  }

  Future<String> _collectCookieHeader(String url) async {
    try {
      final cookies =
          await CookieManager.instance().getCookies(url: WebUri(url));
      return cookies.map((c) => '${c.name}=${c.value}').join('; ');
    } catch (_) {
      return '';
    }
  }

  /// 对捕获到的多条流按正片画质排序（优先 master playlist.m3u8 或高码率 1080p/720p）
  List<String> _prioritizeStreams(Iterable<String> urls) {
    final unique = urls.toSet().toList();
    int scoreOf(String u) {
      final l = u.toLowerCase();
      var s = 0;
      if (l.contains('playlist.m3u8') || l.contains('master.m3u8')) s += 50;
      if (l.contains('1080')) s += 30;
      if (l.contains('720')) s += 20;
      if (l.contains('.m3u8')) s += 10;
      return s;
    }

    unique.sort((a, b) => scoreOf(b).compareTo(scoreOf(a)));
    return unique;
  }

  /// 提取当前正片详情页的标题、番号、封面、自带标签（如中出/巨乳/无码流出）、女优与片商
  Future<void> _extractPageMetadata(InAppWebViewController controller) async {
    const js = r'''
      (function() {
        try {
          var rawTitle = document.querySelector('meta[property="og:title"]')?.content || document.title || '';
          var title = rawTitle.replace(/\s*[-|]\s*(MissAV|Pornhub|xHamster|JavDB|Jable).*$/i, '').trim();
          var poster = document.querySelector('meta[property="og:image"]')?.content
            || document.querySelector('meta[name="twitter:image"]')?.content || '';
          var url = location.href;
          var codeMatch = (url + ' ' + title).match(/([A-Za-z]{2,6}-\d{2,5}|FC2-PPV-\d{5,7})/i);
          var code = codeMatch ? codeMatch[1].toUpperCase() : '';

          // 提取 MissAV / JavDB / Pornhub / xHamster 页面自带标签（如 中出、巨乳、单体作品、无码流出）
          var tagSet = {};
          var ignoreWords = {'全部':1,'更多':1,'首页':1,'首頁':1,'类型':1,'類型':1,'标签':1,'標籤':1,'categories':1,'tags':1,'all':1,'more':1};
          document.querySelectorAll('a[href*="/genres/"], a[href*="/tags"], a[href*="/categories/"], a[href*="genre="]').forEach(function(a) {
            var t = (a.textContent || '').replace(/\s+/g, ' ').replace(/^#/, '').trim();
            if (t && t.length <= 18 && !ignoreWords[t.toLowerCase()]) {
              tagSet[t] = true;
            }
          });

          var lowerAll = (url + ' ' + rawTitle).toLowerCase();
          if (lowerAll.includes('uncensored-leak') || rawTitle.includes('无码流出') || rawTitle.includes('無碼流出')) {
            tagSet['无码流出'] = true;
          } else if (lowerAll.includes('uncensored') || rawTitle.includes('无码') || rawTitle.includes('無碼')) {
            tagSet['无码'] = true;
          }
          if (lowerAll.includes('chinese-subtitle') || rawTitle.includes('中文字幕')) {
            tagSet['中文字幕'] = true;
          }

          // 提取演员/女优
          var actorSet = {};
          document.querySelectorAll('a[href*="/actors/"], a[href*="/actresses/"], a[href*="/pornstars/"], a[href*="/star/"]').forEach(function(a) {
            var name = (a.textContent || '').replace(/\s+/g, ' ').trim();
            if (name && name.length <= 24 && !/^(女优|女優|演员|演員|actors|pornstars)$/i.test(name)) {
              actorSet[name] = true;
            }
          });

          // 提取片商/发行商
          var studio = '';
          var makerEl = document.querySelector('a[href*="/makers/"], a[href*="/studios/"]');
          if (makerEl) {
            studio = (makerEl.textContent || '').replace(/\s+/g, ' ').trim();
          }

          var videos = [];
          document.querySelectorAll('video, video source').forEach(function(el) {
            if (el.src && (el.src.includes('.m3u8') || el.src.includes('.mp4'))) {
              videos.push(el.src);
            }
          });

          // 轻量隐藏常见弹窗广告容器
          document.querySelectorAll('iframe[src*="ads"], div[class*="ad-"], div[id*="ad-"]').forEach(function(el) {
            el.style.display = 'none';
          });

          return JSON.stringify({
            code: code,
            title: title,
            posterUrl: poster,
            studio: studio,
            tags: Object.keys(tagSet),
            actors: Object.keys(actorSet),
            pageUrl: url,
            videos: videos
          });
        } catch (e) {
          return JSON.stringify({});
        }
      })();
    ''';

    final res = await controller.evaluateJavascript(source: js);
    if (res is String && res.isNotEmpty) {
      try {
        final data = jsonDecode(res) as Map<String, dynamic>;
        final foundVideos = (data['videos'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList();
        final mergedStreams = _prioritizeStreams([
          ..._sniffed.streamUrls,
          ...foundVideos,
        ]);
        final parsedTags = (data['tags'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList();
        final parsedActors = (data['actors'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList();

        if (mounted) {
          setState(() {
            _sniffed = _sniffed.copyWith(
              code: (data['code'] as String?)?.isNotEmpty == true
                  ? data['code'] as String
                  : _sniffed.code,
              title: (data['title'] as String?) ?? _sniffed.title,
              posterUrl: (data['posterUrl'] as String?) ?? _sniffed.posterUrl,
              studio: (data['studio'] as String?) ?? _sniffed.studio,
              tags: parsedTags.isNotEmpty ? parsedTags : _sniffed.tags,
              actors: parsedActors.isNotEmpty ? parsedActors : _sniffed.actors,
              pageUrl: (data['pageUrl'] as String?) ?? _sniffed.pageUrl,
              streamUrls: mergedStreams,
            );
          });
        }
      } catch (_) {}
    }
  }

  /// 从当前网页 DOM 提取所有影片卡片（连带卡片角标如 无码 / 中文字幕）
  Future<List<Map<String, dynamic>>> _extractListItemsFromDom() async {
    if (_controller == null) return const [];

    const js = r'''
      (function() {
        try {
          var seen = {};
          var items = [];
          var anchors = document.querySelectorAll('a[href]');
          anchors.forEach(function(a) {
            var href = a.href || '';
            if (!href.startsWith('http') || seen[href]) return;
            if (/\/(login|register|signup|account|saved|favorites|categories|tags|genres|actors|makers)(\/|\?|$)/i.test(href)) return;

            var img = a.querySelector('img');
            if (!img) return;
            var poster = img.getAttribute('data-src') || img.getAttribute('data-original') || img.getAttribute('data-thumb_url') || img.getAttribute('src') || '';
            if (!poster || poster.startsWith('data:image')) return;
            if (/avatar|logo|icon|banner|sprite|flag/i.test(poster)) return;

            var card = a.closest('div, article, li') || a.parentElement;
            var title = (a.getAttribute('title') || img.getAttribute('alt') || '').trim();
            if (!title && card) {
              var titleEl = card.querySelector('h2, h3, h4, .title, .video-title, .video-thumb-info__name, a.text-secondary');
              if (titleEl) title = (titleEl.textContent || '').trim();
            }
            if (!title) title = (a.textContent || '').trim();
            title = title.replace(/\s+/g, ' ').trim();

            var code = '';
            var codeMatch = (href + ' ' + title).match(/([A-Za-z]{2,6}-\d{2,5}|FC2-PPV-\d{5,7})/i);
            if (codeMatch) {
              code = codeMatch[1].toUpperCase();
            } else if (/viewkey=([a-zA-Z0-9]+)/i.test(href)) {
              code = 'PH-' + href.match(/viewkey=([a-zA-Z0-9]+)/i)[1].slice(0, 10).toUpperCase();
            } else if (/xhamster\.com\/videos\/.*-([a-zA-Z0-9]+)$/i.test(href)) {
              code = 'XH-' + href.match(/xhamster\.com\/videos\/.*-([a-zA-Z0-9]+)$/i)[1].slice(-8).toUpperCase();
            } else if (/watch\?v=(\d+)/i.test(href)) {
              code = 'HN-' + href.match(/watch\?v=(\d+)/i)[1];
            } else {
              var segs = href.replace(/\/+$/, '').split('/');
              var last = (segs[segs.length - 1] || '').split('?')[0];
              if (last.length >= 3 && last.length <= 28 && !/\.(html|php)$/i.test(last)) {
                code = last.slice(0, 18).toUpperCase();
              }
            }
            if (!code) return;

            var badges = [];
            var lowerHrefTitle = (href + ' ' + title + ' ' + (card ? card.textContent : '')).toLowerCase();
            if (href.toLowerCase().includes('uncensored-leak') || lowerHrefTitle.includes('无码流出') || lowerHrefTitle.includes('無碼流出')) {
              badges.push('无码流出');
            } else if (href.toLowerCase().includes('uncensored') || lowerHrefTitle.includes('无码') || lowerHrefTitle.includes('無碼')) {
              badges.push('无码');
            }
            if (href.toLowerCase().includes('chinese-subtitle') || lowerHrefTitle.includes('中文字幕')) {
              badges.push('中文字幕');
            }

            seen[href] = true;
            items.push({
              code: code,
              title: title || code,
              posterUrl: poster,
              sourceUrl: href,
              tags: badges
            });
          });
          return JSON.stringify(items);
        } catch (e) {
          return '[]';
        }
      })();
    ''';

    final res = await _controller!.evaluateJavascript(source: js);
    final parsed = <Map<String, dynamic>>[];
    if (res is String && res.isNotEmpty) {
      try {
        final rawList = jsonDecode(res) as List<dynamic>;
        for (final entry in rawList) {
          if (entry is Map<String, dynamic>) {
            parsed.add(entry);
          }
        }
      } catch (_) {}
    }
    return parsed;
  }

  /// 点击「收藏」或「识别选片」时：列出当前页识别到的全部影片（当前正片 + 页面卡片），支持搜索过滤精准勾选收藏
  Future<void> _openRecognizedPicker(SiteProfile currentSite) async {
    if (_controller != null) {
      await _extractPageMetadata(_controller!);
    }
    final domItems = await _extractListItemsFromDom();
    if (!mounted) return;

    final candidates = <_RecognizedCandidate>[];
    final hasMainMedia =
        _sniffed.code.isNotEmpty || _sniffed.streamUrls.isNotEmpty;

    if (hasMainMedia) {
      final mainCode = _sniffed.code.isNotEmpty
          ? _sniffed.code
          : WebMetadataExtractorService.extractCodeFromText(
              '${_sniffed.pageUrl} ${_sniffed.title}',
            );
      final code = mainCode.isNotEmpty
          ? mainCode
          : 'ITEM-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
      candidates.add(
        _RecognizedCandidate(
          code: code,
          title: _sniffed.title.isNotEmpty ? _sniffed.title : code,
          posterUrl: _sniffed.posterUrl,
          sourceUrl: _sniffed.pageUrl,
          studio: _sniffed.studio,
          actors: _sniffed.actors,
          tags: _sniffed.tags,
          streamUrl: _sniffed.streamUrls.isNotEmpty
              ? _sniffed.streamUrls.first
              : null,
          isCurrentMain: true,
        ),
      );
    }

    for (final m in domItems) {
      final srcUrl = (m['sourceUrl'] as String? ?? '').trim();
      if (srcUrl.isEmpty || srcUrl == _sniffed.pageUrl) continue;
      final code = (m['code'] as String? ?? '').trim();
      final tags = (m['tags'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList();
      candidates.add(
        _RecognizedCandidate(
          code: code,
          title: (m['title'] as String? ?? code).trim(),
          posterUrl: (m['posterUrl'] as String? ?? '').trim(),
          sourceUrl: srcUrl,
          tags: tags,
        ),
      );
    }

    if (candidates.isEmpty) {
      final jumpToSaved = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('当前页未识别到影片'),
          content: const Text(
            '请打开具体影片播放页，或进入收藏夹/搜索列表页后再点击识别收藏。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('知道了'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('去 MissAV 收藏夹'),
            ),
          ],
        ),
      );
      if (jumpToSaved == true) {
        final base = currentSite.baseUrl.replaceAll(RegExp(r'/+$'), '');
        await _loadUrl('$base/cn/saved');
      }
      return;
    }

    // 默认勾选策略：若当前在正片播放页，默认精准勾中第 1 项「当前正片」；若是纯列表页，由用户自由点选或一键全选
    final selectedUrls = <String>{
      if (candidates.first.isCurrentMain) candidates.first.sourceUrl,
    };
    var searchKeyword = '';

    final confirmed = await showModalBottomSheet<List<_RecognizedCandidate>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: EmbyTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final kw = searchKeyword.trim().toLowerCase();
          final filtered = kw.isEmpty
              ? candidates
              : candidates.where((c) {
                  return c.code.toLowerCase().contains(kw) ||
                      c.title.toLowerCase().contains(kw) ||
                      c.tags.any((t) => t.toLowerCase().contains(kw));
                }).toList();

          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.76,
            minChildSize: 0.45,
            maxChildSize: 0.94,
            builder: (_, scrollCtrl) => Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 12, 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '识别到 ${candidates.length} 部影片 · 勾选要收藏的片子',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          setSheetState(() {
                            if (selectedUrls.length == filtered.length) {
                              selectedUrls.clear();
                            } else {
                              for (final c in filtered) {
                                selectedUrls.add(c.sourceUrl);
                              }
                            }
                          });
                        },
                        child: Text(
                          selectedUrls.length == filtered.length &&
                                  filtered.isNotEmpty
                              ? '清空选择'
                              : '全选当前',
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    height: 38,
                    child: TextField(
                      decoration: const InputDecoration(
                        hintText: '在识别结果中搜索番号或标题精准定位...',
                        prefixIcon: Icon(Icons.search_rounded, size: 18),
                        contentPadding: EdgeInsets.symmetric(horizontal: 10),
                      ),
                      onChanged: (v) => setSheetState(() => searchKeyword = v),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.separated(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, idx) {
                      final c = filtered[idx];
                      final checked = selectedUrls.contains(c.sourceUrl);
                      return CheckboxListTile(
                        value: checked,
                        activeColor: EmbyTheme.accent,
                        checkColor: Colors.black,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 4),
                        onChanged: (_) {
                          setSheetState(() {
                            if (checked) {
                              selectedUrls.remove(c.sourceUrl);
                            } else {
                              selectedUrls.add(c.sourceUrl);
                            }
                          });
                        },
                        secondary: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: SizedBox(
                            width: 84,
                            height: 50,
                            child: c.posterUrl.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: c.posterUrl,
                                    fit: BoxFit.cover,
                                    errorWidget: (_, __, ___) => Container(
                                      color: Colors.black26,
                                      child: const Icon(Icons.movie, size: 20),
                                    ),
                                  )
                                : Container(
                                    color: Colors.black26,
                                    child: const Icon(Icons.movie, size: 20),
                                  ),
                          ),
                        ),
                        title: Row(
                          children: [
                            if (c.isCurrentMain)
                              Container(
                                margin: const EdgeInsets.only(right: 6),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: EmbyTheme.accent,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  '当前正片',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.black,
                                  ),
                                ),
                              ),
                            Flexible(
                              child: Text(
                                c.code,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: EmbyTheme.accentSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              c.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                            if (c.tags.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: Text(
                                  '标签: ${c.tags.take(6).join(' · ')}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFFFF7AA8),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Row(
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('取消'),
                        ),
                        const Spacer(),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: EmbyTheme.accent,
                            foregroundColor: Colors.black,
                          ),
                          onPressed: selectedUrls.isEmpty
                              ? null
                              : () {
                                  final picked = candidates
                                      .where(
                                          (c) => selectedUrls.contains(c.sourceUrl))
                                      .toList();
                                  Navigator.pop(ctx, picked);
                                },
                          icon: const Icon(Icons.check_rounded, size: 18),
                          label: Text('加入私人影库 (${selectedUrls.length})'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    if (confirmed == null || confirmed.isEmpty) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final itemsToSave = confirmed.map((c) {
      final id = WebMetadataExtractorService.buildMediaId(
        siteKey: _activeSiteKey,
        code: c.code,
        sourceUrl: c.sourceUrl,
        tags: c.tags,
      );
      return MediaItem(
        id: id,
        code: c.code,
        title: c.title.isNotEmpty ? c.title : c.code,
        posterUrl: c.posterUrl,
        studio: c.studio,
        actors: c.actors,
        tags: c.tags,
        isFavorite: true,
        sourceSite: _activeSiteKey,
        sourceUrl: c.sourceUrl,
        lastStreamUrl: c.streamUrl,
        updatedAtMs: now,
      );
    }).toList();

    if (itemsToSave.length == 1) {
      await ref.read(mediaLibraryProvider.notifier).saveItem(itemsToSave.first);
    } else {
      await ref.read(mediaLibraryProvider.notifier).saveItemsBatch(itemsToSave);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            itemsToSave.length == 1
                ? '已精准收藏: ${itemsToSave.first.code}'
                : '已精准收藏选中的 ${itemsToSave.length} 部影片到私人影库',
          ),
        ),
      );
    }
  }

  Future<void> _bookmarkCurrentPage() async {
    final currentUrl = _urlController.text.trim().isNotEmpty
        ? _urlController.text.trim()
        : _sniffed.pageUrl;
    if (currentUrl.isEmpty) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final bm = BookmarkItem(
      id: 'bm_$now',
      title: _sniffed.title.isNotEmpty ? _sniffed.title : currentUrl,
      url: currentUrl,
      siteKey: _activeSiteKey,
      folder: '默认收藏',
      createdAtMs: now,
    );
    await ref.read(bookmarksProvider.notifier).save(bm);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已收藏当前网页到本地书签夹（免登录）')),
      );
    }
  }

  Future<void> _openNativePlayer(String streamUrl) async {
    final cookieHeader = await _collectCookieHeader(_sniffed.pageUrl);
    final now = DateTime.now().millisecondsSinceEpoch;
    final code = _sniffed.code.isNotEmpty ? _sniffed.code : 'STREAM';
    final id = WebMetadataExtractorService.buildMediaId(
      siteKey: _activeSiteKey,
      code: code,
      sourceUrl: _sniffed.pageUrl,
      tags: _sniffed.tags,
    );
    final item = MediaItem(
      id: id,
      code: code,
      title: _sniffed.title.isNotEmpty ? _sniffed.title : code,
      posterUrl: _sniffed.posterUrl,
      studio: _sniffed.studio,
      actors: _sniffed.actors,
      tags: _sniffed.tags,
      sourceSite: _activeSiteKey,
      sourceUrl: _sniffed.pageUrl,
      lastStreamUrl: streamUrl,
      updatedAtMs: now,
    );
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EnhancedPlayerPage(
          mediaItem: item,
          streamUrl: streamUrl,
          referer: _sniffed.pageUrl,
          cookieHeader: cookieHeader,
          initialSubtitleUrl: _sniffed.subtitleUrls.isNotEmpty
              ? _sniffed.subtitleUrls.first
              : null,
        ),
      ),
    );
  }

  Future<void> _enqueueDownload(String streamUrl) async {
    final cookieHeader = await _collectCookieHeader(_sniffed.pageUrl);
    final code = _sniffed.code.isNotEmpty ? _sniffed.code : 'VIDEO';
    await ref.read(downloadTasksProvider.notifier).enqueue(
          code: code,
          title: _sniffed.title.isNotEmpty ? _sniffed.title : code,
          posterUrl: _sniffed.posterUrl,
          streamUrl: streamUrl,
          referer: _sniffed.pageUrl,
          cookieHeader: cookieHeader,
        );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已加入离线缓存队列: $code')),
      );
    }
  }

  Future<void> _quickAddSiteDialog() async {
    final nameCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    final searchCtrl = TextEditingController(text: '{base}/search/{query}');
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加新片源网站'),
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
                controller: urlCtrl,
                decoration: const InputDecoration(
                    labelText: '网站地址（如 https://xxx.com）'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: searchCtrl,
                decoration:
                    const InputDecoration(labelText: '搜索模板（可选，默认即可）'),
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
            child: const Text('添加并打开'),
          ),
        ],
      ),
    );
    if (saved == true && urlCtrl.text.trim().isNotEmpty) {
      var rawUrl = urlCtrl.text.trim();
      if (!rawUrl.startsWith('http://') && !rawUrl.startsWith('https://')) {
        rawUrl = 'https://$rawUrl';
      }
      final base = rawUrl.replaceAll(RegExp(r'/+$'), '');
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
      final displayName = nameCtrl.text.trim().isNotEmpty
          ? nameCtrl.text.trim()
          : (uri?.host ?? key);

      final newSite = SiteProfile(
        key: key,
        name: displayName,
        baseUrl: base,
        searchTemplate: searchCtrl.text.trim().isNotEmpty
            ? searchCtrl.text.trim()
            : '{base}/search/{query}',
        loginUrl: base,
      );
      await ref.read(siteProfilesProvider.notifier).addSite(newSite);
      if (mounted) {
        setState(() => _activeSiteKey = newSite.key);
        await _loadUrl(newSite.baseUrl);
      }
    }
    nameCtrl.dispose();
    urlCtrl.dispose();
    searchCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sites = ref.watch(siteProfilesProvider);
    final prefs = ref.watch(appPreferencesProvider);
    final currentSite = _currentSite(sites);
    final startUrl = widget.initialUrl ?? currentSite.baseUrl;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 8,
        title: SizedBox(
          height: 38,
          child: TextField(
            controller: _urlController,
            style: const TextStyle(fontSize: 13),
            textInputAction: TextInputAction.go,
            decoration: InputDecoration(
              hintText: '输入网址或番号搜索...',
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
              prefixIcon: const Icon(Icons.public, size: 18),
              suffixIcon: IconButton(
                icon: const Icon(Icons.refresh, size: 18),
                onPressed: () => _controller?.reload(),
              ),
            ),
            onSubmitted: (val) {
              final q = val.trim();
              if (q.isEmpty) return;
              if (q.contains('.') || q.startsWith('http')) {
                _loadUrl(q);
              } else {
                _loadUrl(currentSite.buildSearchUrl(q));
              }
            },
          ),
        ),
        actions: [
          IconButton(
            tooltip: '识别本页影片并勾选收藏',
            icon: const Icon(Icons.playlist_add_check_rounded,
                color: EmbyTheme.accent),
            onPressed: () => _openRecognizedPicker(currentSite),
          ),
          IconButton(
            tooltip: '收藏当前网页（免登录）',
            icon:
                const Icon(Icons.bookmark_add_rounded, color: EmbyTheme.warning),
            onPressed: _bookmarkCurrentPage,
          ),
          IconButton(
            tooltip: '登录当前站点账号',
            icon: const Icon(Icons.login_rounded),
            onPressed: () => _loadUrl(currentSite.loginUrl),
          ),
          if (_canGoBack)
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
              onPressed: () => _controller?.goBack(),
            ),
        ],
      ),
      body: Column(
        children: [
          // 站点快速切换条
          SizedBox(
            height: 44,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              scrollDirection: Axis.horizontal,
              itemBuilder: (_, idx) {
                if (idx == sites.length) {
                  return ActionChip(
                    avatar: const Icon(Icons.add_rounded,
                        size: 16, color: EmbyTheme.accent),
                    label: const Text('添加网站'),
                    onPressed: _quickAddSiteDialog,
                  );
                }
                final site = sites[idx];
                final selected = site.key == _activeSiteKey;
                return ChoiceChip(
                  label: Text(site.key.toUpperCase()),
                  selected: selected,
                  selectedColor: EmbyTheme.accent.withValues(alpha: 0.25),
                  onSelected: (_) {
                    setState(() => _activeSiteKey = site.key);
                    _loadUrl(site.baseUrl);
                  },
                );
              },
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemCount: sites.length + 1,
            ),
          ),
          if (_progress < 1.0)
            LinearProgressIndicator(
              value: _progress,
              minHeight: 2,
              color: EmbyTheme.accent,
            ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final barWidth = _snifferCollapsed
                    ? 56.0
                    : (constraints.maxWidth - 24).clamp(240.0, 440.0);
                const barHeight = 64.0;
                final defaultLeft = _snifferCollapsed
                    ? constraints.maxWidth - 68.0
                    : (constraints.maxWidth - barWidth) / 2;
                final defaultTop = (constraints.maxHeight - barHeight - 16.0)
                    .clamp(8.0, constraints.maxHeight - barHeight);
                final currentLeft = (_snifferPos?.dx ?? defaultLeft).clamp(
                  8.0,
                  (constraints.maxWidth - barWidth - 8.0)
                      .clamp(8.0, constraints.maxWidth),
                );
                final currentTop = (_snifferPos?.dy ?? defaultTop).clamp(
                  8.0,
                  (constraints.maxHeight - barHeight - 8.0)
                      .clamp(8.0, constraints.maxHeight),
                );

                return Stack(
                  children: [
                    InAppWebView(
                      initialUrlRequest: URLRequest(url: WebUri(startUrl)),
                      initialSettings: InAppWebViewSettings(
                        javaScriptEnabled: true,
                        mediaPlaybackRequiresUserGesture: false,
                        allowsInlineMediaPlayback: true,
                        sharedCookiesEnabled: true,
                        useShouldOverrideUrlLoading: true,
                        useOnLoadResource: true,
                        userAgent: prefs.customUserAgent.isNotEmpty
                            ? prefs.customUserAgent
                            : null,
                      ),
                      onWebViewCreated: (controller) {
                        _controller = controller;
                      },
                      onLoadStart: (controller, url) {
                        final u = url?.toString() ?? '';
                        _urlController.text = u;
                        setState(() {
                          _sniffed = SniffedMediaInfo(pageUrl: u);
                        });
                      },
                      onProgressChanged: (_, progress) {
                        setState(() => _progress = progress / 100.0);
                      },
                      onLoadStop: (controller, url) async {
                        final canBack = await controller.canGoBack();
                        if (mounted) {
                          setState(() => _canGoBack = canBack);
                        }
                        await _extractPageMetadata(controller);
                      },
                      shouldOverrideUrlLoading: (controller, action) async {
                        final target = action.request.url?.toString() ?? '';
                        if (prefs.blockPopupAds &&
                            _adHostKeywords.any((k) => target.contains(k))) {
                          return NavigationActionPolicy.CANCEL;
                        }
                        return NavigationActionPolicy.ALLOW;
                      },
                      onLoadResource: (controller, resource) {
                        final resUrl = resource.url.toString();
                        final lower = resUrl.toLowerCase();
                        final isPreviewClip = lower.contains('preview') ||
                            lower.contains('thumb') ||
                            lower.contains('trailer') ||
                            lower.contains('teaser') ||
                            lower.contains('_t.mp4');
                        if ((lower.contains('.m3u8') ||
                                lower.contains('.mp4')) &&
                            !isPreviewClip) {
                          if (!_sniffed.streamUrls.contains(resUrl)) {
                            setState(() {
                              _sniffed = _sniffed.copyWith(
                                streamUrls: _prioritizeStreams(
                                  [..._sniffed.streamUrls, resUrl],
                                ),
                              );
                            });
                          }
                        } else if (lower.endsWith('.vtt') ||
                            lower.endsWith('.srt') ||
                            lower.endsWith('.ass')) {
                          if (!_sniffed.subtitleUrls.contains(resUrl)) {
                            setState(() {
                              _sniffed = _sniffed.copyWith(
                                subtitleUrls: [
                                  ..._sniffed.subtitleUrls,
                                  resUrl,
                                ],
                              );
                            });
                          }
                        }
                      },
                    ),
                    // 可自由拖动 + 可折叠的嗅探悬浮条
                    Positioned(
                      left: currentLeft,
                      top: currentTop,
                      width: barWidth,
                      child: GestureDetector(
                        onPanUpdate: (details) {
                          setState(() {
                            final nextX = (currentLeft + details.delta.dx)
                                .clamp(
                                    8.0,
                                    (constraints.maxWidth - barWidth - 8.0)
                                        .clamp(8.0, constraints.maxWidth));
                            final nextY = (currentTop + details.delta.dy)
                                .clamp(
                                    8.0,
                                    (constraints.maxHeight - barHeight - 8.0)
                                        .clamp(8.0, constraints.maxHeight));
                            _snifferPos = Offset(nextX, nextY);
                          });
                        },
                        child: _SnifferActionBar(
                          sniffed: _sniffed,
                          collapsed: _snifferCollapsed,
                          onToggleCollapse: () {
                            setState(() {
                              _snifferCollapsed = !_snifferCollapsed;
                            });
                          },
                          onSaveLibrary: () =>
                              _openRecognizedPicker(currentSite),
                          onPlayStream: _openNativePlayer,
                          onDownloadStream: _enqueueDownload,
                        ),
                      ),
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
}

class _SnifferActionBar extends StatelessWidget {
  final SniffedMediaInfo sniffed;
  final bool collapsed;
  final VoidCallback onToggleCollapse;
  final VoidCallback onSaveLibrary;
  final ValueChanged<String> onPlayStream;
  final ValueChanged<String> onDownloadStream;

  const _SnifferActionBar({
    required this.sniffed,
    required this.collapsed,
    required this.onToggleCollapse,
    required this.onSaveLibrary,
    required this.onPlayStream,
    required this.onDownloadStream,
  });

  @override
  Widget build(BuildContext context) {
    final hasStream = sniffed.streamUrls.isNotEmpty;

    if (collapsed) {
      return GestureDetector(
        onTap: onToggleCollapse,
        child: Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: EmbyTheme.surfaceGlass,
            shape: BoxShape.circle,
            border: Border.all(
              color: hasStream
                  ? EmbyTheme.accent
                  : Colors.white.withValues(alpha: 0.2),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(
                hasStream
                    ? Icons.play_circle_filled_rounded
                    : Icons.radar_rounded,
                color: hasStream ? EmbyTheme.accent : EmbyTheme.textPrimary,
                size: 26,
              ),
              if (hasStream)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: const BoxDecoration(
                      color: EmbyTheme.accent,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${sniffed.streamUrls.length}',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: EmbyTheme.surfaceGlass,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasStream
              ? EmbyTheme.accent.withValues(alpha: 0.6)
              : Colors.white.withValues(alpha: 0.14),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.drag_indicator_rounded,
              size: 18, color: EmbyTheme.textSecondary),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  hasStream
                      ? '已捕获 ${sniffed.streamUrls.length} 条流'
                      : '可拖动 · 监听中...',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (sniffed.code.isNotEmpty)
                  Text(
                    sniffed.tags.isNotEmpty
                        ? '${sniffed.code} · ${sniffed.tags.take(2).join('/')}'
                        : sniffed.code,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: EmbyTheme.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: '识别并选择要收藏的影片',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.bookmark_add_outlined, size: 20),
            onPressed: onSaveLibrary,
          ),
          if (hasStream) ...[
            IconButton(
              tooltip: '离线缓存',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.download_for_offline_outlined, size: 20),
              onPressed: () => onDownloadStream(sniffed.streamUrls.first),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: EmbyTheme.accent,
                foregroundColor: Colors.black,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                minimumSize: Size.zero,
              ),
              onPressed: () => onPlayStream(sniffed.streamUrls.first),
              child: const Text('播放', style: TextStyle(fontSize: 12)),
            ),
          ],
          IconButton(
            tooltip: '收起成悬浮球（防遮挡）',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close_fullscreen_rounded, size: 18),
            onPressed: onToggleCollapse,
          ),
        ],
      ),
    );
  }
}
