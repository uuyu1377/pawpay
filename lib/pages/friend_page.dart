import 'package:flutter/material.dart';
import 'package:user_interface/pages/add_friend_page.dart';
import 'package:user_interface/services/game_api_service.dart';

class FriendPage extends StatefulWidget {
  const FriendPage({super.key});

  @override
  State<FriendPage> createState() => _FriendPageState();
}

class _FriendPageState extends State<FriendPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  List<Map<String, dynamic>> _friends = [];
  List<Map<String, dynamic>> _leaderboard = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    try {
      final api = GameApiService.instance;
      final results = await Future.wait([
        api.fetchFriends(),
        api.fetchLeaderboard().catchError((_) => <Map<String, dynamic>>[]),
      ]);
      if (!mounted) return;
      setState(() {
        _friends     = results[0];
        _leaderboard = results[1];
        _isLoading   = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  // ── helpers ───────────────────────────────────────────────────────────────

  String _name(Map<String, dynamic> m) =>
      (m['nickname'] ?? m['display_name'] ?? m['username'] ?? '玩家').toString();

  int _money(Map<String, dynamic> m) {
    final v = m['money'] ?? m['coins'] ?? m['score'] ?? 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  String _petEmoji(Map<String, dynamic> m) =>
      (m['pet_emoji'] ?? m['emoji'] ?? '🐾').toString();

  Color _avatarColor(String name) =>
      Colors.primaries[name.hashCode.abs() % Colors.primaries.length];

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF5F5),
      appBar: AppBar(
        title: const Text('好友 & 排行榜',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.brown)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.brown,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_rounded, color: Colors.pink),
            tooltip: '新增好友',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AddFriendPage()),
            ).then((_) => _loadAll()),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.pink,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.pink,
          tabs: [
            Tab(text: '好友列表${_friends.isEmpty ? '' : ' (${_friends.length})'}'),
            const Tab(text: '排行榜'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.pink))
          : RefreshIndicator(
              onRefresh: _loadAll,
              child: TabBarView(
                controller: _tabController,
                children: [_buildFriendList(), _buildLeaderboard()],
              ),
            ),
    );
  }

  // ── 好友列表 Tab ──────────────────────────────────────────────────────────

  Widget _buildFriendList() {
    if (_friends.isEmpty) {
      return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(
          height: 500,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Text('🐾', style: TextStyle(fontSize: 64)),
            const SizedBox(height: 16),
            const Text('還沒有好友', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.brown)),
            const SizedBox(height: 6),
            const Text('去加幾個好友一起玩吧！', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AddFriendPage()),
              ).then((_) => _loadAll()),
              icon: const Icon(Icons.person_add_rounded),
              label: const Text('新增好友'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.pink,
                foregroundColor: Colors.white,
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ]),
        ),
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      itemCount: _friends.length,
      itemBuilder: (_, i) => _friendCard(_friends[i]),
    );
  }

  Widget _friendCard(Map<String, dynamic> f) {
    final name  = _name(f);
    final money = _money(f);
    final emoji = _petEmoji(f);
    final petName = (f['pet_name'] ?? f['active_pet'] ?? '').toString();
    final color = _avatarColor(name);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: color.withOpacity(0.12), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(children: [
        // 頭像
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            shape: BoxShape.circle,
            border: Border.all(color: color.withOpacity(0.5), width: 2),
          ),
          child: Center(
            child: Text(
              name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color),
            ),
          ),
        ),
        const SizedBox(width: 12),
        // 名稱 + 寵物
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.brown)),
          const SizedBox(height: 3),
          Row(children: [
            Text(emoji, style: const TextStyle(fontSize: 14)),
            if (petName.isNotEmpty) ...[
              const SizedBox(width: 4),
              Text(petName, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            ],
          ]),
        ])),
        // 代幣
        _coinBadge(money),
      ]),
    );
  }

  // ── 排行榜 Tab ────────────────────────────────────────────────────────────

  Widget _buildLeaderboard() {
    // 若後端沒有 leaderboard endpoint，fallback 用好友列表排序
    final rankList = _leaderboard.isNotEmpty
        ? _leaderboard
        : ([..._friends]..sort((a, b) => _money(b).compareTo(_money(a))));

    if (rankList.isEmpty) {
      return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: const SizedBox(
          height: 500,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('🏆', style: TextStyle(fontSize: 64)),
            SizedBox(height: 16),
            Text('排行榜空空的', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.brown)),
            SizedBox(height: 6),
            Text('先去加好友，再來拚排名！', style: TextStyle(color: Colors.grey)),
          ]),
        ),
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      itemCount: rankList.length + 1,
      itemBuilder: (_, i) {
        if (i == 0) return _leaderboardHeader();
        final entry = rankList[i - 1];
        final isMe = (entry['is_me'] as bool?) == true ||
            entry['user_id']?.toString() == '1';
        return _rankRow(rank: i, entry: entry, isMe: isMe);
      },
    );
  }

  Widget _leaderboardHeader() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Text('🏆', style: TextStyle(fontSize: 28)),
        const SizedBox(width: 8),
        Text(
          '代幣排行榜',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.brown.shade700),
        ),
      ]),
    );
  }

  Widget _rankRow({required int rank, required Map<String, dynamic> entry, required bool isMe}) {
    const medals = {1: '🥇', 2: '🥈', 3: '🥉'};
    final medal = medals[rank];
    final badgeColor = rank == 1
        ? const Color(0xFFFFD700)
        : rank == 2
            ? const Color(0xFFC0C0C0)
            : rank == 3
                ? const Color(0xFFCD7F32)
                : Colors.grey.shade300;

    final name  = _name(entry);
    final money = _money(entry);
    final emoji = _petEmoji(entry);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: isMe ? Colors.pink.shade50 : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isMe
              ? Colors.pink.shade200
              : rank <= 3
                  ? badgeColor.withOpacity(0.6)
                  : Colors.transparent,
          width: isMe || rank <= 3 ? 1.5 : 0,
        ),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Row(children: [
        // 名次
        SizedBox(
          width: 36,
          child: medal != null
              ? Text(medal, style: const TextStyle(fontSize: 22), textAlign: TextAlign.center)
              : Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(color: badgeColor, shape: BoxShape.circle),
                  child: Center(
                    child: Text('$rank',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: rank <= 3 ? Colors.white : Colors.grey.shade700)),
                  ),
                ),
        ),
        const SizedBox(width: 8),
        // 寵物 emoji
        Text(emoji, style: const TextStyle(fontSize: 22)),
        const SizedBox(width: 10),
        // 名稱
        Expanded(
          child: Text(
            name + (isMe ? '  (我)' : ''),
            style: TextStyle(
              fontSize: 14,
              fontWeight: isMe ? FontWeight.bold : FontWeight.w500,
              color: isMe ? Colors.pink.shade700 : Colors.brown,
            ),
          ),
        ),
        // 代幣
        _coinBadge(money, highlight: rank == 1),
      ]),
    );
  }

  Widget _coinBadge(int amount, {bool highlight = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: highlight ? Colors.orange.withOpacity(0.18) : Colors.orange.withOpacity(0.09),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withOpacity(highlight ? 0.5 : 0.25)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.monetization_on, color: Colors.orange.shade700, size: 14),
        const SizedBox(width: 4),
        Text('$amount',
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: highlight ? Colors.orange.shade800 : Colors.brown)),
      ]),
    );
  }
}
