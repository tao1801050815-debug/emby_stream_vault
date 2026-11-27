import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/emby_theme.dart';

/// 纯代码绘制的微缩计数图标：
/// 包茎柱身 + 包皮环形收口褶皱 + 微露半截龟头与马眼 + 喷射精液水滴
class EjaculationMiniIcon extends StatelessWidget {
  final double size;
  final bool highlighted;

  const EjaculationMiniIcon({
    super.key,
    this.size = 16,
    this.highlighted = true,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _EjaculationMiniPainter(highlighted: highlighted),
      ),
    );
  }
}

class _EjaculationMiniPainter extends CustomPainter {
  final bool highlighted;

  const _EjaculationMiniPainter({required this.highlighted});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 1. 将坐标系移到左下往右上 42° 方向绘制柱身与半露龟头
    canvas.save();
    canvas.translate(w * 0.34, h * 0.68);
    canvas.rotate(-math.pi / 4.2);

    final shaftLen = w * 0.46;
    final shaftRadius = w * 0.145;

    // 2. 微露的一点粉红龟头（在包皮口前方微微探出）
    final glansPaint = Paint()
      ..color = highlighted
          ? const Color(0xFFFF7B93)
          : const Color(0xFFD98B99)
      ..style = PaintingStyle.fill;
    final glansRect = Rect.fromCenter(
      center: Offset(shaftLen * 0.52, 0),
      width: shaftRadius * 1.65,
      height: shaftRadius * 1.72,
    );
    canvas.drawOval(glansRect, glansPaint);

    // 龟头顶端马眼细口
    final meatusPaint = Paint()
      ..color = const Color(0xFF8C2D43)
      ..strokeWidth = (w * 0.055).clamp(0.8, 2.0)
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(shaftLen * 0.52 + shaftRadius * 0.45, 0),
      Offset(shaftLen * 0.52 + shaftRadius * 0.80, 0),
      meatusPaint,
    );

    // 3. 包茎肉棒柱身（包裹住大部分龟头，仅前端开口露出一小截）
    final skinPaint = Paint()
      ..color = highlighted
          ? const Color(0xFFF3B391)
          : const Color(0xFFC49A84)
      ..style = PaintingStyle.fill;
    final shaftRRect = RRect.fromRectAndCorners(
      Rect.fromLTRB(
        -shaftLen * 0.55,
        -shaftRadius,
        shaftLen * 0.36,
        shaftRadius,
      ),
      topLeft: Radius.circular(shaftRadius),
      bottomLeft: Radius.circular(shaftRadius),
      topRight: Radius.circular(shaftRadius * 0.65),
      bottomRight: Radius.circular(shaftRadius * 0.65),
    );
    canvas.drawRRect(shaftRRect, skinPaint);

    // 包皮前端环形隆起褶皱包口（凸显包茎包裹感）
    final foreskinRimPaint = Paint()
      ..color = highlighted
          ? const Color(0xFFE59872)
          : const Color(0xFFB0846E)
      ..style = PaintingStyle.fill;
    final rimRRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(shaftLen * 0.30, 0),
        width: shaftRadius * 0.82,
        height: shaftRadius * 2.18,
      ),
      Radius.circular(shaftRadius * 0.45),
    );
    canvas.drawRRect(rimRRect, foreskinRimPaint);

    // 包皮口细微褶皱暗线
    final creasePaint = Paint()
      ..color = const Color(0xFF9E583C).withValues(alpha: 0.65)
      ..style = PaintingStyle.stroke
      ..strokeWidth = (w * 0.045).clamp(0.7, 1.6);
    canvas.drawLine(
      Offset(shaftLen * 0.22, -shaftRadius * 0.85),
      Offset(shaftLen * 0.22, shaftRadius * 0.85),
      creasePaint,
    );

    canvas.restore();

    // 4. 从马眼向外喷射出的三道乳白色精液水滴与弧线
    final dropPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final streamPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.95)
      ..style = PaintingStyle.stroke
      ..strokeWidth = (w * 0.075).clamp(1.0, 2.4)
      ..strokeCap = StrokeCap.round;

    // 主喷射弧线（右上）
    final jet1 = Path()
      ..moveTo(w * 0.63, h * 0.37)
      ..quadraticBezierTo(w * 0.76, h * 0.18, w * 0.90, h * 0.14);
    canvas.drawPath(jet1, streamPaint);
    canvas.drawCircle(Offset(w * 0.92, h * 0.14), w * 0.065, dropPaint);

    // 上方飞溅液滴
    final jet2 = Path()
      ..moveTo(w * 0.60, h * 0.33)
      ..quadraticBezierTo(w * 0.64, h * 0.14, w * 0.72, h * 0.08);
    canvas.drawPath(jet2, streamPaint..strokeWidth = (w * 0.06).clamp(0.9, 1.9));
    canvas.drawCircle(Offset(w * 0.73, h * 0.07), w * 0.052, dropPaint);

    // 右侧飞溅液滴
    canvas.drawCircle(Offset(w * 0.88, h * 0.33), w * 0.055, dropPaint);
  }

  @override
  bool shouldRepaint(covariant _EjaculationMiniPainter oldDelegate) =>
      oldDelegate.highlighted != highlighted;
}

/// 封面与详情页通用的「射过次数」交互胶囊徽章（点击可快捷 +1 / -1 / 自定义数字）
class CumCountBadge extends StatelessWidget {
  final int count;
  final ValueChanged<int> onChanged;
  final bool compact;

  const CumCountBadge({
    super.key,
    required this.count,
    required this.onChanged,
    this.compact = true,
  });

  Future<void> _openEditor(BuildContext context) async {
    var current = count;
    final ctrl = TextEditingController(text: '$count');
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          void syncVal(int next) {
            final clamped = next < 0 ? 0 : next;
            setModalState(() {
              current = clamped;
              ctrl.text = '$clamped';
              ctrl.selection = TextSelection.fromPosition(
                TextPosition(offset: ctrl.text.length),
              );
            });
          }

          return AlertDialog(
            title: const Row(
              children: [
                EjaculationMiniIcon(size: 22),
                SizedBox(width: 8),
                Text('记录射过次数'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton.filledTonal(
                      onPressed: () => syncVal(current - 1),
                      icon: const Icon(Icons.remove_rounded),
                    ),
                    const SizedBox(width: 14),
                    SizedBox(
                      width: 92,
                      child: TextField(
                        controller: ctrl,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                        decoration: const InputDecoration(
                          labelText: '次数',
                          isDense: true,
                        ),
                        onChanged: (v) {
                          final parsed = int.tryParse(v.trim());
                          if (parsed != null && parsed >= 0) {
                            current = parsed;
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 14),
                    IconButton.filled(
                      style: IconButton.styleFrom(
                        backgroundColor: EmbyTheme.accent,
                        foregroundColor: Colors.black,
                      ),
                      onPressed: () => syncVal(current + 1),
                      icon: const Icon(Icons.add_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    ActionChip(
                      label: const Text('直接 +1 并保存'),
                      onPressed: () => Navigator.pop(ctx, count + 1),
                    ),
                    ActionChip(
                      label: const Text('归零'),
                      onPressed: () => syncVal(0),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  final parsed = int.tryParse(ctrl.text.trim()) ?? current;
                  Navigator.pop(ctx, parsed < 0 ? 0 : parsed);
                },
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );
    ctrl.dispose();
    if (result != null && result != count) {
      onChanged(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openEditor(context),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 6 : 9,
          vertical: compact ? 3 : 5,
        ),
        decoration: BoxDecoration(
          color: count > 0
              ? const Color(0xDD1A1025)
              : Colors.black.withValues(alpha: 0.68),
          borderRadius: BorderRadius.circular(compact ? 7 : 9),
          border: Border.all(
            color: count > 0
                ? const Color(0xFFFF7B93).withValues(alpha: 0.75)
                : Colors.white.withValues(alpha: 0.18),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            EjaculationMiniIcon(
              size: compact ? 14 : 18,
              highlighted: count > 0,
            ),
            const SizedBox(width: 4),
            Text(
              '$count',
              style: TextStyle(
                fontSize: compact ? 11 : 13,
                fontWeight: FontWeight.w800,
                color: count > 0 ? Colors.white : EmbyTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
