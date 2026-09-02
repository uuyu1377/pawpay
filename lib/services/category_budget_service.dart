import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 使用者為個別消費類別設定的預算金額。
/// 只存「有啟用」的類別：某個類別若不在這個表裡，就代表使用者沒有幫它設定預算。
/// 跟「月底預算提醒」不一樣，這裡不需要提醒門檻，只提供金額給大富翁城市那邊算超支警告用。
class CategoryBudgetService {
  static const _prefKey = 'setting_category_budgets';

  /// HomePage 被 IndexedStack 保留在記憶體裡不會重新 initState，
  /// 靠這個計數器通知它「設定頁存檔了，該重讀一次」。
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static Future<Map<String, double>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((key, value) => MapEntry(key, (value as num).toDouble()));
    } catch (_) {
      return {};
    }
  }

  static Future<void> saveAll(Map<String, double> budgets) async {
    final prefs = await SharedPreferences.getInstance();
    final cleaned = <String, double>{}
      ..addEntries(budgets.entries.where((e) => e.value > 0));
    await prefs.setString(_prefKey, jsonEncode(cleaned));
    revision.value++;
  }
}
