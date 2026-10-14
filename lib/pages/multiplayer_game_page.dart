import 'dart:async';
import 'dart:math' show sqrt;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../data/pet_skill_data.dart';
import '../services/current_pet_manager.dart';
import '../services/game_api_service.dart';
import '../theme/app_palette.dart';
import '../widgets/game_chat.dart';
import '../widgets/game_event_card.dart';
import '../widgets/island_board_3d.dart';
import 'playground_page.dart' show Dice3D; // ★ 跟單人大富翁共用同一個 3D 骰子

/// ★ 新增：好友對戰的棋盤畫面（輪流制）
/// 遊戲狀態全部來自 8000 後端；這裡只負責顯示、送出操作、定時刷新。
class MultiplayerGamePage extends StatefulWidget {
  final int gameId;

  const MultiplayerGamePage({super.key, required this.gameId});

  @override
  State<MultiplayerGamePage> createState() => _MultiplayerGamePageState();
}

class _MultiplayerGamePageState extends State<MultiplayerGamePage> {
  static const _seatColors = [Color(0xFF2196F3), Color(0xFFE53935), Color(0xFF43A047), Color(0xFFFF9800)];
  static const _botImages = [
    'assets/pets/bunny_bow.png',
    'assets/pets/hamster_foodie.png',
    'assets/pets/otter_leaf.png',
  ];
  static const _defaultImage = 'assets/pets/pawpay_app_icon1.png';

  final _api = GameApiService.instance;
  Map<String, dynamic>? _v;
  int _uid = 0;
  bool _busy = false;
  bool _diceRolling = false; // 骰子轉動動畫
  String? _error;
  Timer? _poll;
  Timer? _walk;
  final Map<int, int> _shownSteps = {}; // 畫面上棋子目前站的格子（走路動畫用）
  int _lastPendingKey = -1;
  // ★ 新增：重要事件卡片（後端 log 的 kind），棋子走完才一張一張跳出來
  int _seenSeq = -1;
  final List<GameEventCard> _cardQueue = [];
  bool _flushingCards = false;
  // ★ 新增：聊天室（每 2.5 秒拉一次新訊息，跟遊戲狀態的輪詢分開，輪到自己時也會更新）
  final GameChatController _chat = GameChatController();
  Timer? _chatPoll;
  int _chatAfterId = 0;
  bool _chatLoaded = false;
  bool _chatPolling = false;
  StreamSubscription? _shakeSub; // 搖一搖擲骰（跟單人版一樣）
  DateTime _lastShake = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _init();
    _shakeSub = accelerometerEvents.listen((e) {
      final v = _v;
      if (v == null || v['my_turn'] != true || v['pending'] != null || _busy || _diceRolling || _flushingCards) return;
      final acc = sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
      if (acc > 18 && DateTime.now().difference(_lastShake).inMilliseconds > 1500) {
        _lastShake = DateTime.now();
        _roll();
      }
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _walk?.cancel();
    _shakeSub?.cancel();
    _chatPoll?.cancel();
    _chat.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    _uid = await _api.resolveCurrentUserId();
    await _refresh();
    // 不是自己的回合時每 3 秒刷新一次，看別人走到哪
    _poll = Timer.periodic(const Duration(seconds: 3), (_) {
      final v = _v;
      if (_busy || v == null || v['status'] == 'finished') return;
      if (v['my_turn'] == true && v['status'] == 'playing') return;
      _refresh(silent: true);
    });
    if (!mounted) return;
    _pollChat();
    _chatPoll = Timer.periodic(const Duration(milliseconds: 2500), (_) => _pollChat());
  }

  // ── ★ 新增：聊天 ──────────────────────────────────────────────────────
  Future<void> _pollChat() async {
    final v = _v;
    if (_chatPolling || v == null || v['status'] == 'waiting') return;
    _chatPolling = true;
    try {
      final list = await _api.mpChatList(gameId: widget.gameId, userId: _uid, afterId: _chatAfterId);
      if (!mounted) return;
      final players = _players();
      for (final m in list) {
        final id = (m['id'] as num?)?.toInt() ?? 0;
        if (id <= _chatAfterId) continue;
        _chatAfterId = id;
        final seat = (m['seat'] as num?)?.toInt() ?? 0;
        final pl = players.firstWhere((p) => p['seat'] == seat, orElse: () => <String, dynamic>{'seat': seat});
        final isSticker = m['kind'] == 'sticker';
        final body = m['body']?.toString() ?? '';
        _chat.add(
          GameChatMessage(
            id: 'mp-$id',
            name: (m['name'] ?? pl['name'] ?? '').toString(),
            avatarPath: _imageOf(pl),
            emoji: (m['emoji'] ?? pl['emoji'])?.toString(),
            text: isSticker ? null : body,
            stickerKey: isSticker ? body : null,
            stickerAsset: isSticker ? petStickerAsset(m['pet_key']?.toString(), body) : null,
            isMe: m['is_me'] == true,
            color: _seatColors[seat % _seatColors.length],
          ),
          silent: !_chatLoaded, // 剛進來時的舊訊息只放紀錄，不跳泡泡
        );
      }
      _chatLoaded = true;
    } catch (_) {
      // 聊天失敗不影響遊戲，下一輪再試
    } finally {
      _chatPolling = false;
    }
  }

  Future<void> _sendChat({String? text, String? stickerKey}) async {
    try {
      await _api.mpChatSend(
        gameId: widget.gameId,
        userId: _uid,
        kind: stickerKey != null ? 'sticker' : 'text',
        body: stickerKey ?? text ?? '',
      );
      await _pollChat();
    } catch (e) {
      _snack(GameApiService.errorMessage(e));
    }
  }

  void _openChat() {
    final me = _players().where((p) => p['is_me'] == true).toList();
    showGameChatPanel(
      context,
      controller: _chat,
      myPetKey: me.isEmpty ? null : me.first['pet_key']?.toString(),
      onSend: ({String? text, String? stickerKey}) => _sendChat(text: text, stickerKey: stickerKey),
    );
  }

  Future<void> _refresh({bool silent = false}) async {
    try {
      final v = await _api.mpGet(gameId: widget.gameId, userId: _uid);
      if (!mounted) return;
      _apply(v);
    } catch (e) {
      if (!mounted || silent) return;
      setState(() => _error = GameApiService.errorMessage(e));
    }
  }

  // ── 收到新狀態：更新畫面、讓棋子一格一格走過去 ─────────────────────────
  void _apply(Map<String, dynamic> v) {
    final board = (v['board'] as List?) ?? const [];
    final n = board.isEmpty ? 1 : board.length;
    final players = _players(v);
    final targets = <int, int>{};
    for (final p in players) {
      final seat = p['seat'] as int;
      final step = (p['step'] as num).toInt();
      targets[seat] = step;
      final old = _shownSteps[seat];
      final dist = old == null ? 0 : (step - old) % n;
      // 第一次載入、被關進監獄、或一次跳太遠（例如很久沒看），直接放到位置上
      final jumped = old == null || dist > 13 || ((p['jail'] as num? ?? 0) > 0 && step == 9 && old != 9);
      if (jumped) _shownSteps[seat] = step;
    }
    _collectEventCards(v);
    setState(() {
      _v = v;
      _error = null;
    });
    _walk?.cancel();
    if (targets.entries.any((e) => _shownSteps[e.key] != e.value)) {
      _walk = Timer.periodic(const Duration(milliseconds: 300), (t) {
        var moving = false;
        for (final e in targets.entries) {
          final cur = _shownSteps[e.key] ?? e.value;
          if (cur != e.value) {
            _shownSteps[e.key] = (cur + 1) % n;
            moving = true;
          }
        }
        if (!mounted) return t.cancel();
        setState(() {});
        if (!moving) {
          t.cancel();
          _afterWalk();
        }
      });
    } else {
      _afterWalk();
    }
  }

  // ── ★ 新增：事件卡片 ──────────────────────────────────────────────────
  void _collectEventCards(Map<String, dynamic> v) {
    final log = ((v['log'] as List?) ?? const []).whereType<Map>().toList();
    var maxSeq = _seenSeq;
    for (final e in log) {
      final seq = (e['seq'] as num?)?.toInt() ?? 0;
      if (seq > maxSeq) maxSeq = seq;
    }
    if (_seenSeq < 0) {
      // 第一次載入：舊事件不補跳
      _seenSeq = maxSeq;
      return;
    }
    final mySeat = (v['my_seat'] as num?)?.toInt();
    for (final e in log) {
      final seq = (e['seq'] as num?)?.toInt() ?? 0;
      if (seq <= _seenSeq) continue;
      final card = _cardFor(Map<String, dynamic>.from(e), mySeat);
      if (card != null) _cardQueue.add(card);
    }
    _seenSeq = maxSeq;
  }

  GameEventCard? _cardFor(Map<String, dynamic> e, int? mySeat) {
    final kind = e['kind']?.toString();
    if (kind == null) return null;
    final text = e['text']?.toString() ?? '';
    final seat = (e['seat'] as num?)?.toInt();
    final target = (e['target'] as num?)?.toInt();
    final mine = seat != null && seat == mySeat;
    if (kind == 'bankrupt') return GameEventCard(emoji: '💸', title: mine ? '你破產了…' : '有人破產了！', message: text, negative: mine);
    if (kind == 'win') return GameEventCard(emoji: '🏆', title: mine ? '你贏了！' : '遊戲結束', message: text, negative: !mine);
    if (!mine) {
      if (kind == 'rent' && target != null && target == mySeat) {
        return GameEventCard(emoji: '💰', title: '收到租金！', message: text);
      }
      return null;
    }
    switch (kind) {
      case 'rent':
        return GameEventCard(emoji: '💸', title: '付租金', message: text, negative: true);
      case 'rent_defer':
        return GameEventCard(emoji: '⏳', title: '租金先欠著', message: text);
      case 'tax':
        return GameEventCard(emoji: '🧾', title: '繳稅', message: text, negative: true);
      case 'jail':
        return GameEventCard(emoji: '🚔', title: '進監獄！', message: text, negative: true);
      case 'jail_stay':
        return GameEventCard(emoji: '🚔', title: '還在監獄裡', message: text, negative: true);
      case 'chance_good':
        return GameEventCard(emoji: '🎁', title: '機會：好運降臨！', message: text);
      case 'chance_bad':
        return GameEventCard(emoji: '😱', title: '機會：運氣不太好…', message: text, negative: true);
      case 'chance_safe':
        return GameEventCard(emoji: '🛡️', title: '機會：成功躲過！', message: text);
      case 'start_bonus':
        return GameEventCard(emoji: '🏁', title: '經過起點', message: text);
      case 'guard':
        return GameEventCard(emoji: '💗', title: '暖心守護', message: text);
    }
    return null;
  }

  Future<void> _afterWalk() async {
    if (_flushingCards) return;
    _flushingCards = true;
    try {
      while (_cardQueue.isNotEmpty && mounted) {
        final card = _cardQueue.removeAt(0);
        await showGameEventCard(context, card);
      }
    } finally {
      _flushingCards = false;
    }
    if (mounted) _maybeAskDecision();
  }

  List<Map<String, dynamic>> _players([Map<String, dynamic>? v]) =>
      (((v ?? _v)?['players'] as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();

  String _fmt(num v) => v >= 10000 ? '${(v / 10000).toStringAsFixed(1)}萬' : v.toInt().toString();

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m), duration: const Duration(seconds: 2)));
  }

  Future<void> _act(String action, [Map<String, dynamic> extra = const {}]) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final v = await _api.mpAction(widget.gameId, action, {'user_id': _uid, ...extra});
      if (!mounted) return;
      _apply(v);
    } catch (e) {
      _snack(GameApiService.errorMessage(e));
      await _refresh(silent: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    // 動作期間 _busy 擋住了買地視窗，結束後再檢查一次（走路動畫跑完時也會再檢查）
    if (mounted && (_walk == null || !_walk!.isActive)) _afterWalk();
  }

  // ── 買地 / 升級 ────────────────────────────────────────────────────────
  Future<void> _maybeAskDecision() async {
    final pend = _v?['pending'];
    if (pend is! Map || _busy || _flushingCards) return;
    final key = Object.hash(pend['type'], pend['idx'], _v?['version']);
    if (key == _lastPendingKey) return;
    _lastPendingKey = key;
    final board = (_v!['board'] as List);
    final block = Map<String, dynamic>.from(board[(pend['idx'] as num).toInt()] as Map);
    final me = _players().firstWhere((p) => p['is_me'] == true);
    final isBuy = pend['type'] == 'buy';
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(isBuy ? '🏗 抵達 ${block['name']}' : '⬆️ 升級 ${block['name']}'),
        content: Text(
          isBuy
              ? '基礎建設費用 \$${_fmt(pend['cost'] as num)}\n您的資金 \$${_fmt(me['money'] as num)}\n要投資嗎？'
              : '升級費用 \$${_fmt(pend['cost'] as num)}\n升至 Lv.${(block['level'] as num) + 1}，租金提升！\n您的資金 \$${_fmt(me['money'] as num)}',
          style: const TextStyle(height: 1.6),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(isBuy ? '路過' : '取消', style: const TextStyle(color: Colors.grey))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(isBuy ? '確認建設' : '確認升級')),
        ],
      ),
    );
    if (ok == null || !mounted) return;
    await _act('decide', {'accept': ok});
    // ★ 新增：每日任務「大富翁買地或升級 1 次」（好友對戰也算）
    if (ok) {
      _api.recordMonopolyBuild(hint: 'mp:${widget.gameId}:${pend['idx']}:${pend['type']}:${_v?['version']}');
    }
  }

  // ── 主動技能 ──────────────────────────────────────────────────────────
  Future<void> _useSkill(String petKey) async {
    final skill = getPetSkill(petKey);
    if (skill == null) return;
    final extra = <String, dynamic>{};
    if (petKey == 'giraffe') {
      final steps = await showDialog<int>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('🦒 看得更遠'),
          content: const Text('選擇要前進幾格'),
          actions: [for (var i = 1; i <= 6; i++) TextButton(onPressed: () => Navigator.pop(ctx, i), child: Text('$i'))],
        ),
      );
      if (steps == null) return;
      extra['steps'] = steps;
    } else if (petKey == 'clingy_dog') {
      final others = _players().where((p) => p['is_me'] != true && p['bankrupt'] != true).toList();
      final target = await showDialog<int>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('🐕 跟我來！帶誰前進 2 格？'),
          children: [
            for (final p in others)
              SimpleDialogOption(onPressed: () => Navigator.pop(ctx, p['seat'] as int), child: Text('${p['emoji'] ?? ''} ${p['name']}')),
          ],
        ),
      );
      if (target == null) return;
      extra['target_seat'] = target;
    } else {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('使用「${skill.activeName}」？'),
          content: Text('${skill.activeDescription}\n\n每局只能用一次。'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('使用')),
          ],
        ),
      );
      if (ok != true) return;
    }
    await _act('skill', extra);
  }

  Future<void> _confirmForfeit() async {
    final waitingHost = _v?['status'] == 'waiting' && _v?['host_user_id'] == _uid;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(waitingHost ? '取消這場對戰？' : '退出對戰？'),
        content: Text(waitingHost ? '好友的邀請會一起取消。' : '退出後你的位置由電腦接手，遊戲會繼續進行。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('先不要')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(waitingHost ? '取消對戰' : '退出'),
          ),
        ],
      ),
    );
    if (ok == true) await _act('forfeit');
  }

  void _showLog() {
    final log = ((_v?['log'] as List?) ?? const []).whereType<Map>().toList().reversed.toList();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.55,
          child: Column(children: [
            const SizedBox(height: 12),
            const Text('事件紀錄', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const Divider(),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: log.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(log[i]['text'].toString(), style: TextStyle(fontSize: 13, color: i == 0 ? Colors.black87 : Colors.grey.shade700)),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // ── 畫面（★ 樣式跟單人大富翁一致：上方玩家列、事件列、毛玻璃底部列 + 3D 骰子）──
  String _imageOf(Map<String, dynamic> p) {
    if (p['is_bot'] == true && p['user_id'] == null) {
      final seat = p['seat'] as int;
      return _botImages[(seat - 1) % _botImages.length];
    }
    return CurrentPetManager.petImageMap[(p['pet_key'] ?? '').toString()] ?? _defaultImage;
  }

  bool get _isMagic => _v?['theme'] == 'magicIsland';

  @override
  Widget build(BuildContext context) {
    final v = _v;
    final isMagic = _isMagic;
    return Scaffold(
      body: Stack(children: [
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
            child: v == null
                ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : Column(mainAxisSize: MainAxisSize.min, children: [
                Text(_error!),
                const SizedBox(height: 10),
                ElevatedButton(onPressed: _refresh, child: const Text('重新載入')),
              ]),
            )
                : Column(children: [
              _buildTopBar(v),
              _buildGameLog(v),
              const SizedBox(height: 4),
              Expanded(child: _board(v, isMagic)),
              _buildBottomBar(v),
            ]),
          ),
        ),
        // ── ★ 新增：聊天泡泡 + 💬 按鈕（對戰開始後才有）──
        if (v != null && v['status'] == 'playing')
          Positioned(
            left: 14,
            right: 84,
            bottom: 112 + MediaQuery.of(context).padding.bottom,
            child: Align(alignment: Alignment.bottomLeft, child: GameChatFeed(controller: _chat)),
          ),
        if (v != null && v['status'] == 'playing')
          Positioned(
            right: 16,
            bottom: 112 + MediaQuery.of(context).padding.bottom,
            child: GameChatButton(controller: _chat, onPressed: _openChat),
          ),
        if (v != null && v['status'] == 'finished') _buildGameOverOverlay(v),
      ]),
    );
  }

  Widget _roundIconButton(IconData icon, Color color, VoidCallback? onTap) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 44,
        height: 44,
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

  // --- 上方：返回 + 玩家列（跟單人版一樣，多了「我」和好友名字）---
  Widget _buildTopBar(Map<String, dynamic> v) {
    final accent = _isMagic ? const Color(0xFFCE93D8) : const Color(0xFF81C784);
    final current = v['current'];
    final playing = v['status'] == 'playing';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(children: [
        _roundIconButton(Icons.arrow_back_ios_new_rounded, accent, () => Navigator.of(context).maybePop()),
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
              children: _players(v).map((p) {
                final seat = p['seat'] as int;
                final color = _seatColors[seat];
                final isActive = playing && seat == current;
                final bankrupt = p['bankrupt'] == true;
                return Opacity(
                  opacity: bankrupt ? 0.35 : 1,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    padding: isActive ? const EdgeInsets.symmetric(horizontal: 6, vertical: 2) : EdgeInsets.zero,
                    decoration: BoxDecoration(
                      color: isActive ? color.withOpacity(0.15) : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: color.withOpacity(isActive ? 1.0 : 0.45)),
                        child: Padding(
                          padding: const EdgeInsets.all(3),
                          child: Image.asset(_imageOf(p), fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => const Icon(Icons.person_rounded, size: 13, color: Colors.white)),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        bankrupt
                            ? '破產'
                            : '${p['is_me'] == true ? '我 ' : ''}\$${((p['money'] as num) / 1000).toStringAsFixed(1)}k',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                          color: isActive ? color : Colors.grey.shade500,
                        ),
                      ),
                    ]),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ]),
    );
  }

  // --- 事件日誌（跟單人版同樣式，點一下看完整紀錄）---
  Widget _buildGameLog(Map<String, dynamic> v) {
    final isMagic = _isMagic;
    final bg = isMagic ? const Color(0xFFF8E8FF) : const Color(0xFFF1F8E9);
    final border = isMagic ? const Color(0xFFCE93D8) : const Color(0xFF81C784);
    final log = ((v['log'] as List?) ?? const []).whereType<Map>().toList();
    final last = log.length >= 2 ? log.sublist(log.length - 2) : log;
    final text = v['status'] == 'waiting'
        ? '⏳ 等待好友接受邀請…（${v['theme_name']}）'
        : last.map((e) => e['text']).join('\n');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: GestureDetector(
        onTap: log.isEmpty ? null : _showLog,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: border.withOpacity(0.5), width: 1.5),
          ),
          child: Row(children: [
            Text(isMagic ? "✨" : "🌸", style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text,
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 11.5, fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2),
            ),
            if (log.isNotEmpty) Icon(Icons.history_rounded, size: 18, color: Colors.grey.shade500),
          ]),
        ),
      ),
    );
  }

  Widget _board(Map<String, dynamic> v, bool magic) {
    final players = _players(v);
    final board = ((v['board'] as List?) ?? const []).whereType<Map>().toList();
    final bySeat = {for (final p in players) p['seat'] as int: p};
    final me = players.where((p) => p['is_me'] == true).firstOrNull;
    return IslandBoard3D(
      key: ValueKey(v['theme']),
      sites: [
        for (final b in board)
          BoardSite3D(
            name: b['name'].toString(),
            kind: b['type'].toString(),
            cost: (b['cost'] as num).toInt(),
            rent: (b['rent'] as num? ?? 0).toInt(),
            level: (b['level'] as num? ?? 0).toInt(),
            ownerColor: b['owner'] == null ? null : _seatColors[(b['owner'] as num).toInt()],
            ownerName: b['owner'] == null ? null : bySeat[(b['owner'] as num).toInt()]?['name']?.toString(),
          ),
      ],
      pawns: [
        for (final p in players.where((p) => p['bankrupt'] != true))
          BoardPawn3D(
            id: p['seat'] as int,
            name: p['name'].toString(),
            step: _shownSteps[p['seat'] as int] ?? (p['step'] as num).toInt(),
            color: _seatColors[p['seat'] as int],
            imagePath: _imageOf(p),
            emoji: p['emoji']?.toString(),
          ),
      ],
      activePlayerId: (v['current'] as num? ?? 0).toInt(),
      nextStep: v['my_turn'] == true && me != null && board.isNotEmpty
          ? ((me['step'] as num).toInt() + 1) % board.length
          : null,
      magic: magic,
      accent: AppPalette.of(context).accent,
    );
  }

  // --- 底部：骰子 + 出發 + 技能（跟單人版一樣的毛玻璃樣式）---
  Widget _buildBottomBar(Map<String, dynamic> v) {
    final isMagic = _isMagic;
    final accent = isMagic ? const Color(0xFFBA68C8) : const Color(0xFF66BB6A);
    final players = _players(v);
    final me = players.where((p) => p['is_me'] == true).firstOrNull;
    final current = players.where((p) => p['seat'] == v['current']).firstOrNull;
    final dice = ((v['dice'] as List?) ?? const [1, 1]).map((e) => (e as num).toInt()).toList();
    final status = v['status'];
    final myTurn = v['my_turn'] == true;
    final canRoll = status == 'playing' && myTurn && v['pending'] == null && !_busy;
    final skill = me == null ? null : getPetSkill(me['pet_key']?.toString());
    final skillUsed = me?['active_used'] == true;
    final isHostWaiting = status == 'waiting' && v['host_user_id'] == _uid;

    String rollLabel;
    if (_diceRolling) {
      rollLabel = '擲中...';
    } else if (status == 'waiting') {
      rollLabel = isHostWaiting ? '直接開始' : '等待開局';
    } else if (status != 'playing') {
      rollLabel = '已結束';
    } else if (myTurn) {
      rollLabel = '出發！';
    } else {
      rollLabel = '${current?['name'] ?? ''} 行動中';
    }
    final VoidCallback? rollAction = isHostWaiting && !_busy
        ? _confirmForceStart
        : (canRoll ? _roll : null);

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
                // 左邊：骰子（同一個 Dice3D 元件）
                Row(
                  children: dice
                      .map((d) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Dice3D(value: d, isRolling: _diceRolling, isMagic: isMagic),
                  ))
                      .toList(),
                ),
                // 右邊：出發 + 選單，下方技能
                Column(mainAxisSize: MainAxisSize.min, children: [
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    ElevatedButton(
                      onPressed: rollAction,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: rollAction != null ? accent : Colors.grey.shade300,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
                        shape: const StadiumBorder(),
                      ),
                      child: Text(rollLabel, overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 8),
                    // 原本是「選擇寵物」的圓形按鈕；對戰中寵物固定，改成選單（事件紀錄 / 重新整理 / 退出）
                    PopupMenuButton<String>(
                      onSelected: (x) {
                        if (x == 'log') _showLog();
                        if (x == 'refresh') _refresh();
                        if (x == 'forfeit') _confirmForfeit();
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'log', child: Text('📜 事件紀錄')),
                        const PopupMenuItem(value: 'refresh', child: Text('🔄 重新整理')),
                        if (status != 'finished')
                          PopupMenuItem(
                            value: 'forfeit',
                            child: Text(status == 'waiting' && v['host_user_id'] == _uid ? '取消對戰' : '退出對戰（電腦接手）',
                                style: const TextStyle(color: Colors.red)),
                          ),
                      ],
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: accent.withOpacity(0.6), width: 1.5),
                          boxShadow: [BoxShadow(color: accent.withOpacity(0.18), blurRadius: 8, offset: const Offset(0, 3))],
                        ),
                        child: Icon(Icons.more_horiz_rounded, color: accent, size: 23),
                      ),
                    ),
                  ]),
                  if (skill != null) ...[
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 30,
                      child: ElevatedButton.icon(
                        onPressed: canRoll && !skillUsed ? () => _useSkill(me!['pet_key'].toString()) : null,
                        icon: Icon(skill.skillIcon, size: 14),
                        label: Text(
                          skillUsed ? '技能已使用' : skill.activeName,
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFFA726),
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.grey.shade300,
                          disabledForegroundColor: Colors.grey.shade600,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          shape: const StadiumBorder(),
                        ),
                      ),
                    ),
                  ],
                  if (v['giraffe_preview'] is List) ...[
                    const SizedBox(height: 4),
                    Text('🦒 前方：${(v['giraffe_preview'] as List).join('、')}',
                        style: const TextStyle(fontSize: 10), overflow: TextOverflow.ellipsis),
                  ],
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 擲骰：骰子先轉一下（跟單人版一樣約 0.65 秒），再顯示伺服器擲出的結果
  Future<void> _roll() async {
    if (_busy || _flushingCards) return;
    setState(() => _diceRolling = true);
    await Future.wait([
      _act('roll'),
      Future.delayed(const Duration(milliseconds: 650)),
    ]);
    if (mounted) setState(() => _diceRolling = false);
  }

  Future<void> _confirmForceStart() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('直接開始？'),
        content: const Text('還沒回覆邀請的好友會由電腦代打。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('再等等')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('開始')),
        ],
      ),
    );
    if (ok == true) await _act('start');
  }

  // --- 遊戲結束（跟單人版同樣的卡片，多了排名）---
  Widget _buildGameOverOverlay(Map<String, dynamic> v) {
    final isMagic = _isMagic;
    final players = _players(v)
      ..sort((a, b) {
        if (a['bankrupt'] != b['bankrupt']) return a['bankrupt'] == true ? 1 : -1;
        return (b['money'] as num).compareTo(a['money'] as num);
      });
    final winner = players.where((p) => p['seat'] == v['winner']).firstOrNull;
    final isWin = winner?['is_me'] == true;
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
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(isWin ? '🏆' : '😢', style: const TextStyle(fontSize: 54)),
            const SizedBox(height: 10),
            Text(
              isWin ? '你贏了！' : '對戰結束',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF5D4037)),
            ),
            const SizedBox(height: 8),
            Text(
              '${winner?['name'] ?? ''} 獲得最終勝利！',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600, height: 1.5),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isMagic ? const Color(0xFFF3E5F5) : const Color(0xFFF1F8E9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(children: [
                for (var i = 0; i < players.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(children: [
                      SizedBox(width: 22, child: Text('${i + 1}', style: const TextStyle(fontWeight: FontWeight.bold))),
                      Expanded(child: Text('${players[i]['is_me'] == true ? '我' : players[i]['name']}', overflow: TextOverflow.ellipsis)),
                      Text(
                        players[i]['bankrupt'] == true ? '破產' : '\$${_fmt(players[i]['money'] as num)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: isMagic ? const Color(0xFF8E24AA) : const Color(0xFF388E3C),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ]),
                  ),
              ]),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppPalette.of(context).accent,
                  foregroundColor: Colors.white,
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text('回到大廳'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}