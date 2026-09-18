import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'board_3d_geometry.dart';
import 'board_scene_model.dart';

class BoardSite3D {
  const BoardSite3D({
    required this.name,
    required this.kind,
    required this.cost,
    required this.rent,
    required this.level,
    this.ownerColor,
    this.ownerName,
  });
  final String name, kind;
  final int cost, rent, level;
  final Color? ownerColor;
  final String? ownerName;
  Color get color =>
      ownerColor ??
      switch (kind) {
        'start' => const Color(0xFFFFD87C),
        'chance' => const Color(0xFFC9AFE4),
        'tax' => const Color(0xFFF29FA0),
        'jail' => const Color(0xFFADBECB),
        'goJail' => const Color(0xFFF4B496),
        _ => const Color(0xFFFFF9EA),
      };
  String get description => kind == 'land'
      ? '${ownerName ?? '尚未購買'} · 建築 $level 級 · 地價 \$$cost · 租金 \$$rent'
      : switch (kind) {
          'start' => '起點：經過可領取原有遊戲獎勵',
          'chance' => '機會：停留時觸發事件',
          'tax' => '繳稅：依原有規則支付費用',
          'jail' => '監獄：依原有回合規則停留',
          'goJail' => '停留後移動到監獄',
          _ => '',
        };
}

class BoardPawn3D {
  const BoardPawn3D({
    required this.id,
    required this.name,
    required this.step,
    required this.color,
    this.imagePath,
    this.emoji,
  });
  final int id, step;
  final String name;
  final Color color;
  final String? imagePath, emoji;
}

/// A small native 3D scene: perspective camera, mesh face depth sorting,
/// directional lighting, real island/roof/pawn geometry, and orbit gestures.
/// No WebView, remote models, new plug-ins, or changes to game rules.
class IslandBoard3D extends StatefulWidget {
  const IslandBoard3D({
    super.key,
    required this.sites,
    required this.pawns,
    required this.activePlayerId,
    required this.magic,
    required this.accent,
    this.nextStep,
    this.model,
  });
  final BoardSceneModel? model;
  final List<BoardSite3D> sites;
  final List<BoardPawn3D> pawns;
  final int activePlayerId;
  final int? nextStep;
  final bool magic;
  final Color accent;
  @override
  State<IslandBoard3D> createState() => _IslandBoard3DState();
}

class _IslandBoard3DState extends State<IslandBoard3D>
    with SingleTickerProviderStateMixin {
  late final AnimationController _movement;
  late Future<BoardSceneModel> _model;
  Future<BoardSceneModel> _loadModel() => widget.model == null
      ? BoardSceneModel.load(widget.magic)
      : Future.value(widget.model!);
  double _yaw = -.20, _elevation = 1.05, _zoom = 1, _startZoom = 1;
  Offset _previousFocal = Offset.zero;
  int _selected = 0;
  bool _names = true;
  final Map<String, ui.Image> _images = {};
  final Set<String> _requestedImages = {};
  Map<int, BoardPoint3> _from = {}, _to = {};

  List<BoardPoint3> get _route =>
      boardRoute3D(widget.sites.length, magic: widget.magic);
  int get _activeStep {
    for (final pawn in widget.pawns) {
      if (pawn.id == widget.activePlayerId) return pawn.step;
    }
    return 0;
  }

  Map<int, BoardPoint3> _targets() {
    final route = _route;
    if (route.isEmpty) return {};
    return {
      for (final pawn in widget.pawns)
        pawn.id:
            route[pawn.step % route.length] +
            BoardPoint3(
              (pawn.id.isEven ? -1 : 1) * .038,
              .030,
              .095 + (pawn.id < 2 ? -.018 : .018),
            ),
    };
  }

  Map<int, BoardPoint3> _positions() {
    final t = Curves.easeInOut.transform(_movement.value);
    BoardPoint3 position(int id, BoardPoint3 end) {
      final start = _from[id] ?? end;
      final p = BoardPoint3.lerp(start, end, t);
      // The longer sky segments use the same arch as their wooden bridge.
      return widget.magic && (end - start).length > .60
          ? p + BoardPoint3(0, .16 * math.sin(math.pi * t), 0)
          : p;
    }

    return {
      for (final entry in _to.entries)
        entry.key: position(entry.key, entry.value),
    };
  }

  @override
  void initState() {
    super.initState();
    _model = _loadModel();
    _yaw = widget.magic ? -.20 : .10;
    _elevation = widget.magic ? .74 : 1.02;
    _movement = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 340),
    );
    _to = _targets();
    _from = Map.of(_to);
    _movement.value = 1;
    _selected = _activeStep;
    _loadImages();
  }

  void _loadImages() {
    for (final pawn in widget.pawns) {
      final path = pawn.imagePath;
      if (path == null ||
          !path.toLowerCase().endsWith('.png') ||
          !_requestedImages.add(path))
        continue;
      _loadImage(path);
    }
  }

  Future<void> _loadImage(String path) async {
    try {
      final data = await rootBundle.load(path);
      final codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        targetWidth: 96,
      );
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      setState(() => _images[path] = frame.image);
    } catch (_) {
      /* The 3D pawn and pet emoji are always available. */
    }
  }

  @override
  void didUpdateWidget(covariant IslandBoard3D oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.magic != widget.magic || oldWidget.model != widget.model) {
      _model = _loadModel();
      _yaw = widget.magic ? -.20 : .10;
      _elevation = widget.magic ? .74 : 1.02;
      _zoom = 1;
    }
    final next = _targets();
    final changed =
        next.length != _to.length ||
        next.entries.any(
          (e) => _to[e.key] == null || (e.value - _to[e.key]!).length > .0001,
        );
    if (changed) {
      _from = _positions();
      _to = next;
      _movement.forward(from: 0);
      _selected = _activeStep;
    }
    if (oldWidget.activePlayerId != widget.activePlayerId)
      _selected = _activeStep;
    if (_selected >= widget.sites.length) _selected = 0;
    _loadImages();
  }

  @override
  void dispose() {
    _movement.dispose();
    for (final image in _images.values) {
      image.dispose();
    }
    super.dispose();
  }

  void _reset() => setState(() {
    _yaw = widget.magic ? -.20 : .10;
    _elevation = widget.magic ? .74 : 1.02;
    _zoom = 1;
  });

  void _showLocations() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView.builder(
          itemCount: widget.sites.length,
          itemBuilder: (_, i) {
            final site = widget.sites[i];
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: site.color,
                child: Text(
                  '${i + 1}',
                  style: const TextStyle(color: Color(0xFF564C43)),
                ),
              ),
              title: Text(site.name),
              subtitle: Text(site.description),
              selected: i == _selected,
              onTap: () {
                setState(() => _selected = i);
                Navigator.pop(sheetContext);
              },
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.sites.isEmpty) return const SizedBox.shrink();
    final site = widget.sites[_selected % widget.sites.length];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '拖曳旋轉 · 雙指縮放',
                  style: TextStyle(fontSize: 11, color: Colors.brown.shade400),
                ),
              ),
              IconButton(
                tooltip: _names ? '隱藏地名' : '顯示地名',
                onPressed: () => setState(() => _names = !_names),
                icon: Icon(
                  _names ? Icons.label_outline : Icons.label_off_outlined,
                  size: 20,
                ),
              ),
              IconButton(
                tooltip: '重設視角',
                onPressed: _reset,
                icon: const Icon(Icons.center_focus_strong, size: 20),
              ),
            ],
          ),
        ),
        Expanded(
          child: ClipRect(
            child: FutureBuilder<BoardSceneModel>(
              future: _model,
              builder: (context, snapshot) {
                if (snapshot.hasError)
                  return Center(
                    child: TextButton.icon(
                      onPressed: () => setState(() => _model = _loadModel()),
                      icon: const Icon(Icons.refresh),
                      label: const Text('重新載入地圖'),
                    ),
                  );
                if (!snapshot.hasData)
                  return const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  );
                return LayoutBuilder(
                  builder: (context, box) {
                    final size = Size(box.maxWidth, box.maxHeight);
                    final camera = BoardCamera3D(
                      size: size,
                      yaw: _yaw,
                      elevation: _elevation,
                      zoom: _zoom,
                      magic: widget.magic,
                    );
                    final painter = IslandScenePainter3D(
                      model: snapshot.data!,
                      camera: camera,
                      sites: widget.sites,
                      pawns: widget.pawns,
                      positions: _positions,
                      route: _route,
                      selected: _selected,
                      activePlayerId: widget.activePlayerId,
                      magic: widget.magic,
                      accent: widget.accent,
                      nextStep: widget.nextStep,
                      showNames: _names,
                      images: _images,
                      movement: _movement,
                    );
                    return Semantics(
                      label: '立體島嶼棋盤，可拖曳旋轉與雙指縮放，全部地點可從下方地點清單選取',
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onScaleStart: (d) {
                          _startZoom = _zoom;
                          _previousFocal = d.localFocalPoint;
                        },
                        onScaleUpdate: (d) {
                          final delta = d.localFocalPoint - _previousFocal;
                          _previousFocal = d.localFocalPoint;
                          setState(() {
                            if (d.pointerCount >= 2) {
                              _zoom = (_startZoom * d.scale)
                                  .clamp(.8, 2.2)
                                  .toDouble();
                            } else {
                              _yaw = (_yaw + delta.dx * .009) % (math.pi * 2);
                              _elevation = (_elevation - delta.dy * .006)
                                  .clamp(.60, 1.40)
                                  .toDouble();
                            }
                          });
                        },
                        onDoubleTap: _reset,
                        onTapUp: (d) {
                          final hit = painter.locationAt(d.localPosition);
                          if (hit != null) setState(() => _selected = hit);
                        },
                        child: RepaintBoundary(
                          child: CustomPaint(size: size, painter: painter),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.fromLTRB(12, 4, 12, 6),
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .86),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: site.color),
          ),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: site.color,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${_selected + 1}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      site.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      site.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.brown.shade400,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '全部地點',
                onPressed: _showLocations,
                icon: const Icon(Icons.format_list_numbered_rounded, size: 22),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PaintedBoardFace {
  const _PaintedBoardFace(this.path, this.depth, this.color);
  final Path path;
  final double depth;
  final Color color;
}

class IslandScenePainter3D extends CustomPainter {
  IslandScenePainter3D({
    required this.model,
    required this.camera,
    required this.sites,
    required this.pawns,
    required this.positions,
    required this.route,
    required this.selected,
    required this.activePlayerId,
    required this.magic,
    required this.accent,
    required this.showNames,
    required this.images,
    this.nextStep,
    Listenable? movement,
  }) : super(repaint: movement);
  final BoardSceneModel model;
  final BoardCamera3D camera;
  final List<BoardSite3D> sites;
  final List<BoardPawn3D> pawns;
  final Map<int, BoardPoint3> Function() positions;
  final List<BoardPoint3> route;
  final int selected, activePlayerId;
  final int? nextStep;
  final bool magic, showNames;
  final Color accent;
  final Map<String, ui.Image> images;
  final Map<int, Rect> _labelRects = {};
  final Map<String, Color> _colors = {};

  int? locationAt(Offset p) {
    for (final e in _labelRects.entries) {
      if (e.value.contains(p)) return e.key;
    }
    int? nearest;
    var distance = 24.0;
    for (var i = 0; i < route.length; i++) {
      final d =
          (camera.project(route[i] + const BoardPoint3(0, .09, 0)).screen - p)
              .distance;
      if (d < distance) {
        nearest = i;
        distance = d;
      }
    }
    return nearest;
  }

  Path _path(List<Offset> points) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    return path..close();
  }

  Color _material(String value) => _colors.putIfAbsent(
    value,
    () => Color(0xFF000000 | int.parse(value.substring(1), radix: 16)),
  );

  _PaintedBoardFace _project(
    BoardMeshFace3D face, {
    BoardPoint3 offset = const BoardPoint3(0, 0, 0),
    Color? tile,
    Color? roof,
    double scale = 1,
  }) {
    final points = face.points.map((p) => p * scale + offset).toList();
    final vertices = points.map(camera.project).toList();
    final normal = (points[1] - points[0])
        .cross(points[2] - points[0])
        .normalized;
    final luminance =
        .79 + normal.dot(const BoardPoint3(-.5, 1, -.3).normalized).abs() * .20;
    final color = face.material == 'tile'
        ? tile!
        : face.material == 'roof'
        ? roof!
        : _material(face.material);
    return _PaintedBoardFace(
      _path(vertices.map((p) => p.screen).toList()),
      vertices.fold<double>(0, (a, b) => a + b.depth) / vertices.length,
      Color.lerp(Colors.black, color, luminance)!,
    );
  }

  List<_PaintedBoardFace> _projectLayer(List<BoardMeshFace3D> faces) =>
      faces.map((f) => _project(f)).toList()
        ..sort((a, b) => a.depth.compareTo(b.depth));
  late final _clouds = _projectLayer(model.clouds);
  late final _ground = _projectLayer(model.base);
  late final _roads = _projectLayer(model.paths);
  late final List<_PaintedBoardFace> _scenery = _makeScenery();

  List<_PaintedBoardFace> _makeScenery() {
    final faces = model.decor.map((f) => _project(f)).toList();
    const taiwanRoofs = [
      Color(0xFFDC9C8F),
      Color(0xFF9BBEC2),
      Color(0xFFCBB486),
      Color(0xFF99B69F),
    ];
    const skyRoofs = [
      Color(0xFFC1ACD8),
      Color(0xFFA9C7D8),
      Color(0xFFDEAFC9),
      Color(0xFFADCFC7),
    ];
    for (var i = 0; i < route.length; i++) {
      final site = sites[i];
      final key = site.kind == 'land'
          ? 'land${site.level.clamp(0, 3)}'
          : site.kind;
      final building = model.buildings[key] ?? model.buildings['land0']!;
      final baseColor = i == selected
          ? Color.lerp(accent, Colors.white, .62)!
          : site.color;
      final roofColor = site.ownerColor == null
          ? (magic ? skyRoofs : taiwanRoofs)[i % 4]
          : Color.lerp(site.ownerColor, Colors.white, .35)!;
      faces.addAll(
        building.map(
          (f) =>
              _project(f, offset: route[i], tile: baseColor, roof: roofColor,
                scale: boardTileScale3D(i, magic: magic)),
        ),
      );
    }
    return faces..sort((a, b) => a.depth.compareTo(b.depth));
  }

  List<_PaintedBoardFace> _pawnFaces(Map<int, BoardPoint3> locations) {
    final faces = <_PaintedBoardFace>[];
    void cylinder(
      BoardPoint3 p,
      double radius,
      double height,
      double topRadius,
      Color color,
    ) {
      const n = 10;
      final bottom = List.generate(
        n,
        (i) =>
            p +
            BoardPoint3(
              math.cos(i * math.pi * 2 / n) * radius,
              0,
              math.sin(i * math.pi * 2 / n) * radius,
            ),
      );
      final top = List.generate(
        n,
        (i) =>
            p +
            BoardPoint3(
              math.cos(i * math.pi * 2 / n) * topRadius,
              height,
              math.sin(i * math.pi * 2 / n) * topRadius,
            ),
      );
      faces.add(_project(BoardMeshFace3D(top, 'tile'), tile: color));
      for (var i = 0; i < n; i++) {
        final j = (i + 1) % n;
        faces.add(
          _project(
            BoardMeshFace3D([bottom[i], bottom[j], top[j], top[i]], 'tile'),
            tile: color,
          ),
        );
      }
    }

    for (final pawn in pawns) {
      final p = locations[pawn.id];
      if (p == null) continue;
      cylinder(p, .035, .026, .035, pawn.color);
      cylinder(
        p + const BoardPoint3(0, .025, 0),
        .027,
        .071,
        .020,
        Color.lerp(pawn.color, Colors.white, .2)!,
      );
      cylinder(
        p + const BoardPoint3(0, .096, 0),
        .029,
        .038,
        .018,
        Color.lerp(pawn.color, Colors.white, .35)!,
      );
    }
    return faces;
  }

  void _drawFaces(Canvas canvas, List<_PaintedBoardFace> faces) {
    final paint = Paint();
    for (final face in faces) {
      canvas.drawPath(face.path, paint..color = face.color);
    }
  }

  TextPainter _text(
    String text,
    double size,
    Color color, {
    bool bold = false,
  }) => TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontSize: size,
        color: color,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
        height: 1.15,
      ),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();

  void _ring(Canvas canvas, int index, Color color) {
    if (index < 0 || index >= route.length) return;
    final center = route[index];
    final radius = .119 * boardTileScale3D(index, magic: magic);
    final points = List.generate(
      32,
      (i) => camera
          .project(
            center +
                BoardPoint3(
                  math.cos(i * math.pi / 16) * radius,
                  .006,
                  math.sin(i * math.pi / 16) * radius,
                ),
          )
          .screen,
    );
    canvas.drawPath(
      _path(points),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.7,
    );
  }

  void _names(Canvas canvas, Size size) {
    _labelRects.clear();
    final anchors = route
        .map((p) => camera.project(p + const BoardPoint3(0, .09, 0)).screen)
        .toList();
    final labels = List.generate(
      sites.length,
      (i) => _text(
        sites[i].name,
        9.5,
        const Color(0xFF615E58),
        bold: i == selected,
      ),
    );
    final rects = boardNameRails3D(
      anchors,
      labels.map((p) => Size(p.width + 10, p.height + 6)).toList(),
      size,
    );
    // All names fit on ordinary portrait phones. On unusually short viewports,
    // keep selection readable; the complete location list remains available.
    final allFit = rects.values.every(
      (r) => r.top >= 0 && r.bottom <= size.height,
    );
    for (var i = 0; i < sites.length; i++) {
      if ((!showNames || !allFit) && i != selected) continue;
      final anchor = anchors[i];
      if (!(Offset.zero & size).contains(anchor)) continue;
      final rect = rects[i]!;
      _labelRects[i] = rect;
      final edge = Offset(
        rect.center.dx < size.width / 2 ? rect.right : rect.left,
        rect.center.dy,
      );
      final stroke = Paint()
        ..color = i == selected
            ? accent.withValues(alpha: .85)
            : const Color(0xFF819C96).withValues(alpha: .33)
        ..strokeWidth = i == selected ? 1.2 : .65;
      canvas.drawLine(anchor, edge, stroke);
      canvas.drawCircle(
        anchor,
        i == selected ? 2.4 : 1.5,
        Paint()..color = stroke.color,
      );
    }
    for (final entry in _labelRects.entries) {
      final i = entry.key, rect = entry.value;
      final rounded = RRect.fromRectAndRadius(rect, const Radius.circular(6));
      canvas.drawRRect(
        rounded,
        Paint()
          ..color = i == selected
              ? Color.lerp(accent, Colors.white, .82)!
              : Colors.white.withValues(alpha: .87),
      );
      if (i == selected)
        canvas.drawRRect(
          rounded,
          Paint()
            ..color = accent
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
      labels[i].paint(canvas, rect.topLeft + const Offset(5, 3));
    }
    for (final label in labels) {
      label.dispose();
    }
  }

  void _portraits(Canvas canvas, Size size, Map<int, BoardPoint3> locations) {
    final occupied = <Rect>[..._labelRects.values];
    for (final pawn in pawns) {
      final point = locations[pawn.id];
      if (point == null) continue;
      final anchor = camera
          .project(point + const BoardPoint3(0, .25, 0))
          .screen;
      if (!(Offset.zero & size).inflate(10).contains(anchor)) continue;
      const diameter = 19.0, radius = diameter / 2 + 3;
      Offset clamp(Offset p) => Offset(
        p.dx.clamp(radius, math.max(radius, size.width - radius)).toDouble(),
        p.dy.clamp(radius, math.max(radius, size.height - radius)).toDouble(),
      );
      var center = clamp(anchor);
      var rect = Rect.fromCenter(
        center: center,
        width: diameter,
        height: diameter,
      );
      for (
        var attempt = 0;
        attempt < 30 && occupied.any((r) => r.inflate(2).overlaps(rect));
        attempt++
      ) {
        final column = attempt % 5 - 2, row = attempt ~/ 5 + 1;
        center = clamp(anchor + Offset(column * 24.0, -row * 23.0));
        rect = Rect.fromCenter(
          center: center,
          width: diameter,
          height: diameter,
        );
      }
      occupied.add(rect);
      if ((center - anchor).distance > 2)
        canvas.drawLine(
          anchor,
          center,
          Paint()
            ..color = pawn.color.withValues(alpha: .55)
            ..strokeWidth = .8,
        );
      canvas.drawCircle(
        center,
        diameter / 2 + 1.5,
        Paint()..color = Colors.white,
      );
      canvas.drawCircle(
        center,
        diameter / 2 + 1.5,
        Paint()
          ..color = pawn.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = pawn.id == activePlayerId ? 2 : 1,
      );
      final image = images[pawn.imagePath];
      if (image != null) {
        canvas.save();
        canvas.clipPath(Path()..addOval(rect));
        final fitted = applyBoxFit(
          BoxFit.contain,
          Size(image.width.toDouble(), image.height.toDouble()),
          rect.size,
        );
        final source = Alignment.center.inscribe(
          fitted.source,
          Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        );
        canvas.drawImageRect(
          image,
          source,
          Alignment.center.inscribe(fitted.destination, rect),
          Paint(),
        );
        canvas.restore();
      } else {
        final text = _text(
          pawn.emoji ?? (pawn.id == 0 ? '🐾' : '●'),
          diameter * .72,
          pawn.color,
        );
        text.paint(canvas, center - Offset(text.width / 2, text.height / 2));
        text.dispose();
      }
    }
  }

  void _compass(Canvas canvas, Size size) {
    final origin = camera.project(const BoardPoint3(0, .12, 0)).screen;
    final north = camera.project(const BoardPoint3(0, .12, -1)).screen - origin;
    if (north.distance < .01) return;
    final direction = north / north.distance;
    final center = Offset(size.width / 2, 23);
    canvas.drawCircle(center, 19, Paint()..color = Colors.white.withValues(alpha: .88));
    canvas.drawLine(center + direction * 3, center + direction * 13,
      Paint()..color = const Color(0xFFB77D74)..strokeWidth = 2..strokeCap = StrokeCap.round);
    final tip = center + direction * 13;
    final side = Offset(-direction.dy, direction.dx);
    canvas.drawPath(Path()..moveTo(tip.dx, tip.dy)
      ..lineTo((tip - direction * 5 + side * 3).dx, (tip - direction * 5 + side * 3).dy)
      ..lineTo((tip - direction * 5 - side * 3).dx, (tip - direction * 5 - side * 3).dy)..close(),
      Paint()..color = const Color(0xFFB77D74));
    final label = _text('北', 9, const Color(0xFF615E58), bold: true);
    final at = center - direction * 7;
    label.paint(canvas, at - Offset(label.width / 2, label.height / 2));
    label.dispose();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final locations = positions();
    _drawFaces(canvas, _clouds);
    _drawFaces(canvas, _ground);
    _drawFaces(canvas, _roads);
    if (nextStep != null) _ring(canvas, nextStep!, const Color(0xFFE5AE60));
    _ring(canvas, selected, accent);
    final pieces = [..._scenery, ..._pawnFaces(locations)]
      ..sort((a, b) => a.depth.compareTo(b.depth));
    _drawFaces(canvas, pieces);
    _names(canvas, size);
    _portraits(canvas, size, locations);
    if (!magic) _compass(canvas, size);
  }

  @override
  bool shouldRepaint(covariant IslandScenePainter3D oldDelegate) => true;
}
