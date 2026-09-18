import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_palette.dart';

// The same warm resin, cream trim and soft accent as PawGachaPainter.
const pawToyCream = Color(0xFFFFF8EB);
const pawToyTrim = Color(0xFFEAD4B5);

class PawToyCard extends StatelessWidget {
  const PawToyCard({super.key, required this.child, this.padding = const EdgeInsets.all(24)});
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Colors.white, Color.lerp(pawToyCream, p.accentSoft, .22)!]),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(color: pawToyTrim.withValues(alpha: .65), offset: const Offset(0, 5)),
          BoxShadow(color: p.accentInk.withValues(alpha: .10), blurRadius: 28, offset: const Offset(0, 14)),
        ],
      ),
      child: child,
    );
  }
}

class PawToyButton extends StatelessWidget {
  const PawToyButton({super.key, required this.label, required this.onPressed, this.icon = Icons.pets_rounded});
  final String label;
  final VoidCallback? onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final color = Color.lerp(p.accent, pawToyCream, .22)!;
    final ink = ThemeData.estimateBrightnessForColor(color) == Brightness.dark ? Colors.white : p.ink;
    return Container(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), boxShadow: [
        BoxShadow(color: p.accentInk.withValues(alpha: .24), offset: const Offset(0, 4)),
      ]),
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 19),
        label: Text(label, textAlign: TextAlign.center),
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(double.infinity, 54),
          backgroundColor: color, foregroundColor: ink, elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          side: const BorderSide(color: Colors.white, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
      ),
    );
  }
}

/// A small native 2.5D scene. No timers, network images or extra packages.
/// The pet stays in the user's existing illustration style inside the capsule.
class PawCapsuleStage extends StatelessWidget {
  const PawCapsuleStage({super.key, this.imagePath, this.fallbackIcon = Icons.pets_rounded,
    this.open = true, this.progress = 1});
  final String? imagePath;
  final IconData fallbackIcon;
  final bool open;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return ExcludeSemantics(child: RepaintBoundary(child: AspectRatio(
      aspectRatio: 1.4,
      child: LayoutBuilder(builder: (context, box) {
        final petSize = box.maxHeight * .55;
        return Stack(alignment: Alignment.center, children: [
          Positioned.fill(child: CustomPaint(painter: _CapsulePainter(p, open, progress))),
          if (open)
            Transform.translate(offset: Offset(0, box.maxHeight * (-.08 + (1 - progress) * .13)),
              child: Opacity(opacity: progress.clamp(0.0, 1.0).toDouble(),
                child: SizedBox(width: petSize, height: petSize,
                  child: imagePath == null
                    ? Icon(fallbackIcon, size: petSize * .62, color: p.accentInk)
                    : Image.asset(imagePath!, fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Icon(fallbackIcon, size: petSize * .62, color: p.accentInk)),
                ),
              ),
            ),
        ]);
      }),
    )));
  }
}

class _CapsulePainter extends CustomPainter {
  const _CapsulePainter(this.palette, this.open, this.progress);
  final AppPalette palette;
  final bool open;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 320, size.height / 230);
    final rose = Color.lerp(palette.accent, pawToyCream, .22)!;
    final shadow = palette.accentInk.withValues(alpha: .14);
    final paint = Paint()..isAntiAlias = true;
    const glow = Rect.fromLTWH(54, 5, 212, 212);
    canvas.drawOval(glow, paint..shader = RadialGradient(colors: [Colors.white,
      palette.accentSoft.withValues(alpha: .85), palette.accentSoft.withValues(alpha: 0)]).createShader(glow));
    paint.shader = null;
    canvas.drawOval(const Rect.fromLTWH(53, 193, 214, 23), paint..color = shadow
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    paint.maskFilter = null;
    // Low cream pedestal, like the base of the gacha machine.
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(58, 177, 204, 29), const Radius.circular(15)),
      paint..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [pawToyCream, pawToyTrim]).createShader(const Rect.fromLTWH(58, 177, 204, 29)));
    paint.shader = null;
    canvas.drawOval(const Rect.fromLTWH(58, 163, 204, 35), paint..color = pawToyCream);
    canvas.drawOval(const Rect.fromLTWH(88, 173, 144, 19), paint..color = shadow);

    final lift = open ? 49.0 * progress : 0.0;
    canvas.save();
    canvas.translate(open ? 23 * progress : 0, -lift);
    // Cat ears carry over the silhouette of the original machine.
    for (final left in [true, false]) {
      final x = left ? 99.0 : 193.0;
      final ear = Path()..moveTo(x, 78)..quadraticBezierTo(x - 3, 28, x + 13, 42)
        ..lineTo(x + 35, 76)..close();
      canvas.drawPath(ear, paint..color = rose);
      final inner = Path()..moveTo(x + 9, 65)..lineTo(x + 11, 48)..lineTo(x + 24, 66)..close();
      canvas.drawPath(inner, paint..color = pawToyCream);
    }
    final top = Path()..moveTo(89, 118)..cubicTo(87, 29, 233, 29, 231, 118)..close();
    canvas.drawPath(top, paint..shader = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
      colors: [Colors.white, pawToyCream, Color.lerp(pawToyTrim, rose, .25)!])
      .createShader(const Rect.fromLTWH(89, 50, 142, 74)));
    paint.shader = null;
    canvas.drawOval(const Rect.fromLTWH(89, 109, 142, 19), paint..color = pawToyTrim);
    canvas.drawOval(const Rect.fromLTWH(97, 113, 126, 10), paint..color = pawToyCream);
    if (!open) {
      for (final x in [140.0, 180.0]) {
        canvas.drawOval(Rect.fromCenter(center: Offset(x, 90), width: 5, height: 8), paint..color = palette.accentInk);
        canvas.drawOval(Rect.fromCenter(center: Offset(x == 140 ? 127 : 193, 99), width: 15, height: 7), paint..color = rose);
      }
      canvas.drawPath(Path()..moveTo(153, 99)..quadraticBezierTo(160, 105, 167, 99),
        paint..color = palette.accentInk..style = PaintingStyle.stroke..strokeWidth = 2..strokeCap = StrokeCap.round);
      paint.style = PaintingStyle.fill;
    }
    canvas.restore();
    final bottom = Path()..moveTo(89, 125)..cubicTo(91, 211, 229, 211, 231, 125)..close();
    canvas.drawPath(bottom, paint..shader = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
      colors: [Color.lerp(rose, Colors.white, .45)!, rose, Color.lerp(rose, palette.accentInk, .18)!])
      .createShader(const Rect.fromLTWH(89, 123, 142, 72)));
    paint.shader = null;
    canvas.drawOval(const Rect.fromLTWH(89, 116, 142, 20), paint..color = pawToyCream);
    if (open) canvas.drawOval(const Rect.fromLTWH(98, 121, 124, 10), paint..color = Color.lerp(rose, palette.accentInk, .18)!);
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(107, 143, 9, 21), const Radius.circular(5)),
      paint..color = Colors.white.withValues(alpha: .65));
    // Paw seal on the capsule.
    canvas.drawOval(const Rect.fromLTWH(149, 165, 22, 14), paint..color = pawToyCream);
    for (var i = 0; i < 3; i++) {
      canvas.drawCircle(Offset(149.0 + i * 11, 157 - (i == 1 ? 4 : 0)), 4, paint);
    }
    for (final star in [(54.0, 78.0, 7.0), (268.0, 100.0, 9.0), (72.0, 141.0, 4.0), (246.0, 46.0, 5.0)]) {
      final (x, y, r) = star;
      final path = Path()..moveTo(x, y - r)..quadraticBezierTo(x + 1, y - 1, x + r, y)
        ..quadraticBezierTo(x + 1, y + 1, x, y + r)..quadraticBezierTo(x - 1, y + 1, x - r, y)
        ..quadraticBezierTo(x - 1, y - 1, x, y - r)..close();
      canvas.drawPath(path, paint..color = (x < 160 ? const Color(0xFFEACD96) : palette.accent));
    }
    // Pastel capsule beside the main toy.
    canvas.save();
    canvas.translate(269, 175);
    canvas.rotate(-math.pi / 7);
    canvas.drawCircle(Offset.zero, 16, paint..color = const Color(0xFFAACBC6));
    canvas.drawArc(const Rect.fromLTWH(-16, -16, 32, 32), math.pi, math.pi, true, paint..color = pawToyCream);
    canvas.drawLine(const Offset(-15, 0), const Offset(15, 0), paint..color = Colors.white..strokeWidth = 2);
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CapsulePainter oldDelegate) =>
    oldDelegate.palette != palette || oldDelegate.open != open || oldDelegate.progress != progress;
}
