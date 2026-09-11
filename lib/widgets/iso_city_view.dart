import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'package:user_interface/widgets/city_expense_carousel.dart' show CategoryExpense;

/// ---------------------------------------------------------------------------
/// 花費城市（等距 / isometric 版）
///
/// 一個類別一棟房子，金額每翻一倍就長高一層，跨過門檻換屋頂樣式。
/// 素材：Kenney「Isometric Tiles City」+「Isometric Tiles Buildings」(CC0，商用免標示)
///
/// 疊法（Kenney 這套模組的固定規格）：
///   一樓底座 b_base_*（132px 寬，自帶地磚）
///   → 中段樓層 b_mid_*（99px 寬，每層往上 34px）
///   → 屋頂 b_roof*
///
/// 每張圖用「圖片底邊往上 anchor 像素」這一點對齊菱形中心，anchor 見 _kAnchor。
/// 畫之前一定要照 gx + gy 由小到大排序，後面的先畫，遮擋才會正確。
/// ---------------------------------------------------------------------------

/// 金額 → 樓層：每翻一倍 +1 層，150 元起蓋，封頂 9 層。
///
/// 刻意用「絕對金額」而不是佔總額的比例：佔比會讓總支出變高時，
/// 每一棟房子反而變矮，兩個月之間就沒辦法比較了。
int isoFloorsFor(double amount) {
  if (amount <= 0) return 0;
  return (1 + (math.log(amount / 150) / math.ln2).floor()).clamp(1, 9);
}

const double _kTileW = 132; // 地磚菱形寬
const double _kTileH = 66; // 地磚菱形高（2:1）
const double _kFloorH = 34; // 一層樓的像素高度
const int _kMaxPlots = 24; // 安全上限，正常不會碰到
const double _kBodyAnchor = 26; // 中段樓層與所有屋頂共用的錨點

/// 每張圖的錨點（圖片底邊 → 對齊點的距離，單位 px）。
/// 這些數字是從 PNG 的 alpha 邊界量出來的，換圖就要重量。
const Map<String, double> _kAnchor = {
  't_pave': 66,
  't_road_gy': 66,
  't_road_gx': 69,
  't_road_cross': 69,
  't_hedge': 68,
  't_tree': 68,
  't_lamp_a': 69,
  't_lamp_b': 69,
  'b_base_0': 68,
  'b_base_1': 68,
  'b_base_2': 68,
  'b_base_3': 69,
  'b_base_4': 69,
  'b_base_5': 68,
  'b_base_6': 68,
  'b_base_7': 68,
};

/// 街區的尺寸與地塊位置。街區會跟著類別數量長大。
///
/// 城市是由一個個 2x2 的「街廓」拼出來的，街廓之間的第 3 格永遠是馬路
/// （`gx % 3 == 2` 或 `gy % 3 == 2`）。一個街廓蓋 2 棟房子，取對角線上的兩格，
/// 這樣同一個街廓的兩棟深度相同、並排不互相遮擋。
class _IsoLayout {
  const _IsoLayout(this.gxMax, this.gyMax, this.plots);

  final int gxMax;
  final int gyMax;

  /// 依金額排名對應的格子，由後往前。第 0 個是最花錢的類別。
  final List<List<int>> plots;
}

_IsoLayout isoLayoutFor(int categories) {
  // 最少 2x2 個街廓（＝ 5x5 的街區），之後每多 2 個類別就多蓋一個街廓
  final blocks = math.max(4, (categories + 1) ~/ 2);
  final cols = math.sqrt(blocks).ceil();
  final rows = (blocks + cols - 1) ~/ cols;

  final order = <List<int>>[];
  for (var by = 0; by < rows; by++) {
    for (var bx = 0; bx < cols; bx++) {
      order.add(<int>[bx, by]);
    }
  }
  // 由後往前：金額最大＝樓最高，蓋在最後排才不會擋住別人
  order.sort((a, b) {
    final d = (a[0] + a[1]).compareTo(b[0] + b[1]);
    return d != 0 ? d : a[0].compareTo(b[0]);
  });

  final plots = <List<int>>[];
  for (final b in order) {
    plots.add(<int>[b[0] * 3 + 1, b[1] * 3]);
    plots.add(<int>[b[0] * 3, b[1] * 3 + 1]);
  }
  return _IsoLayout(cols * 3 - 2, rows * 3 - 2, plots);
}

/// 沒蓋房子的格子放什麼：馬路、行道樹、草皮、路燈。
String isoGroundKey(int gx, int gy) {
  final roadX = gx % 3 == 2;
  final roadY = gy % 3 == 2;
  if (roadX && roadY) return 't_road_cross';
  if (roadX) return 't_road_gy';
  if (roadY) return 't_road_gx';
  if (gx % 3 == 0 && gy % 3 == 0) return 't_tree';
  if (gx % 3 == 1 && gy % 3 == 1) {
    return (gx ~/ 3 + gy ~/ 3).isEven ? 't_hedge' : 't_lamp_a';
  }
  // 還沒被用到的建地
  return (gx + gy) % 3 == 0 ? 't_tree' : 't_pave';
}

double _anchorOf(String key) => _kAnchor[key] ?? _kBodyAnchor;

/// 類別名稱 → 建築外觀編號（0..7）。用自己算的雜湊，確保每次啟動都一樣。
int isoStyleFor(String name) {
  var h = 0;
  for (final unit in name.codeUnits) {
    h = (h * 31 + unit) & 0x7fffffff;
  }
  return h % 8;
}

Offset _isoPoint(num gx, num gy, double originX, double originY) => Offset(
      originX + (gx - gy) * _kTileW / 2,
      originY + (gx + gy) * _kTileH / 2,
    );

String _roofKey(int floors, int style) {
  if (floors <= 1) return 'b_roof1_$style'; // 一層樓：斜屋頂小屋
  if (floors <= 3) return 'b_roof_a'; // 街屋：平屋頂
  if (floors <= 5) return 'b_roof_b'; // 公寓
  if (floors <= 7) return 'b_roof_c'; // 大樓：屋頂加設備
  return 'b_roof_d'; // 地標：屋突 + 水塔
}

// ---------------------------------------------------------------------------
// 貼圖載入（整個 App 只載一次）
// ---------------------------------------------------------------------------

class IsoAtlas {
  const IsoAtlas(this.images);

  final Map<String, ui.Image> images;

  static Future<IsoAtlas>? _pending;

  static Future<IsoAtlas> load() => _pending ??= _loadAll();

  static Future<IsoAtlas> _loadAll() async {
    final keys = <String>[
      't_pave',
      't_road_gy',
      't_road_gx',
      't_road_cross',
      't_hedge',
      't_tree',
      't_lamp_a',
      't_lamp_b',
      'b_roof_a',
      'b_roof_b',
      'b_roof_c',
      'b_roof_d',
      for (var i = 0; i < 8; i++) 'b_base_$i',
      for (var i = 0; i < 8; i++) 'b_mid_$i',
      for (var i = 0; i < 8; i++) 'b_roof1_$i',
    ];
    final out = <String, ui.Image>{};
    for (final k in keys) {
      final data = await rootBundle.load('assets/iso/$k.png');
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      out[k] = frame.image;
    }
    return IsoAtlas(out);
  }
}

// ---------------------------------------------------------------------------
// Widget
// ---------------------------------------------------------------------------

class IsoCityView extends StatefulWidget {
  const IsoCityView({
    super.key,
    required this.expenses,
    this.onTapCategory,
    this.showLabels = true,
  });

  /// 直接沿用 CityExpenseCarousel 的資料型別，home_page 那段不用改。
  final List<CategoryExpense> expenses;
  final ValueChanged<CategoryExpense>? onTapCategory;
  final bool showLabels;

  @override
  State<IsoCityView> createState() => _IsoCityViewState();
}

class _IsoCityViewState extends State<IsoCityView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late Future<IsoAtlas> _atlas;

  Map<String, double> _from = <String, double>{};
  Map<String, double> _to = <String, double>{};
  int? _selected;

  /// 沒有任何花費時就是一塊空地：只鋪馬路、人行道和綠地，不蓋房子。
  List<CategoryExpense> get _items {
    final list = List<CategoryExpense>.from(widget.expenses)
      ..sort((a, b) => b.amount.compareTo(a.amount));
    return list.length > _kMaxPlots ? list.sublist(0, _kMaxPlots) : list;
  }

  @override
  void initState() {
    super.initState();
    _atlas = IsoAtlas.load();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _to = <String, double>{
      for (final e in _items) e.id: isoFloorsFor(e.amount).toDouble(),
    };
    _from = <String, double>{for (final k in _to.keys) k: 0};
    _ctrl.forward();
  }

  @override
  void didUpdateWidget(covariant IsoCityView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = <String, double>{
      for (final e in _items) e.id: isoFloorsFor(e.amount).toDouble(),
    };
    final changed = next.length != _to.length ||
        next.entries.any((e) => _to[e.key] != e.value);
    if (!changed) return;
    final t = Curves.easeOutCubic.transform(_ctrl.value);
    _from = <String, double>{
      for (final k in next.keys)
        k: ui.lerpDouble(_from[k] ?? 0, _to[k] ?? 0, t) ?? 0,
    };
    _to = next;
    _ctrl.forward(from: 0);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _handleTap(
    Offset local,
    double scale,
    _IsoLayout layout,
    double originX,
    double originY,
  ) {
    final world = local / scale;
    final items = _items;
    for (var i = items.length - 1; i >= 0; i--) {
      if (i >= layout.plots.length) continue;
      final p = _isoPoint(
          layout.plots[i][0], layout.plots[i][1], originX, originY);
      final floors = isoFloorsFor(items[i].amount);
      final rect = Rect.fromLTRB(
        p.dx - 52,
        p.dy - _kFloorH * floors - 46,
        p.dx + 52,
        p.dy + 32,
      );
      if (rect.contains(world)) {
        setState(() => _selected = _selected == i ? null : i);
        widget.onTapCategory?.call(items[i]);
        return;
      }
    }
    setState(() => _selected = null);
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    var maxFloors = 3;
    for (final e in items) {
      maxFloors = math.max(maxFloors, isoFloorsFor(e.amount));
    }
    final layout = isoLayoutFor(items.length);
    // 依街區實際大小算出繪圖用的邏輯畫布，再等比縮放到 widget 寬度
    final minX = -(layout.gyMax * _kTileW / 2) - _kTileW / 2;
    final maxX = layout.gxMax * _kTileW / 2 + _kTileW / 2;
    final worldW = maxX - minX + 40;
    final originX = -minX + 20;
    final originY = 44 + _kFloorH * maxFloors;
    final worldH =
        originY + (layout.gxMax + layout.gyMax) * _kTileH / 2 + 76;

    return FutureBuilder<IsoAtlas>(
      future: _atlas,
      builder: (context, snap) {
        return LayoutBuilder(
          builder: (context, box) {
            final w = box.maxWidth;
            final scale = w / worldW;
            final h = worldH * scale;
            if (!snap.hasData) {
              return SizedBox(
                height: h,
                child: const Center(child: CircularProgressIndicator()),
              );
            }
            return SizedBox(
              width: w,
              height: h,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => _handleTap(
                    d.localPosition, scale, layout, originX, originY),
                child: AnimatedBuilder(
                  animation: _ctrl,
                  builder: (context, _) {
                    final t = Curves.easeOutCubic.transform(_ctrl.value);
                    final floors = <int>[
                      for (final e in items)
                        (ui.lerpDouble(_from[e.id] ?? 0, _to[e.id] ?? 0, t) ??
                                0)
                            .round(),
                    ];
                    return CustomPaint(
                      size: Size(w, h),
                      painter: _CityPainter(
                        images: snap.data!.images,
                        items: items,
                        floors: floors,
                        selected: _selected,
                        layout: layout,
                        worldW: worldW,
                        originX: originX,
                        originY: originY,
                        showLabels: widget.showLabels,
                      ),
                    );
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Painter
// ---------------------------------------------------------------------------

class _CityPainter extends CustomPainter {
  _CityPainter({
    required this.images,
    required this.items,
    required this.floors,
    required this.selected,
    required this.layout,
    required this.worldW,
    required this.originX,
    required this.originY,
    required this.showLabels,
  });

  final Map<String, ui.Image> images;
  final List<CategoryExpense> items;
  final List<int> floors;
  final int? selected;
  final _IsoLayout layout;
  final double worldW;
  final double originX;
  final double originY;
  final bool showLabels;

  final Paint _p = Paint()..filterQuality = FilterQuality.medium;

  void _blit(Canvas c, String key, Offset at) {
    final im = images[key];
    if (im == null) return;
    c.drawImage(
      im,
      Offset(at.dx - im.width / 2, at.dy + _anchorOf(key) - im.height),
      _p,
    );
  }

  void _drawBuilding(Canvas c, int index, Offset at) {
    final n = floors[index];
    if (n <= 0) {
      _blit(c, 't_pave', at);
      return;
    }
    final style = isoStyleFor(items[index].id);
    _blit(c, 'b_base_$style', at);
    for (var k = 1; k < n; k++) {
      _blit(c, 'b_mid_$style', Offset(at.dx, at.dy - _kFloorH * k));
    }
    _blit(c, _roofKey(n, style), Offset(at.dx, at.dy - _kFloorH * n));
  }

  void _drawSelection(Canvas c, Offset at, Color color) {
    final path = Path()
      ..moveTo(at.dx - _kTileW / 2 + 6, at.dy)
      ..lineTo(at.dx, at.dy - _kTileH / 2 + 3)
      ..lineTo(at.dx + _kTileW / 2 - 6, at.dy)
      ..lineTo(at.dx, at.dy + _kTileH / 2 - 3)
      ..close();
    c.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = color,
    );
  }

  void _drawLabel(Canvas c, Offset at, CategoryExpense e, int n) {
    final tp = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      text: TextSpan(
        children: <InlineSpan>[
          TextSpan(
            text: '${e.name}\n',
            style: const TextStyle(
              fontSize: 15,
              height: 1.25,
              fontWeight: FontWeight.w600,
              color: Color(0xFF37474F),
            ),
          ),
          TextSpan(
            text: n == 0
                ? '空地'
                : 'NT\$${e.amount.round()}・${n}F',
            style: const TextStyle(
              fontSize: 13,
              height: 1.25,
              color: Color(0xFF78909C),
            ),
          ),
        ],
      ),
    )..layout(maxWidth: 150);
    final origin = Offset(at.dx - tp.width / 2, at.dy + 26);
    final bg = RRect.fromRectAndRadius(
      Rect.fromLTWH(origin.dx - 8, origin.dy - 4, tp.width + 16, tp.height + 8),
      const Radius.circular(9),
    );
    c.drawRRect(bg, Paint()..color = Colors.white.withOpacity(0.82));
    tp.paint(c, origin);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / worldW;
    canvas.save();
    canvas.scale(scale);

    final plotOf = <String, int>{};
    for (var i = 0; i < items.length && i < layout.plots.length; i++) {
      plotOf['${layout.plots[i][0]},${layout.plots[i][1]}'] = i;
    }

    final cells = <List<int>>[];
    for (var gx = 0; gx <= layout.gxMax; gx++) {
      for (var gy = 0; gy <= layout.gyMax; gy++) {
        cells.add(<int>[gx, gy]);
      }
    }
    // 一定要由後往前畫，否則前排的房子會被後排蓋掉
    cells.sort((a, b) => (a[0] + a[1]).compareTo(b[0] + b[1]));

    for (final cell in cells) {
      final at = _isoPoint(cell[0], cell[1], originX, originY);
      final idx = plotOf['${cell[0]},${cell[1]}'];
      if (idx == null) {
        _blit(canvas, isoGroundKey(cell[0], cell[1]), at);
      } else {
        if (idx == selected) _drawSelection(canvas, at, items[idx].baseColor);
        _drawBuilding(canvas, idx, at);
      }
    }

    if (showLabels) {
      for (var i = 0; i < items.length && i < layout.plots.length; i++) {
        final at = _isoPoint(
            layout.plots[i][0], layout.plots[i][1], originX, originY);
        _drawLabel(canvas, at, items[i], floors[i]);
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CityPainter old) =>
      old.items != items ||
      !_sameInts(old.floors, floors) ||
      old.selected != selected ||
      old.originY != originY ||
      old.originX != originX ||
      old.worldW != worldW;

  static bool _sameInts(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
