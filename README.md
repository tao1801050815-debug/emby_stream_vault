# EmbyStreamVault (`v1.1.02`)

跨平台（iOS / iPadOS / Android）私人 Emby 风格媒体库、私人小说书架、片源嗅探浏览器、增强原生播放器与纯手机端 AI 实时中文字幕应用（基于 Flutter 构建）。

---

## 核心功能一览

### 1. 双风格分页私人影库（`lib/features/library/`）
- **双布局一键切换**：
  - **Pornhub 单列宽卡模式**：`16:9` 全宽高清大横卡，展示完整双行大标题、来源站点、女优及标签胶囊。
  - **MissAV 双列并排模式**：两部片横向封面紧凑并排，完整保留横版封面比例。
- **严格分页浏览**：每页固定 **8 部影片**，底部常驻页码分页条，翻页自动平滑回顶。
- **封面四象限信息徽章**：
  - 左上角：番号徽章 + **无码版本**高亮角标；
  - 右上角：**网上评分（JavDB 自动抓取）** + **个人 1~5 星评分**；
  - 右下角：纯代码绘制专属微缩计数图标 + **自定义计数**（点击即可快捷 `+1` / `-1` / 归零 / 手动输入任意次数）。
- **三合一标签筛选与专题汇总**：
  - 首页常驻「标签筛选」弹窗，自动汇总全库的**来源网站标签**（`MISSAV`、`HANIME1`、`PORNHUB` 等）、**女优/演员标签**与**影片内容标签**（如 `中出`、`后宫`、`无码流出`），支持弹窗内搜标签及多条件组合筛选。
  - 在影片详情页点击任意**女优名字、标签或来源徽章**，可直接进入该女优/标签的专属作品汇总页（`tag_collection_page.dart`）无限连跳探索。
- **多维排序与管理**：支持按最近收藏、次数最多、个人高分、网上高分、番号排序，支持长按快捷操作、批量多选删除与元数据纠错锁定。
- **自定义网址添加收藏**：输入或粘贴任意视频网址，一键自动提取影片名称、高清封面（实时预览）、番号、来源与页面标签，所有字段均可自由修改。
- **免登录网页书签夹**：对无需登录的站点一键收藏网页直达。

### 2. 内置嗅探浏览器与精准选片（`lib/features/browser/`）
- **共享持久化 Cookie**：支持直接登录 MissAV / JavDB 等站点账号并手动通过 Cloudflare 验证。
- **可视化识别选片弹窗**：点击收藏时自动汇总当前正片与页面内识别到的全部影片（带封面、番号、标题与标签），支持弹窗内搜索定位、勾选单部或多部精准入库。
- **MissAV 标签与版本隔离**：自动抓取页面自带标签（如中出、巨乳、无码流出、中文字幕等）；普通版与无码版独立隔离存储，原生播放精准锁定用户收藏版本的高画质流。
- **可自由拖动与折叠的嗅探悬浮条**：支持全屏拖动或一键收起为迷你悬浮球，避免遮挡网页登录按钮。
- **自由添加片源网站**：预置 MissAV、JavDB、Jable、Pornhub、xHamster、Hanime1、MoTV、糖心Vlog、Active1 (`active1.didktiekw.cc`)，并可在浏览器顶部或设置页随时增删改任意站点。

### 3. 增强型原生播放器 & 纯手机端 AI 实时中文字幕（`lib/features/player/`）
- 基于 `media_kit` (`libmpv`) 内核，自动携带 `Referer` 与 `Cookie` 播放流媒体。
- 支持 **断点续播**、**双击快进/快退**、**长按 2.0x 临时倍速**、**单手模式**、**画面锐化**、**本地外挂字幕与时间轴偏移（`sub-delay`）**。
- **纯手机端 AI 实时中文字幕**（`lib/core/services/live_ai_subtitle_service.dart`）：
  - 无需电脑中转，直接按播放进度拉取最低码率音频分片送入云端语音识别（内置 **Groq 免费极速** / **硅基流动国内直连** / **OpenAI** 一键预设）并实时翻译为简体中文双语字幕；
  - 已识别字幕按影片自动持久化到本地 JSON（仅数十 KB），下次打开同一部片自动秒现并跳过已识别片段；
  - 支持单部影片删除字幕缓存、删片联动清理及设置页查看占用空间与一键清空。

### 4. 自动抓取网上评分（`lib/core/services/rating_fetcher_service.dart`）
- 收藏标准番号（支持漏写横杠如 `mimk134` 自动标准化为 `MIMK-134`）后自动从 JavDB 逐卡片精准匹配对应番号的评分；
- 自动携带 `over18=1; locale=zh` 并共享 WebView Cookie，支持启动自动补齐老收藏评分与主页一键刷新当前页网评。

### 5. 跨平台云同步与离线备份（`lib/core/services/cloud_sync_service.dart`）
- 同步内容覆盖：**全部收藏影片、自定义计数、个人/网上评分、标签、笔记、观看进度、网页书签与自定义站点**。
- 支持 3 种跨设备同步方式（iPhone / iPad / Android 全通用）：
  1. **GitHub 私有 Gist（推荐）**：生成一个仅含 `gist` 权限的 Token，多台设备填同一个 Token 自动认领私密同步文件，支持双向智能合并（按最新时间择新 + 标签取并集）或以本机为准覆盖云端。
  2. **WebDAV 云同步**：原生支持坚果云（国内直连免费）、Alist 与自建 NAS。
  3. **离线剪贴板 JSON**：无需任何账号，一键导出/导入合并。

### 6. 私人小说书架与沉浸式阅读器（`lib/features/novels/`）
- **三通道追更同步**：
  1. **局域网 Wi-Fi 直连**：配合电脑端 `启动小说局域网同步服务.bat`，自动按章排序扫描写作目录并秒速拉取到手机；
  2. **坚果云 / WebDAV 云端同步**：配合 `一键同步小说到坚果云.bat`，出门在外随时追更；
  3. **本地 TXT / MD 文件导入**：自动识别 `第XXX章` / `# 标题` 拆分成完整章节目录。
- **沉浸式护眼阅读**：支持深黑夜读 / 羊皮纸 / 豆沙绿 3 套配色、字号与行距调节、目录跳章，同步更新新章节时**自动保留原阅读进度**。

### 7. 隐私安全锁（`lib/features/shell/app_lock_screen.dart`）
- **4~6 位数字密码锁**（加盐哈希存储，不存明文），锁屏界面极简无敏感字样；
- **切后台自动上锁 + 多任务防窥遮罩**：上滑切后台卡片或锁屏时自动隐藏真实画面，返回需重新解锁。

### 8. m3u8 离线缓存引擎（`lib/core/services/m3u8_downloader_service.dart`）
- 自动解析 Master Playlist（优先最高码率）并并发下载分片至本地，生成本地 `local.m3u8` 离线播放。

---

## GitHub Actions 云端自动编译 & 全能签软件源一键更新

本项目已配置完整的 GitHub Actions 云端构建与发布工作流（`.github/workflows/build.yml`），无需 Mac 即可同时产出未签名 iOS `.ipa`、Android `.apk` 和标准软件源 `apps.json`。

### 自动版本发布、真实 UI 预览图与 Release
每次向 `main` 分支推送代码后，Actions 会自动执行：
1. `analyze_and_test`：运行 `flutter analyze --no-fatal-infos`、`flutter test test/models_test.dart`，并自动渲染 **4 张真实 iPhone 比例高清 UI 预览图**（MissAV 双列主页、Pornhub 单列大卡、三合一标签筛选面板、详情页）；
2. `build_android` & `build_ios_unsigned`：打包双端安装包（当前版本 `v1.1.02`，`buildNumber` 自动递增）；
3. `publish_release`：自动汇总最近 5 条更新说明生成标准软件源 `apps.json`，将双端安装包与 **4 张真实界面截图** 一并发布到 GitHub Release `latest`（安装前可直接看图验收）。

### 全能签 / 轻松签 / AltStore 一键更新配置
1. 确保仓库为 **Public**（仅包含 App 源码，你的登录状态、影库收藏与 API Key 均只存在手机本地）。
2. 在手机 **全能签 → 软件源 → 添加源** 中粘贴以下固定地址：
   ```text
   https://github.com/tao1801050815-debug/emby_stream_vault/releases/download/latest/apps.json
   ```
3. 以后每次推送新功能并构建完成后：
   - 打开 App 会自动弹窗提示**发现新版本与更新日志**；
   - 切到全能签刷新软件源并点击「更新」，即可自动下载、重签并原地覆盖安装，所有本地数据完整保留。

---

## 目录结构

```text
lib/
├── main.dart
├── core/
│   ├── models/          # MediaItem / SiteProfile / AppPreferences / BookmarkItem / DownloadTask
│   ├── providers/       # Riverpod 全局状态管理
│   ├── services/        # 评分抓取 / AI 实时字幕 / 网页元数据提取 / 云同步 / 更新检测 / m3u8 下载
│   ├── storage/         # SQLite (v5 无损迁移) & SharedPreferences 持久化
│   ├── theme/           # Emby 深色主题配色
│   └── widgets/         # 自定义矢量计数微缩图标与交互徽章
└── features/
    ├── shell/           # 底部导航壳、隐私密码锁与启动自动更新检测
    ├── library/         # Pornhub/MissAV 双布局分页主页、毛玻璃详情页 & 女优/标签作品汇总页
    ├── novels/          # 私人小说书架与沉浸式护眼阅读器
    ├── browser/         # 内置嗅探浏览器、可拖动悬浮条与选片弹窗
    ├── player/          # libmpv 增强播放器与双语实时字幕浮层
    ├── downloads/       # 离线缓存任务管理页
    └── settings/        # 站点管理、AI 字幕、跨平台云同步与更新设置页
```
