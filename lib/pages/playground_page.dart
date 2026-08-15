import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:lottie/lottie.dart';
import 'package:sensors_plus/sensors_plus.dart';

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

  // 縮放手勢
  double _scale = 1.0;
  double _baseScale = 1.0;

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
      final data = await GameApiService.instance.fetchGameState(
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
      await GameApiService.instance.updatePlayerState(
        localId: p.id, money: p.money, pathStep: p.pathStep,
        jailTurns: p.jailTurns, isBankrupt: p.isBankrupt, theme: _themeKey,
      );
    } catch (_) {}
  }

  Future<void> _persistBlockState(GameNode block) async {
    final idx = _currentPath.indexOf(block);
    if (idx < 0) return;
    try {
      await GameApiService.instance.updateBlockState(
        theme: _themeKey, index: idx, name: block.name, baseCost: block.baseCost,
        blockType: _blockTypeKey(block.type), positionDx: block.position.dx, positionDy: block.position.dy,
        level: block.level, ownerLocalId: block.ownerId,
      );
    } catch (_) {}
  }

  Future<void> _persistAllPlayers() async { for (final p in _players) await _persistPlayerState(p); }
  Future<void> _persistAllBlocks()  async { for (final b in _currentPath) await _persistBlockState(b); }

  @override
  void initState() {
    super.initState();
    _initPlayers();
    _initShakeSensor();
    final autoMap = widget.initialMapTheme ?? SelectedPet.lastMapTheme;
    if (autoMap != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startGame(autoMap);
      });
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
    final petAnim  = widget.petAnimationPath ?? SelectedPet.animationPath;
    final petEmoji = widget.petEmoji         ?? SelectedPet.emoji;
    final petName  = widget.petName          ?? SelectedPet.name ?? "您";
    final petColor = widget.petColor         ?? SelectedPet.color ?? const Color(0xFF2196F3);

    _players = [
      Player(
        id: 0,
        name: petName,
        color: petColor,
        icon: Icons.pets_rounded,
        animationPath: petAnim,
        emoji: petEmoji,
      ),
      Player(id: 1, name: "小明", color: const Color(0xFFE53935), icon: Icons.face_rounded,
        animationPath: 'assets/animations/Cat.json', emoji: '🐱'),
      Player(id: 2, name: "小華", color: const Color(0xFF43A047), icon: Icons.face_retouching_natural_rounded,
        animationPath: 'assets/animations/Fox.json', emoji: '🦊'),
      Player(id: 3, name: "系統", color: const Color(0xFFFF9800), icon: Icons.computer_rounded,
        animationPath: 'assets/animations/Parrot.json', emoji: '🦜'),
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

  void _rollDice() async {
    if (_isRolling || _gameOver || !_gameStarted) return;
    final p = _players[_currentPlayerIdx];

    // 監獄：扣除一回合，繼續跳過
    if (p.jailTurns > 0) {
      setState(() => p.jailTurns--);
      _addLog("${p.name} 在監獄中，還剩 ${p.jailTurns} 回合");
      _endTurn();
      return;
    }

    setState(() => _isRolling = true);
    await Future.delayed(const Duration(milliseconds: 650));
    if (!mounted || _gameOver) { setState(() => _isRolling = false); return; }
    setState(() {
      _diceValues = [Random().nextInt(6) + 1, Random().nextInt(6) + 1];
      _movePlayer(p, _diceValues[0] + _diceValues[1]);
      _isRolling = false;
    });
  }

  void _movePlayer(Player p, int steps) async {
    for (int i = 0; i < steps; i++) {
      await Future.delayed(const Duration(milliseconds: 180));
      if (!mounted) return;
      setState(() => p.pathStep = (p.pathStep + 1) % _currentPath.length);
    }
    _handleLandingEvent(p);
  }

  void _handleLandingEvent(Player p) {
    final block = _currentPath[p.pathStep];
    switch (block.type) {
      case BlockType.land:    _handleLandEvent(p, block); break;
      case BlockType.chance:  _handleChanceEvent(p); break;
      case BlockType.goJail:
        _addLog("${p.name} 觸發禁閉事件！");
        p.pathStep = 9; p.jailTurns = 3;
        _persistPlayerState(p); _endTurn(); break;
      default: _endTurn();
    }
  }

  void _handleLandEvent(Player p, GameNode block) {
    if (block.ownerId == null) {
      // 無主地：詢問是否購買
      if (p.id == 0) {
        if (p.money >= block.baseCost) {
          _showBuildDialog(p, block);
        } else {
          _addLog("資金不足，無法購買 ${block.name}");
          _endTurn();
        }
        return;
      }
      // AI 購買邏輯
      if (p.money >= block.baseCost) {
        setState(() { p.money -= block.baseCost; block.ownerId = p.id; block.level = 1; });
        _persistPlayerState(p); _persistBlockState(block);
        _addLog("${p.name} 佔領了 ${block.name}");
      }
      _endTurn();
    } else if (block.ownerId == p.id) {
      // 自己的地：詢問升級
      if (block.level < 3 && p.id == 0 && p.money >= (block.baseCost * 0.6).toInt()) {
        _showUpgradeDialog(p, block);
        return;
      }
      _endTurn();
    } else {
      // 他人的地：繳租金
      final rent = block.rent;
      setState(() { p.money -= rent; _players[block.ownerId!].money += rent; });
      _persistPlayerState(p); _persistPlayerState(_players[block.ownerId!]);
      _addLog("${p.name} 支付租金 \$${_fmt(rent)} 給 ${_players[block.ownerId!].name}");
      _endTurn();
    }
  }

  void _handleChanceEvent(Player p) {
    final delta = Random().nextBool() ? 5000 : -2000;
    p.money += delta;
    _persistPlayerState(p);
    _addLog("${p.name} ${delta > 0 ? '獲得' : '損失'} \$${delta.abs()} 機遇事件！");
    _endTurn();
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
          setState(() { _gameOver = true; _gameLog = "你的寵物破產了！本月冒險結束 😢"; });
          return;
        }
        _addLog("${p.name} 已破產，退出遊戲！");
      }
    }

    // 若存活玩家只剩自己，也算結束
    final alive = _players.where((p) => !p.isBankrupt).toList();
    if (alive.length == 1) {
      setState(() { _gameOver = true; _gameLog = "${alive.first.name} 獲得最終勝利！🏆 本月冒險結束"; });
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
    GameApiService.instance.addGameLog(eventType: 'game', message: msg).catchError((_) {});
  }

  void _startGame(MapTheme theme) {
    SelectedPet.lastMapTheme = theme;
    setState(() {
      _initMapData(theme);
      _initPlayers();
      _gameStarted = true;
      _gameOver = false;
      _isLoadingGameState = true;
      _scale = 1.0;
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
                Expanded(
                  child: LayoutBuilder(builder: (ctx, box) {
                    final mapSize = (min(box.maxWidth, box.maxHeight) * 0.96).clamp(240.0, 640.0);
                    return GestureDetector(
                      onScaleStart: (_) => _baseScale = _scale,
                      onScaleUpdate: (d) => setState(() => _scale = (_baseScale * d.scale).clamp(0.6, 2.5)),
                      child: Center(
                        child: Transform.scale(
                          scale: _scale,
                          child: _buildMapLayer(mapSize),
                        ),
                      ),
                    );
                  }),
                ),
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
                        _scale = 1.0;
                      }),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF8FAB),
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

  // --- 地圖層（無 3D 傾斜，平面但帶陰影）---
  Widget _buildMapLayer(double mapSize) {
    return SizedBox(
      width: mapSize,
      height: mapSize,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 背景畫布
          CustomPaint(
            size: Size(mapSize, mapSize),
            painter: _currentTheme == MapTheme.taiwan
                ? TaiwanMapPainter()
                : MagicIslandPainter(),
          ),
          // 路徑連線
          CustomPaint(
            size: Size(mapSize, mapSize),
            painter: PathLinePainter(
              nodes: _currentPath,
              isMagic: _currentTheme == MapTheme.magicIsland,
            ),
          ),
          // 地塊標記
          ..._currentPath.asMap().entries.map((e) => _buildMarker(e.value, e.key, mapSize)),
          // 渲染所有玩家，將使用者 (id == 0) 放到最後面繪製，確保寵物不會被其他棋子蓋住
          ..._players.where((p) => !p.isBankrupt && p.id != 0).map((p) => _buildPawn(p, mapSize)),
          if (!_players[0].isBankrupt) _buildPawn(_players[0], mapSize),
        ],
      ),
    );
  }

  // --- 地塊標記 ---
  Widget _buildMarker(GameNode node, int idx, double mapSize) {
    final isNext = idx == (_players[_currentPlayerIdx].pathStep + 1) % _currentPath.length && !_gameOver && _currentPlayerIdx == 0;
    final owner  = node.ownerId != null ? _players[node.ownerId!] : null;

    Color bg;
    Color textColor;
    Widget? icon;

    switch (node.type) {
      case BlockType.start:
        bg = const Color(0xFFFFE082);
        textColor = const Color(0xFF5D4037);
        icon = const Text("🚩", style: TextStyle(fontSize: 10));
        break;
      case BlockType.jail:
        bg = const Color(0xFFB0BEC5);
        textColor = Colors.white;
        icon = const Text("🔒", style: TextStyle(fontSize: 10));
        break;
      case BlockType.goJail:
        bg = const Color(0xFFFFAB91);
        textColor = const Color(0xFF5D4037);
        icon = const Text("⚠️", style: TextStyle(fontSize: 10));
        break;
      case BlockType.chance:
        bg = const Color(0xFFCE93D8);
        textColor = Colors.white;
        icon = const Text("🎁", style: TextStyle(fontSize: 10));
        break;
      case BlockType.tax:
        bg = const Color(0xFFEF9A9A);
        textColor = Colors.white;
        icon = const Text("💸", style: TextStyle(fontSize: 10));
        break;
      case BlockType.land:
        bg = owner != null ? owner.color.withOpacity(0.85) : Colors.white;
        textColor = owner != null ? Colors.white : Colors.grey.shade700;
        if (node.level > 0) icon = Row(mainAxisSize: MainAxisSize.min, children: List.generate(node.level, (_) => const Text("🏠", style: TextStyle(fontSize: 7))));
        break;
    }

    return Positioned(
      left: node.position.dx * mapSize - 22,
      top:  node.position.dy * mapSize - 20,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isNext)
            const Text("👇", style: TextStyle(fontSize: 14)),
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: isNext ? const Color(0xFFFF8FAB) : Colors.grey.shade300, width: isNext ? 2 : 1),
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: isNext ? 6 : 2, offset: const Offset(0, 2))],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) icon,
                Text(
                  node.name,
                  style: TextStyle(fontSize: 7.5, fontWeight: FontWeight.bold, color: textColor, height: 1.1),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- 玩家棋子（更新為寵物 Lottie 動畫）---
  Widget _buildPawn(Player p, double mapSize) {
    final pos = _currentPath[p.pathStep].position;

    // 如果是使用者 (寵物)，給他比較大的尺寸，其他電腦玩家用預設小尺寸
    final isUser = p.id == 0;
    final size = isUser ? 75.0 : 40.0;

    final cx = pos.dx * mapSize;
    final cy = pos.dy * mapSize;
    final left = (cx - size / 2).clamp(0.0, mapSize - size);
    final top  = (cy - size).clamp(0.0, mapSize - size);

    return Positioned(
      left: left,
      top:  top,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 名字標籤
          Container(
            margin: const EdgeInsets.only(bottom: 3),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: p.color,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [BoxShadow(color: p.color.withOpacity(0.6), blurRadius: 8)],
            ),
            child: Text(
              p.name,
              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ),

          if (p.animationPath != null)
          // ===== 寵物渲染模式（與分析畫面一致：所有寵物均顯示 Lottie 動畫）=====
            Stack(
              alignment: Alignment.bottomCenter,
              children: [
                // 腳下的魔力底圈
                Container(
                  width: size * 0.7,
                  height: size * 0.25,
                  margin: const EdgeInsets.only(bottom: 5),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(100),
                    color: p.color.withOpacity(0.3),
                    boxShadow: [
                      BoxShadow(color: p.color.withOpacity(0.6), blurRadius: 15, spreadRadius: 2),
                    ],
                  ),
                ),
                // 寵物動畫本體
                SizedBox(
                  width: size,
                  height: size,
                  child: Lottie.asset(
                    p.animationPath!,
                    fit: BoxFit.contain,
                    animate: true,
                    repeat: true,
                  ),
                ),
              ],
            )
          else
          // ===== 沒有寵物時的傳統圓圈模式 =====
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.9),
                border: Border.all(color: p.color, width: 2),
                boxShadow: [BoxShadow(color: p.color.withOpacity(0.5), blurRadius: 8)],
              ),
              child: Center(
                child: p.emoji != null
                    ? Text(p.emoji!, style: const TextStyle(fontSize: 18))
                    : Icon(p.icon, color: p.color, size: 20),
              ),
            ),
        ],
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
                              ? Center(child: Text(p.emoji ?? '🐾', style: const TextStyle(fontSize: 16)))
                              : Icon(p.icon, size: 13, color: Colors.white),
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
    final isMagic = _currentTheme == MapTheme.magicIsland;
    final canRoll  = !_gameOver && !_isRolling && _currentPlayerIdx == 0;
    final accent = isMagic ? const Color(0xFFBA68C8) : const Color(0xFF66BB6A);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.68),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: accent.withOpacity(0.3), width: 1.5),
              boxShadow: [BoxShadow(color: accent.withOpacity(0.18), blurRadius: 16, offset: const Offset(0, 6))],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Row(
                  children: _diceValues.map((v) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Dice3D(value: v, isRolling: _isRolling, isMagic: isMagic),
                  )).toList(),
                ),
                ElevatedButton(
                  onPressed: canRoll ? _rollDice : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: canRoll ? accent : Colors.grey.shade300,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 13),
                    shape: const StadiumBorder(),
                    elevation: canRoll ? 4 : 0,
                  ),
                  child: Text(
                    _isRolling ? "🎲 擲中..." : (_gameOver ? "遊戲結束" : (_currentPlayerIdx == 0 ? "出發！🎲" : "電腦回合")),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
                InkWell(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PetPage())),
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 52, height: 52,
                    decoration: BoxDecoration(
                      color: (_players[0].color).withOpacity(0.15),
                      shape: BoxShape.circle,
                      border: Border.all(color: _players[0].color, width: 2),
                      boxShadow: [BoxShadow(color: _players[0].color.withOpacity(0.3), blurRadius: 8)],
                    ),
                    child: Center(
                      child: Text(
                        _players[0].emoji ?? SelectedPet.emoji ?? '🐾',
                        style: const TextStyle(fontSize: 26),
                      ),
                    ),
                  ),
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
          colors: [Color(0xFFFFF0F5), Color(0xFFE8F5E9)],
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
                const Color(0xFFFF8FAB),
                () => Navigator.of(context).maybePop(),
              ),
            ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text("🎲", style: TextStyle(fontSize: 56)),
                const SizedBox(height: 10),
                const Text("選擇冒險地圖", style: TextStyle(color: Color(0xFF5D4037), fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                const SizedBox(height: 6),
                Text("搖一搖手機可以擲骰子！", style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                const SizedBox(height: 40),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _themeCard(MapTheme.taiwan,      "台灣環島",   "🗺️", const Color(0xFF81C784), const Color(0xFFF1F8E9), const Color(0xFFE8F5E9)),
                    const SizedBox(width: 20),
                    _themeCard(MapTheme.magicIsland, "魔法天空島", "✨", const Color(0xFFBA68C8), const Color(0xFFF8E8FF), const Color(0xFFF3E5F5)),
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
  void _showBuildDialog(Player p, GameNode b) {
    showDialog(
      context: context,
      builder: (ctx) => _gameDialog(
        title: "🏗 抵達 ${b.name}",
        content: "基礎建設費用 \$${_fmt(b.baseCost)}\n您的資金 \$${_fmt(p.money)}\n要投資嗎？",
        cancelLabel: "路過",
        confirmLabel: "確認建設",
        onConfirm: () {
          setState(() { p.money -= b.baseCost; b.ownerId = p.id; b.level = 1; });
          _persistPlayerState(p); _persistBlockState(b);
          _addLog("${p.name} 佔領了 ${b.name}！");
          Navigator.pop(ctx); _endTurn();
        },
        onCancel: () { Navigator.pop(ctx); _endTurn(); },
      ),
    );
  }

  void _showUpgradeDialog(Player p, GameNode b) {
    final cost = (b.baseCost * 0.6).toInt();
    showDialog(
      context: context,
      builder: (ctx) => _gameDialog(
        title: "⬆️ 升級 ${b.name}",
        content: "升級費用 \$${_fmt(cost)}\n升至 Lv.${b.level + 1}，租金提升！\n您的資金 \$${_fmt(p.money)}",
        cancelLabel: "取消",
        confirmLabel: "確認升級",
        onConfirm: () {
          setState(() { p.money -= cost; b.level += 1; });
          _persistPlayerState(p); _persistBlockState(b);
          Navigator.pop(ctx); _endTurn();
        },
        onCancel: () { Navigator.pop(ctx); _endTurn(); },
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
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF8FAB), foregroundColor: Colors.white, shape: const StadiumBorder()),
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
        colors: [const Color(0xFFFCE4EC), const Color(0xFFEDE7F6)],
      ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );

    // 可愛彩虹弧
    _drawRainbow(canvas, Offset(w * 0.5, h * 0.55), w * 0.42);

    // 散落小愛心
    final rng = Random(42);
    final heartColors = [
      const Color(0xFFFF8FAB), const Color(0xFFCE93D8),
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
        Paint()..color = const Color(0xFFFFD6E0).withOpacity(0.7));
    canvas.drawCircle(Offset(w / 2, h / 2), w * 0.10,
        Paint()..color = const Color(0xFFFF8FAB).withOpacity(0.6)
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