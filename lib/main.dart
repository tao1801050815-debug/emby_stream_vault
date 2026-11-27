import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'core/theme/emby_theme.dart';
import 'features/shell/app_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const ProviderScope(child: EmbyStreamVaultApp()));
}

class EmbyStreamVaultApp extends StatelessWidget {
  const EmbyStreamVaultApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EmbyStreamVault',
      debugShowCheckedModeBanner: false,
      theme: EmbyTheme.darkTheme(),
      home: const AppShell(),
    );
  }
}
