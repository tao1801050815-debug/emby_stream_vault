import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/app_providers.dart';
import '../../core/services/app_update_service.dart';
import '../browser/webview_sniffer_page.dart';
import '../downloads/downloads_page.dart';
import '../library/library_home_page.dart';
import '../settings/settings_page.dart';

/// 主界面导航壳（影库 / 嗅探浏览器 / 离线缓存 / 设置）
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _index = 0;
  bool _checkedUpdateOnLaunch = false;

  static const _pages = [
    LibraryHomePage(),
    WebViewSnifferPage(),
    DownloadsPage(),
    SettingsPage(),
  ];

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(seconds: 2), _checkUpdateSilently);
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
    return Scaffold(
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
  }
}
