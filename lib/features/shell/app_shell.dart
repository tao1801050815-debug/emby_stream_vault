import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/app_providers.dart';
import '../../core/services/app_update_service.dart';
import '../browser/webview_sniffer_page.dart';
import '../downloads/downloads_page.dart';
import '../library/library_home_page.dart';
import '../novels/novel_shelf_page.dart';
import '../settings/settings_page.dart';
import 'app_lock_screen.dart';

/// 主界面导航壳（影库 / 书架 / 嗅探浏览器 / 离线缓存 / 设置 + 隐私密码锁与后台防窥遮罩）
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with WidgetsBindingObserver {
  int _index = 0;
  bool _checkedUpdateOnLaunch = false;
  bool _unlockedThisSession = false;
  bool _inPrivacyCurtain = false;

  static const _pages = [
    LibraryHomePage(),
    NovelShelfPage(),
    WebViewSnifferPage(),
    DownloadsPage(),
    SettingsPage(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future<void>.delayed(const Duration(seconds: 2), _checkUpdateSilently);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final prefs = ref.read(appPreferencesProvider);
    final lockActive =
        prefs.appLockEnabled && prefs.appLockPinHash.isNotEmpty;
    if (!lockActive) return;

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      setState(() {
        _inPrivacyCurtain = true;
        if (prefs.lockOnBackground && state == AppLifecycleState.paused) {
          _unlockedThisSession = false;
        }
      });
    } else if (state == AppLifecycleState.resumed) {
      setState(() {
        _inPrivacyCurtain = false;
      });
    }
  }

  Future<void> _checkUpdateSilently() async {
    if (_checkedUpdateOnLaunch || !mounted) return;
    _checkedUpdateOnLaunch = true;
    final prefs = ref.read(appPreferencesProvider);
    if (!prefs.autoCheckUpdate) return;
    final res = await AppUpdateService.checkForUpdate(
      feedUrl: prefs.updateFeedUrl,
    );
    if (!mounted) return;
    if (res.hasUpdate && res.release != null) {
      await AppUpdateService.showUpdateDialog(
        context,
        release: res.release!,
        feedUrl: prefs.updateFeedUrl,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(appPreferencesProvider);
    final lockActive =
        prefs.appLockEnabled && prefs.appLockPinHash.isNotEmpty;
    final needUnlock = lockActive && !_unlockedThisSession;

    final mainScaffold = Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.movie_filter_outlined),
            selectedIcon: Icon(Icons.movie_filter_rounded),
            label: '私人影库',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_stories_outlined),
            selectedIcon: Icon(Icons.auto_stories_rounded),
            label: '私人书架',
          ),
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore_rounded),
            label: '嗅探浏览',
          ),
          NavigationDestination(
            icon: Icon(Icons.download_outlined),
            selectedIcon: Icon(Icons.download_rounded),
            label: '离线缓存',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune_rounded),
            label: '设置',
          ),
        ],
      ),
    );

    return Stack(
      children: [
        mainScaffold,
        if (needUnlock)
          Positioned.fill(
            child: AppLockScreen(
              expectedHash: prefs.appLockPinHash,
              onUnlocked: () => setState(() => _unlockedThisSession = true),
            ),
          )
        else if (_inPrivacyCurtain)
          const Positioned.fill(
            child: ColoredBox(
              color: Color(0xFF090C12),
              child: Center(
                child: Icon(
                  Icons.lock_outline_rounded,
                  size: 42,
                  color: Colors.white24,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
