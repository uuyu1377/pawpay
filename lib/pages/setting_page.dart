import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';

import '../config/api_config.dart';
import '../services/avatar_service.dart';
import '../services/settings_export_service.dart';
import '../services/database_helper.dart'; // ★★★ 新增這行 ★★★
import '../services/currency_service.dart';
import '../services/notification_service.dart'; // ★ 合併自朋友版：旅遊/每日提醒通知服務
import '../services/category_budget_service.dart';
import '../services/game_api_service.dart';
import '../services/recurring_api_service.dart'; // ★ 任務2：算「上月收入/月固定收入」建議預算用
import '../models/transaction_model.dart';
import 'settings_category_manage_page.dart';
import 'settings_faq_page.dart';
import 'recurring_transactions_page.dart';
import 'category_memory_page.dart'; // ★ AI 自適應：AI 學到的分類規則面板
import 'fund_allocation_page.dart'; // ★ 資金分配頁

class SettingPage extends StatefulWidget {
  const SettingPage({super.key});

  @override
  State<SettingPage> createState() => SettingPageState();
}

// ★ 即時同步：state 改為 public，讓外層(main_app_shell) 能在切回設定頁時呼叫 reload()。
class SettingPageState extends State<SettingPage> {
  bool _isLoading = true;

  String _nickname = '尚未設定';
  String _identityCode = 'u23';
  String _currency = 'TWD / 新台幣';
  String _currencyDetail = '目前顯示：TWD / 新台幣'; // ★ 合併自朋友版
  CurrencyDisplaySettings _currencySettings = CurrencyDisplaySettings.twd(); // ★ 合併自朋友版
  CurrencyDisplaySettings _budgetCurrencySettings = CurrencyDisplaySettings.twd(); // ★ 合併自朋友版
  String _dailyReminderTime = '21:00';
  int _budgetThreshold = 90;
  int _monthlyBudgetAmount = 0;
  int _monthlyTargetSavings = 0; // ★ 任務2：本月目標存款（先存後花，跟固定支出分開）
  int _suggestedBudget = 0; // ★ 任務2：建議預算，0 代表沒資料不顯示
  String _suggestedBudgetSource = ''; // ★ 選項B+第1層：建議預算的來源標籤（歷史平均／收入／身分預設）
  int _suggestedTargetSavings = 0; // ★ 選項B+第1層：建議目標存款（依身分儲蓄率，不看做不到的歷史）
  String _suggestedTargetSavingsSource = ''; // ★ 選項B+第1層：目標存款建議的來源標籤
  double _monthlySpent = 0;
  Map<String, double> _categoryBudgets = {};

  bool _dailyReminder = true;
  bool _monthlyBudgetReminder = true;
  bool _useAiSuggestion = true;
  bool _appLock = false;
  bool _showBeginnerTips = true;

  AvatarProfile _avatar = const AvatarProfile(imagePath: null, iconKey: 'cat');

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  // ★ 即時同步：外層切回設定頁時呼叫，重新載入預算/目標存款/已花/建議，避免顯示舊資料要滑掉 App 才更新。
  void reload() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final avatar = await AvatarService.load();
    final identityCode = prefs.getString('user_identity') ?? 'u23';
    final budgetAmount = prefs.getInt('setting_monthly_budget_amount') ?? _defaultBudgetForIdentity(identityCode);
    // ★ 任務2：載入本月目標存款（沒設過就用身分別預設值）
    final targetSavings = prefs.getInt('setting_monthly_target_savings') ?? _defaultTargetSavingsForIdentity(identityCode);
    final monthlySpent = await _loadCurrentMonthExpenseSafely();
    // ★ 選項B+第1層：建議「預算」用三層 fallback（取到就停）——
    //   1) 歷史夠(≥2個月且≥10筆) → 近3個月平均花費；2) 有收入 → 收入×身分比例；3) 都沒有 → 身分預設值。
    double incomeBase = await _loadLastMonthIncomeSafely();
    if (incomeBase <= 0) {
      incomeBase = await _loadMonthlyRecurringIncomeSafely();
    }
    final history = await _loadHistoryExpenseStats();
    final double histAvg = (history['avg'] as double);
    final bool historyEnough = (history['monthsWithData'] as int) >= 2 && (history['txCount'] as int) >= 10;

    int suggestedBudget;
    String suggestedBudgetSource;
    if (historyEnough && histAvg > 0) {
      suggestedBudget = histAvg.round();
      suggestedBudgetSource = '你近 3 個月平均花費';
    } else if (incomeBase > 0) {
      final ratio = _budgetRatioForIdentity(identityCode);
      suggestedBudget = (incomeBase * ratio).round();
      suggestedBudgetSource = '收入的 ${(ratio * 100).round()}%';
    } else {
      suggestedBudget = _defaultBudgetForIdentity(identityCode);
      suggestedBudgetSource = '身分預設，記帳一陣子後會更準';
    }

    // ★ 選項B+第1層：建議「目標存款」＝收入×身分儲蓄率（目標是志向，不看做不到的歷史，避免越設越低）；
    //   沒有收入資料才退回身分預設值。歷史只在「詳細分析頁」拿來顯示達成率，不拿來下修目標。
    int suggestedTargetSavings;
    String suggestedTargetSavingsSource;
    if (incomeBase > 0) {
      final sr = _savingsRateForIdentity(identityCode);
      suggestedTargetSavings = (incomeBase * sr).round();
      suggestedTargetSavingsSource = '收入的 ${(sr * 100).round()}%';
    } else {
      suggestedTargetSavings = _defaultTargetSavingsForIdentity(identityCode);
      suggestedTargetSavingsSource = '身分預設';
    }
    final categoryBudgets = await CategoryBudgetService.loadAll();
    // ★ 合併自朋友版：載入旅遊/預設幣別顯示設定
    final currencySettings = await CurrencyService.instance.loadDisplaySettings();
    final budgetCurrencySettings = await CurrencyService.instance.loadDefaultDisplaySettings();
    final currencySummary = await CurrencyService.instance.travelSummaryText();

    if (!mounted) return;
    setState(() {
      _nickname = prefs.getString('user_nickname') ?? '尚未設定';
      _identityCode = identityCode;
      // ★ 合併自朋友版：以旅遊/預設幣別顯示設定更新幣別狀態
      _currencySettings = currencySettings;
      _budgetCurrencySettings = budgetCurrencySettings;
      _currency = currencySettings.label;
      _currencyDetail = '${currencySettings.isTravelMode ? '旅行期間顯示' : '目前顯示'}：${currencySettings.label}（匯率 ${currencySettings.rateFromTwd.toStringAsFixed(4)}）\n$currencySummary';
      _dailyReminderTime = prefs.getString('setting_daily_reminder_time') ?? '21:00';
      _budgetThreshold = prefs.getInt('setting_budget_threshold') ?? 90;
      _monthlyBudgetAmount = budgetAmount;
      _monthlyTargetSavings = targetSavings; // ★ 任務2
      _suggestedBudget = suggestedBudget; // ★ 任務2：收入基準建議預算
      _suggestedBudgetSource = suggestedBudgetSource; // ★ 選項B+第1層
      _suggestedTargetSavings = suggestedTargetSavings; // ★ 選項B+第1層
      _suggestedTargetSavingsSource = suggestedTargetSavingsSource; // ★ 選項B+第1層
      _monthlySpent = monthlySpent;
      _categoryBudgets = categoryBudgets;
      _dailyReminder = prefs.getBool('setting_daily_reminder') ?? true;
      _monthlyBudgetReminder = prefs.getBool('setting_monthly_budget_reminder') ?? true;
      _useAiSuggestion = prefs.getBool('setting_ai_suggestion') ?? true;
      _appLock = prefs.getBool('setting_app_lock') ?? false;
      _showBeginnerTips = prefs.getBool('setting_beginner_tips') ?? true;
      _avatar = avatar;
      _isLoading = false;
    });
  }

  // ★ 選項B：依身分別給「建議預算比例」（收入的幾成當預算）。學生生活費為主留多、上班族留多去投資、家庭先顧固定支出。
  double _budgetRatioForIdentity(String code) {
    switch (code) {
      case 'a23_35':
        return 0.70; // 上班族：留多一點去投資
      case 'a35p':
        return 0.65; // 家庭：固定支出優先
      case 'u23':
      default:
        return 0.85; // 學生：生活費為主
    }
  }

  // ★ 選項B：依身分別給「儲蓄率」（目標存款佔收入幾成）。這是目標(志向)，不看做不到的歷史。
  double _savingsRateForIdentity(String code) {
    switch (code) {
      case 'a23_35':
        return 0.20; // 上班族：先存後花的紀律
      case 'a35p':
        return 0.12; // 家庭：兼顧家用
      case 'u23':
      default:
        return 0.08; // 學生：能存就好
    }
  }

  // ★ 第1層：近 3 個完整月（不含本月）的「平均每月支出」與資料量。
  //   回傳 avg / monthsWithData / txCount，供上層判斷歷史夠不夠格當建議基準（避免髒資料把平均拉歪）。
  Future<Map<String, dynamic>> _loadHistoryExpenseStats() async {
    try {
      final txs = await DatabaseHelper.instance.getAllTransactions();
      final now = DateTime.now();
      final Map<String, double> monthTotals = {};
      for (int i = 1; i <= 3; i++) {
        final m = DateTime(now.year, now.month - i, 1);
        monthTotals['${m.year}-${m.month}'] = 0;
      }
      int txCount = 0;
      for (final tx in txs) {
        if (tx.type != TransactionType.expense) continue;
        for (int i = 1; i <= 3; i++) {
          final m = DateTime(now.year, now.month - i, 1);
          if (tx.date.year == m.year && tx.date.month == m.month) {
            final key = '${m.year}-${m.month}';
            monthTotals[key] = (monthTotals[key] ?? 0) + tx.amount.abs();
            txCount++;
            break;
          }
        }
      }
      final withData = monthTotals.values.where((v) => v > 0).toList();
      final double avg = withData.isNotEmpty ? withData.reduce((a, b) => a + b) / withData.length : 0.0;
      return {'avg': avg, 'monthsWithData': withData.length, 'txCount': txCount};
    } catch (_) {
      return {'avg': 0.0, 'monthsWithData': 0, 'txCount': 0};
    }
  }

  int _defaultBudgetForIdentity(String code) {
    switch (code) {
      case 'a23_35':
        return 25000;
      case 'a35p':
        return 50000;
      case 'u23':
      default:
        return 8000;
    }
  }

  // ★ 任務2：依身分別給「本月目標存款」預設值（學生低、上班族先存後花較高、家庭中等）。
  //   只是預設值，使用者仍可自行覆寫。
  int _defaultTargetSavingsForIdentity(String code) {
    switch (code) {
      case 'a23_35': // 上班族：強調存款/投資紀律
        return 5000;
      case 'a35p': // 家庭：中等，家用為主
        return 8000;
      case 'u23': // 學生：預設低，別月底吃土
      default:
        return 1000;
    }
  }

  Future<double> _loadCurrentMonthExpenseSafely() async {
    try {
      final txs = await DatabaseHelper.instance.getAllTransactions();
      final now = DateTime.now();
      return txs
          .where((tx) =>
      tx.type == TransactionType.expense &&
          tx.date.year == now.year &&
          tx.date.month == now.month)
          .fold<double>(0, (sum, tx) => sum + tx.amount.abs());
    } catch (e) {
      debugPrint('讀取本月支出失敗：$e');
      return 0;
    }
  }

  // ★ 任務2(收入基準建議預算)：上月實際收入（income 型別、上一個月），沒有就回 0。
  Future<double> _loadLastMonthIncomeSafely() async {
    try {
      final txs = await DatabaseHelper.instance.getAllTransactions();
      final now = DateTime.now();
      final lastMonth = DateTime(now.year, now.month - 1, 1);
      return txs
          .where((tx) =>
      tx.type == TransactionType.income &&
          tx.date.year == lastMonth.year &&
          tx.date.month == lastMonth.month)
          .fold<double>(0, (sum, tx) => sum + tx.amount.abs());
    } catch (e) {
      debugPrint('讀取上月收入失敗：$e');
      return 0;
    }
  }

  // ★ 任務2：固定收支金額依週期換算成每月等值（cadence 只有 weekly/monthly/yearly）。
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

  // ★ 任務2：月固定收入（上月沒有收入紀錄時，用固定收支的收入當備援基準）。
  Future<double> _loadMonthlyRecurringIncomeSafely() async {
    try {
      final rules = await RecurringApiService.instance.fetchRules();
      double total = 0;
      for (final r in rules) {
        if (!r.isActive) continue;
        if (r.direction == 'income') {
          total += _toMonthlyAmount(r.amount, r.cadence);
        }
      }
      return total;
    } catch (e) {
      return 0;
    }
  }

  String _money(num value) {
    final text = value.round().toString();
    return text.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
          (match) => ',',
    );
  }

  String _moneyWithCurrency(num value) {
    return CurrencyService.format(value, currencyCode: CurrencyService.codeFromSetting(_currency));
  }

  String get _monthlyBudgetSubtitle {
    if (!_monthlyBudgetReminder) return '目前已關閉';
    if (_monthlyBudgetAmount <= 0) return '尚未設定預算，點此設定';
    final percent = (_monthlySpent / _monthlyBudgetAmount * 100).clamp(0, 999).round();
    // ★★★ 修改：門檻已固定，副標不再顯示可自選的門檻百分比 ★★★
    return '本月已用 ${_moneyWithCurrency(_monthlySpent)} / ${_moneyWithCurrency(_monthlyBudgetAmount)}，達 $percent%';
  }

  String get _categoryBudgetSubtitle {
    if (_categoryBudgets.isEmpty) return '尚未設定，點此為個別類別設定預算';
    return '已為 ${_categoryBudgets.length} 個類別設定預算，點此管理';
  }

  Future<void> _saveBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  Future<void> _uploadCsv() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
      withData: true,
    );

    if (result == null || result.files.isEmpty) return;
    if (!mounted) return;

    final picked = result.files.single;
    final fileName = picked.name;
    final isCsv = fileName.toLowerCase().endsWith('.csv');

    if (!isCsv) {
      _showResultDialog('檔案格式不正確', '請選擇 .csv 檔案');
      return;
    }

    _showLoadingDialog('AI 批次分析中，請稍候...');

    try {
      // ★★★ 修正：讀取 Token 並加入 Request Headers 中 ★★★
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');

      var request = http.MultipartRequest('POST', Uri.parse(ApiConfig.importCsv));

      if (token != null && token.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $token';
      }

      final userId = prefs.getString('user_id')?.trim();
      request.fields['user_id'] = (userId != null && userId.isNotEmpty) ? userId : '1';

      if (picked.path != null && picked.path!.isNotEmpty) {
        request.files.add(await http.MultipartFile.fromPath('file', picked.path!, filename: fileName));
      } else if (picked.bytes != null) {
        request.files.add(http.MultipartFile.fromBytes('file', picked.bytes!, filename: fileName));
      } else {
        if (!mounted) return;
        Navigator.of(context).pop();
        _showResultDialog('讀取檔案失敗', '系統沒有取得檔案路徑或檔案內容，請把 CSV 放到手機本機下載資料夾後再試一次。');
        return;
      }

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);
      var responseBody = utf8.decode(response.bodyBytes);

      if (!mounted) return;
      Navigator.of(context).pop();

      if (response.statusCode == 200) {
        var jsonResponse = jsonDecode(responseBody);
        // 方法 A：用 \n
        _showResultDialog(
          '✅ 匯入成功',
          '${jsonResponse['message'] ?? "匯入完成"}\n獲得資金：${jsonResponse['earned'] ?? 0} 元',
        );
      } else {
        _showResultDialog('❌ 伺服器錯誤 (${response.statusCode})', responseBody);
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      _showResultDialog('⚠️ 連線失敗', '$e請檢查 Python 後端是否啟動，以及手機是否連到同一個後端 IP。');
    }
  }

  Future<void> _exportData() async {
    var loadingOpen = true;
    _showLoadingDialog('正在整理交易資料...');
    try {
      final file = await SettingsExportService.exportTransactionsToCsv();
      if (!mounted) return;
      Navigator.of(context).pop();
      loadingOpen = false;

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/csv', name: file.uri.pathSegments.last)],
        subject: 'AI 記帳資料備份',
        text: '這是從 AI 記帳匯出的 CSV 備份檔。',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已開啟分享視窗，可選 LINE、Google Drive、Gmail 或其他 App')),
      );
    } catch (e) {
      if (!mounted) return;
      if (loadingOpen) Navigator.of(context).pop();
      _showResultDialog('❌ 匯出失敗', '$e\n\n如果你目前沒有啟動後端，交易資料可能無法從 MySQL API 讀取。');
    }
  }

  Future<void> _pickAvatarFromGallery() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 82,
        maxWidth: 800,
      );
      if (picked == null) return;
      await AvatarService.savePickedImage(picked);
      final avatar = await AvatarService.load();
      if (!mounted) return;
      setState(() => _avatar = avatar);
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('頭像已更新')),
      );
    } catch (e) {
      if (!mounted) return;
      _showResultDialog('無法更換頭像', '$e\n\n若是在 iOS 測試，請確認 Info.plist 有加入相簿權限說明。');
    }
  }

  Future<void> _saveAvatarIcon(String iconKey) async {
    await AvatarService.saveIcon(iconKey);
    final avatar = await AvatarService.load();
    if (!mounted) return;
    setState(() => _avatar = avatar);
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已套用內建頭像')),
    );
  }

  // ★★★ 新增：修改暱稱（跟頭像一樣讓使用者自己改）★★★
  Future<void> _showRenameDialog() async {
    final controller = TextEditingController(
      text: _nickname == '尚未設定' ? '' : _nickname,
    );

    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('修改暱稱'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 12,
          decoration: const InputDecoration(
            hintText: '輸入新的暱稱',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('儲存'),
          ),
        ],
      ),
    );

    if (newName == null) return; // 使用者按取消

    if (newName.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('暱稱不能是空白')),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_nickname', newName);

    // 一併同步到資料庫／後端（沿用登入時寫入使用者資料的同一個方法）
    try {
      final provider = prefs.getString('auth_provider') ?? 'local';
      await DatabaseHelper.instance.updateUserInfo(newName, provider);
    } catch (e) {
      debugPrint('暱稱同步失敗：$e');
    }

    if (!mounted) return;
    setState(() => _nickname = newName);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('暱稱已更新')),
    );
  }

  void _showAvatarSheet() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        final icons = <String, IconData>{
          'cat': Icons.pets_rounded,
          'dog': Icons.cruelty_free_rounded,
          'person': Icons.person_rounded,
          'star': Icons.star_rounded,
          'wallet': Icons.account_balance_wallet_rounded,
          'robot': Icons.smart_toy_rounded,
        };

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('更換頭像', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                const Text('可以使用相簿圖片，也可以先用內建頭像。', style: TextStyle(color: Colors.black54)),
                const SizedBox(height: 18),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(child: Icon(Icons.photo_library_rounded)),
                  title: const Text('從相簿選擇'),
                  subtitle: const Text('適合正式展示或使用者自訂'),
                  onTap: _pickAvatarFromGallery,
                ),
                const Divider(),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: icons.entries.map((entry) {
                    final selected = !_avatar.hasImage && _avatar.iconKey == entry.key;
                    return InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () => _saveAvatarIcon(entry.key),
                      child: Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          color: selected ? const Color(0xFFEDE7F6) : const Color(0xFFF5F5F5),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: selected ? const Color(0xFF6750A4) : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: Icon(entry.value, color: const Color(0xFF6750A4)),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showCurrencyPicker() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          children: [
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: Text('幣別設定', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const Icon(Icons.home_rounded),
              title: const Text('變更預設幣別'),
              subtitle: const Text('平常記帳畫面使用的幣別'),
              onTap: () => Navigator.of(context).pop('default'),
            ),
            ListTile(
              leading: const Icon(Icons.flight_takeoff_rounded),
              title: const Text('設定旅行期間幣別'),
              subtitle: const Text('例如去日本期間自動顯示日圓，回來後提醒切回預設'),
              onTap: () => Navigator.of(context).pop('travel'),
            ),
            ListTile(
              leading: const Icon(Icons.undo_rounded),
              title: const Text('取消旅行幣別'),
              subtitle: const Text('立即回到預設幣別'),
              onTap: () => Navigator.of(context).pop('disable_travel'),
            ),
          ],
        ),
      ),
    );

    if (action == 'default') {
      await _showDefaultCurrencySheet();
    } else if (action == 'travel') {
      await _showTravelCurrencySheet();
    } else if (action == 'disable_travel') {
      await CurrencyService.instance.disableTravelCurrency();
      await NotificationService.instance.cancelTravelReturnReminder();
      await _loadSettings();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已回到預設幣別')));
    }
  }

  Future<void> _showDefaultCurrencySheet() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          children: [
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: Text('選擇預設幣別', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ),
            ...CurrencyService.supportedCodes.map((code) {
              final label = CurrencyService.labelForCode(code);
              return ListTile(
                title: Text(label),
                trailing: code == _currencySettings.defaultCode ? const Icon(Icons.check_rounded) : null,
                onTap: () => Navigator.of(context).pop(code),
              );
            }),
          ],
        ),
      ),
    );

    if (selected == null) return;
    await CurrencyService.instance.setDefaultCurrency(selected);
    await NotificationService.instance.syncFromPreferences();
    await _loadSettings();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('預設幣別已改為 ${CurrencyService.labelForCode(selected)}')));
  }

  Future<void> _showTravelCurrencySheet() async {
    String selectedCode = 'JPY';
    DateTimeRange selectedRange = DateTimeRange(
      start: DateTime.now(),
      end: DateTime.now().add(const Duration(days: 5)),
    );

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.of(context).viewInsets.bottom + 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('旅行期間幣別', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedCode,
                  decoration: const InputDecoration(labelText: '旅行時顯示幣別'),
                  items: CurrencyService.supportedCodes
                      .where((code) => code != 'TWD')
                      .map((code) => DropdownMenuItem(
                    value: code,
                    child: Text(CurrencyService.labelForCode(code)),
                  ))
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setModalState(() => selectedCode = value);
                  },
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.date_range_rounded),
                  label: Text('${_dateKey(selectedRange.start)} ~ ${_dateKey(selectedRange.end)}'),
                  onPressed: () async {
                    final picked = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime.now().subtract(const Duration(days: 1)),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                      initialDateRange: selectedRange,
                    );
                    if (picked != null) {
                      setModalState(() => selectedRange = picked);
                    }
                  },
                ),
                const SizedBox(height: 8),
                const Text(
                  '系統會在這段日期內自動以旅行幣別顯示金額，日期結束後提醒你切回預設幣別。',
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('儲存旅行幣別'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (saved != true) return;
    await CurrencyService.instance.setTravelCurrency(
      code: selectedCode,
      startDate: selectedRange.start,
      endDate: selectedRange.end,
    );
    final defaultCode = await CurrencyService.instance.getDefaultCurrencyCode();
    await NotificationService.instance.scheduleTravelReturnReminder(
      endDate: selectedRange.end,
      defaultCurrencyLabel: CurrencyService.labelForCode(defaultCode),
    );
    await _loadSettings();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已設定 ${CurrencyService.labelForCode(selectedCode)}：${_dateKey(selectedRange.start)} ~ ${_dateKey(selectedRange.end)}')),
    );
  }

  String _dateKey(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Future<void> _pickReminderTime() async {
    final parts = _dailyReminderTime.split(':');
    final initial = TimeOfDay(
      hour: int.tryParse(parts.first) ?? 21,
      minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
    );
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return;
    final text = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('setting_daily_reminder_time', text);
    await NotificationService.instance.scheduleDailyReminder(
      hour: picked.hour,
      minute: picked.minute,
    );
    if (!mounted) return;
    setState(() => _dailyReminderTime = text);
  }

  Future<void> _showMonthlyBudgetEditor() async {
    final amountController = TextEditingController(
      text: _monthlyBudgetAmount > 0 ? _monthlyBudgetAmount.toString() : '',
    );
    // ★ 任務2：本月目標存款輸入框（先存後花）
    final targetController = TextEditingController(
      text: _monthlyTargetSavings > 0 ? _monthlyTargetSavings.toString() : '',
    );
    int selectedThreshold = _budgetThreshold;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  8,
                  20,
                  MediaQuery.of(context).viewInsets.bottom + 24,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('月底預算提醒', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    const Text(
                      '先設定每月可用預算，系統會在本月支出達到指定比例時提醒。',
                      style: TextStyle(color: Colors.black54, height: 1.4),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: amountController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: (_) => setSheetState(() {}), // ★ 任務2：改預算時也即時更新下方「可花上限」
                      decoration: InputDecoration(
                        labelText: '每月預算',
                        prefixText: '${CurrencyService.symbolForCode(CurrencyService.codeFromSetting(_currency))} ',
                        suffixText: CurrencyService.codeFromSetting(_currency),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    // ★ 任務2(收入基準建議預算)：有算出建議值才顯示建議+套用；
                    //   沒資料時改顯示灰字提示，避免整行消失讓人以為功能壞了。
                    if (_suggestedBudget > 0) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _suggestedBudget > _monthlyBudgetAmount && _monthlyBudgetAmount > 0
                                  ? '建議每月預算約 ${_moneyWithCurrency(_suggestedBudget)}（$_suggestedBudgetSource）。本月只能維持或調低，這個較高的建議下個月才套得上。'
                                  : '建議每月預算約 ${_moneyWithCurrency(_suggestedBudget)}（$_suggestedBudgetSource）',
                              style: const TextStyle(color: Colors.black54, fontSize: 12, height: 1.3),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              amountController.text = _suggestedBudget.toString();
                              setSheetState(() {}); // 更新下方可花上限
                            },
                            child: const Text('套用建議'),
                          ),
                        ],
                      ),
                    ] else ...[
                      const SizedBox(height: 8),
                      Text(
                        '記帳或設定「固定收支」的收入後，這裡會自動給你預算建議',
                        style: TextStyle(color: Colors.grey.shade500, fontSize: 12, height: 1.3),
                      ),
                    ],
                    const SizedBox(height: 16),
                    // ★ 任務2：本月目標存款（先存後花）。跟固定支出分開，是「想主動留下的錢」。
                    TextField(
                      controller: targetController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: (_) => setSheetState(() {}), // 讓下方「可花上限」即時更新
                      decoration: InputDecoration(
                        labelText: '本月目標存款（先存後花）',
                        helperText: '想主動留下的錢（存款／投資／預備金），會先從預算裡預留',
                        prefixText: '${CurrencyService.symbolForCode(CurrencyService.codeFromSetting(_currency))} ',
                        suffixText: CurrencyService.codeFromSetting(_currency),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    // ★ 選項B+第1層：目標存款建議（依身分儲蓄率，目標是志向、不看做不到的歷史）。
                    if (_suggestedTargetSavings > 0) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '建議目標存款約 ${_moneyWithCurrency(_suggestedTargetSavings)}（$_suggestedTargetSavingsSource）',
                              style: const TextStyle(color: Colors.black54, fontSize: 12, height: 1.3),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              targetController.text = _suggestedTargetSavings.toString();
                              setSheetState(() {});
                            },
                            child: const Text('套用建議'),
                          ),
                        ],
                      ),
                    ],
                    // ★ 任務2：原本這裡有「可花上限」即時預覽，已改放到「詳細分析頁」的預算規劃表。
                    //   設定頁只保留「設定值」，畫面較乾淨、不再像規劃結果。
                    const SizedBox(height: 16),
                    // ★★★ 移除：原本可自選 70/80/90/100% 的「提醒門檻」下拉選單，
                    //     會跟固定的三級預算提醒衝突，改為固定門檻 90%。★★★
                    const SizedBox(height: 14),
                    if (_monthlyBudgetAmount > 0)
                      Text(
                        '目前本月支出：${_moneyWithCurrency(_monthlySpent)}（約 ${(_monthlySpent / _monthlyBudgetAmount * 100).clamp(0, 999).round()}%）',
                        style: const TextStyle(color: Colors.black54),
                      ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => Navigator.of(context).pop(true),
                        icon: const Icon(Icons.save_rounded),
                        label: const Text('儲存預算提醒'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (saved != true) return;
    final amount = int.tryParse(amountController.text.trim().replaceAll(',', '')) ?? 0;
    if (amount <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請輸入大於 0 的每月預算')),
      );
      return;
    }

    // ★ 選項3：本月「不可調高」是原本的防呆規則(防止超支後偷偷調高)，我不動它。
    //   但改成：調高被擋時「不整個失敗」——保留原預算、照樣存其他設定，並給友善說明，
    //   而不是像以前那樣直接 return，害目標存款/門檻也一起沒存到。
    bool budgetRaiseBlocked = false;
    try {
      await GameApiService.instance.setMonthlyBudget(amount: amount.toDouble());
    } catch (e) {
      budgetRaiseBlocked = true;
    }

    final prefs = await SharedPreferences.getInstance();
    // ★ 任務2：存本月目標存款（沒填或負數當作 0）
    final targetSavings = int.tryParse(targetController.text.trim().replaceAll(',', '')) ?? 0;
    final safeTarget = targetSavings < 0 ? 0 : targetSavings;
    if (!budgetRaiseBlocked) {
      await prefs.setInt('setting_monthly_budget_amount', amount); // 只有後端接受(維持或調低)才更新預算
    }
    await prefs.setInt('setting_monthly_target_savings', safeTarget);
    await prefs.setInt('setting_budget_threshold', selectedThreshold);
    await prefs.setBool('setting_monthly_budget_reminder', true);
    final spent = await _loadCurrentMonthExpenseSafely();

    if (!mounted) return;
    // ★ 修正(數學不成立提醒)：目標存款 ≥ 每月預算 → 可花上限 ≤ 0，先存後花沒得花，存檔時提醒（不強制擋，使用者自己決定）。
    final bool savingsTooHigh = safeTarget >= amount && amount > 0;
    setState(() {
      if (!budgetRaiseBlocked) _monthlyBudgetAmount = amount; // 被擋就維持原預算
      _monthlyTargetSavings = safeTarget; // ★ 任務2
      _budgetThreshold = selectedThreshold;
      _monthlyBudgetReminder = true;
      _monthlySpent = spent;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          budgetRaiseBlocked
              ? '本月預算只能維持或調低（避免超支後才調高），已保留原本的 ${_moneyWithCurrency(_monthlyBudgetAmount)}；其他設定已儲存，想調高請下個月再套用建議。'
              : (savingsTooHigh
              ? '已儲存，但提醒你：目標存款 ≥ 每月預算，先存後花後幾乎沒得花，建議把目標存款調低一點。'
              : '月底預算提醒已更新'),
        ),
        duration: (budgetRaiseBlocked || savingsTooHigh) ? const Duration(seconds: 5) : const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _showCategoryBudgetEditor() async {
    final categories = DatabaseHelper.instance.getMainNamesForType('expense');
    final existing = Map<String, double>.from(_categoryBudgets);

    final enabledMap = <String, bool>{
      for (final name in categories) name: existing.containsKey(name),
    };
    final controllers = <String, TextEditingController>{
      for (final name in categories)
        name: TextEditingController(
          text: existing[name] != null ? existing[name]!.toStringAsFixed(0) : '',
        ),
    };

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  8,
                  20,
                  MediaQuery.of(context).viewInsets.bottom + 16,
                ),
                child: SizedBox(
                  height: MediaQuery.of(context).size.height * 0.75,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('類別預算', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      const Text(
                        '可以選擇要幫哪些類別單獨設定預算，不用像每月預算一樣設定提醒門檻。'
                            '大富翁城市那邊的建築會依照「花費速度」自動判斷是否顯示超支警告。',
                        style: TextStyle(color: Colors.black54, height: 1.4, fontSize: 12.5),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: ListView.separated(
                          itemCount: categories.length,
                          separatorBuilder: (_, __) => const Divider(height: 24),
                          itemBuilder: (context, index) {
                            final name = categories[index];
                            final isEnabled = enabledMap[name] ?? false;
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: Text(
                                    name,
                                    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
                                  ),
                                ),
                                if (isEnabled) ...[
                                  const SizedBox(width: 10),
                                  Expanded(
                                    flex: 4,
                                    child: TextField(
                                      controller: controllers[name],
                                      keyboardType: TextInputType.number,
                                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                      decoration: InputDecoration(
                                        isDense: true,
                                        prefixText: '${CurrencyService.symbolForCode(CurrencyService.codeFromSetting(_currency))} ',
                                        border: const OutlineInputBorder(),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(width: 6),
                                Switch(
                                  value: isEnabled,
                                  onChanged: (value) => setSheetState(() => enabledMap[name] = value),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () => Navigator.of(context).pop(true),
                          icon: const Icon(Icons.save_rounded),
                          label: const Text('儲存類別預算'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (saved != true) return;

    final result = <String, double>{};
    for (final name in categories) {
      if (enabledMap[name] != true) continue;
      final amount = double.tryParse(controllers[name]!.text.trim()) ?? 0;
      if (amount > 0) result[name] = amount;
    }

    await CategoryBudgetService.saveAll(result);
    if (!mounted) return;
    setState(() => _categoryBudgets = result);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('類別預算已更新')),
    );
  }

  Future<void> _toggleAppLock(bool value) async {
    final prefs = await SharedPreferences.getInstance();

    if (!value) {
      await prefs.setBool('setting_app_lock', false);
      if (!mounted) return;
      setState(() => _appLock = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('App 鎖已關閉')),
      );
      return;
    }

    final passcode = await _showPasscodeDialog();
    if (passcode == null) return;
    await prefs.setBool('setting_app_lock', true);
    await prefs.setString('setting_app_passcode', passcode);
    if (!mounted) return;
    setState(() => _appLock = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('App 鎖已開啟，密碼已儲存')),
    );
  }

  Future<String?> _showPasscodeDialog() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text('設定 App 鎖密碼'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            maxLength: 4,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: '4 位數密碼',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
            FilledButton(
              onPressed: () {
                final text = controller.text.trim();
                if (!RegExp(r'^\d{4}$').hasMatch(text)) return;
                Navigator.of(context).pop(text);
              },
              child: const Text('儲存'),
            ),
          ],
        );
      },
    );
  }

  void _showBeginnerGuideDialog() {
    _showResultDialog(
      '新手提示',
      '1. 第一次進入會先選生活模式、暱稱與月底預算。\n'
          '2. 掃描電子發票時會先用 MobileScanner，即時掃不到才進 YOLO 定位、ML Kit 解碼與 OCR 備援。\n'
          '3. 每日記帳提醒與月底預算提醒目前會在 App 內檢查並提示；若要推播通知，之後需要再接通知套件。\n'
          '4. 類別與標籤可以在設定頁管理，自訂分類會影響後續記帳選項。',
    );
  }

  void _showFeedbackDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text('問題回報 / 意見回饋'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('目前先做成 App 內回饋紀錄。之後若要串 Google 表單或 Email，可以再接外部服務。'),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                minLines: 3,
                maxLines: 5,
                decoration: const InputDecoration(
                  hintText: '請輸入遇到的問題或建議...',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
            FilledButton(
              onPressed: () async {
                final text = controller.text.trim();
                if (text.isEmpty) return;
                final prefs = await SharedPreferences.getInstance();
                final list = prefs.getStringList('setting_feedback_logs') ?? <String>[];
                list.add('${DateTime.now().toIso8601String()}\n$text');
                await prefs.setStringList('setting_feedback_logs', list);
                if (!mounted) return;
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已暫存在本機回饋紀錄')),
                );
              },
              child: const Text('送出'),
            ),
          ],
        );
      },
    );
  }

  void _showVersionDialog() {
    _showResultDialog(
      '版本資訊',
      'App 版本：1.0.0\n專題功能：AI 記帳、發票掃描、分類解鎖、大富翁養成。\n\n掃描流程：MobileScanner 即時讀 QR；3 秒後 YOLO 輔助提示並預載模型；若即時掃描逾時，才拍照進 YOLO 定位 QR、ML Kit 解碼裁切圖；若仍失敗，最後才進 OCR 備援。',
    );
  }

  // ★★★ 新增：徹底刪除資料的防呆與串接邏輯 ★★★
  Future<void> _confirmDeleteAllData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            '⚠️ 刪除所有資料',
            style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
          ),
          content: const Text(
            '你確定要刪除所有的記帳資料與大富翁遊戲紀錄嗎？\n\n此操作無法復原，你的所有資料將會被雲端與本地端徹底銷毀！',
            style: TextStyle(height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消', style: TextStyle(fontSize: 16, color: Colors.grey)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('確定刪除', style: TextStyle(fontSize: 16)),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;
    if (!mounted) return;

    _showLoadingDialog('資料徹底銷毀中，請稍候...');

    try {
      // 1. 呼叫後端 API 銷毀遠端資料
      // ★★★ 修正：取代原本的 MysqlApiService，直接在這裡帶上 Token 呼叫後端 ★★★
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');

      // 利用 ApiConfig.importCsv 推導出 baseUrl，確保 IP 和 Port 不會寫死
      final baseUri = Uri.parse(ApiConfig.importCsv);
      final deleteUri = baseUri.replace(path: '/api/privacy/delete-data');

      final response = await http.post(
        deleteUri,
        headers: {
          "Content-Type": "application/json",
          if (token != null && token.isNotEmpty) "Authorization": "Bearer $token",
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        throw Exception('伺服器拒絕請求或發生錯誤 (狀態碼: ${response.statusCode})');
      }

      // ★★★ 關鍵修復：不僅刪除雲端，也要把手機本地的 SQLite 清空！ ★★★
      try {
        await DatabaseHelper.instance.wipeAllLocalData();
      } catch (e) {
        debugPrint("清空本地資料庫時發生錯誤：$e");
      }

      // 2. 清空本地 SharedPreferences，確保使用者完全登出
      await prefs.clear();

      if (!mounted) return;
      Navigator.of(context).pop(); // 關閉 loading

      _showResultDialog(
        '✅ 資料已徹底刪除',
        '你在系統中的所有記帳紀錄與資金已全部銷毀，符合隱私權規範。\n\n請重新啟動 App 建立新的設定與角色。',
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // 關閉 loading
      _showResultDialog('❌ 刪除失敗', '$e\n\n請檢查網路連線狀態。');
    }
  }

  void _showLoadingDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Center(
          child: Card(
            elevation: 8,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(16)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(message, style: const TextStyle(fontSize: 16)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showResultDialog(String title, String content) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(child: Text(content, style: const TextStyle(height: 1.5))),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('確定', style: TextStyle(fontSize: 16)),
            ),
          ],
        );
      },
    );
  }

  String get _identityLabel {
    switch (_identityCode) {
      case 'a23_35':
        return '上班族';
      case 'a35p':
        return '家庭 / 資產';
      case 'u23':
      default:
        return '學生 / 新鮮人';
    }
  }

  IconData _avatarIconData(String key) {
    switch (key) {
      case 'dog':
        return Icons.cruelty_free_rounded;
      case 'person':
        return Icons.person_rounded;
      case 'star':
        return Icons.star_rounded;
      case 'wallet':
        return Icons.account_balance_wallet_rounded;
      case 'robot':
        return Icons.smart_toy_rounded;
      case 'cat':
      default:
        return Icons.pets_rounded;
    }
  }

  Widget _buildAvatar() {
    if (_avatar.hasImage) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Image.file(
          File(_avatar.imagePath!),
          width: 56,
          height: 56,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildAvatarIcon(),
        ),
      );
    }
    return _buildAvatarIcon();
  }

  Widget _buildAvatarIcon() {
    return Icon(
      _avatarIconData(_avatar.iconKey),
      color: Colors.white,
      size: 30,
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF2D3142),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionCard(List<Widget> children) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }

  Widget _buildTile({
    required IconData icon,
    required String title,
    String? subtitle,
    VoidCallback? onTap,
    Color iconBg = const Color(0xFFF3F6FB),
    Color iconColor = const Color(0xFF4E7CF0),
    Widget? trailing,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: iconBg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: iconColor),
      ),
      title: Text(
        title,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      subtitle: subtitle == null
          ? null
          : Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          subtitle,
          style: const TextStyle(fontSize: 12.5, color: Colors.black54),
        ),
      ),
      trailing: trailing ?? const Icon(Icons.chevron_right_rounded, color: Colors.black38),
      onTap: onTap,
    );
  }

  Widget _buildDivider() {
    return const Divider(height: 1, indent: 16, endIndent: 16);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 12, 20, 4),
                child: Text(
                  '設定',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF222222),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  '管理你的記帳偏好、提醒方式與資料入口。',
                  style: TextStyle(fontSize: 13.5, color: Colors.black54),
                ),
              ),
              Container(
                margin: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6EA8FE), Color(0xFF8E7CFF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF8E7CFF).withOpacity(0.18),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: _showAvatarSheet,
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.20),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: _buildAvatar(),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _nickname,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '目前模式：$_identityLabel',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.92),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // ★★★ 新增：把「頭像」與「改名」兩顆按鈕直式排列 ★★★
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton.icon(
                          onPressed: _showAvatarSheet,
                          icon: const Icon(Icons.edit_rounded, color: Colors.white),
                          label: const Text('頭像', style: TextStyle(color: Colors.white)),
                        ),
                        TextButton.icon(
                          onPressed: _showRenameDialog,
                          icon: const Icon(Icons.drive_file_rename_outline_rounded, color: Colors.white),
                          label: const Text('改名', style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              _buildSectionTitle('帳務與資料'),
              _buildSectionCard([
                _buildTile(
                  icon: Icons.upload_file_rounded,
                  title: '上傳載具csv檔',
                  subtitle: '匯入財政部明細，並由 AI 自動分析記帳',
                  onTap: _uploadCsv,
                  iconBg: const Color(0xFFEAF4FF),
                  iconColor: const Color(0xFF2979FF),
                ),
                _buildDivider(),
                _buildTile(
                  icon: Icons.category_rounded,
                  title: '類別與標籤管理',
                  subtitle: '查看收入、支出分類，也可以新增自訂分類',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsCategoryManagePage()),
                  ),
                  iconBg: const Color(0xFFFFF4E6),
                  iconColor: const Color(0xFFFF9800),
                ),
                _buildDivider(),
                _buildTile(
                  icon: Icons.repeat_rounded,
                  title: '固定收支',
                  subtitle: '設定房租、薪水、訂閱費等週期性記帳',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const RecurringTransactionsPage()),
                  ),
                  iconBg: const Color(0xFFF1ECFF),
                  iconColor: const Color(0xFF6D4CC7),
                ),
                _buildDivider(),
                _buildTile(
                  icon: Icons.pie_chart_rounded,
                  title: '資金分配',
                  subtitle: '收入扣掉想存/想花後，剩下的錢怎麼分（AI 依身分+歷史給建議）',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const FundAllocationPage()),
                  ),
                  iconBg: const Color(0xFFFFF0E6),
                  iconColor: const Color(0xFFFF7043),
                ),
                _buildDivider(),
                _buildTile(
                  icon: Icons.psychology_rounded,
                  title: 'AI 學到的分類規則',
                  subtitle: '看 AI 記住了哪些「店家/關鍵字 → 分類」，越用越準',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const CategoryMemoryPage()),
                  ),
                  iconBg: const Color(0xFFEDE7FF),
                  iconColor: const Color(0xFF7C4DFF),
                ),
                _buildDivider(),
                _buildTile(
                  icon: Icons.backup_rounded,
                  title: '備份 / 匯出資料',
                  subtitle: '將目前交易資料匯出成 CSV 檔',
                  onTap: _exportData,
                  iconBg: const Color(0xFFEAFBF3),
                  iconColor: const Color(0xFF2E7D32),
                ),
                _buildDivider(),
                _buildTile(
                  icon: Icons.currency_exchange_rounded,
                  title: '預設幣別',
                  subtitle: _currencyDetail, // ★ 合併自朋友版：顯示旅遊/匯率狀態
                  onTap: _showCurrencyPicker,
                  iconBg: const Color(0xFFFFEEF4),
                  iconColor: const Color(0xFFE91E63),
                ),
              ]),
              _buildSectionTitle('記帳偏好'),
              _buildSectionCard([
                _buildTile(
                  icon: Icons.notifications_active_rounded,
                  title: '每日記帳提醒',
                  subtitle: _dailyReminder ? '每天 $_dailyReminderTime 提醒你補登支出與收入' : '目前已關閉',
                  onTap: _dailyReminder ? _pickReminderTime : null,
                  iconBg: const Color(0xFFEFF6FF),
                  iconColor: const Color(0xFF3B82F6),
                  trailing: Switch(
                    value: _dailyReminder,
                    onChanged: (value) async {
                      setState(() => _dailyReminder = value);
                      await _saveBool('setting_daily_reminder', value);
                      if (value) {
                        // ★ 改用朋友版 NotificationService（退役 DailyNotificationService）
                        await _pickReminderTime();
                      } else {
                        await NotificationService.instance.cancelDailyReminder();
                      }
                    },
                  ),
                ),
                _buildDivider(),
                _buildTile(
                  icon: Icons.savings_rounded,
                  title: '月底預算提醒',
                  subtitle: _monthlyBudgetSubtitle,
                  onTap: _showMonthlyBudgetEditor,
                  iconBg: const Color(0xFFEAFBF3),
                  iconColor: const Color(0xFF16A34A),
                  trailing: Switch(
                    value: _monthlyBudgetReminder,
                    onChanged: (value) async {
                      setState(() => _monthlyBudgetReminder = value);
                      await _saveBool('setting_monthly_budget_reminder', value);
                      if (value) await _showMonthlyBudgetEditor();
                    },
                  ),
                ),
                _buildDivider(),
                _buildTile(
                  icon: Icons.apartment_rounded,
                  title: '類別預算',
                  subtitle: _categoryBudgetSubtitle,
                  onTap: _showCategoryBudgetEditor,
                  iconBg: const Color(0xFFEFF6FF),
                  iconColor: const Color(0xFF0EA5E9),
                ),
                _buildDivider(),
                _buildTile(
                  icon: Icons.auto_awesome_rounded,
                  title: 'AI 分類建議',
                  subtitle: _useAiSuggestion ? '掃描與語音記帳時會保留 AI 分類建議' : '關閉後以手動確認分類為主',
                  iconBg: const Color(0xFFF3E8FF),
                  iconColor: const Color(0xFF9333EA),
                  trailing: Switch(
                    value: _useAiSuggestion,
                    onChanged: (value) async {
                      setState(() => _useAiSuggestion = value);
                      await _saveBool('setting_ai_suggestion', value);
                    },
                  ),
                ),
              ]),
              _buildSectionTitle('安全與介面'),
              _buildSectionCard([
                _buildTile(
                  icon: Icons.lock_rounded,
                  title: 'App 鎖',
                  subtitle: _appLock ? '已啟用：啟動 App 與回到前景時會要求密碼' : '開啟後會要求設定 4 位數密碼',
                  iconBg: const Color(0xFFFFF0F0),
                  iconColor: const Color(0xFFDC2626),
                  trailing: Switch(
                    value: _appLock,
                    onChanged: _toggleAppLock,
                  ),
                ),
                _buildDivider(),
                _buildTile(
                  icon: Icons.lightbulb_rounded,
                  title: '顯示新手提示',
                  subtitle: _showBeginnerTips ? '會顯示操作導覽與提示；點此查看內容' : '已關閉提示',
                  onTap: _showBeginnerGuideDialog,
                  iconBg: const Color(0xFFFFF9E8),
                  iconColor: const Color(0xFFF59E0B),
                  trailing: Switch(
                    value: _showBeginnerTips,
                    onChanged: (value) async {
                      setState(() => _showBeginnerTips = value);
                      await _saveBool('setting_beginner_tips', value);
                    },
                  ),
                ),
              ]),
              _buildSectionTitle('支援與關於'),
              _buildSectionCard([
                _buildTile(
                  icon: Icons.help_center_rounded,
                  title: '常見問題',
                  subtitle: '說明資料來源、掃描方式與同步邏輯',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsFaqPage()),
                  ),
                  iconBg: const Color(0xFFEFF6FF),
                  iconColor: const Color(0xFF2563EB),
                ),
                _buildDivider(),
                _buildTile(
                  icon: Icons.feedback_rounded,
                  title: '問題回報 / 意見回饋',
                  subtitle: '先暫存在本機，之後可再接 Email 或表單',
                  onTap: _showFeedbackDialog,
                  iconBg: const Color(0xFFEEF2FF),
                  iconColor: const Color(0xFF4F46E5),
                ),
                _buildDivider(),
                _buildTile(
                  icon: Icons.info_rounded,
                  title: '版本資訊',
                  subtitle: '目前版本 1.0.0',
                  onTap: _showVersionDialog,
                  iconBg: const Color(0xFFF4F4F5),
                  iconColor: const Color(0xFF52525B),
                ),
              ]),

              // ★★★ 新增：危險區域 (刪除所有資料) ★★★
              _buildSectionTitle('危險區域'),
              _buildSectionCard([
                _buildTile(
                  icon: Icons.delete_forever_rounded,
                  title: '刪除我的所有資料',
                  subtitle: '永久刪除記帳紀錄與大富翁進度，不可復原',
                  onTap: _confirmDeleteAllData,
                  iconBg: const Color(0xFFFFF0F0),
                  iconColor: const Color(0xFFDC2626),
                ),
              ]),
              // ★★★ ============================ ★★★

              const SizedBox(height: 24),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  '提醒：每日提醒與月底預算提醒已接到 App 內檢查；App 鎖已接到主程式入口，啟動 App 與從背景回到前景時會要求輸入密碼。若要手機系統推播，之後需再加入通知套件。',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.5,
                    color: Colors.black54,
                  ),
                ),
              ),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }
}