import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/game_api_service.dart';
import '../services/current_pet_manager.dart';
import 'multiplayer_game_page.dart';
import 'add_friend_page.dart';

/// ★ 新增：好友對戰大廳
/// - 建立對戰：選 1～3 位好友 + 地圖，空位由電腦補上
/// - 收到的邀請：接受 / 拒絕
/// - 進行中 / 已結束的對戰列表（輪到你的會標出來）
class MultiplayerLobbyPage extends StatefulWidget {
  /// 從好友頁「邀請對戰」進來時，預先勾選這位好友並直接打開建立視窗
  final int? preselectFriendId;

  const MultiplayerLobbyPage({super.key, this.preselectFriendId});

  @override
  State<MultiplayerLobbyPage> createState() => _MultiplayerLobbyPageState();
}

class _MultiplayerLobbyPageState extends State<MultiplayerLobbyPage> {
  final _api = GameApiService.instance;
  bool _loading = true;
  String? _error;
  int _uid = 0;
  List<Map<String, dynamic>> _games = [];

  @override
  void initState() {
    super.initState();
    _load().then((_) {
      if (widget.preselectFriendId != null && mounted) _openCreateSheet();
    });
  }

  Future<String?> _myPetKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('current_pet_key');
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _uid = await _api.resolveCurrentUserId();
      final games = await _api.mpList(userId: _uid);
      if (!mounted) return;
      setState(() {
        _games = games;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = GameApiService.errorMessage(e);
      });
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _openGame(int id) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => MultiplayerGamePage(gameId: id)));
    await _load();
  }

  Future<void> _respond(Map<String, dynamic> g, bool accept) async {
    try {
      final pet = accept ? await _myPetKey() : null;
      final v = await _api.mpRespond(gameId: g['id'] as int, userId: _uid, accept: accept, petKey: pet);
      if (accept) {
        _snack(v['status'] == 'playing' ? '對戰開始了！' : '已加入，等其他好友回覆');
        await _openGame(g['id'] as int);
      } else {
        _snack('已婉拒這場對戰');
        await _load();
      }
    } catch (e) {
      _snack(GameApiService.errorMessage(e));
    }
  }

  // ── 建立對戰 ────────────────────────────────────────────────────────────
  Future<void> _openCreateSheet() async {
    List<Map<String, dynamic>> friends;
    try {
      friends = await _api.fetchFriends(userId: _uid);
    } catch (e) {
      _snack(GameApiService.errorMessage(e));
      return;
    }
    if (!mounted) return;
    if (friends.isEmpty) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('還沒有好友'),
          content: const Text('好友對戰要先有好友，先去加幾位吧！'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('去加好友')),
          ],
        ),
      );
      if (go == true && mounted) {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => const AddFriendPage()));
      }
      return;
    }

    int idOf(Map<String, dynamic> f) => int.tryParse((f['friend_id'] ?? f['id'])?.toString() ?? '') ?? 0;
    final selected = <int>{if (widget.preselectFriendId != null) widget.preselectFriendId!};
    String theme = 'taiwan';
    try {
      final map = await _api.fetchCurrentMap();
      theme = (map['theme'] ?? 'taiwan').toString();
    } catch (_) {}
    if (!mounted) return;

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(height: 14),
              const Text('建立好友對戰', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF5D4037))),
              const SizedBox(height: 4),
              Text('邀請 1～3 位好友・空位由電腦補上・輪流擲骰，不用同時在線',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600), textAlign: TextAlign.center),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'taiwan', label: Text('🗺️ 台灣環島')),
                    ButtonSegment(value: 'magicIsland', label: Text('✨ 魔法天空島')),
                  ],
                  selected: {theme},
                  onSelectionChanged: (v) => setSheet(() => theme = v.first),
                ),
              ),
              const SizedBox(height: 6),
              Flexible(
                child: ListView(shrinkWrap: true, children: [
                  for (final f in friends)
                    Builder(builder: (_) {
                      final id = idOf(f);
                      final img = CurrentPetManager.petImageMap[(f['pet_key'] ?? '').toString()];
                      return CheckboxListTile(
                        value: selected.contains(id),
                        onChanged: (v) => setSheet(() {
                          if (v == true && selected.length < 3) {
                            selected.add(id);
                          } else if (v != true) {
                            selected.remove(id);
                          }
                        }),
                        secondary: CircleAvatar(
                          backgroundColor: const Color(0xFFFFF0F5),
                          backgroundImage: img != null ? AssetImage(img) : null,
                          child: img == null ? Text((f['pet_emoji'] ?? '🐾').toString()) : null,
                        ),
                        title: Text((f['nickname'] ?? '好友').toString(), style: const TextStyle(fontWeight: FontWeight.w600)),
                      );
                    }),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: selected.isEmpty ? null : () => Navigator.pop(ctx, true),
                    icon: const Icon(Icons.send_rounded),
                    label: Text(selected.isEmpty ? '至少選 1 位好友' : '送出邀請（${selected.length} 位）'),
                  ),
                ),
              ),
            ]),
          ),
        );
      }),
    );
    if (result != true) return;
    try {
      final v = await _api.mpCreate(
        userId: _uid,
        friendIds: selected.toList(),
        theme: theme,
        petKey: await _myPetKey(),
      );
      _snack('邀請已送出！好友接受後就會開始');
      await _openGame(v['id'] as int);
    } catch (e) {
      _snack(GameApiService.errorMessage(e));
    }
  }

  // ── UI ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final invites = _games.where((g) => g['invite_status'] == 'pending' && g['status'] == 'waiting').toList();
    final active = _games.where((g) => g['status'] != 'finished' && !invites.contains(g)).toList();
    final finished = _games.where((g) => g['status'] == 'finished').toList();

    return Scaffold(
      backgroundColor: const Color(0xFFFFF5F5),
      appBar: AppBar(
        title: const Text('好友對戰', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.brown)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.brown,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreateSheet,
        backgroundColor: Colors.pink,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('建立對戰'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.pink))
          : _error != null
          ? Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.wifi_off_rounded, size: 52, color: Colors.grey),
          const SizedBox(height: 10),
          Text(_error!),
          const SizedBox(height: 12),
          FilledButton(onPressed: _load, child: const Text('重新載入')),
        ]),
      )
          : RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            if (_games.isEmpty) _empty(),
            if (invites.isNotEmpty) ...[
              _section('收到的邀請'),
              ...invites.map(_inviteCard),
            ],
            if (active.isNotEmpty) ...[
              _section('進行中'),
              ...active.map(_gameCard),
            ],
            if (finished.isNotEmpty) ...[
              _section('已結束'),
              ...finished.take(10).map(_gameCard),
            ],
          ],
        ),
      ),
    );
  }

  Widget _empty() => Padding(
    padding: const EdgeInsets.only(top: 80),
    child: Column(children: const [
      Text('🎲', style: TextStyle(fontSize: 60)),
      SizedBox(height: 12),
      Text('還沒有對戰', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.brown)),
      SizedBox(height: 6),
      Text('按右下角「建立對戰」邀請好友一起玩大富翁', style: TextStyle(color: Colors.grey)),
    ]),
  );

  Widget _section(String t) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
    child: Text(t, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.brown)),
  );

  String _playersLine(Map<String, dynamic> g) {
    final ps = ((g['players'] as List?) ?? const []).whereType<Map>();
    return ps.map((p) => '${p['emoji'] ?? ''}${p['is_me'] == true ? '我' : p['name']}').join('、');
  }

  Widget _inviteCard(Map<String, dynamic> g) {
    final host = ((g['players'] as List?) ?? const []).whereType<Map>().firstOrNull;
    return Card(
      elevation: 0,
      color: Colors.pink.shade50,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: Colors.pink.shade100)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('📨 ${host?['name'] ?? '好友'} 邀請你玩「${g['theme_name']}」',
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.brown)),
          const SizedBox(height: 4),
          Text('玩家：${_playersLine(g)}', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
          const SizedBox(height: 4),
          Text('會用你目前上場的寵物和技能參戰', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: () => _respond(g, false), child: const Text('婉拒', style: TextStyle(color: Colors.grey))),
            const SizedBox(width: 6),
            FilledButton(onPressed: () => _respond(g, true), child: const Text('接受')),
          ]),
        ]),
      ),
    );
  }

  Widget _gameCard(Map<String, dynamic> g) {
    final status = g['status'];
    final myTurn = g['my_turn'] == true;
    String subtitle;
    Color badgeColor;
    String badge;
    if (status == 'waiting') {
      subtitle = '等待好友接受邀請…';
      badge = '等待中';
      badgeColor = Colors.orange;
    } else if (status == 'finished') {
      subtitle = g['i_won'] == true ? '🏆 你贏了！' : '冠軍：${g['winner_name'] ?? '-'}';
      badge = '已結束';
      badgeColor = Colors.grey;
    } else {
      subtitle = myTurn ? '輪到你擲骰子了！' : '等待 ${g['current_name']} 行動…（第 ${g['round']} 輪）';
      badge = myTurn ? '輪到你' : '進行中';
      badgeColor = myTurn ? Colors.pink : Colors.teal;
    }
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: myTurn ? Colors.pink.shade200 : Colors.grey.shade200, width: myTurn ? 2 : 1),
      ),
      child: ListTile(
        onTap: () => _openGame(g['id'] as int),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        title: Row(children: [
          Expanded(child: Text(g['theme_name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.brown))),
          if (g['has_news'] == true && status != 'finished')
            const Padding(padding: EdgeInsets.only(right: 6), child: Icon(Icons.circle, size: 8, color: Colors.pink)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: badgeColor.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
            child: Text(badge, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: badgeColor)),
          ),
        ]),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(color: myTurn ? Colors.pink : Colors.grey.shade700, fontWeight: myTurn ? FontWeight.bold : FontWeight.normal)),
          const SizedBox(height: 2),
          Text(_playersLine(g), style: TextStyle(fontSize: 11, color: Colors.grey.shade500), maxLines: 1, overflow: TextOverflow.ellipsis),
        ]),
      ),
    );
  }
}
