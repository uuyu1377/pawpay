// ★ 資金分配頁（圖像化改版）：全新整頁，不動任何原有程式碼。
// 特色：
//  - 一根「滿版分配水柱」：每個分類＝一段有顏色的水，高度 ∝ 它的百分比，水面有波浪動畫。
//  - 使用者調的是「百分比」，金額由 App 自動算（可分配 × %）。收入變了金額會自動重算。
//  - 水柱底部黑色「＋」可新增自訂分類；★所有分類都可刪（按「套用建議」可一鍵復原）。
//  - AI 依「身分＋歷史存錢習慣」給一組建議比例，可一鍵套用。
// 資料存手機 prefs（key: fund_allocation_percents，存「百分比」）。不動資料庫。
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/transaction_model.dart';
import '../services/database_helper.dart';
import '../services/recurring_api_service.dart';

class FundAllocationPage extends StatefulWidget {
  const FundAllocationPage({super.key});

  @override
  State<FundAllocationPage> createState() => _FundAllocationPageState();
}

class _FundAllocationPageState extends State<FundAllocationPage> with SingleTickerProviderStateMixin {
  bool _loading = true;
  double _allocatable = 0;
  double _income = 0;
  double _targetSavings = 0;
  double _budget = 0;
  String _identity = 'u23';
  String _historyNote = '';

  // 分類 → 百分比
  final Map<String, int> _percents = {};
  late List<String> _buckets; // 顯示順序
  late List<String> _defaultBuckets; // 預設順序用

  late final AnimationController _wave;

  // 每個分類的顏色（依順序取用）
  static const List<Color> _palette = [
    Color(0xFF4FC3F7), // 藍
    Color(0xFF7E57C2), // 紫
    Color(0xFF66BB6A), // 綠
    Color(0xFFFFB74D), // 橘
    Color(0xFFEF5350), // 紅
    Color(0xFF26A69A), // 青
    Color(0xFFEC407A), // 粉
    Color(0xFF8D6E63), // 棕
  ];

  @override
  void initState() {
    super.initState();
    _wave = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();
    _load();
  }

  @override
  void dispose() {
    _wave.dispose();
    super.dispose();
  }

  double _toMonthly(double amount, String cadence) {
    switch (cadence) {
      case 'weekly':
        return amount * 4.345;
      case 'yearly':
        return amount / 12.0;
      case 'monthly':
      default:
        return amount;
    }
  }

  Map<String, int> _basePercents(String code) {
    switch (code) {
      case 'a23_35':
        return {'緊急預備金': 15, '投資理財': 35, '短期目標': 25, '彈性花費': 25};
      case 'a35p':
        return {'緊急預備金': 20, '投資理財': 20, '短期目標': 25, '彈性花費': 15, '家庭專用': 20};
      case 'u23':
      default:
        return {'緊急預備金': 20, '投資理財': 10, '短期目標': 40, '彈性花費': 30};
    }
  }

  // 近 3 個完整月(不含本月)的「存下 / 收入」比例，用來微調建議（null=歷史不足）。
  Future<double?> _storingRatioFromHistory() async {
    try {
      final txs = await DatabaseHelper.instance.getAllTransactions();
      final now = DateTime.now();
      final Map<String, double> inc = {};
      final Map<String, double> exp = {};
      for (int i = 1; i <= 3; i++) {
        final m = DateTime(now.year, now.month - i, 1);
        inc['${m.year}-${m.month}'] = 0;
        exp['${m.year}-${m.month}'] = 0;
      }
      for (final tx in txs) {
        for (int i = 1; i <= 3; i++) {
          final m = DateTime(now.year, now.month - i, 1);
          if (tx.date.year == m.year && tx.date.month == m.month) {
            final k = '${m.year}-${m.month}';
            if (tx.type == TransactionType.income) {
              inc[k] = (inc[k] ?? 0) + tx.amount.abs();
            } else {
              exp[k] = (exp[k] ?? 0) + tx.amount.abs();
            }
            break;
          }
        }
      }
      double ti = 0, ts = 0;
      int months = 0;
      inc.forEach((k, v) {
        final e = exp[k] ?? 0;
        if (v > 0 || e > 0) {
          months++;
          ti += v;
          ts += (v - e);
        }
      });
      if (months < 2 || ti <= 0) return null;
      return ts / ti;
    } catch (_) {
      return null;
    }
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _identity = prefs.getString('user_identity') ?? 'u23';
    _targetSavings = (prefs.getInt('setting_monthly_target_savings') ?? 0).toDouble();
    _budget = (prefs.getInt('setting_monthly_budget_amount') ?? 0).toDouble();

    double income = 0;
    try {
      final txs = await DatabaseHelper.instance.getAllTransactions();
      final now = DateTime.now();
      for (final tx in txs) {
        if (tx.type == TransactionType.income && tx.date.year == now.year && tx.date.month == now.month) {
          income += tx.amount.abs();
        }
      }
    } catch (_) {}
    if (income <= 0) {
      try {
        final rules = await RecurringApiService.instance.fetchRules();
        for (final r in rules) {
          if (r.isActive && r.direction == 'income') {
            income += _toMonthly(r.amount, r.cadence);
          }
        }
      } catch (_) {}
    }
    _income = income;
    _allocatable = (income - _targetSavings - _budget);
    if (_allocatable < 0) _allocatable = 0;

    _defaultBuckets = _basePercents(_identity).keys.toList();

    // 建議比例（身分＋歷史微調）
    final suggested = Map<String, int>.from(_basePercents(_identity));
    final ratio = await _storingRatioFromHistory();
    if (ratio == null) {
      _historyNote = '記帳久一點，AI 會依你的存錢習慣微調比例。';
    } else if (ratio < 0.1) {
      final inv = suggested['投資理財'] ?? 0;
      final cut = inv >= 10 ? 10 : inv;
      suggested['投資理財'] = inv - cut;
      suggested['彈性花費'] = (suggested['彈性花費'] ?? 0) + cut;
      _historyNote = '你近 3 個月平均只存下約 ${(ratio * 100).round()}%，先把投資比例調低、從做得到的開始。';
    } else if (ratio > 0.3) {
      final flex = suggested['彈性花費'] ?? 0;
      final add = flex >= 10 ? 10 : flex;
      suggested['彈性花費'] = flex - add;
      suggested['投資理財'] = (suggested['投資理財'] ?? 0) + add;
      _historyNote = '你近 3 個月平均存下約 ${(ratio * 100).round()}%，存得不錯，可以多分一點去投資。';
    } else {
      _historyNote = '你近 3 個月平均存下約 ${(ratio * 100).round()}%，維持身分建議的比例即可。';
    }
    _aiCache = suggested;

    // 載入上次存的百分比；沒有就用建議
    _percents.clear();
    try {
      final saved = prefs.getString('fund_allocation_percents');
      if (saved != null && saved.isNotEmpty) {
        final Map<String, dynamic> m = jsonDecode(saved);
        m.forEach((k, v) {
          _percents[k] = (v is num) ? v.toInt() : int.tryParse(v.toString()) ?? 0;
        });
      }
    } catch (_) {}
    if (_percents.isEmpty) {
      _percents.addAll(suggested);
    }
    // 順序：先預設桶、再自訂桶
    _rebuildOrder();

    if (!mounted) return;
    setState(() => _loading = false);
  }

  Map<String, int> _aiCache = {};

  void _rebuildOrder() {
    final order = <String>[];
    for (final b in _defaultBuckets) {
      if (_percents.containsKey(b)) order.add(b);
    }
    for (final b in _percents.keys) {
      if (!order.contains(b)) order.add(b);
    }
    _buckets = order;
  }

  int get _totalPct => _percents.values.fold(0, (a, b) => a + b);
  double _moneyOf(int pct) => _allocatable * pct / 100;

  void _applyAiSuggestion() {
    setState(() {
      _percents
        ..clear()
        ..addAll(_aiCache);
      _rebuildOrder();
    });
  }

  void _bump(String bucket, int delta) {
    setState(() {
      final cur = _percents[bucket] ?? 0;
      final next = (cur + delta).clamp(0, 100);
      _percents[bucket] = next;
    });
  }

  Future<void> _addBucket() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新增分配分類'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '例如：旅遊基金、孝親費'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('新增')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    if (_percents.containsKey(name)) return;
    setState(() {
      _percents[name] = 0;
      _rebuildOrder();
    });
  }

  void _deleteBucket(String bucket) {
    setState(() {
      _percents.remove(bucket);
      _rebuildOrder();
    });
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('fund_allocation_percents', jsonEncode(_percents));
    if (!mounted) return;
    final over = _totalPct > 100;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(over ? '總比例超過 100%，請調整後再存。' : '資金分配已儲存')),
    );
  }

  String _money(num v) =>
      'NT\$ ${v.round().toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}';

  Color _colorFor(int index) => _palette[index % _palette.length];

  @override
  Widget build(BuildContext context) {
    final total = _totalPct;
    final over = total > 100;
    return Scaffold(
      backgroundColor: const Color(0xFFFFF5F5),
      appBar: AppBar(
        title: const Text('資金分配'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.brown,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 可分配總覽
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('本月可自由分配',
                    style: TextStyle(color: Colors.brown, fontWeight: FontWeight.w900, fontSize: 15)),
                const SizedBox(height: 6),
                Text(_money(_allocatable),
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Color(0xFF2E7D32))),
                const SizedBox(height: 4),
                Text('＝ 收入 ${_money(_income)} − 目標存款 ${_money(_targetSavings)} − 每月預算 ${_money(_budget)}',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600, height: 1.4)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // 水柱 + 圖例
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _buildWaterColumn(),
                const SizedBox(width: 18),
                Expanded(child: _buildLegend()),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // AI 建議
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: const Color(0xFFEDE7FF), borderRadius: BorderRadius.circular(14)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text('依你的身分與存錢習慣，幫你想了一組分配比例。',
                          style: TextStyle(color: Color(0xFF5E35B1), fontSize: 13, height: 1.4)),
                    ),
                    TextButton(onPressed: _applyAiSuggestion, child: const Text('套用建議')),
                  ],
                ),
                Text(_historyNote,
                    style: TextStyle(color: Colors.deepPurple.shade400, fontSize: 12, height: 1.4)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // 各分類調整
          ...List.generate(_buckets.length, (i) => _buildBucketRow(_buckets[i], i)),
          const SizedBox(height: 8),
          // 黑色 ＋ 新增
          Center(
            child: GestureDetector(
              onTap: _addBucket,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(30)),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, color: Colors.white, size: 20),
                    SizedBox(width: 6),
                    Text('新增分類', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // 合計
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: (over ? Colors.red : Colors.green).withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('總共 $total%（剩 ${100 - total > 0 ? 100 - total : 0}%）',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(
                  over ? '超過 100%' : '已分配 ${_money(_moneyOf(total))}',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: over ? Colors.red.shade700 : Colors.green.shade800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: over ? null : _save,
              icon: const Icon(Icons.save_rounded),
              label: const Text('儲存資金分配'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8D3B4A),
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade300,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text('這只是你的理財計畫（記錄用），App 不會自動扣款或強制你照做。',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildWaterColumn() {
    // 準備由下往上的分段（只放 >0 的）
    final segs = <MapEntry<Color, double>>[];
    for (int i = 0; i < _buckets.length; i++) {
      final pct = _percents[_buckets[i]] ?? 0;
      if (pct > 0) segs.add(MapEntry(_colorFor(i), pct / 100.0));
    }
    return SizedBox(
      width: 96,
      height: 240,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            Container(color: const Color(0xFFF0F2F5)),
            AnimatedBuilder(
              animation: _wave,
              builder: (context, _) => CustomPaint(
                size: const Size(96, 240),
                painter: _WaterColumnPainter(segs, _wave.value),
              ),
            ),
            // 中央顯示已分配總比例
            Center(
              child: Text(
                '${_totalPct.clamp(0, 999)}%',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: _totalPct >= 55 ? Colors.white : Colors.black87,
                  shadows: const [Shadow(color: Colors.black26, blurRadius: 4)],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegend() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(_buckets.length, (i) {
        final b = _buckets[i];
        final pct = _percents[b] ?? 0;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Container(width: 12, height: 12, decoration: BoxDecoration(color: _colorFor(i), shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Expanded(child: Text(b, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
              Text('$pct%', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildBucketRow(String bucket, int index) {
    final pct = _percents[bucket] ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          Container(width: 12, height: 12, decoration: BoxDecoration(color: _colorFor(index), shape: BoxShape.circle)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(bucket, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                Text(_money(_moneyOf(pct)), style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ],
            ),
          ),
          _roundBtn(Icons.remove, () => _bump(bucket, -5)),
          Container(
            width: 46,
            alignment: Alignment.center,
            child: Text('$pct%', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
          ),
          _roundBtn(Icons.add, () => _bump(bucket, 5)),
          // ★ 所有分類都可刪（原本限制「只有自訂可刪」已移除）
          IconButton(
            icon: Icon(Icons.delete_outline_rounded, color: Colors.grey.shade400, size: 20),
            onPressed: () => _deleteBucket(bucket),
          ),
        ],
      ),
    );
  }

  Widget _roundBtn(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 30,
        height: 30,
        decoration: const BoxDecoration(color: Color(0xFFF0F2F5), shape: BoxShape.circle),
        child: Icon(icon, size: 18, color: Colors.brown),
      ),
    );
  }
}

// 分段水柱：由下往上堆疊各分類的顏色，最上面的水面加波浪。
class _WaterColumnPainter extends CustomPainter {
  final List<MapEntry<Color, double>> segments; // color, fraction(0..1)
  final double phase;
  _WaterColumnPainter(this.segments, this.phase);

  @override
  void paint(Canvas canvas, Size size) {
    double filled = 0;
    for (final s in segments) {
      filled += s.value;
    }
    if (filled > 1) filled = 1;

    // 由下往上畫每一段
    double y = size.height;
    for (int i = 0; i < segments.length; i++) {
      double frac = segments[i].value;
      // 若總和超過 1，等比壓縮到剛好填滿
      if (filled >= 1) {
        double totalRaw = 0;
        for (final s in segments) {
          totalRaw += s.value;
        }
        frac = segments[i].value / (totalRaw == 0 ? 1 : totalRaw);
      }
      final h = size.height * frac;
      final rect = Rect.fromLTWH(0, y - h, size.width, h);
      canvas.drawRect(rect, Paint()..color = segments[i].key);
      y -= h;
    }

    // 水面波浪（沒填滿時，在水面上畫一層最上面那段的顏色波）
    if (filled > 0 && filled < 1 && segments.isNotEmpty) {
      final surfaceY = size.height * (1 - filled);
      final topColor = segments.last.key;
      final path = Path()..moveTo(0, surfaceY);
      for (double x = 0; x <= size.width; x++) {
        final yy = surfaceY + 5 * math.sin((x / size.width * 2 * math.pi * 2) + (phase * 2 * math.pi));
        path.lineTo(x, yy);
      }
      path.lineTo(size.width, surfaceY + 14);
      path.lineTo(0, surfaceY + 14);
      path.close();
      canvas.drawPath(path, Paint()..color = topColor.withOpacity(0.9));
    }
  }

  @override
  bool shouldRepaint(covariant _WaterColumnPainter old) => true;
}