import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../services/solar_time_service.dart';

/// ==========================================================
/// 資料模型：單一消費類別
/// 未來接後端時，直接把 CityExpenseCarousel 的 expensesFuture
/// 換成呼叫 FastAPI 的 http.get(...).then((res) => ... ) 即可，
/// 不需要更動這個 Widget 內部的任何邏輯。
/// ==========================================================
class CategoryExpense {
  final String id;
  final String name;
  final double amount; // 本月已花費
  final double budget; // 該類別預算上限
  final Color baseColor; // 該類別主題色

  const CategoryExpense({
    required this.id,
    required this.name,
    required this.amount,
    required this.budget,
    required this.baseColor,
  });

  /// 超支警告不是單看「花費是否超過預算」，而是比較「時間進度」跟「花費節奏」：
  /// 若 本月已過天數/本月總天數 < (花費 * 120%) / 預算，代表照這個花錢速度，月底前一定會爆表。
  /// budget <= 0（使用者沒有為這個類別設定預算）時完全不檢查，不會顯示警告。
  bool get isOverBudget {
    if (budget <= 0) return false;
    final now = DateTime.now();
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final dayRatio = now.day / daysInMonth;
    final paceRatio = (amount * 1.2) / budget;
    return dayRatio < paceRatio;
  }
}

/// ==========================================================
/// 記帳城市輪播（Accounting City Carousel）
/// 用「公寓大樓」呈現本月各消費類別的佔比與超支狀態
/// ==========================================================
class CityExpenseCarousel extends StatefulWidget {
  /// 之後接後端時傳入真正的 API Future；不傳則使用內建假資料。
  final Future<List<CategoryExpense>>? expensesFuture;

  const CityExpenseCarousel({super.key, this.expensesFuture});

  @override
  State<CityExpenseCarousel> createState() => _CityExpenseCarouselState();
}

class _CityExpenseCarouselState extends State<CityExpenseCarousel> {
  static const double _itemWidth = 104; // 每棟建築的卡片寬度：夠緊湊，同時能完整看到好幾棟
  static const int _maxFloors = 6;
  static const double _carouselHeight = 260;

  // 抓不到定位（沒開權限、模擬器沒有定位服務…）時的預設地點：台北。
  // 這樣太陽/月亮還是會依照台北的日出日落時間跑，不會整個功能就沒作用。
  static const double _fallbackLat = 25.0330;
  static const double _fallbackLon = 121.5654;

  late Future<List<CategoryExpense>> _future;

  double? _latitude;
  double? _longitude;
  SkyState? _skyState;
  Timer? _skyTimer;

  @override
  void initState() {
    super.initState();
    _future = widget.expensesFuture ?? _fetchMockExpenses();
    _initSky();
  }

  Future<void> _initSky() async {
    final position = await _resolveLocationSafely();
    _latitude = position?.latitude ?? _fallbackLat;
    _longitude = position?.longitude ?? _fallbackLon;
    _refreshSkyState();
    // 每 2 分鐘重算一次，讓太陽/月亮的位置持續跟著現在的時間慢慢移動。
    _skyTimer = Timer.periodic(const Duration(minutes: 2), (_) => _refreshSkyState());
  }

  void _refreshSkyState() {
    if (!mounted || _latitude == null || _longitude == null) return;
    final sky = SolarTimeService.skyStateFor(DateTime.now(), _latitude!, _longitude!);
    setState(() => _skyState = sky);
  }

  Future<Position?> _resolveLocationSafely() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        return null;
      }
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.low),
      ).timeout(const Duration(seconds: 6));
    } catch (_) {
      return null;
    }
  }

  @override
  void didUpdateWidget(covariant CityExpenseCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 呼叫端（例如 home_page）每次資料變動都會傳入一個新的 Future；
    // 沒有這段，State 會一直沿用 initState 當下抓到的第一份資料，畫面就永遠不會更新。
    if (widget.expensesFuture != oldWidget.expensesFuture) {
      _future = widget.expensesFuture ?? _fetchMockExpenses();
    }
  }

  @override
  void dispose() {
    _skyTimer?.cancel();
    super.dispose();
  }

  /// ===== 假資料：先用固定的 4 個類別撐住畫面，之後直接換成 API 呼叫 =====
  Future<List<CategoryExpense>> _fetchMockExpenses() async {
    await Future.delayed(const Duration(milliseconds: 300));
    return const [
      CategoryExpense(id: 'food', name: '飲食', amount: 3200, budget: 3000, baseColor: Color(0xFFFF8A65)),
      CategoryExpense(id: 'transport', name: '交通', amount: 500, budget: 2000, baseColor: Color(0xFF4FC3F7)),
      CategoryExpense(id: 'entertainment', name: '娛樂', amount: 1800, budget: 1500, baseColor: Color(0xFFBA68C8)),
      CategoryExpense(id: 'daily', name: '生活用品', amount: 600, budget: 2000, baseColor: Color(0xFF81C784)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<CategoryExpense>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox(
            height: _carouselHeight,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return SizedBox(
            height: _carouselHeight,
            child: Center(
              child: Text(
                '城市資料載入失敗\n請稍後再試',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade500),
              ),
            ),
          );
        }

        final expenses = snapshot.data ?? const [];
        if (expenses.isEmpty) {
          return SizedBox(
            height: _carouselHeight,
            child: Center(
              child: Text('本月尚無消費紀錄', style: TextStyle(color: Colors.grey.shade500)),
            ),
          );
        }

        final totalAmount = expenses.fold<double>(0.0, (sum, e) => sum + e.amount);

        return SizedBox(
          height: _carouselHeight,
          child: Stack(
            children: [
              Positioned.fill(child: _CityBackground(skyState: _skyState)),
              // 一般水平捲動列表：一次可以看到好幾棟完整的建築，緊緊排在一起，
              // 不像輪播那樣強迫畫面正中央一次只有一棟房子清楚。
              ListView.builder(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                itemCount: expenses.length,
                itemBuilder: (context, index) {
                  return SizedBox(
                    width: _itemWidth,
                    child: _CityBuildingCard(
                      expense: expenses[index],
                      totalAmount: totalAmount,
                      maxFloors: _maxFloors,
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 單一棟公寓 + 底下的名稱／金額／百分比資訊
class _CityBuildingCard extends StatelessWidget {
  final CategoryExpense expense;
  final double totalAmount;
  final int maxFloors;

  const _CityBuildingCard({
    required this.expense,
    required this.totalAmount,
    required this.maxFloors,
  });

  double get _percentage => totalAmount <= 0 ? 0.0 : (expense.amount / totalAmount) * 100;

  int get _floors {
    if (expense.amount <= 0) return 0;
    final ratio = (_percentage / 100).clamp(0.0, 1.0);
    final f = (ratio * maxFloors).round();
    return f.clamp(1, maxFloors);
  }

  @override
  Widget build(BuildContext context) {
    final textColor = Color.lerp(expense.baseColor, Colors.black, 0.35)!;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        mainAxisSize: MainAxisSize.max,
        children: [
          Expanded(
            child: Stack(
              alignment: Alignment.bottomCenter,
              clipBehavior: Clip.none,
              children: [
                _ApartmentBuilding(color: expense.baseColor, floors: _floors),
                if (expense.isOverBudget)
                  const Positioned(top: -4, child: _OverBudgetBadge()),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            expense.name,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: textColor),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            '\$${expense.amount.toStringAsFixed(0)} (${_percentage.toStringAsFixed(0)}%)',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}

/// 公寓大樓本體：屋頂（CustomPaint）＋ 逐層窗戶（Container 組合）＋ 底座
class _ApartmentBuilding extends StatelessWidget {
  final Color color;
  final int floors; // 0 代表沒有花費，只留底座

  const _ApartmentBuilding({required this.color, required this.floors});

  static const double _buildingWidth = 76;
  static const double _floorHeight = 24;

  @override
  Widget build(BuildContext context) {
    if (floors <= 0) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.grass_rounded, size: 22, color: color.withOpacity(0.55)),
          const SizedBox(height: 6),
          _base(),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CustomPaint(
          size: const Size(_buildingWidth, 20),
          painter: _RoofPainter(color: Color.lerp(color, Colors.black, 0.25)!),
        ),
        ...List.generate(floors, (i) => _floorRow(i)),
        _base(),
      ],
    );
  }

  Widget _floorRow(int index) {
    final floorColor = Color.lerp(color, Colors.white, index.isEven ? 0.0 : 0.08)!;
    return Container(
      width: _buildingWidth,
      height: _floorHeight,
      margin: const EdgeInsets.only(top: 1),
      decoration: BoxDecoration(
        color: floorColor,
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.25))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(3, (_) => _window()),
      ),
    );
  }

  Widget _window() {
    return Container(
      width: 11,
      height: 13,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.85),
        borderRadius: BorderRadius.circular(2),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 1, offset: Offset(0, 1))],
      ),
    );
  }

  Widget _base() {
    return Container(
      width: _buildingWidth + 14,
      height: 12,
      decoration: BoxDecoration(
        color: Color.lerp(color, Colors.black, 0.35),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(5)),
      ),
    );
  }
}

class _RoofPainter extends CustomPainter {
  final Color color;
  const _RoofPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(-4, size.height)
      ..lineTo(size.width / 2, 0)
      ..lineTo(size.width + 4, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _RoofPainter oldDelegate) => oldDelegate.color != color;
}

/// 超支警示標籤：懸浮在屋頂上方
class _OverBudgetBadge extends StatelessWidget {
  const _OverBudgetBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.redAccent,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.red.withOpacity(0.4), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.warning_rounded, color: Colors.white, size: 12),
          SizedBox(width: 2),
          Text('超支', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

/// ==========================================================
/// 城市場景背景：天空（依日出日落漸層變色）＋ 太陽/月亮（跟著真實時間移動）
/// ＋ 遠景天際線剪影 ＋ 貫穿全寬的地面道路，讓所有建築像站在同一座城市裡。
/// ==========================================================
class _CityBackground extends StatelessWidget {
  final SkyState? skyState;

  const _CityBackground({required this.skyState});

  static const double _groundHeight = 10;
  static const double _groundBottom = 44; // 大約對齊每棟建築自己的底座位置
  static const double _skylineHeight = 64;

  @override
  Widget build(BuildContext context) {
    final isDaytime = skyState?.isDaytime ?? true;
    final progress = skyState?.progress ?? 0.5;

    final skyTop = isDaytime ? const Color(0xFFAEE1FF) : const Color(0xFF1B2452);
    final skyBottom = isDaytime ? const Color(0xFFFFF0D6) : const Color(0xFF3B4A7A);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final skylineBottom = _groundBottom + _groundHeight;
        final sunAreaHeight = (height - skylineBottom - _skylineHeight).clamp(30.0, height);

        // 用 sin 曲線畫弧：progress 0/1 在地平線，0.5（正中午或半夜）最高。
        final arcHeight = math.sin((progress.clamp(0.0, 1.0)) * math.pi);
        const glyphSize = 30.0;
        final sunX = (glyphSize / 2) + (width - glyphSize) * progress.clamp(0.0, 1.0);
        final sunY = (sunAreaHeight * 0.92) - (sunAreaHeight * 0.68 * arcHeight);

        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [skyTop, skyBottom],
                ),
              ),
            ),
            if (!isDaytime)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: sunAreaHeight,
                child: CustomPaint(painter: _StarsPainter()),
              ),
            if (skyState != null)
              Positioned(
                left: sunX - glyphSize / 2,
                top: sunY - glyphSize / 2,
                child: isDaytime ? const _SunGlyph() : const _MoonGlyph(),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: skylineBottom,
              height: _skylineHeight,
              child: CustomPaint(painter: _DistantSkylinePainter(isDaytime: isDaytime)),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: _groundBottom,
              height: _groundHeight,
              child: _GroundStrip(isDaytime: isDaytime),
            ),
          ],
        );
      },
    );
  }
}

class _SunGlyph extends StatelessWidget {
  const _SunGlyph();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(colors: [Color(0xFFFFF59D), Color(0xFFFFA726)]),
        boxShadow: [BoxShadow(color: Colors.orange.withOpacity(0.55), blurRadius: 18, spreadRadius: 4)],
      ),
    );
  }
}

class _MoonGlyph extends StatelessWidget {
  const _MoonGlyph();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFFF5F3E7),
        boxShadow: [BoxShadow(color: Colors.white.withOpacity(0.35), blurRadius: 14, spreadRadius: 2)],
      ),
      child: CustomPaint(painter: _MoonCraterPainter()),
    );
  }
}

class _MoonCraterPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFFDCD6C0);
    canvas.drawCircle(Offset(size.width * 0.35, size.height * 0.4), size.width * 0.12, paint);
    canvas.drawCircle(Offset(size.width * 0.66, size.height * 0.62), size.width * 0.09, paint);
    canvas.drawCircle(Offset(size.width * 0.5, size.height * 0.22), size.width * 0.06, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _StarsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(7); // 固定種子：星星位置每次重繪都一樣，不會閃爍亂跳
    final paint = Paint()..color = Colors.white.withOpacity(0.85);
    for (int i = 0; i < 22; i++) {
      final dx = rng.nextDouble() * size.width;
      final dy = rng.nextDouble() * size.height * 0.85;
      canvas.drawCircle(Offset(dx, dy), rng.nextDouble() * 1.1 + 0.4, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 遠景天際線剪影：跟真實資料無關，純粹讓城市看起來有密度、不是只有主建築孤零零地飄著。
class _DistantSkylinePainter extends CustomPainter {
  final bool isDaytime;
  const _DistantSkylinePainter({required this.isDaytime});

  @override
  void paint(Canvas canvas, Size size) {
    final color = isDaytime
        ? const Color(0xFF9FB8CE).withOpacity(0.55)
        : const Color(0xFF12173A).withOpacity(0.85);
    final paint = Paint()..color = color;
    final rng = math.Random(99); // 固定種子：天際線形狀每次重繪保持一致
    double x = 0;
    while (x < size.width) {
      final w = 16 + rng.nextDouble() * 20;
      final h = size.height * (0.35 + rng.nextDouble() * 0.65);
      canvas.drawRect(Rect.fromLTWH(x, size.height - h, w, h), paint);
      x += w + 3;
    }
  }

  @override
  bool shouldRepaint(covariant _DistantSkylinePainter oldDelegate) => oldDelegate.isDaytime != isDaytime;
}

/// 貫穿全寬的地面道路：讓每一棟建築看起來站在「同一條路」上，而不是各自浮在半空中。
class _GroundStrip extends StatelessWidget {
  final bool isDaytime;
  const _GroundStrip({required this.isDaytime});

  @override
  Widget build(BuildContext context) {
    final base = isDaytime ? const Color(0xFFC9BFAE) : const Color(0xFF2B2E42);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: base,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 3, offset: const Offset(0, -1))],
      ),
      child: CustomPaint(painter: _RoadLinePainter(color: Colors.white.withOpacity(0.5))),
    );
  }
}

class _RoadLinePainter extends CustomPainter {
  final Color color;
  const _RoadLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    double x = 4;
    final y = size.height / 2;
    while (x < size.width) {
      canvas.drawLine(Offset(x, y), Offset(x + 10, y), paint);
      x += 18;
    }
  }

  @override
  bool shouldRepaint(covariant _RoadLinePainter oldDelegate) => false;
}
