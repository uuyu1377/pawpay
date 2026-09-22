import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../widgets/toy_board_art.dart';
import '../widgets/island_board_3d.dart';

import '../theme/app_palette.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../data/pet_skill_data.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart'; // ★ 新增：讀取使用者實際選的寵物 key，修復大富翁沒圖片的問題

import 'add_friend_page.dart';
import 'friend_page.dart';
import 'pet_page.dart';
import 'package:user_interface/services/game_api_service.dart';

// --- 全局選定寵物狀態（跨頁面共享）---
class SelectedPet {
  static String? name;
  static String? animationPath;
  static String? emoji;
  static Color? color;
  static MapTheme? lastMapTheme;

  static void set({
    required String name,
    required String animationPath,
    required String emoji,
    required Color color,
  }) {
    SelectedPet.name = name;
    SelectedPet.animationPath = animationPath;
    SelectedPet.emoji = emoji;
    SelectedPet.color = color;
  }
}

// ★★★ 新增：寵物 key 對應的圖片路徑，跟 pet_page.dart / weekly_share_page.dart 用同一批圖檔 ★★★
// 用途：如果使用者直接從底部導覽列點「大富翁」進來（沒有先經過選寵物頁面），
// SelectedPet.animationPath 會是 null，導致玩家棋子變成沒有圖片的空白圓圈。
// 有這張對照表，才能在遊戲開始後補撈使用者實際選的寵物圖片。
const Map<String, String> _kPetImageMap = {
  'dog': 'assets/pets/dog_action.png',
  'cat': 'assets/pets/cat_action.png',
  'parrot': 'assets/pets/parrot_action.png',
  'sloth': 'assets/pets/sloth_action.png',
  'fox': 'assets/pets/fox_action.png',
  'shiba_dog': 'assets/pets/shiba_action.png',
  'pomeranian': 'assets/pets/pomeranian_action.png',
  'calm_dog': 'assets/pets/calm_dog_action.png',
  'clingy_dog': 'assets/pets/clingy_dog_action.png',
  'love_cat': 'assets/pets/love_cat_action.png',
  'work_cat': 'assets/pets/work_cat_action.png',
  'rocket_cat': 'assets/pets/rocket_cat_action.png',
  'waiting_cat': 'assets/pets/waiting_cat_action.png',
  'bear': 'assets/pets/bear_action.png',
  'bee': 'assets/pets/bee_action.png',
  'giraffe': 'assets/pets/giraffe_action.png',
};
// 電腦三隻代表角色
const String _kDefaultBoardImage =
    'assets/pets/pawpay_app_icon1.png';

const String _kComputerImage1 =
    'assets/pets/bunny_bow.png';

const String _kComputerImage2 =
    'assets/pets/hamster_foodie.png';

const String _kComputerImage3 =
    'assets/pets/otter_leaf.png';
// --- 核心資料模型 ---
enum BlockType { land, start, jail, chance, tax, goJail }
enum MapTheme { taiwan, magicIsland }

class GameNode {
  final String name;
  final Offset position;
  final int baseCost;
  final BlockType type;
  int level;
  int? ownerId;

  GameNode({
    required this.name,
    required this.position,
    required this.baseCost,
    this.type = BlockType.land,
    this.level = 0,
    this.ownerId,
  });

  int get rent => type == BlockType.land ? (baseCost * (0.2 + (level * 0.3))).toInt() : 0;
}

class Player {
  final int id;
  final String name;
  final Color color;
  final IconData icon;
  final String? animationPath; // pet Lottie path for player 0
  final String? emoji;
  int money;
  int pathStep;
  bool isBankrupt;
  int jailTurns;

  Player({
    required this.id,
    required this.name,
    required this.color,
    required this.icon,
    this.animationPath,
    this.emoji,
    this.money = 35000,
    this.pathStep = 0,
    this.isBankrupt = false,
    this.jailTurns = 0,
  });
}

// --- 3D 骰子組件 ---
class Dice3D extends StatelessWidget {
  final int value;
  final bool isRolling;
  final bool isMagic;

  const Dice3D({super.key, required this.value, required this.isRolling, required this.isMagic});

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: isRolling ? 1.25 : 1.0,
      duration: const Duration(milliseconds: 300),
      child: AnimatedRotation(
        turns: isRolling ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutBack,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isMagic
                  ? [const Color(0xFF6A11CB), const Color(0xFF2575FC)]
                  : [Colors.white, Colors.grey.shade200],
            ),
            boxShadow: [
              BoxShadow(
                color: isMagic ? Colors.purpleAccent.withOpacity(0.5) : Colors.black26,
                offset: const Offset(3, 4),
                blurRadius: 8,
              ),
            ],
            border: Border.all(
              color: isMagic ? Colors.white30 : Colors.grey.shade300,
              width: 1.5,
            ),
          ),
          child: _buildDots(value),
        ),
      ),
    );
  }

  Widget _buildDots(int val) {
    final dotPositions = {1: [4], 2: [0, 8], 3: [0, 4, 8], 4: [0, 2, 6, 8], 5: [0, 2, 4, 6, 8], 6: [0, 2, 3, 5, 6, 8]};
    final active = dotPositions[val] ?? [4];
    final dotColor = (val == 1 && !isMagic) ? Colors.redAccent : (isMagic ? Colors.cyanAccent : Colors.black87);

    return Center(
      child: SizedBox(
        width: 34,
        height: 34,
        child: GridView.builder(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 1, mainAxisSpacing: 2, crossAxisSpacing: 2),
          itemCount: 9,
          itemBuilder: (_, i) {
            if (!active.contains(i)) return const SizedBox.shrink();
            return Center(
              child: Container(
                width: 7, height: 7,
                decoration: BoxDecoration(
                  color: dotColor, shape: BoxShape.circle,
                  boxShadow: isMagic ? [BoxShadow(color: dotColor.withOpacity(0.8), blurRadius: 6, spreadRadius: 1)] : null,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// --- 主頁面 ---
class PlaygroundPage extends StatefulWidget {
  final String? petName;
  final String? petAnimationPath;
  final String? petEmoji;
  final Color? petColor;
  final MapTheme? initialMapTheme;

  const PlaygroundPage({
    super.key,
    this.petName,
    this.petAnimationPath,
    this.petEmoji,
    this.petColor,
    this.initialMapTheme,
  });

  @override
  State<PlaygroundPage> createState() => _PlaygroundPageState();
}

class _PlaygroundPageState extends State<PlaygroundPage> {
  bool _gameStarted = false;
  bool _gameOver = false;
  late List<Player> _players;
  int _currentPlayerIdx = 0;
  late List<GameNode> _currentPath;
  MapTheme _currentTheme = MapTheme.taiwan;
  String _gameLog = "";

  List<int> _diceValues = [1, 1];
  bool _isRolling = false;
  StreamSubscription? _accelerometerSub;
  DateTime _lastShakeTime = DateTime.now();
  bool _isLoadingGameState = false;

  String get _themeKey => _currentTheme == MapTheme.taiwan ? 'taiwan' : 'magicIsland';

  String _blockTypeKey(BlockType type) {
    switch (type) {
      case BlockType.start:   return 'start';
      case BlockType.jail:    return 'jail';
      case BlockType.chance:  return 'chance';
      case BlockType.tax:     return 'tax';
      case BlockType.goJail:  return 'goJail';
      case BlockType.land:    return 'land';
    }
  }

  Future<void> _loadGameStateFromApi(MapTheme theme) async {
    try {
      // ★ 新增：先拿到真正登入的 user_id，避免所有帳號共用同一份大富翁進度
      final realUserId = await GameApiService.instance.resolveCurrentUserId();
      final data = await GameApiService.instance.fetchGameState(
        userId: realUserId,
        theme: theme == MapTheme.taiwan ? 'taiwan' : 'magicIsland',
      );
      if (!mounted) return;
      final players = data['players'];
      if (players is List) {
        for (final raw in players.whereType<Map>()) {
          final row = Map<String, dynamic>.from(raw);
          final localId = int.tryParse(row['local_id']?.toString() ?? '') ?? -1;
          if (localId >= 0 && localId < _players.length) {
            _players[localId].money    = int.tryParse(row['money']?.toString() ?? '') ?? _players[localId].money;
            _players[localId].pathStep = (int.tryParse(row['path_step']?.toString() ?? '') ?? _players[localId].pathStep) % _currentPath.length;
            _players[localId].jailTurns = int.tryParse(row['jail_turns']?.toString() ?? '') ?? _players[localId].jailTurns;
            // 不恢復破產狀態：每次開局都從非破產開始，破產只由遊戲中的 _endTurn 判斷
          }
        }
      }
      final blocks = data['blocks'];
      if (blocks is List) {
        for (final raw in blocks.whereType<Map>()) {
          final row = Map<String, dynamic>.from(raw);
          final idx = int.tryParse(row['local_index']?.toString() ?? row['index']?.toString() ?? '') ?? -1;
          if (idx >= 0 && idx < _currentPath.length) {
            _currentPath[idx].level   = int.tryParse(row['level']?.toString() ?? '') ?? _currentPath[idx].level;
            final owner = row['owner_local_id'];
            _currentPath[idx].ownerId = owner == null ? null : int.tryParse(owner.toString());
          }
        }
      }
      setState(() => _isLoadingGameState = false);
      _persistAllBlocks();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingGameState = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('大富翁資料庫連線失敗，先用離線狀態遊玩：$e')));
    }
  }

  Future<void> _persistPlayerState(Player p) async {
    try {
      // ★ 新增：一樣要帶入真正登入的 user_id，跟讀取那邊保持一致
      final realUserId = await GameApiService.instance.resolveCurrentUserId();
      await GameApiService.instance.updatePlayerState(
        userId: realUserId,
        localId: p.id, money: p.money, pathStep: p.pathStep,
        jailTurns: p.jailTurns, isBankrupt: p.isBankrupt, theme: _themeKey,
      );
    } catch (_) {}
  }

  Future<void> _persistBlockState(GameNode block) async {
    final idx = _currentPath.indexOf(block);
    if (idx < 0) return;
    try {
      // ★ 新增：同樣帶入真正登入的 user_id，避免地產歸屬也被共用帳號卡住
      final realUserId = await GameApiService.instance.resolveCurrentUserId();
      await GameApiService.instance.updateBlockState(
        userId: realUserId,
        theme: _themeKey, index: idx, name: block.name, baseCost: block.baseCost,
        blockType: _blockTypeKey(block.type), positionDx: block.position.dx, positionDy: block.position.dy,
        level: block.level, ownerLocalId: block.ownerId,
      );
    } catch (_) {}
  }

  Future<void> _persistAllPlayers() async { for (final p in _players) await _persistPlayerState(p); }
  Future<void> _persistAllBlocks()  async { for (final b in _currentPath) await _persistBlockState(b); }

  Future<void> _loadCurrentPetSkill() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = prefs.getString('current_pet_key');

      if (!mounted) return;

      setState(() {
        _currentPetKey = key;
      });

      debugPrint('🎮 大富翁目前寵物：$_currentPetKey');
    } catch (e) {
      debugPrint('❌ 讀取寵物技能失敗：$e');
    }
  }

  @override
  void initState() {
    super.initState();

    _initPlayers();
    _ensureSelectedPetImageLoaded();
    _loadCurrentPetSkill();

    _initShakeSensor();

    final autoMap =
        widget.initialMapTheme ?? SelectedPet.lastMapTheme;

    if (autoMap != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _startGame(autoMap);
        }
      });
    }
  }
// =========================================================
// 寵物技能
// =========================================================

  String? _currentPetKey;

  bool _activeSkillUsed = false;

// 已經觸發過的一次性被動技能
  final Set<String> _usedPassiveSkills = {};

// 狗狗：下一次骰骰子時重新骰一次
  bool _dogRerollReady = false;

// 貓咪：下一次骰子點數 -2
  bool _catLightStepReady = false;

// 狐狸：下一次購地 / 升級 7 折
  bool _foxDiscountReady = false;

// 佛系狗：下一次負面機會免疫
  bool _calmDogProtection = false;

// 博美：下一次收到租金 ×1.5
  bool _pomeranianRentBoost = false;

// 等待貓：下一次租金延後
  bool _waitingCatDelayRent = false;

// 延後租金資料
  int _deferredRent = 0;
  int? _deferredRentOwnerId;

// 等待貓：不買土地後，下回合 +800
  bool _waitingCatInterestReady = false;

// 蜜蜂：本回合結束後再多一次行動
  bool _beeExtraTurnReady = false;
  // ★★★ 新增：如果玩家 0（使用者）目前沒有寵物圖片，去讀取使用者實際選的寵物 key 補回來 ★★★
  Future<void> _ensureSelectedPetImageLoaded() async {
    if (_players.isEmpty) return;

    try {
      final prefs = await SharedPreferences.getInstance();

      final key = prefs.getString('current_pet_key');

      final imagePath = _kPetImageMap[key];

      if (imagePath == null || !mounted) return;

      final old = _players[0];

      setState(() {
        _players[0] = Player(
          id: old.id,
          name: old.name,
          color: old.color,
          icon: old.icon,
          animationPath: imagePath,
          emoji: old.emoji,
          money: old.money,
          pathStep: old.pathStep,
          isBankrupt: old.isBankrupt,
          jailTurns: old.jailTurns,
        );
      });
    } catch (e) {
      debugPrint('❌ 更新大富翁寵物圖片失敗：$e');
    }
  }

  void _initMapData(MapTheme theme) {
    _currentTheme = theme;
    final petLabel = (widget.petName ?? SelectedPet.name);
    if (theme == MapTheme.taiwan) {
      _currentPath = _generateTaiwanNodes();
      _gameLog = petLabel != null ? "$petLabel 出發冒險！搖一搖手機擲骰子吧！" : "環島旅行開始囉！搖一搖手機擲骰子吧！";
    } else {
      _currentPath = _generateMagicIslandNodes();
      _gameLog = petLabel != null ? "$petLabel 抵達天空島！" : "歡迎來到天空島，請用財富守護這片魔力之源！";
    }
  }

  List<GameNode> _generateTaiwanNodes() {
    return [
      GameNode(name: "台北(GO)",  position: const Offset(0.58, 0.08), baseCost: 0,     type: BlockType.start),
      GameNode(name: "基隆",      position: const Offset(0.68, 0.05), baseCost: 1800),
      GameNode(name: "宜蘭",      position: const Offset(0.76, 0.18), baseCost: 2200),
      GameNode(name: "機會",      position: const Offset(0.80, 0.30), baseCost: 0,     type: BlockType.chance),
      GameNode(name: "花蓮",      position: const Offset(0.78, 0.45), baseCost: 1800),
      GameNode(name: "秀姑巒溪",  position: const Offset(0.72, 0.58), baseCost: 1500),
      GameNode(name: "台東",      position: const Offset(0.65, 0.74), baseCost: 1600),
      GameNode(name: "屏東",      position: const Offset(0.52, 0.87), baseCost: 2000),
      GameNode(name: "墾丁",      position: const Offset(0.56, 0.95), baseCost: 2500),
      GameNode(name: "監獄",      position: const Offset(0.40, 0.93), baseCost: 0,     type: BlockType.jail),
      GameNode(name: "高雄",      position: const Offset(0.32, 0.82), baseCost: 5500),
      GameNode(name: "台南",      position: const Offset(0.25, 0.72), baseCost: 5000),
      GameNode(name: "機會",      position: const Offset(0.20, 0.60), baseCost: 0,     type: BlockType.chance),
      GameNode(name: "嘉義",      position: const Offset(0.18, 0.50), baseCost: 3000),
      GameNode(name: "雲林",      position: const Offset(0.20, 0.40), baseCost: 2200),
      GameNode(name: "彰化",      position: const Offset(0.25, 0.33), baseCost: 3200),
      GameNode(name: "台中",      position: const Offset(0.32, 0.27), baseCost: 7500),
      GameNode(name: "苗栗",      position: const Offset(0.39, 0.20), baseCost: 2500),
      GameNode(name: "新竹",      position: const Offset(0.46, 0.14), baseCost: 8500),
      GameNode(name: "桃園",      position: const Offset(0.52, 0.11), baseCost: 6000),
      GameNode(name: "繳稅",      position: const Offset(0.60, 0.14), baseCost: 3000,  type: BlockType.tax),
      GameNode(name: "新北",      position: const Offset(0.65, 0.09), baseCost: 9500),
      GameNode(name: "101大樓",   position: const Offset(0.58, 0.21), baseCost: 28000),
      GameNode(name: "機會",      position: const Offset(0.50, 0.30), baseCost: 0,     type: BlockType.chance),
      GameNode(name: "南投",      position: const Offset(0.44, 0.44), baseCost: 2800),
      GameNode(name: "阿里山",    position: const Offset(0.38, 0.55), baseCost: 3500),
      GameNode(name: "澎湖",      position: const Offset(0.10, 0.44), baseCost: 2000),
      GameNode(name: "進監獄",    position: const Offset(0.50, 0.02), baseCost: 0,     type: BlockType.goJail),
    ];
  }

  List<GameNode> _generateMagicIslandNodes() {
    const total = 22;
    final rng = Random(7);
    return List.generate(total, (i) {
      final angle = (i / total) * 2 * pi - pi / 2;
      final r = 0.36 + (rng.nextDouble() * 0.03);
      final dx = 0.5 + r * cos(angle);
      final dy = 0.5 + r * sin(angle);

      BlockType type = BlockType.land;
      String name = _magicNames[i % _magicNames.length];
      int cost = 2800 + (i * 350);

      if (i == 0)  { type = BlockType.start;  name = "光之扉";   cost = 0; }
      if (i == 4)  { type = BlockType.chance; name = "許願池";   cost = 0; }
      if (i == 9)  { type = BlockType.jail;   name = "星辰牢籠"; cost = 0; }
      if (i == 13) { type = BlockType.chance; name = "古老祭壇"; cost = 0; }
      if (i == 18) { type = BlockType.goJail; name = "時空裂隙"; cost = 0; }
      if (i == 11) { name = "以太晶礦"; cost = 26000; }

      return GameNode(name: name, position: Offset(dx, dy), baseCost: cost, type: type);
    });
  }

  static const _magicNames = [
    "星塵浮島", "月光礁", "翡翠崖", "虹橋市集", "霧霾峽谷",
    "靈泉廣場", "風暴要塞", "彩虹湖", "天空船塢", "夢幻山頂",
    "寶石坑道", "蒼穹神殿", "雲端集市", "星光農場", "流星驛站",
    "魔晶港口", "影子迷宮", "幻境之橋", "太陽神廟",
  ];

  void _initPlayers() {
    final petAnim = widget.petAnimationPath ??
        SelectedPet.animationPath ??
        _kDefaultBoardImage;

    final petEmoji = widget.petEmoji ?? SelectedPet.emoji;
    final petName = widget.petName ?? SelectedPet.name ?? "您";
    final petColor =
        widget.petColor ?? SelectedPet.color ?? const Color(0xFF2196F3);

    _players = [
      Player(
        id: 0,
        name: petName,
        color: petColor,
        icon: Icons.pets_rounded,
        animationPath: petAnim,
        emoji: petEmoji,
      ),
      Player(
        id: 1,
        name: "小明",
        color: const Color(0xFFE53935),
        icon: Icons.face_rounded,
        animationPath: _kComputerImage1, // bunny_bow
        emoji: '🐰',
      ),
      Player(
        id: 2,
        name: "小華",
        color: const Color(0xFF43A047),
        icon: Icons.face_retouching_natural_rounded,
        animationPath: _kComputerImage2, // hamster_foodie
        emoji: '🐹',
      ),
      Player(
        id: 3,
        name: "系統",
        color: const Color(0xFFFF9800),
        icon: Icons.computer_rounded,
        animationPath: _kComputerImage3, // otter_leaf
        emoji: '🦦',
      ),
    ];

    _currentPlayerIdx = 0;
  }
  void _initShakeSensor() {
    _accelerometerSub = accelerometerEvents.listen((event) {
      if (!_gameStarted || _gameOver || _isRolling || _currentPlayerIdx != 0) return;
      final acc = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
      if (acc > 18 && DateTime.now().difference(_lastShakeTime).inMilliseconds > 1500) {
        _lastShakeTime = DateTime.now();
        _rollDice();
      }
    });
  }

  @override
  void dispose() {
    _accelerometerSub?.cancel();
    super.dispose();
  }
  Future<void> _usePetSkill() async {
    if (_currentPetKey == null) {
      return;
    }

    if (_activeSkillUsed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '這局已經使用過主動技能了',
          ),
        ),
      );

      return;
    }

    if (_currentPlayerIdx != 0 ||
        _isRolling ||
        _gameOver) {
      return;
    }

    final player = _players[0];

    switch (_currentPetKey) {
    // ===================================================
    // 狗
    // ===================================================

      case 'dog':
        setState(() {
          _dogRerollReady = true;
          _activeSkillUsed = true;
        });

        _addLog(
          '🐶 再試一次已準備！下一次擲骰會重新擲一次',
        );
        break;

    // ===================================================
    // 貓
    // ===================================================

      case 'cat':
        setState(() {
          _catLightStepReady = true;
          _activeSkillUsed = true;
        });

        _addLog(
          '🐱 輕盈腳步已準備！下一次移動點數 -2',
        );
        break;

    // ===================================================
    // 鸚鵡
    // ===================================================

      case 'parrot':
        int index = player.pathStep;
        int distance = 0;

        do {
          index =
              (index + 1) %
                  _currentPath.length;

          distance++;
        } while (
        _currentPath[index].type !=
            BlockType.chance
        );

        setState(() {
          _activeSkillUsed = true;
        });

        _addLog(
          '🦜 預言家：下一個機會格還有 $distance 格',
        );
        break;

    // ===================================================
    // 樹懶
    // ===================================================

      case 'sloth':
        setState(() {
          player.money += 1500;
          _activeSkillUsed = true;
        });

        _persistPlayerState(player);

        _addLog(
          '🦥 休息一下！跳過回合並獲得 \$1500',
        );

        _endTurn();
        break;

    // ===================================================
    // 狐狸
    // ===================================================

      case 'fox':
        setState(() {
          _foxDiscountReady = true;
          _activeSkillUsed = true;
        });

        _addLog(
          '🦊 討價還價！下一次購地或升級享 7 折',
        );
        break;

    // ===================================================
    // 柴犬
    // ===================================================

      case 'shiba_dog':
        setState(() {
          _activeSkillUsed = true;
          _isRolling = true;
        });

        _addLog(
          '🔥 暴衝！立即額外前進 3 格',
        );

        await _movePlayer(
          player,
          3,
        );

        if (mounted) {
          setState(() {
            _isRolling = false;
          });
        }

        break;

    // ===================================================
    // 博美
    // ===================================================

      case 'pomeranian':
        setState(() {
          _pomeranianRentBoost =
          true;

          _activeSkillUsed =
          true;
        });

        _addLog(
          '✨ 人氣爆棚！下一次收到租金 ×1.5',
        );
        break;

    // ===================================================
    // 佛系狗
    // ===================================================

      case 'calm_dog':
        setState(() {
          _calmDogProtection =
          true;

          _activeSkillUsed =
          true;
        });

        _addLog(
          '😌 隨緣散步！下一次負面機會事件無效',
        );
        break;

    // ===================================================
    // 黏人狗
    // ===================================================

      case 'clingy_dog':
        final targets =
        _players
            .where(
              (p) =>
          p.id != 0 &&
              !p.isBankrupt,
        )
            .toList();

        if (targets.isEmpty) return;

        final target = targets.first;

        setState(() {
          target.pathStep =
              (target.pathStep + 2) %
                  _currentPath.length;

          _activeSkillUsed =
          true;
        });

        _persistPlayerState(target);

        _addLog(
          '🐕 跟我來！${target.name} 被一起帶著前進 2 格',
        );
        break;

    // ===================================================
    // 愛心貓
    // ===================================================

      case 'love_cat':
        setState(() {
          player.money += 2500;

          _activeSkillUsed =
          true;
        });

        _persistPlayerState(player);

        _addLog(
          '💗 治癒時間！立即獲得 \$2500',
        );
        break;

    // ===================================================
    // 工作貓
    // ===================================================

      case 'work_cat':
        final owned =
        _currentPath
            .where(
              (b) =>
          b.ownerId == 0 &&
              b.type ==
                  BlockType.land &&
              b.level < 3,
        )
            .toList();

        if (owned.isEmpty) {
          ScaffoldMessenger.of(context)
              .showSnackBar(
            const SnackBar(
              content: Text(
                '目前沒有可以升級的土地',
              ),
            ),
          );

          return;
        }

        final block = owned.first;

        setState(() {
          block.level++;
          _activeSkillUsed = true;
        });

        _persistBlockState(block);

        _addLog(
          '💼 加班模式！${block.name} 免費升級至 Lv.${block.level}',
        );
        break;

    // ===================================================
    // 火箭貓
    // ===================================================

      case 'rocket_cat':
        int targetIndex =
            player.pathStep;

        int steps = 0;

        do {
          targetIndex =
              (targetIndex + 1) %
                  _currentPath.length;

          steps++;
        } while (
        _currentPath[targetIndex]
            .type !=
            BlockType.chance
        );

        setState(() {
          _activeSkillUsed = true;
          _isRolling = true;
        });

        _addLog(
          '🚀 發射！直接前往下一個機會格',
        );

        await _movePlayer(
          player,
          steps,
        );

        if (mounted) {
          setState(() {
            _isRolling = false;
          });
        }

        break;

    // ===================================================
    // 等待貓
    // ===================================================

      case 'waiting_cat':
        setState(() {
          _waitingCatDelayRent =
          true;

          _activeSkillUsed =
          true;
        });

        _addLog(
          '⏳ 等等再說！下一次租金延後支付',
        );
        break;

    // ===================================================
    // 熊
    // ===================================================

      case 'bear':
        setState(() {
          player.money += 2000;
          _activeSkillUsed = true;
        });

        _persistPlayerState(player);

        _addLog(
          '🐻 午睡時間！跳過回合並獲得 \$2000',
        );

        _endTurn();
        break;

    // ===================================================
    // 蜜蜂
    // ===================================================

      case 'bee':
        setState(() {
          _beeExtraTurnReady =
          true;

          _activeSkillUsed =
          true;
        });

        _addLog(
          '🐝 超時工作！這回合結束後可以再行動一次',
        );
        break;

    // ===================================================
    // 長頸鹿
    // ===================================================

      case 'giraffe':
        _showGiraffeSkillDialog();
        break;
    }
  }
  void _showGiraffeSkillDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title:
          const Text(
            '🦒 看得更遠',
          ),
          content:
          const Text(
            '選擇要前進幾格',
          ),
          actions: [
            for (int i = 1;
            i <= 6;
            i++)
              TextButton(
                onPressed: () async {
                  Navigator.pop(ctx);

                  setState(() {
                    _activeSkillUsed =
                    true;

                    _isRolling =
                    true;
                  });

                  _addLog(
                    '🦒 看得更遠！選擇前進 $i 格',
                  );

                  await _movePlayer(
                    _players[0],
                    i,
                  );

                  if (mounted) {
                    setState(() {
                      _isRolling =
                      false;
                    });
                  }
                },
                child: Text(
                  '$i',
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _rollDice() async {
    if (_isRolling || _gameOver || !_gameStarted) return;

    final p = _players[_currentPlayerIdx];

    // =====================================================
    // 等待貓：支付上一回合延後的租金
    // =====================================================

    if (p.id == 0 &&
        _deferredRent > 0 &&
        _deferredRentOwnerId != null) {
      final owner = _players[_deferredRentOwnerId!];

      setState(() {
        p.money -= _deferredRent;
        owner.money += _deferredRent;
      });

      _addLog(
        '⏳ 延後租金到期！支付 \$${_fmt(_deferredRent)} 給 ${owner.name}',
      );

      _deferredRent = 0;
      _deferredRentOwnerId = null;

      _persistPlayerState(p);
      _persistPlayerState(owner);

      _checkLovelyCatGuard();

      if (p.money <= 0) {
        _endTurn();
        return;
      }
    }

    // =====================================================
    // 等待貓：耐心利息
    // =====================================================

    if (p.id == 0 &&
        _currentPetKey == 'waiting_cat' &&
        _waitingCatInterestReady) {
      setState(() {
        p.money += 800;
        _waitingCatInterestReady = false;
      });

      _addLog('⏳ 耐心利息發動！獲得 \$800');

      _persistPlayerState(p);
    }

    // =====================================================
    // 長頸鹿被動：預覽前面三格
    // =====================================================

    if (p.id == 0 &&
        _currentPetKey == 'giraffe') {
      final previews = <String>[];

      for (int i = 1; i <= 3; i++) {
        final index =
            (p.pathStep + i) % _currentPath.length;

        previews.add(
          _currentPath[index].name,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '🦒 遠見：前方三格 → ${previews.join('、')}',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }

    // =====================================================
    // 監獄
    // =====================================================

    if (p.jailTurns > 0) {
      setState(() {
        p.jailTurns--;
      });

      _addLog(
        '${p.name} 在監獄中，還剩 ${p.jailTurns} 回合',
      );

      _endTurn();
      return;
    }

    setState(() {
      _isRolling = true;
    });

    await Future.delayed(
      const Duration(milliseconds: 650),
    );

    if (!mounted || _gameOver) {
      setState(() {
        _isRolling = false;
      });
      return;
    }

    int dice1 = Random().nextInt(6) + 1;
    int dice2 = Random().nextInt(6) + 1;

    // =====================================================
    // 狗狗主動：重新骰一次
    // =====================================================

    if (p.id == 0 && _dogRerollReady) {
      final firstTotal = dice1 + dice2;

      dice1 = Random().nextInt(6) + 1;
      dice2 = Random().nextInt(6) + 1;

      _dogRerollReady = false;

      _addLog(
        '🐶 再試一次！原本 $firstTotal 點，重新擲出 ${dice1 + dice2} 點',
      );
    }

    int steps = dice1 + dice2;

    // =====================================================
    // 貓咪主動：點數 -2
    // =====================================================

    if (p.id == 0 && _catLightStepReady) {
      steps = max(1, steps - 2);

      _catLightStepReady = false;

      _addLog(
        '🐱 輕盈腳步！本回合調整為 $steps 格',
      );
    }

    // =====================================================
    // 柴犬被動：雙骰額外 +1 格
    // =====================================================

    if (p.id == 0 &&
        _currentPetKey == 'shiba_dog' &&
        dice1 == dice2) {
      steps += 1;

      _addLog(
        '🔥 熱血衝刺！骰到雙骰，額外前進 1 格',
      );
    }

    setState(() {
      _diceValues = [dice1, dice2];
    });

    await _movePlayer(
      p,
      steps,
    );

    if (mounted) {
      setState(() {
        _isRolling = false;
      });
    }
  }

  // 每走一格的節奏。從 180ms 放慢到 420ms，讓玩家看得見棋子一步一步走過去。
  static const Duration _stepInterval =
  Duration(milliseconds: 420);

  Future<void> _movePlayer(
      Player p,
      int steps,
      ) async {
    for (int i = 0; i < steps; i++) {
      await Future.delayed(_stepInterval);

      if (!mounted) return;

      final oldStep = p.pathStep;

      setState(() {
        p.pathStep =
            (p.pathStep + 1) %
                _currentPath.length;
      });

      // ===================================================
      // 經過起點
      // ===================================================

      if (oldStep != 0 &&
          p.pathStep == 0) {
        _handlePassStart(p);
      }
    }

    _handleLandingEvent(p);
  }
  void _handlePassStart(Player p) {
    if (p.id != 0) return;

    switch (_currentPetKey) {
      case 'clingy_dog':
        setState(() {
          p.money += 500;
        });

        _addLog(
          '🐕 一起玩！經過起點額外獲得 \$500',
        );
        break;

      case 'bear':
        setState(() {
          p.money += 1000;
        });

        _addLog(
          '🐻 吃飽再走！經過起點獲得 \$1000',
        );
        break;

      case 'bee':
        setState(() {
          p.money += 1200;
        });

        _addLog(
          '🐝 辛勤工作！經過起點獲得 \$1200',
        );
        break;
    }

    _persistPlayerState(p);
  }

  void _handleLandingEvent(Player p) {
    final block =
    _currentPath[p.pathStep];

    switch (block.type) {
      case BlockType.land:
        _handleLandEvent(
          p,
          block,
        );
        break;

      case BlockType.chance:
        _handleChanceEvent(p);
        break;

      case BlockType.goJail:
        int jailTurns = 3;

        // 樹懶被動
        if (p.id == 0 &&
            _currentPetKey == 'sloth') {
          jailTurns = 2;

          _addLog(
            '🦥 慢慢來！監獄時間減少 1 回合',
          );
        } else {
          _addLog(
            '${p.name} 觸發禁閉事件！',
          );
        }

        p.pathStep = 9;
        p.jailTurns = jailTurns;

        _persistPlayerState(p);

        _endTurn();
        break;

      default:
        _endTurn();
    }
  }

  void _handleLandEvent(
      Player p,
      GameNode block,
      ) {
    // =====================================================
    // 無主土地
    // =====================================================

    if (block.ownerId == null) {
      if (p.id == 0) {
        final buildCost =
        _getBuildCost(p, block);

        if (p.money >= buildCost) {
          _showBuildDialog(
            p,
            block,
          );
        } else {
          _addLog(
            '資金不足，無法購買 ${block.name}',
          );

          _endTurn();
        }

        return;
      }

      // 電腦玩家
      if (p.money >= block.baseCost) {
        setState(() {
          p.money -= block.baseCost;
          block.ownerId = p.id;
          block.level = 1;
        });

        _persistPlayerState(p);
        _persistBlockState(block);

        _addLog(
          '${p.name} 佔領了 ${block.name}',
        );
      }

      _endTurn();
      return;
    }

    // =====================================================
    // 自己土地
    // =====================================================

    if (block.ownerId == p.id) {
      if (block.level < 3 &&
          p.id == 0) {
        final upgradeCost =
        _getUpgradeCost(
          p,
          block,
        );

        if (p.money >= upgradeCost) {
          _showUpgradeDialog(
            p,
            block,
          );

          return;
        }
      }

      _endTurn();
      return;
    }

    // =====================================================
    // 踩到別人的土地
    // =====================================================

    int rent = block.rent;

    final owner =
    _players[block.ownerId!];

    // -----------------------------------------------------
    // 貓咪被動：第一次租金減半
    // -----------------------------------------------------

    if (p.id == 0 &&
        _currentPetKey == 'cat' &&
        !_usedPassiveSkills.contains(
          'cat_rent',
        )) {
      rent = (rent * 0.5).round();

      _usedPassiveSkills.add(
        'cat_rent',
      );

      _addLog(
        '🐱 優雅閃避！本次租金減少 50%',
      );
    }

    // -----------------------------------------------------
    // 佛系狗：第一次金錢損失減半
    // -----------------------------------------------------

    if (p.id == 0 &&
        _currentPetKey == 'calm_dog' &&
        !_usedPassiveSkills.contains(
          'calm_loss',
        )) {
      rent = (rent * 0.5).round();

      _usedPassiveSkills.add(
        'calm_loss',
      );

      _addLog(
        '😌 看開一點！本次租金損失減少 50%',
      );
    }

    // -----------------------------------------------------
    // 等待貓：延後租金
    // -----------------------------------------------------

    if (p.id == 0 &&
        _currentPetKey == 'waiting_cat' &&
        _waitingCatDelayRent) {
      _waitingCatDelayRent = false;

      _deferredRent = rent;
      _deferredRentOwnerId =
          block.ownerId;

      _addLog(
        '⏳ 等等再說！\$${_fmt(rent)} 租金延後到下個回合支付',
      );

      _endTurn();
      return;
    }

    // -----------------------------------------------------
    // 博美：收到租金
    // -----------------------------------------------------

    if (owner.id == 0 &&
        _currentPetKey == 'pomeranian') {
      if (_pomeranianRentBoost) {
        rent =
            (rent * 1.5).round();

        _pomeranianRentBoost = false;

        _addLog(
          '✨ 人氣爆棚！本次租金提升為 1.5 倍',
        );
      } else if (
      !_usedPassiveSkills.contains(
        'pomeranian_rent',
      )) {
        rent =
            (rent * 1.25).round();

        _usedPassiveSkills.add(
          'pomeranian_rent',
        );

        _addLog(
          '✨ 明星光環！第一次租金增加 25%',
        );
      }
    }

    setState(() {
      p.money -= rent;
      owner.money += rent;
    });

    _persistPlayerState(p);
    _persistPlayerState(owner);

    _addLog(
      '${p.name} 支付租金 \$${_fmt(rent)} 給 ${owner.name}',
    );

    _checkLovelyCatGuard();

    _endTurn();
  }
  int _getBuildCost(
      Player p,
      GameNode block,
      ) {
    int cost = block.baseCost;

    if (p.id != 0) {
      return cost;
    }

    if (_currentPetKey == 'fox') {
      // 主動技能優先
      if (_foxDiscountReady) {
        return (cost * 0.7).round();
      }

      // 被動：第一次購地 8 折
      if (!_usedPassiveSkills.contains(
        'fox_first_buy',
      )) {
        return (cost * 0.8).round();
      }
    }

    return cost;
  }


  int _getUpgradeCost(
      Player p,
      GameNode block,
      ) {
    int cost =
    (block.baseCost * 0.6).round();

    if (p.id != 0) {
      return cost;
    }

    // 狐狸主動
    if (_currentPetKey == 'fox' &&
        _foxDiscountReady) {
      cost = (cost * 0.7).round();
    }

    // 工作貓被動
    if (_currentPetKey == 'work_cat') {
      cost = (cost * 0.9).round();
    }

    return cost;
  }

  void _handleChanceEvent(Player p) {
    int delta =
    Random().nextBool()
        ? 5000
        : -2000;

    if (p.id == 0) {
      // ===================================================
      // 正面事件
      // ===================================================

      if (delta > 0) {
        if (_currentPetKey == 'parrot') {
          delta =
              (delta * 1.15).round();

          _addLog(
            '🦜 消息靈通！機會獎勵增加 15%',
          );
        }

        if (_currentPetKey ==
            'rocket_cat') {
          delta =
              (delta * 1.20).round();

          _addLog(
            '🚀 冒險加成！機會獎勵增加 20%',
          );
        }
      }

      // ===================================================
      // 負面事件
      // ===================================================

      if (delta < 0) {
        // 佛系狗主動：完全免疫
        if (_currentPetKey ==
            'calm_dog' &&
            _calmDogProtection) {
          delta = 0;

          _calmDogProtection =
          false;

          _addLog(
            '😌 隨緣散步！本次負面事件完全無效',
          );
        }

        // 狗狗被動
        else if (_currentPetKey ==
            'dog' &&
            !_usedPassiveSkills.contains(
              'dog_chance',
            )) {
          delta =
              (delta * 0.5).round();

          _usedPassiveSkills.add(
            'dog_chance',
          );

          _addLog(
            '🐶 幸運尾巴！第一次負面事件損失減半',
          );
        }

        // 佛系狗被動
        else if (_currentPetKey ==
            'calm_dog' &&
            !_usedPassiveSkills.contains(
              'calm_loss',
            )) {
          delta =
              (delta * 0.5).round();

          _usedPassiveSkills.add(
            'calm_loss',
          );

          _addLog(
            '😌 看開一點！金錢損失減半',
          );
        }
      }
    }

    setState(() {
      p.money += delta;
    });

    _persistPlayerState(p);

    _checkLovelyCatGuard();

    if (delta == 0) {
      _addLog(
        '${p.name} 成功避開機遇事件的損失！',
      );
    } else {
      _addLog(
        '${p.name} ${delta > 0 ? '獲得' : '損失'} \$${delta.abs()} 機遇事件！',
      );
    }

    _endTurn();
  }
  void _checkLovelyCatGuard() {
    if (_currentPetKey !=
        'love_cat') {
      return;
    }

    if (_usedPassiveSkills.contains(
      'lovely_guard',
    )) {
      return;
    }

    final player = _players[0];

    if (player.money < 5000) {
      setState(() {
        player.money += 2000;
      });

      _usedPassiveSkills.add(
        'lovely_guard',
      );

      _persistPlayerState(player);

      _addLog(
        '💗 暖心守護！資金低於 \$5000，自動補助 \$2000',
      );
    }
  }

  void _endTurn() {
    if (_gameOver) return;
    _persistAllPlayers();

    // 標記並檢查破產
    for (final p in _players) {
      if (p.money <= 0 && !p.isBankrupt) {
        p.isBankrupt = true;
        // 若玩家 0（使用者）破產 → 遊戲直接結束
        if (p.id == 0) {
          setState(() { _gameOver = true; _gameLog = "你的寵物破產了！本月冒險結束"; });
          return;
        }
        _addLog("${p.name} 已破產，退出遊戲！");
      }
    }

    // 若存活玩家只剩自己，也算結束
    final alive = _players.where((p) => !p.isBankrupt).toList();
    if (alive.length == 1) {
      setState(() { _gameOver = true; _gameLog = "${alive.first.name} 獲得最終勝利！本月冒險結束"; });
      return;
    }
    // 蜜蜂主動：再行動一次
    if (_currentPlayerIdx == 0 &&
        _beeExtraTurnReady) {
      setState(() {
        _beeExtraTurnReady = false;
      });

      _addLog(
        '🐝 超時工作發動！再行動一次',
      );

      return;
    }
    // 找下一個未破產的玩家
    int next = (_currentPlayerIdx + 1) % _players.length;
    while (_players[next].isBankrupt) {
      next = (next + 1) % _players.length;
    }
    setState(() => _currentPlayerIdx = next);
    if (_currentPlayerIdx != 0) Future.delayed(const Duration(seconds: 1), _rollDice);
  }

  void _addLog(String msg) {
    setState(() => _gameLog = msg);
    // ★ 新增：一樣先拿真正登入的 user_id，再送出遊戲紀錄，避免紀錄也混在共用帳號裡
    GameApiService.instance.resolveCurrentUserId().then((realUserId) {
      GameApiService.instance
          .addGameLog(userId: realUserId, eventType: 'game', message: msg)
          .catchError((_) {});
    });
  }

  void _startGame(MapTheme theme) {
    SelectedPet.lastMapTheme =
        theme;

    setState(() {
      _initMapData(theme);
      _initPlayers();

      _gameStarted = true;
      _gameOver = false;

      _isLoadingGameState = true;

      // ==============================
      // 每局技能全部重置
      // ==============================

      _activeSkillUsed = false;

      _usedPassiveSkills.clear();

      _dogRerollReady = false;
      _catLightStepReady = false;

      _foxDiscountReady = false;

      _calmDogProtection = false;

      _pomeranianRentBoost = false;

      _waitingCatDelayRent = false;

      _waitingCatInterestReady = false;

      _deferredRent = 0;
      _deferredRentOwnerId = null;

      _beeExtraTurnReady = false;
    });

    _loadGameStateFromApi(theme);
  }

  // =====================================================================
  // BUILD
  // =====================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _gameStarted ? _buildGameBoard() : _buildSelectionScreen(),
    );
  }

  Widget _buildGameBoard() {
    final isMagic = _currentTheme == MapTheme.magicIsland;

    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isMagic
                  ? [const Color(0xFFF8E8FF), const Color(0xFFEDD5F5)]
                  : [const Color(0xFFE1F5FE), const Color(0xFFE8F5E9)],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                _buildGameLog(),
                const SizedBox(height: 4),
                Expanded(child: IslandBoard3D(
                  key: ValueKey(_currentTheme),
                  sites: _currentPath.map((node) {
                    final owners = _players.where((p) => p.id == node.ownerId);
                    final owner = owners.isEmpty ? null : owners.first;
                    return BoardSite3D(name: node.name, kind: node.type.name,
                        cost: node.baseCost, rent: node.rent, level: node.level,
                        ownerColor: owner?.color, ownerName: owner?.name);
                  }).toList(),
                  pawns: _players.where((p) => !p.isBankrupt).map((p) => BoardPawn3D(
                      id: p.id, name: p.name, step: p.pathStep, color: p.color,
                      imagePath: p.animationPath, emoji: p.emoji)).toList(),
                  activePlayerId: _players[_currentPlayerIdx].id,
                  nextStep: !_gameOver && _currentPlayerIdx == 0
                      ? (_players[0].pathStep + 1) % _currentPath.length : null,
                  magic: isMagic, accent: AppPalette.of(context).accent,
                )),
                _buildBottomBar(),
              ],
            ),
          ),
        ),
        // ── 遊戲結束 Overlay ──
        if (_gameOver) _buildGameOverOverlay(),
      ],
    );
  }

  Widget _buildGameOverOverlay() {
    final isMagic = _currentTheme == MapTheme.magicIsland;
    final isWin   = _gameLog.contains('勝利');
    return Container(
      color: Colors.black.withOpacity(0.65),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 32),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 30)],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(isWin ? '🏆' : '😢', style: const TextStyle(fontSize: 54)),
              const SizedBox(height: 10),
              Text(
                isWin ? '本月冒險結束！' : '遊戲結束',
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF5D4037)),
              ),
              const SizedBox(height: 8),
              Text(
                _gameLog,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600, height: 1.5),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: (isMagic ? const Color(0xFFF3E5F5) : const Color(0xFFF1F8E9)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '下次月初可重新開始冒險',
                  style: TextStyle(
                    fontSize: 12,
                    color: isMagic ? const Color(0xFF8E24AA) : const Color(0xFF388E3C),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        shape: const StadiumBorder(),
                        side: BorderSide(color: Colors.grey.shade400),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('回寵物', style: TextStyle(color: Colors.grey)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => setState(() {
                        _gameStarted = false;
                        _gameOver = false;
                      }),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppPalette.of(context).accent,
                        foregroundColor: Colors.white,
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('重新選圖', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- 頂部資產列 ---
  Widget _buildTopBar() {
    final isMagic = _currentTheme == MapTheme.magicIsland;
    final accent = isMagic ? const Color(0xFFCE93D8) : const Color(0xFF81C784);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: [
          _roundIconButton(Icons.arrow_back_ios_new_rounded, accent,
                  () => Navigator.of(context).maybePop()),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.88),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: accent.withOpacity(0.4), width: 1.5),
                boxShadow: [BoxShadow(color: accent.withOpacity(0.15), blurRadius: 8, offset: const Offset(0, 2))],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: _players.map((p) {
                  final isActive = p.id == _currentPlayerIdx;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    padding: isActive ? const EdgeInsets.symmetric(horizontal: 6, vertical: 2) : EdgeInsets.zero,
                    decoration: BoxDecoration(
                      color: isActive ? p.color.withOpacity(0.15) : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: p.color.withOpacity(isActive ? 1.0 : 0.45),
                          ),
                          child: p.animationPath != null
                              ? Padding(
                            padding: const EdgeInsets.all(3),
                            child: Image.asset(
                              p.animationPath!,
                              fit: BoxFit.contain,
                            ),
                          )
                              : Icon(
                            p.icon,
                            size: 13,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          "\$${(p.money / 1000).toStringAsFixed(1)}k",
                          style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: isActive ? p.color : Colors.grey.shade500),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _roundIconButton(Icons.group_rounded, accent,
                  () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FriendPage()))),
        ],
      ),
    );
  }

  Widget _roundIconButton(IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 44, height: 44,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.9),
          shape: BoxShape.circle,
          border: Border.all(color: color.withOpacity(0.4), width: 1.5),
          boxShadow: [BoxShadow(color: color.withOpacity(0.2), blurRadius: 6)],
        ),
        child: Icon(icon, color: color, size: 22),
      ),
    );
  }

  // --- 事件日誌 ---
  Widget _buildGameLog() {
    final isMagic = _currentTheme == MapTheme.magicIsland;
    final bg    = isMagic ? const Color(0xFFF8E8FF) : const Color(0xFFF1F8E9);
    final border = isMagic ? const Color(0xFFCE93D8) : const Color(0xFF81C784);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border.withOpacity(0.5), width: 1.5),
        ),
        child: Row(
          children: [
            Text(isMagic ? "✨" : "🌸", style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 8),
            Expanded(child: Text(_gameLog, style: TextStyle(color: Colors.grey.shade700, fontSize: 11.5, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis, maxLines: 2)),
          ],
        ),
      ),
    );
  }

  // --- 底部骰子 + 按鈕 ---
  Widget _buildBottomBar() {
    final isMagic =
        _currentTheme == MapTheme.magicIsland;

    final canRoll =
        !_gameOver &&
            !_isRolling &&
            _currentPlayerIdx == 0;

    final accent = isMagic
        ? const Color(0xFFBA68C8)
        : const Color(0xFF66BB6A);

    final skill =
    getPetSkill(_currentPetKey);

    return Padding(
      padding:
      const EdgeInsets.fromLTRB(
        14,
        0,
        14,
        10,
      ),
      child: ClipRRect(
        borderRadius:
        BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: 18,
            sigmaY: 18,
          ),
          child: Container(
            padding:
            const EdgeInsets.fromLTRB(
              16,
              12,
              16,
              12,
            ),
            decoration: BoxDecoration(
              color:
              Colors.white.withOpacity(0.68),
              borderRadius:
              BorderRadius.circular(28),
              border: Border.all(
                color:
                accent.withOpacity(0.3),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color:
                  accent.withOpacity(0.18),
                  blurRadius: 16,
                  offset:
                  const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment:
              MainAxisAlignment
                  .spaceBetween,
              crossAxisAlignment:
              CrossAxisAlignment.center,
              children: [
                // =========================
                // 左邊：骰子
                // =========================
                Row(
                  children:
                  _diceValues.map((v) {
                    return Padding(
                      padding:
                      const EdgeInsets
                          .only(
                        right: 8,
                      ),
                      child: Dice3D(
                        value: v,
                        isRolling:
                        _isRolling,
                        isMagic:
                        isMagic,
                      ),
                    );
                  }).toList(),
                ),

                // =========================
                // 右邊：出發 + 選寵物 + 技能
                // =========================
                Column(
                  mainAxisSize:
                  MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize:
                      MainAxisSize.min,
                      children: [
                        ElevatedButton(
                          onPressed:
                          canRoll
                              ? _rollDice
                              : null,
                          style:
                          ElevatedButton
                              .styleFrom(
                            backgroundColor:
                            canRoll
                                ? accent
                                : Colors
                                .grey
                                .shade300,
                            foregroundColor:
                            Colors.white,
                            padding:
                            const EdgeInsets
                                .symmetric(
                              horizontal: 22,
                              vertical: 11,
                            ),
                            shape:
                            const StadiumBorder(),
                          ),
                          child: Text(
                            _isRolling
                                ? '擲中...'
                                : (_currentPlayerIdx ==
                                0
                                ? '出發！'
                                : '電腦回合'),
                          ),
                        ),

                        const SizedBox(
                            width: 8),

                        // =================
                        // 選擇寵物
                        // =================
                        InkWell(
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                const PetPage(),
                              ),
                            );

                            // 回來後重新讀寵物
                            await _loadCurrentPetSkill();
                            await _ensureSelectedPetImageLoaded();

                            if (mounted) {
                              setState(() {});
                            }
                          },
                          customBorder:
                          const CircleBorder(),
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration:
                            BoxDecoration(
                              color:
                              Colors.white,
                              shape:
                              BoxShape.circle,
                              border:
                              Border.all(
                                color: accent
                                    .withOpacity(
                                    0.6),
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: accent
                                      .withOpacity(
                                      0.18),
                                  blurRadius: 8,
                                  offset:
                                  const Offset(
                                      0, 3),
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons
                                  .pets_rounded,
                              color: accent,
                              size: 23,
                            ),
                          ),
                        ),
                      ],
                    ),

                    // =========================
                    // 寵物技能
                    // =========================
                    if (skill != null) ...[
                      const SizedBox(
                          height: 4),

                      SizedBox(
                        height: 30,
                        child:
                        ElevatedButton
                            .icon(
                          onPressed:
                          canRoll &&
                              !_activeSkillUsed
                              ? _usePetSkill
                              : null,
                          icon: Icon(
                            skill.skillIcon,
                            size: 14,
                          ),
                          label: Text(
                            _activeSkillUsed
                                ? '技能已使用'
                                : skill
                                .activeName,
                            style:
                            const TextStyle(
                              fontSize: 10,
                              fontWeight:
                              FontWeight
                                  .bold,
                            ),
                          ),
                          style:
                          ElevatedButton
                              .styleFrom(
                            backgroundColor:
                            const Color(
                                0xFFFFA726),
                            foregroundColor:
                            Colors.white,
                            disabledBackgroundColor:
                            Colors
                                .grey
                                .shade300,
                            disabledForegroundColor:
                            Colors
                                .grey
                                .shade600,
                            padding:
                            const EdgeInsets
                                .symmetric(
                              horizontal: 10,
                            ),
                            shape:
                            const StadiumBorder(),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- 地圖選擇畫面 ---
  Widget _buildSelectionScreen() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFFFFF0F5),
            Color(0xFFE8F5E9),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        child: Stack(
          children: [
            Positioned(
              left: 12,
              top: 8,
              child: _roundIconButton(
                Icons.arrow_back_ios_new_rounded,
                AppPalette.of(context).accent,
                    () => Navigator.of(context).maybePop(),
              ),
            ),

            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  "🎲",
                  style: TextStyle(fontSize: 56),
                ),

                const SizedBox(height: 10),

                const Text(
                  "選擇冒險地圖",
                  style: TextStyle(
                    color: Color(0xFF5D4037),
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),

                const SizedBox(height: 6),

                Text(
                  "搖一搖手機可以擲骰子！",
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 13,
                  ),
                ),

                const SizedBox(height: 40),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _themeCard(
                      MapTheme.taiwan,
                      "台灣環島",
                      "🗺️",
                      const Color(0xFF81C784),
                      const Color(0xFFF1F8E9),
                      const Color(0xFFE8F5E9),
                    ),

                    const SizedBox(width: 20),

                    _themeCard(
                      MapTheme.magicIsland,
                      "魔法天空島",
                      "✨",
                      const Color(0xFFBA68C8),
                      const Color(0xFFF8E8FF),
                      const Color(0xFFF3E5F5),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _themeCard(MapTheme theme, String name, String emoji, Color accent, Color bgTop, Color bgBot) {
    return InkWell(
      onTap: () => _startGame(theme),
      borderRadius: BorderRadius.circular(28),
      child: Container(
        width: 148,
        height: 208,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [bgTop, bgBot], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: accent.withOpacity(0.45), width: 2),
          boxShadow: [BoxShadow(color: accent.withOpacity(0.25), blurRadius: 16, offset: const Offset(0, 4))],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 76, height: 76,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.8),
                shape: BoxShape.circle,
                border: Border.all(color: accent.withOpacity(0.35), width: 2),
              ),
              child: Center(child: Text(emoji, style: const TextStyle(fontSize: 38))),
            ),
            const SizedBox(height: 14),
            Text(name, style: TextStyle(color: accent.withAlpha(230), fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: BoxDecoration(color: accent.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
              child: Text("點擊開始", style: TextStyle(fontSize: 12, color: accent, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  // --- 遊戲結束 ---
  // --- 對話框 ---
  void _showBuildDialog(
      Player p,
      GameNode b,
      ) {
    final cost =
    _getBuildCost(
      p,
      b,
    );

    showDialog(
      context: context,
      builder: (ctx) =>
          _gameDialog(
            title: '🏗 抵達 ${b.name}',
            content:
            '基礎建設費用 \$${_fmt(cost)}\n'
                '您的資金 \$${_fmt(p.money)}\n'
                '要投資嗎？',
            cancelLabel: '路過',
            confirmLabel: '確認建設',

            onConfirm: () {
              setState(() {
                p.money -= cost;

                b.ownerId = p.id;
                b.level = 1;

                if (_currentPetKey ==
                    'fox' &&
                    _foxDiscountReady) {
                  _foxDiscountReady =
                  false;
                } else if (
                _currentPetKey ==
                    'fox') {
                  _usedPassiveSkills.add(
                    'fox_first_buy',
                  );
                }
              });

              _persistPlayerState(p);
              _persistBlockState(b);

              _addLog(
                '${p.name} 佔領了 ${b.name}！',
              );

              Navigator.pop(ctx);

              _endTurn();
            },

            onCancel: () {
              // 等待貓被動
              if (_currentPetKey ==
                  'waiting_cat') {
                _waitingCatInterestReady =
                true;

                _addLog(
                  '⏳ 耐心等待！下回合將獲得 \$800',
                );
              }

              Navigator.pop(ctx);

              _endTurn();
            },
          ),
    );
  }

  void _showUpgradeDialog(
      Player p,
      GameNode b,
      ) {
    final cost =
    _getUpgradeCost(
      p,
      b,
    );

    showDialog(
      context: context,
      builder: (ctx) =>
          _gameDialog(
            title: '⬆️ 升級 ${b.name}',
            content:
            '升級費用 \$${_fmt(cost)}\n'
                '升至 Lv.${b.level + 1}，租金提升！\n'
                '您的資金 \$${_fmt(p.money)}',
            cancelLabel: '取消',
            confirmLabel: '確認升級',

            onConfirm: () {
              setState(() {
                p.money -= cost;
                b.level += 1;

                if (_currentPetKey ==
                    'fox' &&
                    _foxDiscountReady) {
                  _foxDiscountReady =
                  false;
                }
              });

              _persistPlayerState(p);
              _persistBlockState(b);

              Navigator.pop(ctx);

              _endTurn();
            },

            onCancel: () {
              Navigator.pop(ctx);

              _endTurn();
            },
          ),
    );
  }

  Widget _gameDialog({
    required String title,
    required String content,
    required String cancelLabel,
    required String confirmLabel,
    required VoidCallback onConfirm,
    required VoidCallback onCancel,
  }) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      content: Text(content, style: const TextStyle(fontSize: 14, height: 1.6)),
      actions: [
        TextButton(onPressed: onCancel, child: Text(cancelLabel, style: const TextStyle(color: Colors.grey))),
        ElevatedButton(
          onPressed: onConfirm,
          style: ElevatedButton.styleFrom(backgroundColor: AppPalette.of(context).accent, foregroundColor: Colors.white, shape: const StadiumBorder()),
          child: Text(confirmLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  String _fmt(int v) => v >= 10000 ? "${(v / 10000).toStringAsFixed(1)}萬" : v.toString();
}

// ==========================================================
// 棋子的大頭針形狀
// ==========================================================
class _PinPainter extends CustomPainter {
  final Color color;
  _PinPainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }
  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ==========================================================
// 台灣地圖背景繪製器（可愛版）
// ==========================================================
class TaiwanMapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 淡藍海洋底色
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h),
        Paint()..color = const Color(0xFFB3E5FC));

    // 可愛海浪（簡單弧線）
    final wavePaint = Paint()
      ..color = Colors.white.withOpacity(0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (int i = 0; i < 6; i++) {
      final y = h * (0.12 + i * 0.14);
      final path = Path()..moveTo(0, y);
      for (double x = 0; x <= w; x += w / 4) {
        path.quadraticBezierTo(x + w / 8, y - 5, x + w / 4, y);
      }
      canvas.drawPath(path, wavePaint);
    }

    // 台灣島（圓潤可愛形狀）
    final islandPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [const Color(0xFFA5D6A7), const Color(0xFF66BB6A)],
      ).createShader(Rect.fromLTWH(w * 0.2, h * 0.05, w * 0.6, h * 0.9));
    final island = Path();
    island.moveTo(w * 0.55, h * 0.06);
    island.cubicTo(w * 0.68, h * 0.05, w * 0.80, h * 0.16, w * 0.79, h * 0.32);
    island.cubicTo(w * 0.82, h * 0.48, w * 0.77, h * 0.63, w * 0.72, h * 0.76);
    island.cubicTo(w * 0.65, h * 0.92, w * 0.54, h * 0.98, w * 0.48, h * 0.97);
    island.cubicTo(w * 0.36, h * 0.95, w * 0.22, h * 0.82, w * 0.21, h * 0.70);
    island.cubicTo(w * 0.17, h * 0.55, w * 0.19, h * 0.38, w * 0.24, h * 0.28);
    island.cubicTo(w * 0.30, h * 0.13, w * 0.42, h * 0.07, w * 0.55, h * 0.06);
    island.close();
    paintRaisedIsland(canvas, island, side: const Color(0xFF63946B), depth: h * .024);
    canvas.drawPath(island, islandPaint);

    // 島嶼白色邊框
    canvas.drawPath(island, Paint()
      ..color = Colors.white.withOpacity(0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2);

    // 簡單山脈（可愛鋸齒）
    final mtPaint = Paint()
      ..color = const Color(0xFF388E3C).withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeJoin = StrokeJoin.round;
    final mt = Path()..moveTo(w * 0.46, h * 0.15);
    for (final pt in [
      [0.50, 0.24], [0.46, 0.33], [0.49, 0.43],
      [0.44, 0.52], [0.47, 0.62], [0.43, 0.74],
    ]) { mt.lineTo(w * pt[0], h * pt[1]); }
    canvas.drawPath(mt, mtPaint);

    // 澎湖（小圓島）
    final isletPaint = Paint()..color = const Color(0xFF81C784);
    canvas.drawCircle(Offset(w * 0.09, h * 0.43), w * 0.028, isletPaint);
    canvas.drawCircle(Offset(w * 0.09, h * 0.43), w * 0.028,
        Paint()..color = Colors.white.withOpacity(0.6)..style = PaintingStyle.stroke..strokeWidth = 1.5);
    canvas.drawCircle(Offset(w * 0.13, h * 0.47), w * 0.016, isletPaint);

    // 可愛太陽（右上角）
    final sunPaint = Paint()..color = const Color(0xFFFFD54F);
    canvas.drawCircle(Offset(w * 0.88, h * 0.10), w * 0.055, sunPaint);
    canvas.drawCircle(Offset(w * 0.88, h * 0.10), w * 0.055,
        Paint()..color = Colors.white.withOpacity(0.5)..style = PaintingStyle.stroke..strokeWidth = 1);

    // 可愛白雲
    _drawCloud(canvas, Offset(w * 0.15, h * 0.08), w * 0.07);
    _drawCloud(canvas, Offset(w * 0.82, h * 0.25), w * 0.06);
  }

  void _drawCloud(Canvas canvas, Offset center, double r) {
    final p = Paint()..color = Colors.white.withOpacity(0.85);
    canvas.drawCircle(center, r, p);
    canvas.drawCircle(Offset(center.dx + r * 0.9, center.dy), r * 0.75, p);
    canvas.drawCircle(Offset(center.dx - r * 0.7, center.dy), r * 0.7, p);
    canvas.drawCircle(Offset(center.dx + r * 0.3, center.dy - r * 0.5), r * 0.7, p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ==========================================================
// 魔法天空島背景繪製器（可愛版）
// ==========================================================
class MagicIslandPainter extends CustomPainter {
  const MagicIslandPainter({required this.accent});

  /// 從設定頁的色相帶進來，魔法島的粉紅系裝飾才會跟著使用者的配色變。
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 柔和粉紫漸層底色
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          HSLColor.fromColor(accent).withLightness(0.93).toColor(),
          const Color(0xFFEDE7F6),
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );

    // A raised floating platform underneath the original circular route.
    final platform = Path()..addOval(Rect.fromCenter(
        center: Offset(w * .5, h * .53), width: w * .92, height: h * .84));
    paintRaisedIsland(canvas, platform,
        side: Color.lerp(accent, const Color(0xFF786794), .45)!, depth: h * .032);
    canvas.drawPath(platform, Paint()..shader = LinearGradient(
      begin: Alignment.topLeft, end: Alignment.bottomRight,
      colors: [HSLColor.fromColor(accent).withLightness(.96).toColor(),
        HSLColor.fromColor(accent).withLightness(.85).toColor()],
    ).createShader(Rect.fromLTWH(0, 0, w, h)));
    canvas.drawPath(platform, Paint()..color = Colors.white.withOpacity(.65)
      ..style = PaintingStyle.stroke..strokeWidth = 2);

    // 可愛彩虹弧
    _drawRainbow(canvas, Offset(w * 0.5, h * 0.55), w * 0.42);

    // 散落小愛心
    final rng = Random(42);
    final heartColors = [
      accent, const Color(0xFFCE93D8),
      const Color(0xFFFFCC80), const Color(0xFF80DEEA),
    ];
    for (int i = 0; i < 18; i++) {
      final x = rng.nextDouble() * w;
      final y = rng.nextDouble() * h;
      final r = rng.nextDouble() * 4 + 2.5;
      final c = heartColors[i % heartColors.length].withOpacity(0.55);
      _drawHeart(canvas, Offset(x, y), r, c);
    }

    // 可愛星星（★）
    const starPos = [
      [0.12, 0.10], [0.88, 0.08], [0.05, 0.52],
      [0.93, 0.45], [0.50, 0.04], [0.75, 0.90],
      [0.20, 0.85], [0.65, 0.12],
    ];
    final starPaint = Paint()..color = const Color(0xFFFFD54F);
    for (final s in starPos) {
      _drawSimpleStar(canvas, Offset(s[0] * w, s[1] * h), 5.5, starPaint);
    }

    // 中央魔法圓
    canvas.drawCircle(Offset(w / 2, h / 2), w * 0.10,
        Paint()..color = HSLColor.fromColor(accent).withLightness(0.86).toColor().withOpacity(0.7));
    canvas.drawCircle(Offset(w / 2, h / 2), w * 0.10,
        Paint()..color = accent.withOpacity(0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);

    // 軌道圓（淡）
    canvas.drawCircle(Offset(w / 2, h / 2), w * 0.38,
        Paint()..color = const Color(0xFFCE93D8).withOpacity(0.2)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);

    // 白雲
    _drawCloud(canvas, Offset(w * 0.12, h * 0.12), w * 0.07);
    _drawCloud(canvas, Offset(w * 0.85, h * 0.22), w * 0.06);
  }

  void _drawRainbow(Canvas canvas, Offset center, double r) {
    final colors = [
      const Color(0xFFFF8A80), const Color(0xFFFFD180),
      const Color(0xFFCCFF90), const Color(0xFF80D8FF),
      const Color(0xFFEA80FC),
    ];
    for (int i = 0; i < colors.length; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: r - i * (r * 0.1)),
        pi, pi,
        false,
        Paint()..color = colors[i].withOpacity(0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.08,
      );
    }
  }

  void _drawSimpleStar(Canvas canvas, Offset c, double r, Paint p) {
    final path = Path();
    for (int i = 0; i < 5; i++) {
      final outerA = -pi / 2 + i * 2 * pi / 5;
      final innerA = outerA + pi / 5;
      final outerPt = Offset(c.dx + r * cos(outerA), c.dy + r * sin(outerA));
      final innerPt = Offset(c.dx + r * 0.4 * cos(innerA), c.dy + r * 0.4 * sin(innerA));
      if (i == 0) path.moveTo(outerPt.dx, outerPt.dy);
      else path.lineTo(outerPt.dx, outerPt.dy);
      path.lineTo(innerPt.dx, innerPt.dy);
    }
    path.close();
    canvas.drawPath(path, p);
  }

  void _drawHeart(Canvas canvas, Offset c, double r, Color color) {
    final p = Paint()..color = color;
    final path = Path();
    path.moveTo(c.dx, c.dy + r * 0.5);
    path.cubicTo(c.dx - r * 2, c.dy - r, c.dx - r * 2, c.dy - r * 2.5, c.dx, c.dy - r * 1.5);
    path.cubicTo(c.dx + r * 2, c.dy - r * 2.5, c.dx + r * 2, c.dy - r, c.dx, c.dy + r * 0.5);
    canvas.drawPath(path, p);
  }

  void _drawCloud(Canvas canvas, Offset center, double r) {
    final p = Paint()..color = Colors.white.withOpacity(0.8);
    canvas.drawCircle(center, r, p);
    canvas.drawCircle(Offset(center.dx + r * 0.9, center.dy), r * 0.75, p);
    canvas.drawCircle(Offset(center.dx - r * 0.7, center.dy), r * 0.7, p);
    canvas.drawCircle(Offset(center.dx + r * 0.3, center.dy - r * 0.5), r * 0.7, p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ==========================================================
// 路徑連線繪製器（可愛版）
// ==========================================================
class PathLinePainter extends CustomPainter {
  final List<GameNode> nodes;
  final bool isMagic;
  PathLinePainter({required this.nodes, required this.isMagic});

  @override
  void paint(Canvas canvas, Size size) {
    final color = isMagic ? const Color(0xFFCE93D8) : const Color(0xFF66BB6A);
    final dotPaint = Paint()..color = color.withOpacity(0.7)..style = PaintingStyle.fill;

    for (int i = 0; i < nodes.length; i++) {
      final s = Offset(nodes[i].position.dx * size.width, nodes[i].position.dy * size.height);
      final e = Offset(nodes[(i + 1) % nodes.length].position.dx * size.width, nodes[(i + 1) % nodes.length].position.dy * size.height);
      final len = (e - s).distance;
      final dir = (e - s) / len;
      double d = 6;
      while (d < len - 4) {
        canvas.drawCircle(s + dir * d, 2.2, dotPaint);
        d += 9;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}