import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/emby_theme.dart';

/// 隐私数字密码锁工具与极简无敏感字样锁屏界面
class AppLockScreen extends StatefulWidget {
  final String expectedHash;
  final VoidCallback onUnlocked;

  const AppLockScreen({
    super.key,
    required this.expectedHash,
    required this.onUnlocked,
  });

  /// 纯 Dart 加盐哈希（不存明文 PIN，零额外插件依赖）
  static String hashPin(String pin) {
    final salted = 'esv_vault_salt_v1::${pin.trim()}::2026';
    final bytes = utf8.encode(salted);
    var h1 = 0x811c9dc5;
    var h2 = 0x01000193;
    for (final b in bytes) {
      h1 ^= b;
      h1 = (h1 * 0x01000193) & 0xFFFFFFFF;
      h2 = ((h2 << 5) + h2 + b) & 0xFFFFFFFF;
    }
    return '${h1.toRadixString(16).padLeft(8, '0')}${h2.toRadixString(16).padLeft(8, '0')}';
  }

  static bool verifyPin(String pin, String expectedHash) {
    if (pin.trim().isEmpty || expectedHash.isEmpty) return false;
    return hashPin(pin) == expectedHash;
  }

  /// 弹窗设置或修改 4~6 位数字密码（返回新密码的 hash，取消则返回 null）
  static Future<String?> showSetupPinDialog(
    BuildContext context, {
    String? currentPinHash,
    String title = '设置隐私锁密码',
  }) async {
    final oldCtrl = TextEditingController();
    final pin1Ctrl = TextEditingController();
    final pin2Ctrl = TextEditingController();
    String? errorMsg;

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (currentPinHash != null && currentPinHash.isNotEmpty) ...[
                  TextField(
                    controller: oldCtrl,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    maxLength: 6,
                    decoration: const InputDecoration(
                      labelText: '当前旧密码',
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                TextField(
                  controller: pin1Ctrl,
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  maxLength: 6,
                  decoration: const InputDecoration(
                    labelText: '新密码（4~6 位数字）',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: pin2Ctrl,
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  maxLength: 6,
                  decoration: const InputDecoration(
                    labelText: '再次确认新密码',
                    counterText: '',
                  ),
                ),
                if (errorMsg != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    errorMsg!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: EmbyTheme.danger,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                if (currentPinHash != null &&
                    currentPinHash.isNotEmpty &&
                    !verifyPin(oldCtrl.text, currentPinHash)) {
                  setModalState(() => errorMsg = '旧密码不正确');
                  return;
                }
                final p1 = pin1Ctrl.text.trim();
                final p2 = pin2Ctrl.text.trim();
                if (!RegExp(r'^\d{4,6}$').hasMatch(p1)) {
                  setModalState(() => errorMsg = '请输入 4 到 6 位纯数字');
                  return;
                }
                if (p1 != p2) {
                  setModalState(() => errorMsg = '两次输入的密码不一致');
                  return;
                }
                Navigator.pop(ctx, hashPin(p1));
              },
              child: const Text('确认保存'),
            ),
          ],
        ),
      ),
    );

    oldCtrl.dispose();
    pin1Ctrl.dispose();
    pin2Ctrl.dispose();
    return result;
  }

  /// 验证旧密码对话框（用于关闭密码锁前校验）
  static Future<bool> showVerifyPinDialog(
    BuildContext context, {
    required String expectedHash,
    String title = '验证当前密码',
  }) async {
    final ctrl = TextEditingController();
    String? errorMsg;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrl,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 6,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '请输入当前密码',
                  counterText: '',
                ),
              ),
              if (errorMsg != null) ...[
                const SizedBox(height: 8),
                Text(
                  errorMsg!,
                  style: const TextStyle(fontSize: 12, color: EmbyTheme.danger),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                if (verifyPin(ctrl.text, expectedHash)) {
                  Navigator.pop(ctx, true);
                } else {
                  setModalState(() => errorMsg = '密码错误，请重试');
                }
              },
              child: const Text('验证'),
            ),
          ],
        ),
      ),
    );

    ctrl.dispose();
    return ok == true;
  }

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> {
  String _input = '';
  bool _wrong = false;

  void _pressDigit(String digit) {
    if (_input.length >= 6) return;
    HapticFeedback.selectionClick();
    final next = '$_input$digit';
    setState(() {
      _input = next;
      _wrong = false;
    });
    if (AppLockScreen.verifyPin(next, widget.expectedHash)) {
      widget.onUnlocked();
    } else if (next.length == 6) {
      HapticFeedback.heavyImpact();
      setState(() {
        _wrong = true;
        _input = '';
      });
    }
  }

  void _backspace() {
    if (_input.isEmpty) return;
    setState(() {
      _input = _input.substring(0, _input.length - 1);
      _wrong = false;
    });
  }

  void _submitManually() {
    if (_input.length < 4) return;
    if (AppLockScreen.verifyPin(_input, widget.expectedHash)) {
      widget.onUnlocked();
    } else {
      HapticFeedback.heavyImpact();
      setState(() {
        _wrong = true;
        _input = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090C12),
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 2),
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: EmbyTheme.surface,
                shape: BoxShape.circle,
                border: Border.all(
                  color: _wrong
                      ? EmbyTheme.danger
                      : EmbyTheme.accent.withValues(alpha: 0.45),
                  width: 1.5,
                ),
              ),
              child: Icon(
                _wrong ? Icons.lock_reset_rounded : Icons.lock_outline_rounded,
                size: 30,
                color: _wrong ? EmbyTheme.danger : EmbyTheme.accent,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _wrong ? '密码错误，请重新输入' : '请输入解锁密码',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: _wrong ? EmbyTheme.danger : EmbyTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 22),
            // 密码圆点指示器
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(6, (idx) {
                final filled = idx < _input.length;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  width: filled ? 14 : 11,
                  height: filled ? 14 : 11,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: filled
                        ? EmbyTheme.accent
                        : Colors.white.withValues(alpha: 0.16),
                  ),
                );
              }),
            ),
            const Spacer(),
            // 极简九宫格数字键盘
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 42),
              child: Column(
                children: [
                  _buildRow(['1', '2', '3']),
                  const SizedBox(height: 14),
                  _buildRow(['4', '5', '6']),
                  const SizedBox(height: 14),
                  _buildRow(['7', '8', '9']),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _KeyButton(
                        onTap: _submitManually,
                        child: const Icon(Icons.check_rounded,
                            color: EmbyTheme.accent, size: 26),
                      ),
                      _KeyButton(
                        onTap: () => _pressDigit('0'),
                        child: const Text(
                          '0',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      _KeyButton(
                        onTap: _backspace,
                        child: const Icon(Icons.backspace_outlined, size: 22),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Spacer(flex: 2),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(List<String> digits) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: digits
          .map(
            (d) => _KeyButton(
              onTap: () => _pressDigit(d),
              child: Text(
                d,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _KeyButton extends StatelessWidget {
  final VoidCallback onTap;
  final Widget child;

  const _KeyButton({required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(36),
      child: Container(
        width: 72,
        height: 72,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: EmbyTheme.surface,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: child,
      ),
    );
  }
}
