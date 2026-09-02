import 'dart:math';

import 'package:flutter/material.dart';
import 'package:user_interface/services/game_api_service.dart';

class MonsterPage extends StatefulWidget {
  const MonsterPage({super.key});

  @override
  State<MonsterPage> createState() => _MonsterPageState();
}

class _MonsterPageState extends State<MonsterPage> with SingleTickerProviderStateMixin {
  late AnimationController _shakeController;
  double _bossHp = 0.65;
  int _comboCount = 0;
  bool _isLoading = true;

  List<Map<String, dynamic>> _teamMembers = [
    {'name': '我', 'avatar': Icons.person, 'color': Colors.blue, 'doneToday': true},
  ];

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    try {
      final data = await GameApiService.instance.fetchMonsterStatus();
      if (!mounted) return;
      setState(() {
        _bossHp = (_toDouble(data['boss_hp'], fallback: 0.65).clamp(0.0, 1.0) as num).toDouble();
        _comboCount = int.tryParse(data['combo_count']?.toString() ?? '') ?? 0;
        final members = data['team_members'];
        if (members is List) {
          _teamMembers = members.whereType<Map>().map((e) {
            final m = Map<String, dynamic>.from(e);
            return {
              'name': (m['name'] ?? '隊友').toString(),
              'avatar': _avatarByName((m['name'] ?? '').toString()),
              'color': Colors.primaries[(_teamMembers.length + m.hashCode).abs() % Colors.primaries.length],
              'doneToday': m['done_today'] == true,
            };
          }).toList();
        }
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('魔王戰資料庫連線失敗：$e')));
    }
  }

  IconData _avatarByName(String name) {
    if (name == '我') return Icons.person;
    if (name.contains('寵') || name.contains('貓') || name.contains('狗')) return Icons.pets;
    return Icons.face;
  }

  double _toDouble(dynamic v, {double fallback = 0.0}) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? fallback;
  }

  Future<void> _attackBoss() async {
    _shakeController.forward(from: 0.0);
    try {
      final data = await GameApiService.instance.attackMonster();
      if (!mounted) return;
      setState(() {
        _bossHp = (_toDouble(data['boss_hp'], fallback: _bossHp).clamp(0.0, 1.0) as num).toDouble();
        _comboCount = int.tryParse(data['combo_count']?.toString() ?? '') ?? _comboCount;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text((data['message'] ?? '⚔️ 攻擊成功！魔王受到 500 點傷害！').toString()),
          backgroundColor: Colors.redAccent,
          duration: const Duration(seconds: 1),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('攻擊失敗，請確認 MySQL API 是否啟動：$e')));
    }
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E293B),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('公會討伐戰', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: Colors.white), onPressed: () => Navigator.pop(context)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : Column(
              children: [
                _buildBossHeader(),
                Expanded(child: _buildMonsterArea()),
                _buildTeamStatus(),
                _buildActionArea(),
              ],
            ),
    );
  }

  Widget _buildBossHeader() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const Text('🔥 本月限定魔王：手搖飲貪吃龍 🔥', style: TextStyle(color: Colors.orangeAccent, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 15),
          Stack(
            children: [
              Container(height: 25, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(15))),
              FractionallySizedBox(
                widthFactor: _bossHp,
                child: Container(
                  height: 25,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Colors.redAccent, Colors.orange]),
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: [BoxShadow(color: Colors.redAccent.withOpacity(0.5), blurRadius: 10)],
                  ),
                ),
              ),
              Positioned.fill(child: Center(child: Text('${(_bossHp * 10000).toInt()} / 10000', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMonsterArea() {
    return Center(
      child: AnimatedBuilder(
        animation: _shakeController,
        builder: (context, child) {
          final dx = sin(_shakeController.value * pi * 4) * 10;
          return Transform.translate(
            offset: Offset(dx, 0),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(width: 250, height: 250, decoration: BoxDecoration(color: Colors.purple.withOpacity(0.2), shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.purpleAccent.withOpacity(0.3), blurRadius: 40)])),
                const Text('🐉', style: TextStyle(fontSize: 150)),
                if (_shakeController.isAnimating)
                  Positioned(top: 40, right: 40, child: Transform.rotate(angle: 0.3, child: const Text('-500', style: TextStyle(color: Colors.yellow, fontSize: 32, fontWeight: FontWeight.bold, shadows: [Shadow(color: Colors.black, blurRadius: 2)])))),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildTeamStatus() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('小隊狀態', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            Text('連續達成 $_comboCount 天', style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 12),
          Row(
            children: _teamMembers.map((m) {
              final done = m['doneToday'] == true;
              return Expanded(
                child: Column(
                  children: [
                    Stack(
                      children: [
                        CircleAvatar(backgroundColor: (m['color'] as Color).withOpacity(done ? 1.0 : 0.3), child: Icon(m['avatar'] as IconData, color: Colors.white)),
                        if (done) const Positioned(right: 0, bottom: 0, child: Icon(Icons.check_circle, color: Colors.greenAccent, size: 16)),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(m['name'].toString(), style: TextStyle(color: done ? Colors.white : Colors.white38, fontSize: 12)),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildActionArea() {
    final dead = _bossHp <= 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
      child: SizedBox(
        width: double.infinity,
        height: 60,
        child: ElevatedButton.icon(
          onPressed: dead ? null : _attackBoss,
          icon: const Icon(Icons.local_fire_department),
          label: Text(dead ? '魔王已擊敗' : '完成今日記帳，發動攻擊！', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(backgroundColor: dead ? Colors.grey : Colors.redAccent, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)), elevation: 8),
        ),
      ),
    );
  }
}
