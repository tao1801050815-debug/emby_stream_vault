import 'dart:convert';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/bookmark.dart';
import '../models/download_task.dart';
import '../models/media_item.dart';
import '../models/novel_book.dart';

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
      version: 5,
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
            publicRating REAL DEFAULT 0.0,
            publicRatingSource TEXT DEFAULT '',
            cumCount INTEGER DEFAULT 0,
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
        await _createNovelBooksTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createBookmarksTable(db);
        }
        if (oldVersion < 3) {
          await db.execute(
            'ALTER TABLE media_items ADD COLUMN publicRating REAL DEFAULT 0.0',
          );
          await db.execute(
            "ALTER TABLE media_items ADD COLUMN publicRatingSource TEXT DEFAULT ''",
          );
        }
        if (oldVersion < 4) {
          await db.execute(
            'ALTER TABLE media_items ADD COLUMN cumCount INTEGER DEFAULT 0',
          );
        }
        if (oldVersion < 5) {
          await _createNovelBooksTable(db);
        }
      },
    );
  }

  Future<void> _createNovelBooksTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS novel_books (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        author TEXT,
        summary TEXT,
        source TEXT,
        chaptersJson TEXT NOT NULL,
        lastChapterIndex INTEGER DEFAULT 0,
        lastScrollOffset REAL DEFAULT 0.0,
        updatedAtMs INTEGER NOT NULL
      )
    ''');
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
    if (existing != null) {
      if (existing.isMetadataLocked && !item.isMetadataLocked) {
        // 如果原记录已被用户手动纠错锁定，仅更新流地址、观看进度与新增标签
        final mergedTags = {
          ...existing.tags,
          ...item.tags,
        }.toList();
        final merged = existing.copyWith(
          tags: mergedTags,
          lastStreamUrl: item.lastStreamUrl ?? existing.lastStreamUrl,
          publicRating: item.publicRating > 0
              ? item.publicRating
              : existing.publicRating,
          publicRatingSource: item.publicRatingSource.isNotEmpty
              ? item.publicRatingSource
              : existing.publicRatingSource,
          cumCount: item.cumCount > 0 ? item.cumCount : existing.cumCount,
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

      // 未锁定时，若重新嗅探收藏同一部影片，也保留用户已有的评分、次数、笔记与已抓到的标签
      final merged = item.copyWith(
        tags: {...existing.tags, ...item.tags}.toList(),
        actors: item.actors.isNotEmpty ? item.actors : existing.actors,
        posterUrl:
            item.posterUrl.isNotEmpty ? item.posterUrl : existing.posterUrl,
        personalRating: item.personalRating > 0
            ? item.personalRating
            : existing.personalRating,
        publicRating:
            item.publicRating > 0 ? item.publicRating : existing.publicRating,
        publicRatingSource: item.publicRatingSource.isNotEmpty
            ? item.publicRatingSource
            : existing.publicRatingSource,
        cumCount: item.cumCount != existing.cumCount && item.cumCount > 0
            ? item.cumCount
            : existing.cumCount,
        notes: item.notes.isNotEmpty ? item.notes : existing.notes,
        lastStreamUrl: item.lastStreamUrl ?? existing.lastStreamUrl,
        lastPositionSec: item.lastPositionSec > 0
            ? item.lastPositionSec
            : existing.lastPositionSec,
        durationSec:
            item.durationSec > 0 ? item.durationSec : existing.durationSec,
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
      'rating' => 'personalRating DESC, publicRating DESC, updatedAtMs DESC',
      'publicRating' => 'publicRating DESC, personalRating DESC, updatedAtMs DESC',
      'cumCount' => 'cumCount DESC, updatedAtMs DESC',
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

  Future<void> deleteMediaItemsBatch(Iterable<String> ids) async {
    final db = await database;
    final batch = db.batch();
    for (final id in ids) {
      batch.delete('media_items', where: 'id = ?', whereArgs: [id]);
    }
    await batch.commit(noResult: true);
  }

  Future<void> updatePublicRating({
    required String id,
    required double rating,
    required String source,
  }) async {
    final db = await database;
    await db.update(
      'media_items',
      {
        'publicRating': rating,
        'publicRatingSource': source,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateCumCount({
    required String id,
    required int cumCount,
  }) async {
    final db = await database;
    await db.update(
      'media_items',
      {
        'cumCount': cumCount < 0 ? 0 : cumCount,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateTagsAndActors({
    required String id,
    required List<String> tags,
    required List<String> actors,
  }) async {
    final existing = await getMediaItemById(id);
    if (existing == null) return;
    final mergedTags = {...existing.tags, ...tags}.toList();
    final mergedActors = existing.actors.isNotEmpty ? existing.actors : actors;
    final db = await database;
    await db.update(
      'media_items',
      {
        'tags': jsonEncode(mergedTags),
        'actors': jsonEncode(mergedActors),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
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

  // ---- NovelBook CRUD ----

  Future<void> upsertNovelBook(NovelBook book) async {
    final db = await database;
    final existing = await getNovelBookById(book.id);
    final merged = existing == null
        ? book
        : book.copyWith(
            lastChapterIndex: existing.lastChapterIndex
                .clamp(0, (book.chapters.length - 1).clamp(0, 999999)),
            lastScrollOffset: existing.lastScrollOffset,
          );
    await db.insert(
      'novel_books',
      merged.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<NovelBook?> getNovelBookById(String id) async {
    final db = await database;
    final rows =
        await db.query('novel_books', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return NovelBook.fromMap(rows.first);
  }

  Future<List<NovelBook>> getAllNovelBooks() async {
    final db = await database;
    final rows = await db.query('novel_books', orderBy: 'updatedAtMs DESC');
    return rows.map(NovelBook.fromMap).toList();
  }

  Future<void> updateNovelProgress({
    required String id,
    required int chapterIndex,
    required double scrollOffset,
  }) async {
    final db = await database;
    await db.update(
      'novel_books',
      {
        'lastChapterIndex': chapterIndex,
        'lastScrollOffset': scrollOffset,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteNovelBook(String id) async {
    final db = await database;
    await db.delete('novel_books', where: 'id = ?', whereArgs: [id]);
  }
}
