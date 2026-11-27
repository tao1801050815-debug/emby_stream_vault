import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/download_task.dart';
import '../../core/models/media_item.dart';
import '../../core/providers/app_providers.dart';
import '../../core/theme/emby_theme.dart';
import '../player/enhanced_player_page.dart';

/// 离线缓存管理页面
class DownloadsPage extends ConsumerWidget {
  const DownloadsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(downloadTasksProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('离线缓存'),
        actions: [
          IconButton(
            tooltip: '刷新状态',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () =>
                ref.read(downloadTasksProvider.notifier).refresh(),
          ),
        ],
      ),
      body: tasks.isEmpty
          ? const Center(
              child: Text(
                '暂无离线缓存任务\n在嗅探浏览器捕获到视频流后点下载即可离线观看',
                textAlign: TextAlign.center,
                style: TextStyle(color: EmbyTheme.textSecondary, height: 1.5),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: tasks.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, idx) {
                final task = tasks[idx];
                return _DownloadTaskCard(
                  task: task,
                  onPlayOffline: task.status == DownloadStatus.completed &&
                          task.localPlaylistPath != null
                      ? () {
                          final item = MediaItem(
                            id: task.id,
                            code: task.code,
                            title: task.title,
                            posterUrl: task.posterUrl,
                            updatedAtMs: task.createdAtMs,
                          );
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => EnhancedPlayerPage(
                                mediaItem: item,
                                streamUrl: task.localPlaylistPath!,
                              ),
                            ),
                          );
                        }
                      : null,
                  onDelete: () =>
                      ref.read(downloadTasksProvider.notifier).remove(task.id),
                );
              },
            ),
    );
  }
}

class _DownloadTaskCard extends StatelessWidget {
  final DownloadTask task;
  final VoidCallback? onPlayOffline;
  final VoidCallback onDelete;

  const _DownloadTaskCard({
    required this.task,
    required this.onPlayOffline,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final statusLabel = switch (task.status) {
      DownloadStatus.queued => '等待中',
      DownloadStatus.downloading =>
        '下载中 ${task.downloadedSegments}/${task.totalSegments}',
      DownloadStatus.completed => '已完成（可离线播放）',
      DownloadStatus.failed => '下载失败',
      DownloadStatus.paused => '已暂停',
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${task.code} · ${task.title}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        statusLabel,
                        style: TextStyle(
                          fontSize: 12,
                          color: task.status == DownloadStatus.failed
                              ? EmbyTheme.danger
                              : EmbyTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onPlayOffline != null)
                  IconButton(
                    tooltip: '离线播放',
                    icon: const Icon(Icons.play_circle_fill_rounded,
                        color: EmbyTheme.accent, size: 30),
                    onPressed: onPlayOffline,
                  ),
                IconButton(
                  tooltip: '删除任务',
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: onDelete,
                ),
              ],
            ),
            if (task.status == DownloadStatus.downloading) ...[
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: task.progress,
                color: EmbyTheme.accent,
              ),
            ],
            if (task.errorMessage != null &&
                task.status == DownloadStatus.failed) ...[
              const SizedBox(height: 6),
              Text(
                task.errorMessage!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 11, color: EmbyTheme.danger),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
