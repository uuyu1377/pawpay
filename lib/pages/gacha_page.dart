import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:user_interface/services/game_api_service.dart';
import 'mission_page.dart'; // ★ 合併自朋友版：任務中心入口
import 'pet_choice_shop_page.dart';
import '../widgets/paw_gacha_3d.dart';
import '../theme/app_palette.dart';
import '../widgets/paw_toy_widgets.dart';
import '../services/current_pet_manager.dart';

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
  // ★ 修改：跟後端 main.py 的新機率表同步(銘謝惠顧 90%、普通 7%、稀有 2.8%、傳說 0.2%)，
  //   避免「連得到網路時機率很低、一斷線反而變很高」這種線上線下不一致的情況。
  //   weight 單位是 ‱(萬分之一)，總和 10000。
  static const List<Map<String, dynamic>> _gachaPool = [
    {'key': null,          'name': '銘謝惠顧', 'weight': 9000},
    {'key': 'dog',         'name': '狗狗',     'weight': 227},
    {'key': 'cat',         'name': '貓咪',     'weight': 227},
    {'key': 'parrot',      'name': '鸚鵡',     'weight': 95},
    {'key': 'sloth',       'name': '樹懶',     'weight': 76},
    {'key': 'fox',         'name': '狐狸',     'weight': 75},
    {'key': 'shiba_dog',   'name': '柴柴',     'weight': 47},
    {'key': 'pomeranian',  'name': '博美犬',   'weight': 47},
    {'key': 'calm_dog',    'name': '諾姆犬',   'weight': 47},
    {'key': 'clingy_dog',  'name': '甩尾狗',   'weight': 46},
    {'key': 'love_cat',    'name': '愛心貓',   'weight': 23},
    {'key': 'work_cat',    'name': '工作貓',   'weight': 23},
    {'key': 'waiting_cat', 'name': '等待貓',   'weight': 23},
    {'key': 'rocket_cat',  'name': '火箭貓',   'weight': 24},
    {'key': 'bear',        'name': '熊熊',     'weight': 10},
    {'key': 'bee',         'name': '蜜蜂',     'weight': 6},
    {'key': 'giraffe',     'name': '長頸鹿',   'weight': 4},
  ];

  @override
  void initState() {
    super.initState();
    _rollController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
    _dropController = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
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

  Future<void> _openPetChoiceShop() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PetChoiceShopPage()),
    );
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
    final roll = rng.nextInt(10000); // ★ 修改：配合新的 weight 精度(萬分之一)，從 1000 改成 10000
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

  // ★ 新增：單抽 / 十抽送一抽 的價格
  // ★ 調整：任務獎勵一個月約 10～14 幣（記帳 30 筆 = 1 幣），
  //   所以單抽 1 幣、十抽送一抽 10 幣，認真記帳一個月約可十抽送一抽一次。
  static const int _singleCost = 1;
  static const int _multiDraws = 11;  // 十抽送一抽
  static const int _multiCost = 10;   // 只算 10 抽的錢

  Map<String, dynamic>? _resultFromApiPet(dynamic pet, {bool duplicate = false}) {
    if (pet is! Map) return null;
    final type = (pet['icon_key'] ?? pet['species_name'] ?? 'dog').toString();
    return {
      'type': type,
      'name': (pet['name'] ?? pet['species_name'] ?? '新寵物').toString(),
      'color': _getPetColor(type),
      'duplicate': duplicate, // ★ 任務3：帶入後端回傳的「是否為已擁有的同物種」
    };
  }

  // 扭蛋：線上以「扭蛋幣」原子扣款（合併自朋友版經濟），斷線則退回本地機率池、一樣扣扭蛋幣。
  // ★ 修改：加上 draws 參數，1 = 單抽，11 = 十抽送一抽
  Future<void> _startGacha({int draws = 1}) async {
    final isMulti = draws > 1;
    final cost = isMulti ? _multiCost : _singleCost;
    if (_isRolling) return;
    if (_userCoins < cost) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('扭蛋幣不足！${isMulti ? '十抽送一抽需要 $cost 扭蛋幣，' : ''}完成記帳任務可以獲得扭蛋幣。')),
      );
      return;
    }

    setState(() => _isRolling = true);
    Map<String, dynamic>? spendResult;

    _rollController.repeat();
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    _rollController.stop();
    await _dropController.forward();
    if (!mounted) return;
    _dropController.reset();

    final List<Map<String, dynamic>?> results = [];
    var offline = false;
    try {
      // 先由 5000 API 原子扣除扭蛋幣，避免再扣大富翁 money。
      spendResult = await GameApiService.instance.spendGameReward(
        rewardType: 'gacha_coins',
        amount: cost,
        source: isMulti ? 'gacha_draw_multi' : 'gacha_draw',
      );
      if (mounted) {
        setState(() {
          _userCoins = int.tryParse(spendResult?['gacha_coins']?.toString() ?? '') ?? (_userCoins - cost);
        });
      }

      // cost=0：8000 API 只負責抽獎/新增寵物，不再扣玩家 money。
      final realUserId = await GameApiService.instance.resolveCurrentUserId();
      if (isMulti) {
        final apiResult = await GameApiService.instance.gachaDrawMulti(userId: realUserId, draws: draws, cost: 0);
        final list = apiResult['results'];
        if (list is! List) throw Exception('後端回傳格式錯誤');
        for (final item in list) {
          if (item is Map) {
            results.add(_resultFromApiPet(item['pet'], duplicate: item['duplicate'] == true));
          } else {
            results.add(null);
          }
        }
      } else {
        final apiResult = await GameApiService.instance.gachaDraw(userId: realUserId, cost: 0);
        results.add(_resultFromApiPet(apiResult['pet'], duplicate: apiResult['duplicate'] == true));
      }
    } catch (e) {
      // 失敗時不要假裝真的抽到：用本地池給「離線模擬」結果，並在彈窗清楚標示沒有存檔。
      debugPrint('❌ 扭蛋抽獎失敗，改用離線模擬結果：$e');

      //   • spendResult == null：尚未成功扣款，改在本地扣掉扭蛋幣。
      //   • spendResult != null：已在伺服器扣過款，不重複扣，直接用本地池給結果。
      if (mounted && spendResult == null) {
        setState(() => _userCoins = (_userCoins - cost).clamp(0, 999999));
      }
      results.clear();
      offline = true;
      for (var i = 0; i < draws; i++) {
        final r = _runLocalGacha();
        if (r != null) r['offline'] = true; // ★ 標記：這是離線模擬，沒有真的寫進寵物清單
        results.add(r);
      }
    }

    if (!mounted) return;
    setState(() => _isRolling = false);
    if (isMulti) {
      _showMultiResultDialog(results, offline: offline);
    } else {
      _showResultDialog(results.isEmpty ? null : results.first);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(backgroundColor: palette.bg, elevation: 0,
          foregroundColor: palette.accentInk,
          title: Text('寵物扭蛋', style: TextStyle(fontSize: 18,
              color: palette.ink, fontWeight: FontWeight.w600))),
      body: SafeArea(top: false, child: LayoutBuilder(builder: (context, box) {
        final machineWidth = min(max(0.0, box.maxWidth - 40), 360.0);
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                _buildCoinBadge(),
                const SizedBox(height: 10),
                TextButton.icon(onPressed: _openMissions,
                    icon: const Icon(Icons.task_alt_rounded, size: 19),
                    label: const Text('查看任務與領取扭蛋幣', textAlign: TextAlign.center)),
                // ★ 修改：寵物不課金，自選券改用扭蛋幣兌換
                OutlinedButton.icon(onPressed: _openPetChoiceShop,
                    icon: const Icon(Icons.card_giftcard_rounded, size: 19),
                    label: const Text('寵物自選券（用扭蛋幣兌換）', textAlign: TextAlign.center)),
                const SizedBox(height: 6),
                SizedBox(width: machineWidth, child: PawGachaMachine3D(
                    roll: _rollController, drop: _dropController)),
                const SizedBox(height: 12),
                _buildActionBtn(),
                const SizedBox(height: 10),
                _buildMultiActionBtn(),
              ]))),
        );
      })),
    );
  }

  Widget _buildCoinBadge() {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
      decoration: BoxDecoration(color: palette.card, borderRadius: BorderRadius.circular(30),
          border: Border.all(color: palette.line), boxShadow: palette.cardShadow),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.stars_rounded, color: Color(0xFFE3B465)),
        const SizedBox(width: 8),
        Flexible(child: Text("$_userCoins 扭蛋幣", style: TextStyle(fontSize: 17,
            fontWeight: FontWeight.bold, color: palette.ink))),
      ]),
    );
  }

  Widget _buildActionBtn() {
    final palette = AppPalette.of(context);
    return Semantics(button: true, enabled: !_isRolling,
      child: Material(color: Colors.transparent, child: InkWell(
        onTap: () => _startGacha(draws: 1),
        borderRadius: BorderRadius.circular(28),
        child: Ink(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          decoration: BoxDecoration(
            color: _isRolling ? palette.line : palette.accent,
            borderRadius: BorderRadius.circular(28),
            boxShadow: _isRolling ? [] : palette.cardShadow,
          ),
          child: Text(_isRolling ? "扭動中..." : "消耗 $_singleCost 扭蛋幣 扭一次",
              textAlign: TextAlign.center,
              style: TextStyle(color: !_isRolling && ThemeData.estimateBrightnessForColor(palette.accent) == Brightness.dark
                  ? Colors.white : palette.ink, fontSize: 17, fontWeight: FontWeight.bold)),
        ),
      )),
    );
  }

  // ★ 新增：十抽送一抽按鈕
  Widget _buildMultiActionBtn() {
    final palette = AppPalette.of(context);
    return Semantics(button: true, enabled: !_isRolling,
      child: Material(color: Colors.transparent, child: InkWell(
        onTap: () => _startGacha(draws: _multiDraws),
        borderRadius: BorderRadius.circular(28),
        child: Ink(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: palette.card,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: _isRolling ? palette.line : palette.accent, width: 2),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_isRolling ? "扭動中..." : "十抽送一抽",
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.ink, fontSize: 17, fontWeight: FontWeight.bold)),
            if (!_isRolling) ...[
              const SizedBox(height: 2),
              Text("消耗 $_multiCost 扭蛋幣，共抽 $_multiDraws 次",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: palette.ink2, fontSize: 12)),
            ],
          ]),
        ),
      )),
    );
  }

  // ★ 新增：十抽送一抽的結果，用格子一次列出 11 個
  void _showMultiResultDialog(List<Map<String, dynamic>?> results, {bool offline = false}) {
    final got = results.whereType<Map<String, dynamic>>().toList();
    final newCount = got.where((r) => r['duplicate'] != true).length;
    final isOffline = offline;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: AppPalette.of(context).ink.withValues(alpha: .38),
      builder: (ctx) {
        final p = AppPalette.of(ctx);
        return Dialog(
          backgroundColor: Colors.transparent, elevation: 0,
          insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
          child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 400),
            child: SingleChildScrollView(
              child: PawToyCard(padding: const EdgeInsets.fromLTRB(18, 22, 18, 22),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('十抽送一抽結果', style: TextStyle(color: p.ink, fontSize: 20, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text(
                    got.isEmpty ? '這次全部銘謝惠顧，下次好運！' : '獲得 ${got.length} 隻寵物，其中 $newCount 隻是新夥伴',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: p.ink2, fontSize: 13),
                  ),
                  const SizedBox(height: 14),
                  GridView.count(
                    crossAxisCount: 4,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 0.78,
                    children: [for (final r in results) _multiResultTile(r)],
                  ),
                  if (isOffline) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '⚠️ 目前連線不穩，這是離線模擬結果，不會出現在你的寵物清單裡，請稍後恢復連線再抽一次',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.orange[800], fontSize: 12, height: 1.5, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  PawToyButton(label: '收下', onPressed: () => Navigator.pop(ctx), icon: Icons.favorite_rounded),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _multiResultTile(Map<String, dynamic>? r) {
    final p = AppPalette.of(context);
    if (r == null) {
      return Container(
        decoration: BoxDecoration(color: p.line.withValues(alpha: .35), borderRadius: BorderRadius.circular(14)),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.spa_rounded, color: p.ink2, size: 26),
          const SizedBox(height: 4),
          Text('銘謝惠顧', style: TextStyle(fontSize: 10, color: p.ink2)),
        ]),
      );
    }
    final type = r['type']?.toString() ?? '';
    final imagePath = CurrentPetManager.petImageMap[type];
    final isNew = r['duplicate'] != true;
    final color = (r['color'] as Color?) ?? p.accent;
    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isNew ? color : Colors.transparent, width: 2),
      ),
      padding: const EdgeInsets.all(4),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Expanded(
          child: imagePath != null
              ? Image.asset(imagePath, fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Icon(_getPetIcon(type), color: color))
              : Icon(_getPetIcon(type), color: color),
        ),
        Text(r['name']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: p.ink)),
        Text(isNew ? 'NEW' : '已擁有',
            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800,
                color: isNew ? Colors.pink : p.ink2)),
      ]),
    );
  }

  // Presentation only: reward spending and result selection stay above.
  void _showResultDialog(Map<String, dynamic>? res) {
    final isNone = res == null;
    final isDuplicate = res?['duplicate'] == true;
    final isOffline = res?['offline'] == true; // ★ 新增：是否為離線模擬結果（未真正存入資料庫）
    final type = res?['type']?.toString() ?? '';
    final imagePath = CurrentPetManager.petImageMap[type];
    final fallback = isNone ? Icons.spa_rounded : _getPetIcon(type);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: AppPalette.of(context).ink.withValues(alpha: .38),
      builder: (ctx) {
        final p = AppPalette.of(ctx);
        return Dialog(
          backgroundColor: Colors.transparent, elevation: 0,
          insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
          child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 370),
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 12),
              child: PawToyCard(padding: const EdgeInsets.fromLTRB(24, 26, 24, 26),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.pets_rounded, size: 14, color: p.accentInk),
                    const SizedBox(width: 7),
                    Text('PAWPAY · 小小驚喜', style: TextStyle(color: p.accentInk,
                        fontSize: 11, letterSpacing: 1.5, fontWeight: FontWeight.w800)),
                  ]),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(color: p.accentSoft,
                        borderRadius: BorderRadius.circular(30), border: Border.all(color: Colors.white)),
                    child: Text(isNone ? '下次好運' : (isDuplicate ? '已擁有的夥伴' : '新夥伴登場'),
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.accentInk)),
                  ),
                  const SizedBox(height: 8),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: MediaQuery.of(ctx).disableAnimations ? Duration.zero : const Duration(milliseconds: 650),
                    curve: Curves.easeOutCubic,
                    builder: (_, value, __) => PawCapsuleStage(
                        imagePath: imagePath, fallbackIcon: fallback, progress: value),
                  ),
                  const SizedBox(height: 4),
                  Semantics(liveRegion: true, child: Text(
                    isNone ? '銘謝惠顧' : (isDuplicate ? '又見面了，${res?['name']}' : '恭喜獲得 ${res?['name']}！'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: p.ink, fontSize: 24, fontWeight: FontWeight.w800, height: 1.3),
                  )),
                  const SizedBox(height: 12),
                  Text(
                    isNone ? '獲得了再接再厲飼料球！'
                        : (isDuplicate ? '你已經擁有這隻夥伴了（已擁有）' : '新的夥伴已經加入圖鑑囉！'),
                    textAlign: TextAlign.center, style: TextStyle(color: p.ink2, fontSize: 14, height: 1.6),
                  ),
                  // ★ 新增：離線模擬時明確提醒，避免使用者以為真的抽到、之後找不到寵物而困惑
                  if (isOffline && !isNone) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '⚠️ 目前連線不穩，這是離線模擬結果，不會出現在你的寵物清單裡，請稍後恢復連線再抽一次',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.orange[800], fontSize: 12, height: 1.5, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                  const SizedBox(height: 26),
                  PawToyButton(label: '收下', onPressed: () => Navigator.pop(ctx),
                      icon: isNone ? Icons.check_rounded : Icons.favorite_rounded),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }

  Color _getPetColor(String type) {
    switch (type) {
      case 'cat':         return Colors.blueAccent;
      case 'parrot':      return Colors.yellowAccent;
      case 'fox':         return Colors.deepOrangeAccent;
      case 'sloth':       return Colors.brown[400]!;
      case 'shiba_dog':   return const Color(0xFFFF8A65);
      case 'pomeranian':  return const Color(0xFFEC407A);
      case 'calm_dog':    return const Color(0xFF66BB6A);
      case 'clingy_dog':  return const Color(0xFF29B6F6);
      case 'love_cat':    return const Color(0xFFE91E63);
      case 'work_cat':    return const Color(0xFF5C6BC0);
      case 'rocket_cat':  return const Color(0xFF26A69A);
      case 'waiting_cat': return const Color(0xFFBA68C8);
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
      case 'shiba_dog':   return Icons.pets;
      case 'pomeranian':  return Icons.pets;
      case 'calm_dog':    return Icons.pets;
      case 'clingy_dog':  return Icons.pets;
      case 'love_cat':    return FontAwesomeIcons.cat;
      case 'work_cat':    return FontAwesomeIcons.cat;
      case 'rocket_cat':  return Icons.rocket_launch_rounded;
      case 'waiting_cat': return FontAwesomeIcons.cat;
      case 'bear':        return FontAwesomeIcons.tree;
      case 'bee':         return Icons.sports_kabaddi_rounded;
      case 'giraffe':     return Icons.forest_rounded;
      default:            return Icons.pets;
    }
  }
}