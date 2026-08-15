import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:user_interface/services/game_api_service.dart';
import 'mission_page.dart'; // ★ 合併自朋友版：任務中心入口

class GachaPage extends StatefulWidget {
  const GachaPage({super.key});

  @override
  State<GachaPage> createState() => _GachaPageState();
}

class _GachaPageState extends State<GachaPage> with TickerProviderStateMixin {
  late AnimationController _rollController;
  late AnimationController _dropController;
  bool _isRolling = false;
  int _userCoins = 1700;

  // 本地抽獎池（weight 總和 = 1000，對應百分比 × 10）
  // ★ 依手寫標註(A)更新：銘謝惠顧 50%、狗狗/貓咪各 12%、鸚鵡 5%/樹懶 4%/狐狸 4%、
  //   稀有(柴柴/博美/諾姆/甩尾)各 2%、稀有(愛心/工作/等待/火箭)各 1%、傳說 0.5/0.3/0.2%
  static const List<Map<String, dynamic>> _gachaPool = [
    {'key': null,          'name': '銘謝惠顧', 'weight': 500},
    {'key': 'dog',         'name': '狗狗',     'weight': 120},
    {'key': 'cat',         'name': '貓咪',     'weight': 120},
    {'key': 'parrot',      'name': '鸚鵡',     'weight': 50},
    {'key': 'sloth',       'name': '樹懶',     'weight': 40},
    {'key': 'fox',         'name': '狐狸',     'weight': 40},
    {'key': 'cute_dog',    'name': '柴柴',     'weight': 20},
    {'key': 'pomeranian',  'name': '博美犬',   'weight': 20},
    {'key': 'norm_dog',    'name': '諾姆犬',   'weight': 20},
    {'key': 'wagging_dog', 'name': '甩尾狗',   'weight': 20},
    {'key': 'lovely_cat',  'name': '愛心貓',   'weight': 10},
    {'key': 'blue_cat',    'name': '工作貓',   'weight': 10},
    {'key': 'loader_cat',  'name': '等待貓',   'weight': 10},
    {'key': 'rocket_cat',  'name': '火箭貓',   'weight': 10},
    {'key': 'bear',        'name': '熊熊',     'weight': 5},
    {'key': 'bee',         'name': '蜜蜂',     'weight': 3},
    {'key': 'giraffe',     'name': '長頸鹿',   'weight': 2},
  ];

  List<Offset> _capsulePositions = [];
  final double _globeRadius = 90.0;

  @override
  void initState() {
    super.initState();
    _rollController = AnimationController(vsync: this, duration: const Duration(milliseconds: 100))
      ..addListener(() { if (_isRolling) _updateCapsulePhysics(); });
    _dropController = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _initCapsules();
    _loadCoins();
  }

  Future<void> _loadCoins() async {
    try {
      // ★ 合併自朋友版：硬幣來源改讀獎勵錢包的「扭蛋幣」，不再混用大富翁 money。
      final wallet = await GameApiService.instance.fetchRewardWallet();
      final coins = int.tryParse(wallet['gacha_coins']?.toString() ?? '') ?? 0;
      if (!mounted) return;
      setState(() => _userCoins = coins);
    } catch (_) {
      // API 尚未啟動時保留目前畫面（預設幣數），斷線仍可本地抽獎。
    }
  }

  // ★ 合併自朋友版：到任務中心領取扭蛋幣，回來重新讀一次錢包。
  Future<void> _openMissions() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MissionPage()),
    );
    await _loadCoins();
  }

  void _initCapsules() {
    final rng = Random();
    _capsulePositions = List.generate(16, (index) {
      double angle = rng.nextDouble() * 2 * pi;
      double r = rng.nextDouble() * (_globeRadius - 20);
      return Offset(r * cos(angle), r * sin(angle));
    });
  }

  void _updateCapsulePhysics() {
    setState(() {
      final rng = Random();
      for (int i = 0; i < _capsulePositions.length; i++) {
        double angle = rng.nextDouble() * 2 * pi;
        double r = 10 + rng.nextDouble() * (_globeRadius - 30);
        _capsulePositions[i] = Offset(r * cos(angle), r * sin(angle));
      }
    });
  }

  @override
  void dispose() {
    _rollController.dispose();
    _dropController.dispose();
    super.dispose();
  }

  // 本地抽獎（伺服器離線時使用）
  Map<String, dynamic>? _runLocalGacha() {
    final rng = Random();
    final roll = rng.nextInt(1000);
    int cumulative = 0;
    for (final entry in _gachaPool) {
      cumulative += entry['weight'] as int;
      if (roll < cumulative) {
        final key = entry['key'] as String?;
        if (key == null) return null;
        return {
          'type': key,
          'name': entry['name'] as String,
          'color': _getPetColor(key),
        };
      }
    }
    return null;
  }

  // 扭蛋：優先由後端決定結果，離線時使用本地機率池
  // 扭蛋：線上以「扭蛋幣」原子扣款（合併自朋友版經濟），斷線則退回你原本的本地機率池、一樣扣扭蛋幣。
  void _startGacha() async {
    const cost = 100;
    if (_isRolling) return;
    if (_userCoins < cost) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('扭蛋幣不足！完成登入或任務可以獲得扭蛋幣。')),
      );
      return;
    }

    setState(() => _isRolling = true);
    Map<String, dynamic>? spendResult;

    _rollController.repeat();
    await Future.delayed(const Duration(seconds: 2));
    _rollController.stop();
    await _dropController.forward();
    _dropController.reset();

    Map<String, dynamic>? result;
    try {
      // 先由 5000 API 原子扣除扭蛋幣，避免再扣大富翁 money。
      spendResult = await GameApiService.instance.spendGameReward(
        rewardType: 'gacha_coins',
        amount: cost,
        source: 'gacha_draw',
      );
      if (mounted) {
        setState(() {
          _userCoins = int.tryParse(spendResult?['gacha_coins']?.toString() ?? '') ?? (_userCoins - cost);
        });
      }

      // cost=0：8000 API 只負責抽獎/新增寵物，不再扣玩家 money。
      final apiResult = await GameApiService.instance.gachaDraw(cost: 0);
      final pet = apiResult['pet'];
      if (pet is Map) {
        final type = (pet['species_name'] ?? pet['icon_key'] ?? 'dog').toString();
        result = {
          'type': type,
          'name': (pet['name'] ?? pet['species_name'] ?? '新寵物').toString(),
          'color': _getPetColor(type),
        };
      }
    } catch (_) {
      // ★ 斷線備援（保留你原本的本地機率池）：一樣扣「扭蛋幣」。
      //   • spendResult == null：尚未成功扣款，改在本地扣掉扭蛋幣。
      //   • spendResult != null：已在伺服器扣過款，不重複扣，直接用本地池給結果。
      if (mounted && spendResult == null) {
        setState(() => _userCoins = (_userCoins - cost).clamp(0, 999999));
      }
      result = _runLocalGacha();
    }

    if (!mounted) return;
    setState(() => _isRolling = false);
    _showResultDialog(result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF5F5),
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0, foregroundColor: Colors.brown),
      body: Center(
        child: Column(
          children: [
            _buildCoinBadge(),
            const SizedBox(height: 12),
            TextButton.icon( // ★ 合併自朋友版：任務中心入口
              onPressed: _openMissions,
              icon: const Icon(Icons.task_alt_rounded),
              label: const Text('查看任務與領取扭蛋幣'),
            ),
            const Spacer(),
            _buildGachaMachineBody(),
            const SizedBox(height: 50),
            _buildActionBtn(),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _buildCoinBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))]),
      child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.stars, color: Colors.orangeAccent), const SizedBox(width: 8), Text("$_userCoins 扭蛋幣", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.brown))]),
    );
  }

  Widget _buildGachaMachineBody() {
    return SizedBox(
      width: 260, height: 400,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(size: const Size(260, 400), painter: GachaArtPainter()),
          Positioned(left: 0, top: 180, child: _buildSmallHandle(true)),
          Positioned(right: 0, top: 180, child: _buildSmallHandle(false)),
          Positioned(
            top: 60,
            child: Container(
              width: 190, height: 190,
              decoration: const BoxDecoration(shape: BoxShape.circle),
              child: Stack(
                alignment: Alignment.center,
                children: _capsulePositions.asMap().entries.map((e) => _buildBall(e.value, e.key)).toList(),
              ),
            ),
          ),
          AnimatedBuilder(
            animation: _dropController,
            builder: (context, child) {
              if (_dropController.value == 0) return const SizedBox.shrink();
              return Positioned(
                top: 260 + (_dropController.value * 90),
                child: _buildBall(Offset.zero, 0, isFixed: true),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSmallHandle(bool isLeft) {
    return Transform.rotate(
      angle: _isRolling ? (isLeft ? 1 : -1) * pi * 2 * _rollController.value : 0,
      child: Container(width: 25, height: 45, decoration: BoxDecoration(color: const Color(0xFFB71C1C), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.black, width: 3))),
    );
  }

  Widget _buildBall(Offset pos, int index, {bool isFixed = false}) {
    final colors = [Colors.redAccent, Colors.blueAccent, Colors.yellowAccent, Colors.greenAccent, Colors.purpleAccent, Colors.orangeAccent];
    return Positioned(
      left: isFixed ? 78 : (95 + pos.dx - 18),
      top: isFixed ? 0 : (95 + pos.dy - 18),
      child: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle, border: Border.all(color: Colors.black, width: 2),
          gradient: LinearGradient(colors: [colors[index % 6], Colors.white], begin: Alignment.topCenter, end: Alignment.bottomCenter, stops: const [0.5, 0.51]),
        ),
      ),
    );
  }

  Widget _buildActionBtn() {
    return InkWell(
      onTap: _startGacha,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 18),
        decoration: BoxDecoration(color: _isRolling ? Colors.grey : const Color(0xFFFF5252), borderRadius: BorderRadius.circular(40), border: Border.all(color: Colors.black, width: 3), boxShadow: const [BoxShadow(color: Colors.black26, offset: Offset(0, 6))]),
        child: Text(_isRolling ? "扭動中..." : "消耗 100 扭蛋幣 扭一次", style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
      ),
    );
  }

  // --- 修正後的彈窗：動態顯示抽獎結果 ---
  void _showResultDialog(Map<String, dynamic>? res) {
    bool isNone = res == null;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 280, padding: const EdgeInsets.all(25),
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: Colors.black, width: 4),
                boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 20, offset: Offset(0, 10))]
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(isNone ? "可惜！" : "🎉 扭蛋結果 🎉", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.brown)),
                const SizedBox(height: 25),
                Container(
                  width: 110, height: 110,
                  decoration: BoxDecoration(
                      color: isNone ? Colors.grey[100] : res['color'].withOpacity(0.15),
                      shape: BoxShape.circle,
                      border: Border.all(color: isNone ? Colors.grey : res['color'], width: 4),
                      boxShadow: isNone ? [] : [BoxShadow(color: res['color'].withOpacity(0.4), blurRadius: 15, spreadRadius: 2)]
                  ),
                  child: Icon(
                      isNone ? Icons.sentiment_neutral : _getPetIcon(res['type']),
                      size: 65,
                      color: isNone ? Colors.grey : res['color']
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  isNone ? "銘謝惠顧" : "恭喜獲得：${res['name']}",
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  isNone ? "獲得了再接再厲飼料球！" : "新的夥伴已經加入圖鑑囉！",
                  style: const TextStyle(color: Colors.grey, fontSize: 14),
                ),
                const SizedBox(height: 30),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: isNone ? Colors.grey[700] : Colors.redAccent,
                      foregroundColor: Colors.white,
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(horizontal: 45, vertical: 15)
                  ),
                  child: const Text("收下", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _getPetColor(String type) {
    switch (type) {
      case 'cat':         return Colors.blueAccent;
      case 'parrot':      return Colors.yellowAccent;
      case 'fox':         return Colors.deepOrangeAccent;
      case 'sloth':       return Colors.brown[400]!;
      case 'cute_dog':    return const Color(0xFFFF8A65);
      case 'pomeranian':  return const Color(0xFFEC407A);
      case 'norm_dog':    return const Color(0xFF66BB6A);
      case 'wagging_dog': return const Color(0xFF29B6F6);
      case 'lovely_cat':  return const Color(0xFFE91E63);
      case 'blue_cat':    return const Color(0xFF5C6BC0);
      case 'rocket_cat':  return const Color(0xFF26A69A);
      case 'loader_cat':  return const Color(0xFFBA68C8);
      case 'bear':        return const Color(0xFF8D6E63);
      case 'bee':         return const Color(0xFFFFD600);
      case 'giraffe':     return const Color(0xFFFFCA28);
      default:            return Colors.orangeAccent;
    }
  }

  IconData _getPetIcon(String type) {
    switch (type) {
      case 'dog':         return Icons.pets;
      case 'cat':         return FontAwesomeIcons.cat;
      case 'parrot':      return FontAwesomeIcons.dove;
      case 'fox':         return Icons.auto_awesome;
      case 'sloth':       return Icons.hourglass_bottom_rounded;
      case 'cute_dog':    return Icons.pets;
      case 'pomeranian':  return Icons.pets;
      case 'norm_dog':    return Icons.pets;
      case 'wagging_dog': return Icons.pets;
      case 'lovely_cat':  return FontAwesomeIcons.cat;
      case 'blue_cat':    return FontAwesomeIcons.cat;
      case 'rocket_cat':  return Icons.rocket_launch_rounded;
      case 'loader_cat':  return FontAwesomeIcons.cat;
      case 'bear':        return FontAwesomeIcons.tree;
      case 'bee':         return Icons.sports_kabaddi_rounded;
      case 'giraffe':     return Icons.forest_rounded;
      default:            return Icons.pets;
    }
  }
}

class GachaArtPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final bodyPaint = Paint()..color = const Color(0xFFE53935)..style = PaintingStyle.fill;
    final strokePaint = Paint()..color = Colors.black..style = PaintingStyle.stroke..strokeWidth = 4;
    final glassPaint = Paint()..color = Colors.white.withOpacity(0.2)..style = PaintingStyle.fill;

    final capRect = Rect.fromLTWH(size.width / 2 - 60, 25, 120, 40);
    canvas.drawRRect(RRect.fromRectAndRadius(capRect, const Radius.circular(15)), bodyPaint);
    canvas.drawRRect(RRect.fromRectAndRadius(capRect, const Radius.circular(15)), strokePaint);

    canvas.drawCircle(Offset(size.width / 2, 155), 100, glassPaint);
    canvas.drawCircle(Offset(size.width / 2, 155), 100, strokePaint);

    final baseRect = Rect.fromLTWH(size.width / 2 - 85, 240, 170, 130);
    canvas.drawRRect(RRect.fromRectAndRadius(baseRect, const Radius.circular(25)), bodyPaint);
    canvas.drawRRect(RRect.fromRectAndRadius(baseRect, const Radius.circular(25)), strokePaint);

    final signRect = Rect.fromLTWH(size.width / 2 - 40, 310, 80, 40);
    canvas.drawRRect(RRect.fromRectAndRadius(signRect, const Radius.circular(8)), Paint()..color = const Color(0xFFFFFDE7));
    canvas.drawRRect(RRect.fromRectAndRadius(signRect, const Radius.circular(8)), strokePaint);

    canvas.drawCircle(Offset(size.width / 2, 275), 32, Paint()..color = Colors.black45);
    canvas.drawCircle(Offset(size.width / 2, 275), 32, strokePaint);
  }
  @override bool shouldRepaint(covariant CustomPainter old) => false;
}