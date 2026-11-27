# EmbyStreamVault

跨平台（iOS / iPadOS / Android）私人 Emby 风格媒体库与增强流媒体播放器（Flutter）。

## 核心功能

1. **Emby 风格私人海报墙（`lib/features/library/`）**
   - 深色毛玻璃主题，支持手机竖屏 2 列与平板横屏 4~5 列自适应布局
   - 本地 SQLite 数据库存储个人收藏、1~5 星评分、个人备注、断点续播进度
   - **元数据手动纠错与锁定**：修改标题/演员/标签/片商后自动锁定，防止被外部数据覆盖
   - **多站点一键搜索跳转**：详情页一键跳至 MissAV / JavDB / Jable 搜索对应番号

2. **内置嗅探浏览器与账号登录（`lib/features/browser/`）**
   - 共享持久化 Cookie，支持直接登录 **MissAV / JavDB** 账号并手动过 Cloudflare 验证
   - 自动监听页面 `.m3u8` / `.mp4` 视频流与 `.vtt` / `.srt` 字幕链接，并隐藏常见浮层广告
   - 捕获视频流后一键 **原生播放**、**加入私人影库** 或 **离线缓存**

3. **增强型原生播放器（`lib/features/player/`）**
   - 基于 `media_kit` (`libmpv`) 内核，支持携带 `Referer` 与 `Cookie` 播放流媒体
   - 支持 **断点续播**、**双击左右半屏快进/快退**、**长按 2.0x 临时倍速**、**单手控制栏模式**
   - 支持 **加载本地外挂字幕** 及 **字幕时间轴偏移微调（`sub-delay`）**
   - 支持 **画面锐化增强（`sharpen`）**

4. **m3u8 离线缓存引擎（`lib/core/services/m3u8_downloader_service.dart`）**
   - 自动解析 Master Playlist（挑选最高码率）并并发下载分片至本地，生成本地 `local.m3u8` 离线播放

5. **自定义站点域名（`lib/features/settings/`）**
   - 所有站点域名与登录页地址支持在 App 内热修改，无惧域名更换

---

## 如何在没有 Mac 的情况下打包 iOS `.ipa` 和 Android `.apk`

本项目已配置 GitHub Actions 云端自动编译流程（`.github/workflows/build.yml`）：

1. 在 GitHub 创建一个新仓库（可设为 Private 私有仓库），将本目录推送上去：
   ```bash
   git init
   git add .
   git commit -m "feat: initial EmbyStreamVault app"
   git branch -M main
   git remote add origin https://github.com/<你的用户名>/<仓库名>.git
   git push -u origin main
   ```
2. 打开 GitHub 仓库的 **Actions** 标签页，等待工作流跑完（约 5~8 分钟）。
3. 在构建产物（Artifacts）中直接下载：
   - `EmbyStreamVault-iOS-Unsigned-IPA`（未签名 `.ipa`，用你自己的签名方式签完装进 iPhone/iPad）
   - `EmbyStreamVault-Android-APK`（安卓 `.apk`）
