import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import '../models/novel_book.dart';
import '../models/site_config.dart';
import '../storage/database_helper.dart';

class NovelSyncResult {
  final bool success;
  final String message;
  final int bookCount;

  const NovelSyncResult({
    required this.success,
    required this.message,
    this.bookCount = 0,
  });
}

/// 私人小说三通道同步服务：
/// 1. 局域网 Wi-Fi 直连（从电脑端 novel_sync_server.py 秒拉最新章节）
/// 2. 坚果云 / WebDAV 云端同步（自动读取同目录下 novels_sync.json）
/// 3. 手机本地导入 .txt / .md 文件（自动按章拆目录）
class NovelSyncService {
  NovelSyncService._();
  static final NovelSyncService instance = NovelSyncService._();

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 25),
      followRedirects: true,
    ),
  );

  /// 通道 1：局域网 Wi-Fi 直连拉取
  Future<NovelSyncResult> syncFromLan(String rawServerUrl) async {
    var base = rawServerUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (base.isEmpty) {
      return const NovelSyncResult(success: false, message: '请输入电脑局域网地址');
    }
    if (!base.startsWith('http://') && !base.startsWith('https://')) {
      base = 'http://$base';
    }
    final endpoint =
        base.endsWith('/api/novels') ? base : '$base/api/novels';

    try {
      final resp = await _dio.get<String>(
        endpoint,
        options: Options(responseType: ResponseType.plain),
      );
      if (resp.statusCode != 200 || resp.data == null) {
        return NovelSyncResult(
          success: false,
          message: '局域网拉取失败（HTTP ${resp.statusCode}）',
        );
      }
      return await _saveBooksFromPayload(resp.data!, source: 'lan');
    } on DioException catch (e) {
      return NovelSyncResult(
        success: false,
        message: '无法连接电脑同步服务（请确认电脑已启动同步脚本且与手机在同一 Wi-Fi）：${e.message ?? ''}',
      );
    } catch (e) {
      return NovelSyncResult(success: false, message: '局域网同步异常：$e');
    }
  }

  /// 通道 2：坚果云 / WebDAV 云端拉取（自动推算同目录下的 novels_sync.json）
  Future<NovelSyncResult> syncFromWebDav(AppPreferences prefs) async {
    final baseSyncUrl = prefs.syncWebDavUrl.trim();
    final user = prefs.syncWebDavUser.trim();
    final pass = prefs.syncWebDavPass.trim();
    if (baseSyncUrl.isEmpty || user.isEmpty || pass.isEmpty) {
      return const NovelSyncResult(
        success: false,
        message: '请先在「设置 → 跨平台云同步」填好坚果云 WebDAV 账号与应用密码',
      );
    }

    final uri = Uri.tryParse(baseSyncUrl);
    if (uri == null) {
      return const NovelSyncResult(success: false, message: 'WebDAV 地址格式无效');
    }
    final novelUrl = uri.resolve('novels_sync.json').toString();
    final auth = 'Basic ${base64Encode(utf8.encode('$user:$pass'))}';

    try {
      final resp = await _dio.get<String>(
        novelUrl,
        options: Options(
          headers: {'Authorization': auth},
          responseType: ResponseType.plain,
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      if (resp.statusCode == 404) {
        return const NovelSyncResult(
          success: false,
          message: '坚果云尚未上传小说（请先在电脑双击「一键同步小说到坚果云.bat」）',
        );
      }
      if (resp.statusCode != 200 || resp.data == null) {
        return NovelSyncResult(
          success: false,
          message: '坚果云拉取失败（HTTP ${resp.statusCode}，请核对应用密码）',
        );
      }
      return await _saveBooksFromPayload(resp.data!, source: 'webdav');
    } on DioException catch (e) {
      return NovelSyncResult(
        success: false,
        message: '坚果云连接失败：${e.message ?? ''}',
      );
    } catch (e) {
      return NovelSyncResult(success: false, message: '云端同步异常：$e');
    }
  }

  /// 通道 3：手机本地选择 .txt / .md 文件导入并自动分章
  Future<NovelSyncResult> importLocalFile() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['txt', 'md'],
    );
    if (picked == null || picked.files.isEmpty) {
      return const NovelSyncResult(success: false, message: '已取消导入');
    }
    final file = picked.files.first;
    final path = file.path;
    if (path == null || path.isEmpty) {
      return const NovelSyncResult(success: false, message: '无法读取所选文件路径');
    }

    try {
      final bytes = await File(path).readAsBytes();
      final text = utf8.decode(bytes, allowMalformed: true);
      final baseName = file.name.replaceAll(RegExp(r'\.(txt|md)$', caseSensitive: false), '');
      final chapters = NovelBook.parseTextIntoChapters(
        text,
        fallbackTitle: baseName,
      );
      if (chapters.isEmpty) {
        return const NovelSyncResult(success: false, message: '所选文件内容为空');
      }

      final book = NovelBook(
        id: 'local_${baseName.hashCode.abs()}',
        title: baseName,
        source: 'local',
        chapters: chapters,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
      await DatabaseHelper.instance.upsertNovelBook(book);
      return NovelSyncResult(
        success: true,
        message: '已导入《$baseName》（共识别 ${chapters.length} 章 · ${book.formattedWords}）',
        bookCount: 1,
      );
    } catch (e) {
      return NovelSyncResult(success: false, message: '导入文件失败：$e');
    }
  }

  Future<NovelSyncResult> _saveBooksFromPayload(
    String rawJson, {
    required String source,
  }) async {
    final decoded = jsonDecode(rawJson);
    final rawBooks = (decoded is Map && decoded['books'] is List)
        ? decoded['books'] as List<dynamic>
        : (decoded is List ? decoded : const []);

    var savedCount = 0;
    var totalChapters = 0;
    for (final entry in rawBooks) {
      if (entry is Map) {
        final book = NovelBook.fromSyncJson(
          Map<String, dynamic>.from(entry),
          source: source,
        );
        if (book.chapters.isNotEmpty) {
          await DatabaseHelper.instance.upsertNovelBook(book);
          savedCount++;
          totalChapters += book.chapters.length;
        }
      }
    }

    if (savedCount == 0) {
      return const NovelSyncResult(success: false, message: '同步源中未找到有效小说章节');
    }
    return NovelSyncResult(
      success: true,
      message: '同步成功！已更新 $savedCount 本小说（共 $totalChapters 章，已自动保留原阅读进度）',
      bookCount: savedCount,
    );
  }
}
