import 'package:flutter/material.dart';

/// Extra faces share the original map coordinates, so the path and dice rules
/// remain independent of the illustration. No 3D engine or image assets needed.
void paintRaisedIsland(Canvas canvas, Path top, {
  required Color side,
  double depth = 13,
}) {
  canvas.drawShadow(top.shift(Offset(0, depth)), Colors.black38, 8, false);
  for (var y = depth; y >= 1; y -= 1) {
    canvas.drawPath(top.shift(Offset(0, y)), Paint()
      ..color = Color.lerp(side, Colors.black, y / depth * .16)!);
  }
}

class ToyBuildingPainter extends CustomPainter {
  const ToyBuildingPainter({required this.level, required this.color});
  final int level;
  final Color color;

  @override
  void paint(Canvas c, Size size) {
    c.save();
    c.scale(size.width / 38, size.height / 26);
    final h = 8.0 + level.clamp(1, 5) * 1.5;
    c.drawOval(const Rect.fromLTWH(4, 19, 31, 6), Paint()..color = Colors.black12);
    Path face(List<Offset> pts) => Path()..addPolygon(pts, true);
    final front = face([Offset(7, 23 - h), Offset(24, 23 - h),
      const Offset(24, 23), const Offset(7, 23)]);
    final right = face([Offset(24, 23 - h), Offset(32, 18 - h),
      const Offset(32, 18), const Offset(24, 23)]);
    c.drawPath(front, Paint()..color = const Color(0xFFFFF3D6));
    c.drawPath(right, Paint()..color = const Color(0xFFD5BD98));
    final roof = face([Offset(4, 23 - h), Offset(14, 15 - h),
      Offset(24, 23 - h)]);
    c.drawPath(roof, Paint()..color = Color.lerp(color, Colors.white, .1)!);
    c.drawPath(face([Offset(14, 15 - h), Offset(22, 10 - h),
      Offset(35, 18 - h), Offset(24, 23 - h)]),
      Paint()..color = Color.lerp(color, Colors.black, .18)!);
    c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(16, 17, 5, 6),
      const Radius.circular(1)), Paint()..color = const Color(0xFF95755D));
    for (var row = 0; row < (level > 2 ? 2 : 1); row++) {
      c.drawRect(Rect.fromLTWH(10, 24 - h + row * 4, 4, 3),
        Paint()..color = const Color(0xFF83C8D2));
    }
    c.restore();
  }

  @override
  bool shouldRepaint(covariant ToyBuildingPainter old) =>
      old.level != level || old.color != color;
}
