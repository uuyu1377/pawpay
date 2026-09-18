import 'dart:math' as math;
import 'dart:ui';
import 'board_world_data.dart';

/// World coordinates: X = east/west, Y = height, Z = north/south.
/// The board is projected from actual 3D vertices, not a rotated screenshot.
class BoardPoint3 {
  const BoardPoint3(this.x, this.y, this.z);
  final double x, y, z;
  BoardPoint3 operator +(BoardPoint3 p) =>
      BoardPoint3(x + p.x, y + p.y, z + p.z);
  BoardPoint3 operator -(BoardPoint3 p) =>
      BoardPoint3(x - p.x, y - p.y, z - p.z);
  BoardPoint3 operator *(double n) => BoardPoint3(x * n, y * n, z * n);
  double dot(BoardPoint3 p) => x * p.x + y * p.y + z * p.z;
  BoardPoint3 cross(BoardPoint3 p) =>
      BoardPoint3(y * p.z - z * p.y, z * p.x - x * p.z, x * p.y - y * p.x);
  double get length => math.sqrt(dot(this));
  BoardPoint3 get normalized => length < 1e-8 ? this : this * (1 / length);
  BoardPoint3 atHeight(double height) => BoardPoint3(x, height, z);
  static BoardPoint3 lerp(BoardPoint3 a, BoardPoint3 b, double t) =>
      a + (b - a) * t;
}

class BoardProjection3D {
  const BoardProjection3D(this.screen, this.depth, this.scale);
  final Offset screen;
  final double depth, scale;
}

class BoardCamera3D {
  BoardCamera3D({
    required this.size,
    this.yaw = -.20,
    this.elevation = 1.05,
    this.zoom = 1,
    this.magic = false,
  }) : _cosYaw = math.cos(yaw),
       _sinYaw = math.sin(yaw),
       _cosElevation = math.cos(elevation),
       _sinElevation = math.sin(elevation);
  final Size size;
  final double yaw, elevation, zoom;
  final bool magic;
  final double _cosYaw, _sinYaw, _cosElevation, _sinElevation;

  Offset _plane(BoardPoint3 p) {
    final x = p.x * _cosYaw - p.z * _sinYaw;
    final z = p.x * _sinYaw + p.z * _cosYaw;
    final up = p.y * _cosElevation - z * _sinElevation;
    final depth = p.y * _sinElevation + z * _cosElevation;
    final perspective = 9 / (9 - depth);
    return Offset(x * perspective, -up * perspective);
  }

  late final Rect _bounds = _measure();
  late final double unit =
      math.min(
        size.width * .78 / _bounds.width,
        size.height * .86 / _bounds.height,
      ) *
      zoom;

  Rect _measure() {
    final points = <BoardPoint3>[];
    if (magic) {
      for (final p in skyPlatforms3D) {
        for (var i = 0; i < 32; i++) {
          final a = i * math.pi / 16;
          for (final y in [p[1] - 1.05, p[1] + .37]) {
            points.add(
              BoardPoint3(
                p[0] + p[3] * 1.05 * math.cos(a),
                y,
                p[2] + p[4] * 1.05 * math.sin(a),
              ),
            );
          }
        }
      }
      points.add(const BoardPoint3(0, 1.55, -.08));
    } else {
      for (final p in taiwanCoast3D) {
        points.add(BoardPoint3(p[0] * 1.04, -.15, p[2] * 1.04));
        points.add(BoardPoint3(p[0] * .80, .53, p[2] * .80));
      }
      for (final p in taiwanOffshoreBounds3D) {
        points.add(BoardPoint3(p[0], p[1], p[2]));
      }
    }
    final screen = points.map(_plane).toList();
    return Rect.fromLTRB(
      screen.map((p) => p.dx).reduce(math.min),
      screen.map((p) => p.dy).reduce(math.min),
      screen.map((p) => p.dx).reduce(math.max),
      screen.map((p) => p.dy).reduce(math.max),
    );
  }

  BoardProjection3D project(BoardPoint3 p) {
    final z = p.x * _sinYaw + p.z * _cosYaw;
    final depth = p.y * _sinElevation + z * _cosElevation;
    final v = _plane(p) - _bounds.center;
    return BoardProjection3D(
      Offset(size.width / 2 + v.dx * unit, size.height / 2 + v.dy * unit),
      depth,
      unit * 9 / (9 - depth),
    );
  }
}

/// Display positions are generated together with their terrain mesh. They do
/// not change the game's stored step indices, location names or turn order.
List<BoardPoint3> boardRoute3D(int count, {bool magic = false}) {
  if (count <= 0) return [];
  final data = magic ? skyStops3D : taiwanStops3D;
  final route = data.map((p) => BoardPoint3(p[0], p[1], p[2])).toList();
  if (count == route.length) return route;
  // Only used for a preview with a different number of stops.
  return List.generate(count, (i) {
    final position = i * route.length / count;
    final lower = position.floor();
    return BoardPoint3.lerp(
      route[lower],
      route[(lower + 1) % route.length],
      position - lower,
    );
  });
}

/// Dense northern cities keep their geographic anchors; only toy sizes shrink.
double boardTileScale3D(int index, {bool magic = false}) =>
    magic || index < 0 || index >= taiwanTileScales3D.length
        ? 1.0
        : taiwanTileScales3D[index];

/// Equal-size side rails preserve every name, with stable vertical spacing.
/// Sorting by screen Y keeps the leaders in order when the camera rotates.
Map<int, Rect> boardNameRails3D(
  List<Offset> anchors,
  List<Size> labels,
  Size viewport,
) {
  final order = List.generate(anchors.length, (i) => i)
    ..sort((a, b) => anchors[a].dx.compareTo(anchors[b].dx));
  final result = <int, Rect>{};
  final split = (order.length / 2).ceil();
  for (var side = 0; side < 2; side++) {
    final indices = (side == 0 ? order.take(split) : order.skip(split)).toList()
      ..sort((a, b) => anchors[a].dy.compareTo(anchors[b].dy));
    if (indices.isEmpty) continue;
    final heights = indices.map((i) => labels[i].height).toList();
    final total = heights.fold<double>(0, (a, b) => a + b);
    final gap = math.max(
      0.0,
      math.min(4.0, (viewport.height - 16 - total) / indices.length),
    );
    final ys = <double>[];
    var floor = 8.0;
    for (var j = 0; j < indices.length; j++) {
      final y = math.max(floor, anchors[indices[j]].dy - heights[j] / 2);
      ys.add(y);
      floor = y + heights[j] + gap;
    }
    var ceiling = viewport.height - 8;
    for (var j = indices.length - 1; j >= 0; j--) {
      ys[j] = math.min(ys[j], ceiling - heights[j]);
      ceiling = ys[j] - gap;
    }
    for (var j = 0; j < indices.length; j++) {
      final i = indices[j];
      result[i] = Rect.fromLTWH(
        side == 0 ? 3 : viewport.width - labels[i].width - 3,
        ys[j],
        labels[i].width,
        heights[j],
      );
    }
  }
  return result;
}

/// All names remain available in the location list. Labels that cannot fit
/// are omitted from the canvas instead of being drawn on top of one another.
Rect? placeBoardLabel3D({
  required Offset anchor,
  required Size labelSize,
  required Size viewport,
  required List<Rect> occupied,
  required Offset center,
}) {
  final bounds = Rect.fromLTWH(
    6,
    6,
    math.max(0.0, viewport.width - 12),
    math.max(0.0, viewport.height - 12),
  );
  final outward = anchor - center;
  final direction = outward.distance < 1
      ? const Offset(0, -1)
      : outward / outward.distance;
  final tangent = Offset(-direction.dy, direction.dx);
  for (final distance in [23.0, 37.0, 51.0]) {
    for (final shift in [0.0, 19.0, -19.0]) {
      final c = anchor + direction * distance + tangent * shift;
      final rect = Rect.fromCenter(
        center: c,
        width: labelSize.width,
        height: labelSize.height,
      );
      if (!bounds.contains(rect.topLeft) || !bounds.contains(rect.bottomRight))
        continue;
      if (occupied.any((other) => other.inflate(3).overlaps(rect))) continue;
      return rect;
    }
  }
  return null;
}
