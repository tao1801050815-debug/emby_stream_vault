enum DownloadStatus {
  queued,
  downloading,
  completed,
  failed,
  paused,
}

/// m3u8 离线缓存任务模型
class DownloadTask {
  final String id;
  final String code;
  final String title;
  final String posterUrl;
  final String streamUrl;
  final String referer;
  final String cookieHeader;
  final int totalSegments;
  final int downloadedSegments;
  final DownloadStatus status;
  final String localDir;
  final String? localPlaylistPath;
  final String? errorMessage;
  final int createdAtMs;

  const DownloadTask({
    required this.id,
    required this.code,
    required this.title,
    this.posterUrl = '',
    required this.streamUrl,
    this.referer = '',
    this.cookieHeader = '',
    this.totalSegments = 0,
    this.downloadedSegments = 0,
    this.status = DownloadStatus.queued,
    required this.localDir,
    this.localPlaylistPath,
    this.errorMessage,
    required this.createdAtMs,
  });

  double get progress {
    if (totalSegments <= 0) return 0.0;
    return (downloadedSegments / totalSegments).clamp(0.0, 1.0);
  }

  DownloadTask copyWith({
    int? totalSegments,
    int? downloadedSegments,
    DownloadStatus? status,
    String? localPlaylistPath,
    String? errorMessage,
  }) {
    return DownloadTask(
      id: id,
      code: code,
      title: title,
      posterUrl: posterUrl,
      streamUrl: streamUrl,
      referer: referer,
      cookieHeader: cookieHeader,
      totalSegments: totalSegments ?? this.totalSegments,
      downloadedSegments: downloadedSegments ?? this.downloadedSegments,
      status: status ?? this.status,
      localDir: localDir,
      localPlaylistPath: localPlaylistPath ?? this.localPlaylistPath,
      errorMessage: errorMessage ?? this.errorMessage,
      createdAtMs: createdAtMs,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'code': code,
        'title': title,
        'posterUrl': posterUrl,
        'streamUrl': streamUrl,
        'referer': referer,
        'cookieHeader': cookieHeader,
        'totalSegments': totalSegments,
        'downloadedSegments': downloadedSegments,
        'status': status.name,
        'localDir': localDir,
        'localPlaylistPath': localPlaylistPath,
        'errorMessage': errorMessage,
        'createdAtMs': createdAtMs,
      };

  factory DownloadTask.fromMap(Map<String, dynamic> map) {
    final statusName = (map['status'] as String?) ?? 'queued';
    final status = DownloadStatus.values.firstWhere(
      (e) => e.name == statusName,
      orElse: () => DownloadStatus.queued,
    );
    return DownloadTask(
      id: map['id'] as String,
      code: (map['code'] as String?) ?? '',
      title: (map['title'] as String?) ?? '',
      posterUrl: (map['posterUrl'] as String?) ?? '',
      streamUrl: (map['streamUrl'] as String?) ?? '',
      referer: (map['referer'] as String?) ?? '',
      cookieHeader: (map['cookieHeader'] as String?) ?? '',
      totalSegments: (map['totalSegments'] as int?) ?? 0,
      downloadedSegments: (map['downloadedSegments'] as int?) ?? 0,
      status: status,
      localDir: (map['localDir'] as String?) ?? '',
      localPlaylistPath: map['localPlaylistPath'] as String?,
      errorMessage: map['errorMessage'] as String?,
      createdAtMs: (map['createdAtMs'] as int?) ?? 0,
    );
  }
}
