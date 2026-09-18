import 'package:flutter/material.dart';

/// Small vector toys in the same muted, isometric style as the city sprites.
/// (0, 0) is the contact point on the roof, not the top of the illustration.
class RoofCategoryArt {
  static void paint(Canvas c, String category, Offset contact) {
    c.save();
    c.translate(contact.dx, contact.dy);
    c.drawOval(const Rect.fromLTWH(-26, -6, 52, 14),
      Paint()..color = const Color(0x33000000));
    switch (category) {
      case '飲食': _bento(c); break;
      case '交通': _bus(c); break;
      case '生活用品': _bag(c); break;
      case '娛樂': case '小確幸': _controller(c); break;
      case '服飾美容': _shirt(c); break;
      case '醫療健康': _medical(c); break;
      case '學費與教材': case '小孩教育': _books(c); break;
      case '禮物與送禮': case '社交': _gift(c); break;
      case '投資理財': _coins(c); break;
      case '通訊網路': case '線上訂閱': _phone(c); break;
      case '家庭旅遊': case '旅遊': _suitcase(c); break;
      case '住房': case '房貸與修繕': _key(c); break;
      case '家具家電': _sofa(c); break;
      case '保險費用': _shield(c); break;
      default: _sign(c, category);
    }
    c.restore();
  }

  static Path _polygon(List<Offset> points) => Path()..addPolygon(points, true);
  static void _face(Canvas c, List<Offset> pts, Color color) =>
      c.drawPath(_polygon(pts), Paint()..color = color);
  static void _round(Canvas c, Rect r, Color color, [double radius = 3]) =>
      c.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(radius)), Paint()..color = color);

  static void _box(Canvas c, {double width = 46, double height = 25,
    Color color = const Color(0xFFE49D75)}) {
    final x = -width / 2;
    _face(c, [Offset(x, -height), Offset(-x, -height), Offset(-x, 0), Offset(x, 0)], color);
    _face(c, [Offset(-x, -height), Offset(-x + 9, -height - 7),
      Offset(-x + 9, -7), Offset(-x, 0)], Color.lerp(color, Colors.black, .22)!);
    _face(c, [Offset(x, -height), Offset(x + 9, -height - 7),
      Offset(-x + 9, -height - 7), Offset(-x, -height)], Color.lerp(color, Colors.white, .32)!);
  }

  static void _bento(Canvas c) {
    const outer = [Offset(-30, -17), Offset(-5, -32), Offset(30, -17), Offset(5, -2)];
    _face(c, const [Offset(-30, -17), Offset(5, -2), Offset(30, -17),
      Offset(30, -10), Offset(5, 5), Offset(-30, -10)], const Color(0xFF9B6250));
    _face(c, outer, const Color(0xFFD6966E));
    _face(c, const [Offset(-24, -17), Offset(-5, -27), Offset(23, -17),
      Offset(5, -7)], const Color(0xFF694D44));
    _face(c, const [Offset(-22, -17), Offset(-5, -26), Offset(7, -20),
      Offset(-10, -11)], const Color(0xFFFFF4DC));
    c.drawOval(const Rect.fromLTWH(-9, -21, 8, 6), Paint()..color = const Color(0xFFCD6759));
    c.drawOval(const Rect.fromLTWH(4, -18, 12, 7), Paint()..color = const Color(0xFFFFDA81));
    for (final at in [const Offset(15, -17), const Offset(10, -13), const Offset(18, -14)]) {
      c.drawCircle(at, 3.5, Paint()..color = const Color(0xFF85A86B));
    }
    final stick = Paint()..color = const Color(0xFFC5A778)..strokeWidth = 2.2..strokeCap = StrokeCap.round;
    c.drawLine(const Offset(-20, -30), const Offset(13, -36), stick);
    c.drawLine(const Offset(-19, -27), const Offset(14, -33), stick);
  }

  static void _bus(Canvas c) {
    _box(c, height: 27, color: const Color(0xFFDEB95F));
    for (var i = 0; i < 3; i++) {
      _round(c, Rect.fromLTWH(-19 + i * 12, -24, 9, 11), const Color(0xFFB6DAE0), 1);
    }
    _face(c, const [Offset(25, -25), Offset(30, -29), Offset(30, -18), Offset(25, -14)], const Color(0xFF91B5C2));
    for (final x in [-14.0, 16.0]) {
      c.drawCircle(Offset(x, -1), 5, Paint()..color = const Color(0xFF596469));
      c.drawCircle(Offset(x, -1), 2.2, Paint()..color = const Color(0xFFD9D6C9));
    }
    _round(c, const Rect.fromLTWH(-20, -9, 39, 3), const Color(0xFFF4DFAC), 1);
  }

  static void _bag(Canvas c) {
    _box(c, width: 33, height: 30, color: const Color(0xFF8FB6A2));
    c.drawArc(const Rect.fromLTWH(-8, -41, 18, 22), 3.14, 3.14, false,
      Paint()..color = const Color(0xFF557B6A)..style = PaintingStyle.stroke..strokeWidth = 4);
    c.drawCircle(const Offset(0, -14), 7, Paint()..color = const Color(0xFFF1E8C9));
    c.drawLine(const Offset(-3, -14), const Offset(3, -14), Paint()..color = const Color(0xFF8FB6A2)..strokeWidth = 2);
  }

  static void _controller(Canvas c) {
    final shape = Path()..moveTo(-19, -28)..quadraticBezierTo(-29, -28, -30, -8)
      ..quadraticBezierTo(-30, 5, -19, -1)..lineTo(-9, -8)..lineTo(10, -8)
      ..lineTo(20, -1)..quadraticBezierTo(31, 5, 29, -8)
      ..quadraticBezierTo(27, -28, 19, -28)..close();
    c.drawPath(shape.shift(const Offset(3, 4)), Paint()..color = const Color(0xFF857590));
    c.drawPath(shape, Paint()..color = const Color(0xFFC5B4D0));
    _round(c, const Rect.fromLTWH(-19, -23, 5, 15), const Color(0xFF686574), 1);
    _round(c, const Rect.fromLTWH(-24, -18, 15, 5), const Color(0xFF686574), 1);
    c.drawCircle(const Offset(14, -17), 3.5, Paint()..color = const Color(0xFFE29B91));
    c.drawCircle(const Offset(22, -21), 3.5, Paint()..color = const Color(0xFFF1D789));
  }

  static void _shirt(Canvas c) {
    final p = _polygon(const [Offset(-10, -37), Offset(-25, -29), Offset(-19, -17),
      Offset(-11, -21), Offset(-11, 0), Offset(14, 0), Offset(14, -21),
      Offset(22, -17), Offset(28, -29), Offset(12, -37), Offset(6, -30), Offset(-4, -30)]);
    c.drawPath(p.shift(const Offset(4, 4)), Paint()..color = const Color(0xFFAA7272));
    c.drawPath(p, Paint()..color = const Color(0xFFDFA7A0));
    _round(c, const Rect.fromLTWH(3, -23, 7, 8), const Color(0xFFF5D4C1), 1);
  }

  static void _medical(Canvas c) {
    _round(c, const Rect.fromLTWH(-9, -39, 21, 12), const Color(0xFFA9B6AF));
    _round(c, const Rect.fromLTWH(-5, -36, 13, 8), const Color(0xFFF4EFDF));
    _box(c, height: 29, color: const Color(0xFFF2EBDD));
    _round(c, const Rect.fromLTWH(-4, -24, 8, 20), const Color(0xFFCD837C), 1);
    _round(c, const Rect.fromLTWH(-10, -18, 20, 8), const Color(0xFFCD837C), 1);
  }

  static void _books(Canvas c) {
    for (var i = 0; i < 3; i++) {
      c.save(); c.translate(i.isEven ? -3 : 1, -i * 10.0);
      _box(c, width: 41, height: 7, color: [const Color(0xFF9DBBA4),
        const Color(0xFFD79F77), const Color(0xFF8DAFC2)][i]);
      c.drawRect(const Rect.fromLTWH(-16, -5, 33, 3), Paint()..color = const Color(0xFFF5EEDD));
      c.restore();
    }
  }

  static void _gift(Canvas c) {
    _box(c, width: 37, height: 31, color: const Color(0xFFD49C98));
    c.drawRect(const Rect.fromLTWH(-3, -31, 8, 31), Paint()..color = const Color(0xFFF0D69A));
    final bow = Paint()..color = const Color(0xFFD9B677)..style = PaintingStyle.stroke..strokeWidth = 4;
    c.drawOval(const Rect.fromLTWH(-11, -45, 16, 10), bow);
    c.drawOval(const Rect.fromLTWH(3, -45, 16, 10), bow);
  }

  static void _coins(Canvas c) {
    for (var i = 0; i < 4; i++) {
      final top = -7.0 - 6 * i;
      c.drawOval(Rect.fromLTWH(-20, top, 40, 16), Paint()..color = const Color(0xFFB58D4E));
      c.drawOval(Rect.fromLTWH(-20, top - 4, 40, 16), Paint()..color = const Color(0xFFE9C97B));
    }
    _label(c, '\$', const Offset(-5, -29), const Color(0xFFA98045), 16);
  }

  static void _phone(Canvas c) {
    _box(c, width: 24, height: 39, color: const Color(0xFF738B99));
    _round(c, const Rect.fromLTWH(-9, -35, 18, 27), const Color(0xFFBFDADE), 1);
    c.drawCircle(const Offset(0, -4), 2, Paint()..color = const Color(0xFFE6E9DD));
  }

  static void _suitcase(Canvas c) {
    _round(c, const Rect.fromLTWH(-8, -42, 18, 13), const Color(0xFF927866));
    _box(c, width: 38, height: 32, color: const Color(0xFFB79A75));
    for (final x in [-12.0, 11.0]) {
      c.drawRect(Rect.fromLTWH(x, -32, 4, 32), Paint()..color = const Color(0xFFE4C996));
      c.drawCircle(Offset(x + 2, 1), 3, Paint()..color = const Color(0xFF6B635A));
    }
  }

  static void _key(Canvas c) {
    final p = Paint()..color = const Color(0xFFD8B364)..style = PaintingStyle.stroke..strokeWidth = 7;
    c.drawCircle(const Offset(-10, -26), 10, p);
    c.drawLine(const Offset(-2, -19), const Offset(18, -1), p);
    c.drawLine(const Offset(9, -9), const Offset(15, -15), p);
    c.drawLine(const Offset(15, -3), const Offset(21, -9), p);
  }

  static void _sofa(Canvas c) {
    _box(c, height: 23, color: const Color(0xFF91A8A0));
    _round(c, const Rect.fromLTWH(-24, -15, 49, 16), const Color(0xFFAFC5B5));
    _round(c, const Rect.fromLTWH(-28, -24, 9, 27), const Color(0xFF80988E));
    _round(c, const Rect.fromLTWH(20, -24, 9, 27), const Color(0xFF80988E));
  }

  static void _shield(Canvas c) {
    final p = Path()..moveTo(0, -41)..lineTo(22, -33)..lineTo(20, -13)
      ..quadraticBezierTo(14, -2, 0, 4)..quadraticBezierTo(-14, -2, -20, -13)
      ..lineTo(-22, -33)..close();
    c.drawPath(p.shift(const Offset(3, 2)), Paint()..color = const Color(0xFF698C89));
    c.drawPath(p, Paint()..color = const Color(0xFFA0C2AC));
    c.drawPath(Path()..moveTo(-9, -20)..lineTo(-2, -12)..lineTo(12, -28),
      Paint()..color = const Color(0xFFF8EFD8)..style = PaintingStyle.stroke..strokeWidth = 5..strokeCap = StrokeCap.round);
  }

  static void _sign(Canvas c, String name) {
    _round(c, const Rect.fromLTWH(-3, -25, 6, 28), const Color(0xFFAB9070), 1);
    _box(c, width: 42, height: 27, color: const Color(0xFFE9DBBC));
    _label(c, String.fromCharCodes(name.runes.take(2)), const Offset(-17, -24), const Color(0xFF70614D), 16);
  }

  static void _label(Canvas c, String text, Offset at, Color color, double size) {
    final p = TextPainter(text: TextSpan(text: text, style: TextStyle(
      color: color, fontSize: size, fontWeight: FontWeight.w700)), textDirection: TextDirection.ltr)..layout();
    p.paint(c, at);
  }
}
