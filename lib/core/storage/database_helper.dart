import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/bookmark.dart';
import '../models/download_task.dart';
import '../models/media_item.dart';

/// 本地 SQLite 数据库管理（私人媒体库 + 离线缓存任务）
class DatabaseHelper {
  DatabaseHelper._();
  static final DatabaseHelper instance = DatabaseHelper._();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'emby_stream_vault.db');
    return openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE media_items (
            id TEXT PRIMARY KEY,
            code TEXT NOT NULL,
            title TEXT NOT NULL,
            posterUrl TEXT,
            actors TEXT,
            tags TEXT,
            studio TEXT,
            releaseDate TEXT,
            personalRating REAL DEFAULT 0.0,
            notes TEXT,
            isFavorite INTEGER DEFAULT 0,
            isMetadataLocked INTEGER DEFAULT 0,
            sourceSite TEXT,
            sourceUrl TEXT,
            lastStreamUrl TEXT,
            localSubtitlePath TEXT,
            lastPositionSec INTEGER DEFAULT 0,
            durationSec INTEGER DEFAULT 0,
            updatedAtMs INTEGER NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE download_tasks (
            id TEXT PRIMARY KEY,
            code TEXT NOT NULL,
            title TEXT NOT NULL,
            posterUrl TEXT,
            streamUrl TEXT NOT NULL,
            referer TEXT,
            cookieHeader TEXT,
            totalSegments INTEGER DEFAULT 0,
            downloadedSegments INTEGER DEFAULT 0,
            status TEXT NOT NULL,
            localDir TEXT NOT NULL,
            localPlaylistPath TEXT,
            errorMessage TEXT,
            createdAtMs INTEGER NOT NULL
          )
        ''');

        await _createBookmarksTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createBookmarksTable(db);
        }
      },
    );
  }

  Future<void> _createBookmarksTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS bookmarks (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        url TEXT NOT NULL,
        siteKey TEXT,
        folder TEXT,
        notes TEXT,
        createdAtMs INTEGER NOT NULL
      )
    ''');
  }

  // ---- MediaItem CRUD ----

  Future<void> upsertMediaItem(MediaItem item) async {
    final db = await database;
    final existing = await getMediaItemById(item.id);
    if (existing != null && existing.isMetadataLocked && !item.isMetadataLocked) {
      // 如果原记录已被用户手动纠错锁定，仅更新流地址与观看进度，保留手动修正的元数据
      final merged = existing.copyWith(
        lastStreamUrl: item.lastStreamUrl ?? existing.lastStreamUrl,
        lastPositionSec: item.lastPositionSec > 0
            ? item.lastPositionSec
            : existing.lastPositionSec,
        durationSec:
            item.durationSec > 0 ? item.durationSec : existing.durationSec,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
      await db.insert(
        'media_items',
        merged.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return;
    }

    await db.insert(
      'media_items',
      item.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<MediaItem?> getMediaItemById(String id) async {
    final db = await database;
    final rows =
        await db.query('media_items', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return MediaItem.fromMap(rows.first);
  }

  Future<List<MediaItem>> getAllMediaItems({
    bool onlyFavorites = false,
    String? searchQuery,
    double minRating = 0.0,
    String sortBy = 'updatedAtMs',
  }) async {
    final db = await database;
    final whereClauses = <String>[];
    final whereArgs = <Object?>[];

    if (onlyFavorites) {
      whereClauses.add('isFavorite = 1');
    }
    if (minRating > 0) {
      whereClauses.add('personalRating >= ?');
      whereArgs.add(minRating);
    }
    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final q = '%${searchQuery.trim()}%';
      whereClauses.add(
        '(code LIKE ? OR title LIKE ? OR actors LIKE ? OR tags LIKE ? OR notes LIKE ?)',
      );
      whereArgs.addAll([q, q, q, q, q]);
    }

    final orderClause = switch (sortBy) {
      'rating' => 'personalRating DESC, updatedAtMs DESC',
      'code' => 'code ASC',
      _ => 'updatedAtMs DESC',
    };

    final rows = await db.query(
      'media_items',
      where: whereClauses.isEmpty ? null : whereClauses.join(' AND '),
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: orderClause,
    );
    return rows.map(MediaItem.fromMap).toList();
  }

  Future<void> updateWatchProgress({
    required String id,
    required int positionSec,
    required int durationSec,
  }) async {
    final db = await database;
    await db.update(
      'media_items',
      {
        'lastPositionSec': positionSec,
        'durationSec': durationSec,
        'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteMediaItem(String id) async {
    final db = await database;
    await db.delete('media_items', where: 'id = ?', whereArgs: [id]);
  }

  // ---- DownloadTask CRUD ----

  Future<void> upsertDownloadTask(DownloadTask task) async {
    final db = await database;
    await db.insert(
      'download_tasks',
      task.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<DownloadTask>> getAllDownloadTasks() async {
    final db = await database;
    final rows =
        await db.query('download_tasks', orderBy: 'createdAtMs DESC');
    return rows.map(DownloadTask.fromMap).toList();
  }

  Future<void> deleteDownloadTask(String id) async {
    final db = await database;
    await db.delete('download_tasks', where: 'id = ?', whereArgs: [id]);
  }

  // ---- BookmarkItem CRUD ----

  Future<void> upsertBookmark(BookmarkItem item) async {
    final db = await database;
    await db.insert(
      'bookmarks',
      item.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<BookmarkItem>> getBookmarks({String folder = ''}) async {
    final db = await database;
    final hasFolder = folder.isNotEmpty && folder != '全部';
    final rows = await db.query(
      'bookmarks',
      where: hasFolder ? 'folder = ?' : null,
      whereArgs: hasFolder ? [folder] : null,
      orderBy: 'createdAtMs DESC',
    );
    return rows.map(BookmarkItem.fromMap).toList();
  }

  Future<void> deleteBookmark(String id) async {
    final db = await database;
    await db.delete('bookmarks', where: 'id = ?', whereArgs: [id]);
  }
}
