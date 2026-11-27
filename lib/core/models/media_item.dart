import 'dart:convert';

/// 本地私人媒体库中的影片条目模型
class MediaItem {
  final String id;
  final String code; // 番号，如 SSIS-001
  final String title;
  final String posterUrl;
  final List<String> actors;
  final List<String> tags;
  final String studio;
  final String releaseDate;
  final double personalRating; // 0.0 ~ 5.0
  final String notes;
  final bool isFavorite;
  final bool isMetadataLocked; // 手动纠错锁定，防止后续同步覆盖
  final String sourceSite; // missav / javdb / jable / custom
  final String sourceUrl;
  final String? lastStreamUrl;
  final String? localSubtitlePath;
  final int lastPositionSec;
  final int durationSec;
  final int updatedAtMs;

  const MediaItem({
    required this.id,
    required this.code,
    required this.title,
    this.posterUrl = '',
    this.actors = const [],
    this.tags = const [],
    this.studio = '',
    this.releaseDate = '',
    this.personalRating = 0.0,
    this.notes = '',
    this.isFavorite = false,
    this.isMetadataLocked = false,
    this.sourceSite = 'missav',
    this.sourceUrl = '',
    this.lastStreamUrl,
    this.localSubtitlePath,
    this.lastPositionSec = 0,
    this.durationSec = 0,
    required this.updatedAtMs,
  });

  double get watchProgress {
    if (durationSec <= 0) return 0.0;
    return (lastPositionSec / durationSec).clamp(0.0, 1.0);
  }

  MediaItem copyWith({
    String? id,
    String? code,
    String? title,
    String? posterUrl,
    List<String>? actors,
    List<String>? tags,
    String? studio,
    String? releaseDate,
    double? personalRating,
    String? notes,
    bool? isFavorite,
    bool? isMetadataLocked,
    String? sourceSite,
    String? sourceUrl,
    String? lastStreamUrl,
    String? localSubtitlePath,
    int? lastPositionSec,
    int? durationSec,
    int? updatedAtMs,
  }) {
    return MediaItem(
      id: id ?? this.id,
      code: code ?? this.code,
      title: title ?? this.title,
      posterUrl: posterUrl ?? this.posterUrl,
      actors: actors ?? this.actors,
      tags: tags ?? this.tags,
      studio: studio ?? this.studio,
      releaseDate: releaseDate ?? this.releaseDate,
      personalRating: personalRating ?? this.personalRating,
      notes: notes ?? this.notes,
      isFavorite: isFavorite ?? this.isFavorite,
      isMetadataLocked: isMetadataLocked ?? this.isMetadataLocked,
      sourceSite: sourceSite ?? this.sourceSite,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      lastStreamUrl: lastStreamUrl ?? this.lastStreamUrl,
      localSubtitlePath: localSubtitlePath ?? this.localSubtitlePath,
      lastPositionSec: lastPositionSec ?? this.lastPositionSec,
      durationSec: durationSec ?? this.durationSec,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'code': code,
      'title': title,
      'posterUrl': posterUrl,
      'actors': jsonEncode(actors),
      'tags': jsonEncode(tags),
      'studio': studio,
      'releaseDate': releaseDate,
      'personalRating': personalRating,
      'notes': notes,
      'isFavorite': isFavorite ? 1 : 0,
      'isMetadataLocked': isMetadataLocked ? 1 : 0,
      'sourceSite': sourceSite,
      'sourceUrl': sourceUrl,
      'lastStreamUrl': lastStreamUrl,
      'localSubtitlePath': localSubtitlePath,
      'lastPositionSec': lastPositionSec,
      'durationSec': durationSec,
      'updatedAtMs': updatedAtMs,
    };
  }

  factory MediaItem.fromMap(Map<String, dynamic> map) {
    return MediaItem(
      id: map['id'] as String,
      code: (map['code'] as String?) ?? '',
      title: (map['title'] as String?) ?? '',
      posterUrl: (map['posterUrl'] as String?) ?? '',
      actors: _decodeStringList(map['actors']),
      tags: _decodeStringList(map['tags']),
      studio: (map['studio'] as String?) ?? '',
      releaseDate: (map['releaseDate'] as String?) ?? '',
      personalRating: ((map['personalRating'] as num?) ?? 0.0).toDouble(),
      notes: (map['notes'] as String?) ?? '',
      isFavorite: (map['isFavorite'] as int? ?? 0) == 1,
      isMetadataLocked: (map['isMetadataLocked'] as int? ?? 0) == 1,
      sourceSite: (map['sourceSite'] as String?) ?? 'missav',
      sourceUrl: (map['sourceUrl'] as String?) ?? '',
      lastStreamUrl: map['lastStreamUrl'] as String?,
      localSubtitlePath: map['localSubtitlePath'] as String?,
      lastPositionSec: (map['lastPositionSec'] as int?) ?? 0,
      durationSec: (map['durationSec'] as int?) ?? 0,
      updatedAtMs: (map['updatedAtMs'] as int?) ?? 0,
    );
  }

  static List<String> _decodeStringList(dynamic raw) {
    if (raw == null) return const [];
    if (raw is List) return raw.map((e) => e.toString()).toList();
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded.map((e) => e.toString()).toList();
        }
      } catch (_) {}
    }
    return const [];
  }
}
