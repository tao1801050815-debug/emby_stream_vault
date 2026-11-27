import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../core/models/media_item.dart';
import '../../core/providers/app_providers.dart';
import '../../core/services/live_ai_subtitle_service.dart';
import '../../core/theme/emby_theme.dart';

/// 增强型原生播放器：断点续播 + 双击快进 + 长按倍速 + 外挂字幕与时间轴偏移 + 画面锐化
class EnhancedPlayerPage extends ConsumerStatefulWidget {
  final MediaItem mediaItem;
  final String streamUrl;
  final String referer;
  final String cookieHeader;
  final String? initialSubtitleUrl;

  const EnhancedPlayerPage({
    super.key,
    required this.mediaItem,
    required this.streamUrl,
    this.referer = '',
    this.cookieHeader = '',
    this.initialSubtitleUrl,
  });

  @override
  ConsumerState<EnhancedPlayerPage> createState() => _EnhancedPlayerPageState();
}

class _EnhancedPlayerPageState extends ConsumerState<EnhancedPlayerPage> {
  late final Player _player;
  late final VideoController _videoController;

  double _rate = 1.0;
  double _subtitleDelaySec = 0.0;
  bool _sharpnessEnabled = false;
  bool _oneHandMode = false;
  String? _hudMessage;
  Timer? _hudTimer;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration>? _durSub;

  // 纯手机端 AI 实时字幕状态
  LiveAiSubtitleSession? _aiSession;
  bool _aiSubtitleEnabled = false;
  String _aiSubtitleStatus = '';
  List<AiSubtitleCue> _aiCues = const [];

  @override
  void initState() {
    super.initState();
    _player = Player();
    _videoController = VideoController(_player);

    final prefs = ref.read(appPreferencesProvider);
    _rate = prefs.defaultSpeed;
    _sharpnessEnabled = prefs.enableSharpness;

    _posSub = _player.stream.position.listen((d) {
      if (mounted) setState(() => _position = d);
      _aiSession?.updatePosition(d.inMilliseconds / 1000.0);
    });
    _durSub = _player.stream.duration.listen((d) {
      if (mounted) setState(() => _duration = d);
    });

    _initPlayback();
  }

  Future<void> _initPlayback() async {
    final headers = <String, String>{};
    if (widget.referer.isNotEmpty) headers['Referer'] = widget.referer;
    if (widget.cookieHeader.isNotEmpty) headers['Cookie'] = widget.cookieHeader;

    await _player.open(
      Media(
        widget.streamUrl,
        httpHeaders: headers.isEmpty ? null : headers,
      ),
    );
    await _player.setRate(_rate);
    await _applySharpness(_sharpnessEnabled);

    if (widget.initialSubtitleUrl != null &&
        widget.initialSubtitleUrl!.isNotEmpty) {
      await _player.setSubtitleTrack(
        SubtitleTrack.uri(widget.initialSubtitleUrl!),
      );
    }

    // 自动加载本地已保存的 AI 字幕（对应时间点自动出现，无需重新识别）
    final cachedCues =
        await LiveAiSubtitleSession.loadCachedCues(widget.mediaItem.id);
    if (cachedCues.isNotEmpty && mounted) {
      setState(() {
        _aiCues = cachedCues;
      });
      _showHud('已自动加载本地字幕（${cachedCues.length} 句）');
    }

    // 断点续播
    if (widget.mediaItem.lastPositionSec > 5) {
      await _player.seek(Duration(seconds: widget.mediaItem.lastPositionSec));
      _showHud('已从 ${widget.mediaItem.lastPositionSec ~/ 60} 分继续播放');
    }
  }

  Future<void> _applySharpness(bool enable) async {
    if (_player.platform is NativePlayer) {
      await (_player.platform as NativePlayer).setProperty(
        'sharpen',
        enable ? '1.2' : '0',
      );
    }
  }

  Future<void> _applySubtitleDelay(double delaySec) async {
    setState(() => _subtitleDelaySec = delaySec);
    if (_player.platform is NativePlayer) {
      await (_player.platform as NativePlayer).setProperty(
        'sub-delay',
        delaySec.toStringAsFixed(2),
      );
    }
    _showHud('字幕偏移 ${delaySec >= 0 ? '+' : ''}${delaySec.toStringAsFixed(1)}s');
  }

  Future<void> _pickLocalSubtitle() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['srt', 'ass', 'vtt', 'ssa'],
    );
    final filePath = result?.files.single.path;
    if (filePath != null) {
      await _player.setSubtitleTrack(SubtitleTrack.uri(filePath));
      _showHud('已加载外挂字幕');
    }
  }

  void _showHud(String msg) {
    _hudTimer?.cancel();
    setState(() => _hudMessage = msg);
    _hudTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _hudMessage = null);
    });
  }

  Future<void> _seekBy(int deltaSeconds) async {
    final next = _position + Duration(seconds: deltaSeconds);
    final clamped = next < Duration.zero
        ? Duration.zero
        : (_duration > Duration.zero && next > _duration ? _duration : next);
    await _player.seek(clamped);
    _showHud('${deltaSeconds > 0 ? '快进' : '快退'} ${deltaSeconds.abs()} 秒');
  }

  Future<void> _saveProgress() async {
    await ref.read(mediaLibraryProvider.notifier).saveItem(
          widget.mediaItem.copyWith(
            lastStreamUrl: widget.streamUrl,
            lastPositionSec: _position.inSeconds,
            durationSec: _duration.inSeconds,
            updatedAtMs: DateTime.now().millisecondsSinceEpoch,
          ),
        );
  }

  @override
  void dispose() {
    _aiSession?.dispose();
    _hudTimer?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    _saveProgress();
    _player.dispose();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  Future<void> _toggleAiSubtitle() async {
    if (_aiSubtitleEnabled) {
      _aiSession?.dispose();
      _aiSession = null;
      setState(() {
        _aiSubtitleEnabled = false;
        _aiSubtitleStatus = '';
      });
      _showHud('已关闭 AI 实时字幕');
      return;
    }

    final prefs = ref.read(appPreferencesProvider);
    if (prefs.aiApiKey.trim().isEmpty) {
      _showHud('请先到「设置 → AI 实时字幕」填写 API Key');
      return;
    }

    setState(() {
      _aiSubtitleEnabled = true;
      _aiSubtitleStatus = '正在启动 AI 字幕...';
    });

    final session = LiveAiSubtitleSession(
      mediaId: widget.mediaItem.id,
      streamUrl: widget.streamUrl,
      referer: widget.referer,
      cookieHeader: widget.cookieHeader,
      prefs: prefs,
      onCuesUpdated: (cues) {
        if (mounted) setState(() => _aiCues = cues);
      },
      onStatusChanged: (status) {
        if (mounted) setState(() => _aiSubtitleStatus = status);
      },
    );
    _aiSession = session;
    await session.start(_position.inMilliseconds / 1000.0);
  }

  AiSubtitleCue? _activeAiCue() {
    // 只要本地有已保存的字幕（或已开启实时识别），在对应时间点自动显示
    if (_aiCues.isEmpty) return null;
    final currentSec = (_position.inMilliseconds / 1000.0) - _subtitleDelaySec;
    for (final cue in _aiCues) {
      if (currentSec >= cue.startSec - 0.2 && currentSec <= cue.endSec + 0.4) {
        return cue;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(appPreferencesProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black87,
        title: Text(
          widget.mediaItem.code.isNotEmpty
              ? '${widget.mediaItem.code} · ${widget.mediaItem.title}'
              : widget.mediaItem.title,
          style: const TextStyle(fontSize: 15),
        ),
        actions: [
          IconButton(
            tooltip: 'AI 实时中文字幕',
            icon: Icon(
              Icons.translate_rounded,
              color: _aiSubtitleEnabled ? EmbyTheme.accent : Colors.white,
            ),
            onPressed: _toggleAiSubtitle,
          ),
          IconButton(
            tooltip: '单手控制栏',
            icon: Icon(
              _oneHandMode
                  ? Icons.pan_tool_alt_rounded
                  : Icons.pan_tool_alt_outlined,
              color: _oneHandMode ? EmbyTheme.accent : Colors.white,
            ),
            onPressed: () => setState(() => _oneHandMode = !_oneHandMode),
          ),
          IconButton(
            tooltip: '加载外挂字幕',
            icon: const Icon(Icons.subtitles_outlined),
            onPressed: _pickLocalSubtitle,
          ),
          IconButton(
            tooltip: '画面锐化增强',
            icon: Icon(
              Icons.auto_fix_high_rounded,
              color: _sharpnessEnabled ? EmbyTheme.accent : Colors.white,
            ),
            onPressed: () async {
              final next = !_sharpnessEnabled;
              setState(() => _sharpnessEnabled = next);
              await _applySharpness(next);
              _showHud(next ? '已开启画面锐化' : '已关闭画面锐化');
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                Video(controller: _videoController),
                // 左右半屏手势层：双击快进/快退 + 长按 2x 临时倍速
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onDoubleTap: () => _seekBy(-prefs.seekSeconds),
                        onLongPressStart: (_) async {
                          await _player.setRate(2.0);
                          _showHud('2.0x 临时倍速');
                        },
                        onLongPressEnd: (_) async {
                          await _player.setRate(_rate);
                          _showHud('恢复 ${_rate}x');
                        },
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onDoubleTap: () => _seekBy(prefs.seekSeconds),
                        onLongPressStart: (_) async {
                          await _player.setRate(2.0);
                          _showHud('2.0x 临时倍速');
                        },
                        onLongPressEnd: (_) async {
                          await _player.setRate(_rate);
                          _showHud('恢复 ${_rate}x');
                        },
                      ),
                    ),
                  ],
                ),
                if (_hudMessage != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _hudMessage!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                // 顶部 AI 实时字幕状态小徽章
                if (_aiSubtitleEnabled && _aiSubtitleStatus.isNotEmpty)
                  Positioned(
                    top: 10,
                    left: 12,
                    child: IgnorePointer(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          _aiSubtitleStatus,
                          style: const TextStyle(
                            fontSize: 11,
                            color: EmbyTheme.accent,
                          ),
                        ),
                      ),
                    ),
                  ),
                // 底部实时 AI 中文字幕浮层（支持双语与时间轴偏移）
                if (_activeAiCue() case final cue?)
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 24,
                    child: IgnorePointer(
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.76),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                cue.translatedText,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  height: 1.3,
                                ),
                              ),
                              if (prefs.aiBilingual &&
                                  cue.originalText.isNotEmpty &&
                                  cue.originalText != cue.translatedText)
                                Padding(
                                  padding: const EdgeInsets.only(top: 3),
                                  child: Text(
                                    cue.originalText,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // 底部增强控制面板（倍速 + 字幕时间轴偏移 + 单手快捷按钮）
          Container(
            color: EmbyTheme.surface,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: _oneHandMode
                        ? MainAxisAlignment.end
                        : MainAxisAlignment.spaceBetween,
                    children: [
                      // 倍速选择
                      DropdownButton<double>(
                        value: _rate,
                        underline: const SizedBox.shrink(),
                        items: const [0.75, 1.0, 1.25, 1.5, 2.0, 2.5]
                            .map((r) => DropdownMenuItem(
                                  value: r,
                                  child: Text('${r}x'),
                                ))
                            .toList(),
                        onChanged: (val) async {
                          if (val == null) return;
                          setState(() => _rate = val);
                          await _player.setRate(val);
                          _showHud('倍速 ${val}x');
                        },
                      ),
                      const SizedBox(width: 8),
                      // 字幕时间轴偏移微调
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: '字幕提前 0.5s',
                            icon: const Icon(Icons.remove_circle_outline,
                                size: 20),
                            onPressed: () =>
                                _applySubtitleDelay(_subtitleDelaySec - 0.5),
                          ),
                          Text(
                            '字幕 ${_subtitleDelaySec >= 0 ? '+' : ''}${_subtitleDelaySec.toStringAsFixed(1)}s',
                            style: const TextStyle(fontSize: 12),
                          ),
                          IconButton(
                            tooltip: '字幕延后 0.5s',
                            icon:
                                const Icon(Icons.add_circle_outline, size: 20),
                            onPressed: () =>
                                _applySubtitleDelay(_subtitleDelaySec + 0.5),
                          ),
                        ],
                      ),
                      IconButton(
                        tooltip: '快退 ${prefs.seekSeconds}s',
                        icon: const Icon(Icons.replay_10_rounded),
                        onPressed: () => _seekBy(-prefs.seekSeconds),
                      ),
                      IconButton(
                        tooltip: '快进 ${prefs.seekSeconds}s',
                        icon: const Icon(Icons.forward_10_rounded),
                        onPressed: () => _seekBy(prefs.seekSeconds),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
