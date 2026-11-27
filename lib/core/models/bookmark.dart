/// 本地网页书签收藏条目（用于没有账号登录功能的网站）
class BookmarkItem {
  final String id;
  final String title;
  final String url;
  final String siteKey;
  final String folder;
  final String notes;
  final int createdAtMs;

  const BookmarkItem({
    required this.id,
    required this.title,
    required this.url,
    this.siteKey = 'missav',
    this.folder = '默认收藏',
    this.notes = '',
    required this.createdAtMs,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'url': url,
        'siteKey': siteKey,
        'folder': folder,
        'notes': notes,
        'createdAtMs': createdAtMs,
      };

  factory BookmarkItem.fromMap(Map<String, dynamic> map) => BookmarkItem(
        id: map['id'] as String,
        title: (map['title'] as String?) ?? '',
        url: (map['url'] as String?) ?? '',
        siteKey: (map['siteKey'] as String?) ?? 'missav',
        folder: (map['folder'] as String?) ?? '默认收藏',
        notes: (map['notes'] as String?) ?? '',
        createdAtMs: (map['createdAtMs'] as int?) ?? 0,
      );
}
