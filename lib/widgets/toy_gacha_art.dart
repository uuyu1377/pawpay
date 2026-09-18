import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Uses the original 260 x 400 layout; all geometry scales together.
class GachaArtPainter extends CustomPainter {
  const GachaArtPainter();

  @override
  void paint(Canvas c, Size size) {
    c.save();
    c.scale(size.width / 260, size.height / 400);
    final edge = Paint()..color = const Color(0xFF3C2928)
      ..style = PaintingStyle.stroke..strokeWidth = 3.5..strokeJoin = StrokeJoin.round;
    c.drawOval(const Rect.fromLTWH(25, 367, 221, 25), Paint()..color = Colors.black12);

    // Red plinth with an exposed side and a soft bevel.
    final side = Path()..moveTo(198, 241)..lineTo(221, 254)
      ..lineTo(221, 355)..quadraticBezierTo(220, 374, 201, 378)
      ..lineTo(69, 378)..lineTo(51, 365)..close();
    c.drawPath(side, Paint()..color = const Color(0xFFAE3436));
    c.drawPath(side, edge);
    const front = Rect.fromLTWH(44, 237, 166, 132);
    final rr = RRect.fromRectAndRadius(front, const Radius.circular(22));
    c.drawRRect(rr, Paint()..shader = const LinearGradient(
      begin: Alignment.topLeft, end: Alignment.bottomRight,
      colors: [Color(0xFFFF7770), Color(0xFFE64643), Color(0xFFC63335)],
      stops: [0, .55, 1]).createShader(front));
    c.drawRRect(rr, edge);
    c.drawLine(const Offset(57, 261), const Offset(57, 343), Paint()
      ..color = const Color(0x66FFFFFF)..strokeWidth = 4..strokeCap = StrokeCap.round);

    // The capsules are placed between this glass background and the foreground.
    const globe = Rect.fromLTWH(30, 53, 200, 200);
    c.drawCircle(const Offset(135, 160), 99, Paint()..color = const Color(0x20000000));
    c.drawOval(globe, Paint()..shader = const RadialGradient(
      center: Alignment(-.45, -.6), radius: 1.2,
      colors: [Color(0xFFEFFBFA), Color(0xFFD8ECED), Color(0xFFA8C9D0)]).createShader(globe));
    c.drawOval(globe, edge);

    final collar = RRect.fromRectAndRadius(const Rect.fromLTWH(82, 231, 96, 20), const Radius.circular(8));
    c.drawRRect(collar, Paint()..color = const Color(0xFFB83B39));
    c.drawRRect(collar, edge);

    final lid = RRect.fromRectAndRadius(const Rect.fromLTWH(65, 27, 130, 39), const Radius.circular(13));
    c.drawRRect(lid, Paint()..shader = const LinearGradient(
      colors: [Color(0xFFFF8178), Color(0xFFE84C47), Color(0xFFB63033)])
      .createShader(const Rect.fromLTWH(65, 27, 130, 39)));
    c.drawRRect(lid, edge);
    c.drawOval(const Rect.fromLTWH(66, 22, 128, 21), Paint()..color = const Color(0xFFFF9A89));
    c.drawOval(const Rect.fromLTWH(66, 22, 128, 21), edge);
    c.drawOval(const Rect.fromLTWH(96, 25, 54, 8), Paint()..color = const Color(0x55FFFFFF));

    c.drawCircle(const Offset(132, 278), 30, Paint()..color = const Color(0xFF9C3335));
    c.drawCircle(const Offset(129, 274), 27, Paint()..color = const Color(0xFFF2D8AC));
    c.drawCircle(const Offset(129, 274), 27, edge);
    c.drawCircle(const Offset(129, 274), 20, Paint()..color = const Color(0xFFD1AF88));

    final outlet = RRect.fromRectAndRadius(const Rect.fromLTWH(88, 315, 83, 38), const Radius.circular(10));
    c.drawRRect(outlet, Paint()..color = const Color(0xFFFFE5B8));
    c.drawRRect(outlet, edge);
    c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(95, 320, 69, 24), const Radius.circular(6)),
      Paint()..color = const Color(0xFF653C36));
    c.drawLine(const Offset(95, 347), const Offset(164, 347), Paint()
      ..color = const Color(0xFFC39471)..strokeWidth = 3);
    c.restore();
  }

  @override
  bool shouldRepaint(covariant GachaArtPainter oldDelegate) => false;
}

class GachaGlassPainter extends CustomPainter {
  const GachaGlassPainter();
  @override
  void paint(Canvas c, Size size) {
    c.save();
    c.scale(size.width / 260, size.height / 400);
    c.drawArc(const Rect.fromLTWH(43, 66, 174, 174), math.pi * 1.03, math.pi * .38, false,
      Paint()..color = const Color(0xBBFFFFFF)..style = PaintingStyle.stroke
      ..strokeWidth = 9..strokeCap = StrokeCap.round);
    c.drawOval(const Rect.fromLTWH(65, 80, 17, 26), Paint()..color = const Color(0xAAFFFFFF));
    c.drawArc(const Rect.fromLTWH(39, 62, 182, 182), .05, .70, false,
      Paint()..color = const Color(0x55FFFFFF)..style = PaintingStyle.stroke..strokeWidth = 4);
    c.restore();
  }
  @override
  bool shouldRepaint(covariant GachaGlassPainter oldDelegate) => false;
}

class ToyCapsulePainter extends CustomPainter {
  const ToyCapsulePainter({required this.color});
  final Color color;
  @override
  void paint(Canvas c, Size size) {
    final r = size.shortestSide / 2 - 1.5;
    final at = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCircle(center: at, radius: r);
    c.save();
    c.clipPath(Path()..addOval(rect));
    c.drawCircle(at, r, Paint()..shader = const RadialGradient(
      center: Alignment(-.5, -.6), radius: 1.3,
      colors: [Color(0xFFF7FCF9), Color(0xFFCFDFE0), Color(0xFF9CB9C1)]).createShader(rect));
    c.drawRect(Rect.fromLTRB(rect.left, at.dy, rect.right, rect.bottom),
      Paint()..shader = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: [Color.lerp(color, Colors.white, .35)!, color,
          Color.lerp(color, Colors.black, .18)!]).createShader(rect));
    c.drawOval(Rect.fromCenter(center: at, width: r * 2, height: r * .35),
      Paint()..color = Color.lerp(color, Colors.white, .35)!);
    c.drawOval(Rect.fromLTWH(at.dx - r * .60, at.dy - r * .64, r * .35, r * .50),
      Paint()..color = const Color(0xCCFFFFFF));
    c.restore();
    c.drawCircle(at, r, Paint()..color = const Color(0xFF5D4845)
      ..style = PaintingStyle.stroke..strokeWidth = 1.8);
  }
  @override
  bool shouldRepaint(covariant ToyCapsulePainter oldDelegate) => oldDelegate.color != color;
}
