import '../models/transaction_model.dart';

class BudgetSuggestion {
  final double amount;
  final bool hasHistory;
  const BudgetSuggestion(this.amount, this.hasHistory);
}

class CategoryBudgetSuggestionService {
  static const Map<String, double> _defaults = {
    '飲食': 6000,
    '交通': 2000,
    '生活用品': 1500,
    '社交': 1500,
    '通訊網路': 600,
    '服飾美容': 1500,
    '醫療健康': 800,
    '住房': 10000,
    '娛樂': 1500,
    '其他支出': 1000,
    '學費與教材': 3000,
    '線上訂閱': 500,
    '小確幸': 1000,
    '禮物與送禮': 1000,
    '不見了': 500,
    '投資理財': 5000,
    '家具家電': 2000,
    '房貸與修繕': 15000,
    '小孩教育': 5000,
    '保險費用': 3000,
    '長輩支出': 2000,
    '家庭旅遊': 5000,
  };

  /// 批次計算所有分類（只查一次交易紀錄，避免重複 DB 呼叫）
  static Map<String, BudgetSuggestion> suggestAll(
    List<String> categories,
    List<Transaction> transactions,
  ) {
    return {for (final cat in categories) cat: suggest(cat, transactions)};
  }

  /// 計算單一分類的建議金額。
  /// 演算法：抓過去 3-6 個月月支出 → IQR 過濾異常月 → 加權平均（近期權重高）。
  static BudgetSuggestion suggest(
    String categoryName,
    List<Transaction> transactions,
  ) {
    final now = DateTime.now();
    // 截止：6 個月前的月初
    final cutoff = DateTime(now.year, now.month - 6, 1);

    final relevant = transactions.where((tx) {
      if (tx.type != TransactionType.expense) return false;
      if (tx.category != categoryName) return false;
      final d = tx.date;
      // 排除本月（本月尚未結束，加入會低估）
      if (d.year == now.year && d.month == now.month) return false;
      return !d.isBefore(cutoff);
    }).toList();

    if (relevant.isEmpty) {
      return BudgetSuggestion(_defaults[categoryName] ?? 1000, false);
    }

    // 按月份分組加總
    final monthlyTotals = <String, double>{};
    for (final tx in relevant) {
      final key =
          '${tx.date.year}-${tx.date.month.toString().padLeft(2, '0')}';
      monthlyTotals[key] = (monthlyTotals[key] ?? 0) + tx.amount.abs();
    }

    // 依月份排序（升序 → 最後是最近月份）
    final sortedKeys = monthlyTotals.keys.toList()..sort();
    final totals = sortedKeys.map((k) => monthlyTotals[k]!).toList();

    // IQR 異常值過濾（至少 3 個月才做）
    List<double> valid;
    if (totals.length >= 3) {
      final (lower, upper) = _iqrBounds(totals);
      valid = totals.where((v) => v >= lower && v <= upper).toList();
      if (valid.isEmpty) valid = totals; // 全被過濾時 fallback 全用
    } else {
      valid = totals;
    }

    // 加權平均：index 越大（越近期）權重越高
    final n = valid.length;
    double weightedSum = 0;
    double weightTotal = 0;
    for (int i = 0; i < n; i++) {
      final w = i + 1.0;
      weightedSum += valid[i] * w;
      weightTotal += w;
    }

    final result = weightTotal > 0 ? weightedSum / weightTotal : 0.0;
    return BudgetSuggestion(result, true);
  }

  // IQR 上下界（Tukey fences）
  static (double, double) _iqrBounds(List<double> values) {
    final sorted = [...values]..sort();
    final n = sorted.length;
    final q1 = _median(sorted.sublist(0, n ~/ 2));
    final q3 = _median(sorted.sublist((n + 1) ~/ 2));
    final iqr = q3 - q1;
    return (q1 - 1.5 * iqr, q3 + 1.5 * iqr);
  }

  static double _median(List<double> sorted) {
    if (sorted.isEmpty) return 0;
    final n = sorted.length;
    if (n.isOdd) return sorted[n ~/ 2];
    return (sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2;
  }
}
