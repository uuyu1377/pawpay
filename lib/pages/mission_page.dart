import 'package:flutter/material.dart';

import 'package:user_interface/services/game_api_service.dart';

class MissionPage extends StatefulWidget {
  const MissionPage({super.key});

  @override
  State<MissionPage> createState() => _MissionPageState();
}

class _MissionPageState extends State<MissionPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _missions = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final missions = await GameApiService.instance.fetchMissions();
      if (!mounted) return;
      setState(() {
        _missions = missions;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '任務資料讀取失敗：$e';
      });
    }
  }

  Future<void> _claim(Map<String, dynamic> mission) async {
    final id = mission['id']?.toString() ?? '';
    if (id.isEmpty) return;
    try {
      final result = await GameApiService.instance.claimMission(missionId: id);
      final earned = _asInt(result['earned_gacha_coins']);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('任務完成，獲得扭蛋幣 +$earned')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('領取失敗：$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('任務中心')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return ListView(
        physics: AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: 220),
          Center(child: CircularProgressIndicator()),
        ],
      );
    }
    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 120),
          const Icon(Icons.cloud_off_rounded, size: 54, color: Colors.grey),
          const SizedBox(height: 12),
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(onPressed: _load, child: const Text('重試')),
        ],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      itemCount: _missions.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF4E8),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Text(
              '完成任務後可領取扭蛋幣；連續登入的每日獎勵會自動發放。',
              style: TextStyle(fontWeight: FontWeight.w600, height: 1.4),
            ),
          );
        }
        return _missionCard(_missions[index - 1]);
      },
    );
  }

  Widget _missionCard(Map<String, dynamic> mission) {
    final title = mission['title']?.toString() ?? '任務';
    final description = mission['description']?.toString() ?? '';
    final progress = _asInt(mission['progress']);
    final goal = _asInt(mission['goal']).clamp(1, 1 << 30);
    final reward = _asInt(mission['reward']);
    final completed = mission['completed'] == true;
    final claimed = mission['claimed'] == true;
    final ratio = (progress / goal).clamp(0.0, 1.0);

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF2D8),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('扭蛋幣 +$reward', style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            if (description.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(description, style: const TextStyle(color: Colors.black54)),
            ],
            const SizedBox(height: 14),
            LinearProgressIndicator(value: ratio, minHeight: 8, borderRadius: BorderRadius.circular(20)),
            const SizedBox(height: 8),
            Row(
              children: [
                Text('$progress / $goal', style: const TextStyle(fontWeight: FontWeight.w600)),
                const Spacer(),
                if (claimed)
                  const Chip(label: Text('已領取'))
                else
                  FilledButton(
                    onPressed: completed ? () => _claim(mission) : null,
                    child: Text(completed ? '領取' : '未完成'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}