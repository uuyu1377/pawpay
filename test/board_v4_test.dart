import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:user_interface/widgets/board_3d_geometry.dart';

void main() {
  test('all names remain inside the viewport without overlapping', () {
    for (final magic in [false, true]) {
      for (final size in [
        const Size(320, 350),
        const Size(390, 430),
        const Size(600, 420),
      ]) {
        for (final yaw in [.1, -.2, math.pi / 2, math.pi]) {
          final camera = BoardCamera3D(size: size, magic: magic, yaw: yaw);
          final route = boardRoute3D(magic ? 22 : 28, magic: magic);
          final rects = boardNameRails3D(
            route.map((p) => camera.project(p).screen).toList(),
            List.filled(route.length, const Size(55, 18)),
            size,
          );
          expect(rects.length, route.length);
          for (final e in rects.entries) {
            expect(e.value.left, greaterThanOrEqualTo(0));
            expect(e.value.right, lessThanOrEqualTo(size.width));
            expect(e.value.top, greaterThanOrEqualTo(0));
            expect(e.value.bottom, lessThanOrEqualTo(size.height));
            expect(
              rects.entries
                  .where((other) => other.key != e.key)
                  .any((other) => other.value.overlaps(e.value)),
              isFalse,
            );
          }
        }
      }
    }
  });

  test('sky route has distinct land heights and bridge crossings', () {
    final route = boardRoute3D(22, magic: true);
    expect(route.map((p) => p.y).toSet().length, 6);
    expect(
      List.generate(
        route.length,
        (i) => (route[i] - route[(i + 1) % route.length]).length,
      ).where((distance) => distance > .6).length,
      6,
    );
  });
}
