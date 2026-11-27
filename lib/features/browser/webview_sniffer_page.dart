import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/bookmark.dart';
import '../../core/models/media_item.dart';
import '../../core/models/site_config.dart';
import '../../core/providers/app_providers.dart';
import '../../core/theme/emby_theme.dart';
import '../player/enhanced_player_page.dart';

/// 嗅探到的页面媒体信息
class SniffedMediaInfo {
  final String code;
  final String title;
  final String posterUrl;
  final List<String> actors;
  final List<String> tags;
  final String pageUrl;
  final List<String> streamUrls;
  final List<String> subtitleUrls;

  const SniffedMediaInfo({
    this.code = '',
    this.title = '',
    this.posterUrl = '',
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
      actors: actors ?? this.actors,
      tags: tags ?? this.tags,
      pageUrl: pageUrl ?? this.pageUrl,
      streamUrls: streamUrls ?? this.streamUrls,
      subtitleUrls: subtitleUrls ?? this.subtitleUrls,
    );
  }
}

/// 内置浏览器：支持 MissAV/JavDB 账号登录、CF 过验证、广告拦截、m3u8 嗅探与一键入库
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

  Future<void> _extractPageMetadata(InAppWebViewController controller) async {
    const js = '''
      (function() {
        try {
          var title = document.querySelector('meta[property="og:title"]')?.content || document.title || '';
          var poster = document.querySelector('meta[property="og:image"]')?.content || '';
          var url = location.href;
          var codeMatch = (url + ' ' + title).match(/([A-Za-z]{2,6}-\\d{2,5})/);
          var code = codeMatch ? codeMatch[1].toUpperCase() : '';
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
            title: title.trim(),
            posterUrl: poster,
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
        final mergedStreams = {
          ..._sniffed.streamUrls,
          ...foundVideos,
        }.toList();

        if (mounted) {
          setState(() {
            _sniffed = _sniffed.copyWith(
              code: (data['code'] as String?)?.isNotEmpty == true
                  ? data['code'] as String
                  : _sniffed.code,
              title: (data['title'] as String?) ?? _sniffed.title,
              posterUrl: (data['posterUrl'] as String?) ?? _sniffed.posterUrl,
              pageUrl: (data['pageUrl'] as String?) ?? _sniffed.pageUrl,
              streamUrls: mergedStreams,
            );
          });
        }
      } catch (_) {}
    }
  }

  Future<void> _saveToLibrary(SiteProfile currentSite,
      {String? overrideStreamUrl}) async {
    // 若当前页没有单个番号，先检测是否为收藏夹/列表页；若是则自动转为批量导入
    if (_sniffed.code.isEmpty && _controller != null) {
      final listItems = await _extractListItemsFromDom();
      if (listItems.length >= 2) {
        await _promptAndImportBatch(listItems);
        return;
      }
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final code = _sniffed.code.isNotEmpty
        ? _sniffed.code
        : 'ITEM-${now.toString().substring(7)}';
    final item = MediaItem(
      id: '${_activeSiteKey}_$code',
      code: code,
      title: _sniffed.title.isNotEmpty ? _sniffed.title : code,
      posterUrl: _sniffed.posterUrl,
      actors: _sniffed.actors,
      tags: _sniffed.tags,
      isFavorite: true,
      sourceSite: _activeSiteKey,
      sourceUrl: _sniffed.pageUrl,
      lastStreamUrl: overrideStreamUrl ??
          (_sniffed.streamUrls.isNotEmpty ? _sniffed.streamUrls.first : null),
      updatedAtMs: now,
    );
    await ref.read(mediaLibraryProvider.notifier).saveItem(item);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已收藏到私人影库: $code')),
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

  /// 从当前网页 DOM 提取影片列表（兼容 MissAV / xHamster / Pornhub / JavDB / Hanime1）
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
            if (/\/(login|register|signup|account|saved|favorites|categories|tags|actors)(\/|\?|$)/i.test(href)) return;

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

            seen[href] = true;
            items.push({
              code: code,
              title: title || code,
              posterUrl: poster,
              sourceUrl: href
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

  Future<void> _promptAndImportBatch(List<Map<String, dynamic>> parsed) async {
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('识别到 ${parsed.length} 部影片'),
        content: Text(
          '当前是影片列表/收藏页！是否将这 ${parsed.length} 部影片分别拆出并导入到「Emby 私人影库」？\n（已存在且手动锁定纠错的影片会自动保留你的修改）',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('全部导入'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = parsed.map((m) {
      final code = (m['code'] as String? ?? '').trim();
      final title = (m['title'] as String? ?? code).trim();
      return MediaItem(
        id: '${_activeSiteKey}_$code',
        code: code,
        title: title.isNotEmpty ? title : code,
        posterUrl: (m['posterUrl'] as String? ?? '').trim(),
        isFavorite: true,
        sourceSite: _activeSiteKey,
        sourceUrl: (m['sourceUrl'] as String? ?? '').trim(),
        updatedAtMs: now,
      );
    }).toList();

    await ref.read(mediaLibraryProvider.notifier).saveItemsBatch(batch);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('成功导入 ${batch.length} 部影片到私人影库！翻到下一页可继续导入'),
        ),
      );
    }
  }

  /// 批量导入当前网页的影片列表（如 MissAV 收藏夹 /cn/saved、xHamster 收藏页、演员主页）
  Future<void> _batchImportCurrentPage(SiteProfile currentSite) async {
    if (_controller == null) return;
    final parsed = await _extractListItemsFromDom();
    if (!mounted) return;

    if (parsed.isEmpty) {
      final jumpToSaved = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('当前页未识别到影片列表'),
          content: const Text(
            '请先在内置浏览器中打开你的收藏夹页面（如 MissAV /cn/saved 或 xHamster 收藏页），再点此按钮即可一键批量导入到 Emby 海报墙。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('知道了'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('直达 MissAV 收藏夹'),
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

    await _promptAndImportBatch(parsed);
  }

  Future<void> _openNativePlayer(String streamUrl) async {
    final cookieHeader = await _collectCookieHeader(_sniffed.pageUrl);
    final now = DateTime.now().millisecondsSinceEpoch;
    final code = _sniffed.code.isNotEmpty ? _sniffed.code : 'STREAM';
    final item = MediaItem(
      id: '${_activeSiteKey}_$code',
      code: code,
      title: _sniffed.title.isNotEmpty ? _sniffed.title : code,
      posterUrl: _sniffed.posterUrl,
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
            tooltip: '批量导入本页收藏（如 MissAV 收藏夹）',
            icon: const Icon(Icons.playlist_add_check_rounded,
                color: EmbyTheme.accent),
            onPressed: () => _batchImportCurrentPage(currentSite),
          ),
          IconButton(
            tooltip: '收藏当前网页（免登录）',
            icon: const Icon(Icons.bookmark_add_rounded,
                color: EmbyTheme.warning),
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
              itemCount: sites.length,
            ),
          ),
          if (_progress < 1.0)
            LinearProgressIndicator(
              value: _progress,
              minHeight: 2,
              color: EmbyTheme.accent,
            ),
          Expanded(
            child: Stack(
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
                    // 过滤列表页缩略图悬停预览小视频，避免在收藏列表页误报捕获正片流
                    final isPreviewClip = lower.contains('preview') ||
                        lower.contains('thumb') ||
                        lower.contains('trailer') ||
                        lower.contains('teaser') ||
                        lower.contains('_t.mp4');
                    if ((lower.contains('.m3u8') || lower.contains('.mp4')) &&
                        !isPreviewClip) {
                      if (!_sniffed.streamUrls.contains(resUrl)) {
                        setState(() {
                          _sniffed = _sniffed.copyWith(
                            streamUrls: [..._sniffed.streamUrls, resUrl],
                          );
                        });
                      }
                    } else if (lower.endsWith('.vtt') ||
                        lower.endsWith('.srt') ||
                        lower.endsWith('.ass')) {
                      if (!_sniffed.subtitleUrls.contains(resUrl)) {
                        setState(() {
                          _sniffed = _sniffed.copyWith(
                            subtitleUrls: [..._sniffed.subtitleUrls, resUrl],
                          );
                        });
                      }
                    }
                  },
                ),
                // 底部 Emby 嗅探操作胶囊
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12,
                  child: _SnifferActionBar(
                    sniffed: _sniffed,
                    onSaveLibrary: () => _saveToLibrary(currentSite),
                    onPlayStream: _openNativePlayer,
                    onDownloadStream: _enqueueDownload,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SnifferActionBar extends StatelessWidget {
  final SniffedMediaInfo sniffed;
  final VoidCallback onSaveLibrary;
  final ValueChanged<String> onPlayStream;
  final ValueChanged<String> onDownloadStream;

  const _SnifferActionBar({
    required this.sniffed,
    required this.onSaveLibrary,
    required this.onPlayStream,
    required this.onDownloadStream,
  });

  @override
  Widget build(BuildContext context) {
    final hasStream = sniffed.streamUrls.isNotEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: EmbyTheme.surfaceGlass,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasStream
              ? EmbyTheme.accent.withValues(alpha: 0.6)
              : Colors.white.withValues(alpha: 0.12),
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
          Icon(
            hasStream ? Icons.play_circle_filled_rounded : Icons.radar_rounded,
            color: hasStream ? EmbyTheme.accent : EmbyTheme.textSecondary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  hasStream
                      ? '已捕获 ${sniffed.streamUrls.length} 条视频流'
                      : '正在监听页面视频流与字幕...',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (sniffed.code.isNotEmpty)
                  Text(
                    sniffed.code,
                    style: const TextStyle(
                      fontSize: 11,
                      color: EmbyTheme.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: '收藏到私人库',
            icon: const Icon(Icons.bookmark_add_outlined),
            onPressed: onSaveLibrary,
          ),
          if (hasStream) ...[
            IconButton(
              tooltip: '离线缓存',
              icon: const Icon(Icons.download_for_offline_outlined),
              onPressed: () => onDownloadStream(sniffed.streamUrls.first),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: EmbyTheme.accent,
                foregroundColor: Colors.black,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              onPressed: () => onPlayStream(sniffed.streamUrls.first),
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              label: const Text('原生播放'),
            ),
          ],
        ],
      ),
    );
  }
}
