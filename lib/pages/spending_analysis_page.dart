// ★ 任務2（詳細分析頁）：全新檔案，不動任何原有程式碼。
// 這頁把「資料層」的細項全部用程式算出來並呈現：本月收入/已花、剩餘可支配、
// 流速預測、每天可花、各分類佔比與最兇分類、與上月比較（含哪類暴增）、分類預算達成率。
// 教練彈窗底部的「看詳細分析」按鈕會導到這頁。
import 'package:flutter/material.dart';
import 'dart:math' as math; // ★ 任務2：水位計波浪用 sin
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/transaction_model.dart';
import '../services/database_helper.dart';
import '../services/recurring_api_service.dart';
import '../services/category_budget_service.dart';
import 'fund_allocation_page.dart'; // ★ 資金分配頁（收入分配卡的連結）

class SpendingAnalysisPage extends StatefulWidget {
  const SpendingAnalysisPage({super.key});

  @override
  State<SpendingAnalysisPage> createState() => _SpendingAnalysisPageState();
}

class _SpendingAnalysisPageState extends State<SpendingAnalysisPage> {
  bool _loading = true;

  // 統計結果
  double _income = 0; // 本月收入（實際收入交易）
  double _spent = 0; // 本月已花（支出交易）
  double _lastMonthSpent = 0; // 上月支出
  double _monthlyIncome = 0; // 月固定收入（固定收支）
  double _reserveFixed = 0; // 本月尚未入帳的固定支出
  double _targetSavings = 0; // 本月目標存款
  double _budget = 0; // 每月預算（備援基準）

  double _usableBudget = 0; // 可花上限
  double _remaining = 0; // 剩餘可支配
  double _perDay = 0; // 每天可花
  double _projected = 0; // 月底流速預測
  double _projectedOver = 0; // 預估超支
  int _daysLeft = 0;

  Map<String, double> _catTotals = {}; // 本月各分類支出
  Map<String, double> _lastCatTotals = {}; // 上月各分類支出
  Map<String, double> _categoryBudgets = {}; // 分類預算

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  double _toMonthlyAmount(double amount, String cadence) {
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

  Future<void> _loadAll() async {
    final now = DateTime.now();
    final int daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final int daysLeft = (daysInMonth - now.day + 1).clamp(1, daysInMonth);
    final DateTime lastMonth = DateTime(now.year, now.month - 1, 1);

    // 1) 交易：本月收入/支出、各分類（本月＋上月）
    double income = 0;
    double spent = 0;
    double lastMonthSpent = 0;
    final Map<String, double> catTotals = {};
    final Map<String, double> lastCatTotals = {};
    try {
      final txs = await DatabaseHelper.instance.getAllTransactions();
      for (final tx in txs) {
        final bool isThisMonth = tx.date.year == now.year && tx.date.month == now.month;
        final bool isLastMonth = tx.date.year == lastMonth.year && tx.date.month == lastMonth.month;
        if (tx.type == TransactionType.income && isThisMonth) {
          income += tx.amount.abs();
        }
        if (tx.type == TransactionType.expense) {
          final c = tx.category.trim().isEmpty ? '未分類' : tx.category.trim();
          if (isThisMonth) {
            spent += tx.amount.abs();
            catTotals[c] = (catTotals[c] ?? 0) + tx.amount.abs();
          } else if (isLastMonth) {
            lastMonthSpent += tx.amount.abs();
            lastCatTotals[c] = (lastCatTotals[c] ?? 0) + tx.amount.abs();
          }
        }
      }
    } catch (_) {}

    // 2) 固定收支：月固定收入 + 本月尚未入帳的固定支出
    double monthlyIncome = 0;
    double reserveFixed = 0;
    try {
      final rules = await RecurringApiService.instance.fetchRules();
      for (final r in rules) {
        if (!r.isActive) continue;
        if (r.direction == 'income') {
          monthlyIncome += _toMonthlyAmount(r.amount, r.cadence);
        } else {
          if (r.nextRunDate.year == now.year && r.nextRunDate.month == now.month) {
            reserveFixed += r.amount;
          }
        }
      }
    } catch (_) {}

    // 3) prefs：目標存款 + 每月預算
    double targetSavings = 0;
    double budget = 0;
    try {
      final prefs = await SharedPreferences.getInstance();
      targetSavings = (prefs.getInt('setting_monthly_target_savings') ?? 0).toDouble();
      budget = (prefs.getInt('setting_monthly_budget_amount') ?? 0).toDouble();
    } catch (_) {}

    // 4) 分類預算
    Map<String, double> categoryBudgets = {};
    try {
      categoryBudgets = await CategoryBudgetService.loadAll();
    } catch (_) {}

    // 5) 可支配公式（★修正：基準統一為「每月預算 − 目標存款」，跟教練彈窗/進度條一致；
    //    收入不再混進可花上限，改放下面獨立的「本月收入分配」卡呈現全貌）。
    final double usableBudget = (budget - targetSavings) > 0 ? (budget - targetSavings) : 0.0;
    final double remaining = usableBudget - spent;
    final double perDay = remaining > 0 ? remaining / daysLeft : 0.0;
    final double projected = now.day > 0 ? spent / now.day * daysInMonth : spent;
    final double projectedOver = projected - usableBudget;

    if (!mounted) return;
    setState(() {
      _income = income;
      _spent = spent;
      _lastMonthSpent = lastMonthSpent;
      _monthlyIncome = monthlyIncome;
      _reserveFixed = reserveFixed;
      _targetSavings = targetSavings;
      _budget = budget;
      _usableBudget = usableBudget;
      _remaining = remaining;
      _perDay = perDay;
      _projected = projected;
      _projectedOver = projectedOver;
      _daysLeft = daysLeft;
      _catTotals = catTotals;
      _lastCatTotals = lastCatTotals;
      _categoryBudgets = categoryBudgets;
      _loading = false;
    });
  }

  String _money(num v) => 'NT\$ ${NumberFormat('#,##0').format(v.round())}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF5F5),
      appBar: AppBar(
        title: const Text('詳細分析'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.brown,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildOverviewCard(),
          const SizedBox(height: 14),
          _buildIncomeAllocationCard(),
          const SizedBox(height: 14),
          _buildSavingsGoalCard(),
          const SizedBox(height: 14),
          _buildPaceCard(),
          const SizedBox(height: 14),
          _buildCategoryShareCard(),
          const SizedBox(height: 14),
          _buildVsLastMonthCard(),
          const SizedBox(height: 14),
          _buildCategoryBudgetCard(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // 卡片外框
  Widget _card({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.brown)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _stat(String label, String value, {Color? valueColor}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: valueColor ?? Colors.black87)),
      ],
    );
  }

  // ★ 新增：本月收入分配（用「收入」當主角，呈現整月的錢怎麼分；跟「預算執行」分開，各司其職）。
  //   收入 − 目標存款 − 每月預算 = 可自由分配/未分配。
  Widget _buildIncomeAllocationCard() {
    final double income = _income > 0 ? _income : _monthlyIncome; // 有實際收入用實際，否則用月固定收入
    if (income <= 0) {
      return _card(
        title: '本月收入分配',
        child: Text('還沒有收入資料，設定「固定收支」的收入後這裡會顯示整月的錢怎麼分',
            style: TextStyle(color: Colors.grey.shade600)),
      );
    }
    final double leftover = income - _targetSavings - _budget; // 可自由分配（可能為負）
    return _card(
      title: '本月收入分配',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _waterfallRow('本月收入', income, sign: 1),
          _waterfallRow('目標存款（想存）', _targetSavings, sign: -1),
          _waterfallRow('每月預算（想花）', _budget, sign: -1),
          _waterfallDivider(),
          _waterfallRow(leftover >= 0 ? '可自由分配' : '已透支', leftover, isSubtotal: true, isFinal: true),
          const SizedBox(height: 6),
          Text(
            leftover >= 0
                ? '這筆是收入扣掉「想存的」和「想花的」之後，還沒分配的錢。'
                : '你設的目標存款＋預算已超過收入，先調整看看。',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.4),
          ),
          // ★ 新增：一鍵進「資金分配」頁規劃這筆可自由分配的錢
          if (leftover > 0) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const FundAllocationPage()),
                ),
                icon: const Icon(Icons.pie_chart_rounded, size: 18),
                label: const Text('去資金分配 →'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ★ 修正(做法A)：儲蓄達成率改用「先存後花」一致的定義，避免跟「超支」自打嘴巴。
  //   實際存下 = 目標存款 + 剩餘可支配(可花上限 − 已花)。
  //   花在可花上限內 → 存滿目標甚至超額；花超過可花上限 → 會吃掉目標存款，達成率跟著往下。
  Widget _buildSavingsGoalCard() {
    if (_targetSavings <= 0) {
      return _card(
        title: '儲蓄達成率',
        child: Text('尚未設定本月目標存款，去設定頁設一個目標吧', style: TextStyle(color: Colors.grey.shade600)),
      );
    }
    final double actualSaved = _targetSavings + _remaining; // _remaining = 可花上限 − 已花（可為負）
    final double ratio = _targetSavings > 0 ? (actualSaved / _targetSavings) : 0;
    final int pct = (ratio * 100).round();
    final bool reached = _remaining >= 0; // 花在可花上限內 = 目標存款完整保住(甚至超額)
    final double gap = -_remaining; // 超支多少 = 吃掉多少存款
    final Color color = reached ? Colors.green : (pct >= 50 ? Colors.orange : Colors.red);
    return _card(
      title: '儲蓄達成率',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _stat('本月目標', _money(_targetSavings))),
              Expanded(child: _stat('目前實際存下', _money(actualSaved))),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: ratio.clamp(0.0, 1.0),
              minHeight: 10,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            reached
                ? (_remaining > 0
                ? '已存滿目標，還多留了 ${_money(_remaining)}，太棒了！'
                : '剛好守住目標，達成 $pct%！')
                : (actualSaved <= 0
                ? '花太多，這個月不但沒存到、還倒貼，先把支出壓下來'
                : '達成 $pct%，超支已吃掉 ${_money(gap)} 的存款，快踩煞車'),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: reached ? Colors.green.shade800 : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  // ① 預算規劃（水位計 + 瀑布表）
  //   水位＝已花 / 可花上限；超過 100% 水會滿並變紅（用溢出表達超支，取代醜醜的 437%）。
  //   瀑布表把錢的流向由上往下扣清楚，呈現「預算規劃表」的感覺。
  Widget _buildOverviewCard() {
    final double ratio = _usableBudget > 0 ? (_spent / _usableBudget) : 0;
    final int percentUsed = _usableBudget > 0 ? (ratio * 100).round() : 0;
    final Color waterColor = percentUsed >= 100
        ? Colors.red.shade400
        : (percentUsed >= 80 ? Colors.orange : Colors.green);

    return _card(
      title: '預算規劃',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 水位計
          Center(
            child: _LiquidGauge(
              ratio: ratio,
              color: waterColor,
              centerText: '$percentUsed%',
              subText: _remaining >= 0 ? '可花已用' : '已超支',
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              _remaining >= 0
                  ? '剩餘可支配 ${_money(_remaining)}'
                  : '已超支 ${_money(_remaining.abs())}',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: _remaining >= 0 ? Colors.green.shade800 : Colors.red.shade700,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              '每月預算 ${_money(_budget)}　·　已花 ${_money(_spent)}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 12),
          // 瀑布表（由上往下扣）★修正：一律用「每月預算」為基準，跟水位計一致。
          _waterfallRow('每月預算', _budget, sign: 1),
          _waterfallRow('本月目標存款', _targetSavings, sign: -1),
          _waterfallDivider(),
          _waterfallRow('可花上限', _usableBudget, isSubtotal: true),
          _waterfallRow('本月已花', _spent, sign: -1),
          _waterfallDivider(),
          _waterfallRow('剩餘可支配', _remaining, isSubtotal: true, isFinal: true),
          // ★ 修正(數學不成立提醒)：目標存款把「可花上限」吃到 ≤0 時，先存後花根本沒得花，提醒調低目標存款。
          if (_usableBudget <= 0 && _targetSavings > 0) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '目標存款把可花上限吃光了（可花上限 ≤ 0），先存後花會變成沒錢可花，建議調低目標存款或提高收入/預算。',
                style: TextStyle(color: Colors.red.shade700, fontSize: 12, height: 1.4, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // 瀑布表一列：label 在左，金額在右（帶 +/− 與顏色）
  Widget _waterfallRow(String label, double amount, {int sign = 0, bool isSubtotal = false, bool isFinal = false}) {
    // sign: 1 顯示 +、-1 顯示 −、0 不顯示符號（小計用）
    final String prefix = sign > 0 ? '+ ' : (sign < 0 ? '− ' : '');
    final bool negativeValue = isFinal && amount < 0;
    final Color amountColor = negativeValue
        ? Colors.red.shade700
        : (sign < 0 ? Colors.black87 : (isSubtotal ? Colors.brown : Colors.green.shade800));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isSubtotal ? 15 : 14,
              fontWeight: isSubtotal ? FontWeight.w900 : FontWeight.w500,
              color: isSubtotal ? Colors.black87 : Colors.black54,
            ),
          ),
          Text(
            '$prefix${_money(amount.abs())}',
            style: TextStyle(
              fontSize: isSubtotal ? 16 : 14,
              fontWeight: isSubtotal ? FontWeight.w900 : FontWeight.w600,
              color: amountColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _waterfallDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Divider(height: 1, color: Colors.grey.shade300),
    );
  }

  // ② 流速預測
  Widget _buildPaceCard() {
    return _card(
      title: '流速預測',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _stat('照目前速度，月底約花', _money(_projected))),
              Expanded(
                child: _stat(
                  _projectedOver > 0 ? '預估會超支' : '預估仍在範圍',
                  _projectedOver > 0 ? _money(_projectedOver) : '安全',
                  valueColor: _projectedOver > 0 ? Colors.red.shade700 : Colors.green.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _stat('剩餘天數', '$_daysLeft 天')),
              Expanded(child: _stat('每天可花', _money(_perDay))),
            ],
          ),
        ],
      ),
    );
  }

  // ③ 各分類佔比 + 最兇分類
  Widget _buildCategoryShareCard() {
    final entries = _catTotals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    if (entries.isEmpty) {
      return _card(title: '分類佔比', child: Text('本月還沒有支出紀錄', style: TextStyle(color: Colors.grey.shade600)));
    }
    final double total = entries.fold<double>(0, (s, e) => s + e.value);
    return _card(
      title: '分類佔比（最兇：${entries.first.key}）',
      child: Column(
        children: [
          for (int i = 0; i < entries.length && i < 8; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${i == 0 ? '🔥 ' : ''}${entries[i].key}',
                        style: TextStyle(
                          fontWeight: i == 0 ? FontWeight.w900 : FontWeight.w600,
                          color: i == 0 ? Colors.red.shade700 : Colors.black87,
                        ),
                      ),
                      Text(
                        '${_money(entries[i].value)}（${total > 0 ? (entries[i].value / total * 100).round() : 0}%）',
                        style: const TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: total > 0 ? (entries[i].value / total).clamp(0.0, 1.0) : 0.0,
                      minHeight: 8,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        i == 0 ? Colors.red.shade400 : Colors.brown.shade300,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ④ 與上月比較（總額 + 哪類暴增）
  Widget _buildVsLastMonthCard() {
    final double diff = _spent - _lastMonthSpent;
    // 找出「本月比上月暴增最多」的分類
    String riseCat = '無';
    double riseAmt = 0;
    _catTotals.forEach((cat, thisAmt) {
      final last = _lastCatTotals[cat] ?? 0;
      final up = thisAmt - last;
      if (up > riseAmt) {
        riseAmt = up;
        riseCat = cat;
      }
    });
    final String diffText = diff > 0
        ? '比上月多花 ${_money(diff)}'
        : (diff < 0 ? '比上月少花 ${_money(diff.abs())}' : '和上月持平');
    return _card(
      title: '與上月比較',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _stat('上月支出', _money(_lastMonthSpent))),
              Expanded(child: _stat('本月支出', _money(_spent))),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            diffText,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 15,
              color: diff > 0 ? Colors.red.shade700 : (diff < 0 ? Colors.green.shade700 : Colors.black54),
            ),
          ),
          if (riseAmt > 0) ...[
            const SizedBox(height: 6),
            Text('暴增最多的分類：$riseCat（+${_money(riseAmt)}）', style: TextStyle(color: Colors.grey.shade700)),
          ],
        ],
      ),
    );
  }

  // ⑤ 分類預算達成率
  Widget _buildCategoryBudgetCard() {
    if (_categoryBudgets.isEmpty) {
      return _card(
        title: '分類預算達成率',
        child: Text('還沒有設定分類預算', style: TextStyle(color: Colors.grey.shade600)),
      );
    }
    final entries = _categoryBudgets.entries.toList();
    int kept = 0;
    for (final e in entries) {
      final spent = _catTotals[e.key] ?? 0;
      if (spent <= e.value) kept++;
    }
    return _card(
      title: '分類預算達成率（守住 $kept / ${entries.length} 項）',
      child: Column(
        children: [
          for (final e in entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Builder(
                builder: (context) {
                  final double spent = _catTotals[e.key] ?? 0;
                  final double limit = e.value;
                  final double ratio = limit > 0 ? (spent / limit) : 0;
                  final bool over = spent > limit;
                  final Color color = over
                      ? Colors.red.shade400
                      : (ratio >= 0.8 ? Colors.orange : Colors.green);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(e.key, style: const TextStyle(fontWeight: FontWeight.w600)),
                          Text(
                            '${_money(spent)} / ${_money(limit)}（${(ratio * 100).round()}%）',
                            style: TextStyle(
                              fontSize: 12,
                              color: over ? Colors.red.shade700 : Colors.black54,
                              fontWeight: over ? FontWeight.w700 : FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: ratio.clamp(0.0, 1.0),
                          minHeight: 8,
                          backgroundColor: Colors.grey.shade200,
                          valueColor: AlwaysStoppedAnimation<Color>(color),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

// ★ 任務2（水位計）：圓形液體進度，波浪會左右晃動；水位＝ratio(0~1，超過就滿)。
//   超支時外框/水色由呼叫端傳紅色進來，滿水+紅色即表達「爆表」，不必印 437% 這種醜數字。
class _LiquidGauge extends StatefulWidget {
  final double ratio; // 0~1 以上（>1 會被夾成滿水）
  final Color color;
  final String centerText;
  final String subText;
  final double size;
  const _LiquidGauge({
    required this.ratio,
    required this.color,
    required this.centerText,
    this.subText = '',
    this.size = 150,
  });

  @override
  State<_LiquidGauge> createState() => _LiquidGaugeState();
}

class _LiquidGaugeState extends State<_LiquidGauge> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // 波浪左右流動的動畫（2 秒一輪、無限重複）
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double fill = widget.ratio.isNaN ? 0 : widget.ratio.clamp(0.0, 1.0);
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 外圈底
          Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.grey.shade100,
              border: Border.all(color: widget.color.withOpacity(0.5), width: 3),
            ),
          ),
          // 波浪水位
          ClipOval(
            child: SizedBox(
              width: widget.size - 6,
              height: widget.size - 6,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  return CustomPaint(
                    painter: _WavePainter(
                      fill: fill,
                      phase: _controller.value,
                      color: widget.color,
                    ),
                  );
                },
              ),
            ),
          ),
          // 中央文字
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.centerText,
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  color: fill > 0.55 ? Colors.white : Colors.black87,
                ),
              ),
              if (widget.subText.isNotEmpty)
                Text(
                  widget.subText,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: fill > 0.55 ? Colors.white70 : Colors.black54,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  final double fill; // 0~1 水位比例
  final double phase; // 0~1 波浪相位
  final Color color;
  _WavePainter({required this.fill, required this.phase, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (fill <= 0) return;
    final double waterTop = size.height * (1 - fill);
    final double amplitude = 6; // 波浪高度
    final double waveLength = size.width;

    // 兩層波浪（前深後淺）製造層次
    _drawWave(canvas, size, waterTop, amplitude, waveLength, phase, color.withOpacity(0.85));
    _drawWave(canvas, size, waterTop, amplitude * 0.7, waveLength, phase + 0.5, color.withOpacity(0.45));
  }

  void _drawWave(Canvas canvas, Size size, double waterTop, double amp, double waveLength, double phase, Color c) {
    final path = Path();
    path.moveTo(0, size.height);
    path.lineTo(0, waterTop);
    for (double x = 0; x <= size.width; x++) {
      final double y = waterTop + amp * math.sin((x / waveLength * 2 * math.pi) + (phase * 2 * math.pi));
      path.lineTo(x, y);
    }
    path.lineTo(size.width, size.height);
    path.close();
    canvas.drawPath(path, Paint()..color = c);
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) =>
      old.fill != fill || old.phase != phase || old.color != color;
}