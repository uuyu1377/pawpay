import 'package:flutter/material.dart';
import 'package:user_interface/models/transaction_model.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

// ★★★ 來自合併：需要引入 DatabaseHelper 才能讀取解鎖分類
import 'package:user_interface/services/database_helper.dart';
import 'package:user_interface/services/currency_service.dart';
import 'package:user_interface/services/category_budget_service.dart';
import 'package:user_interface/widgets/city_expense_carousel.dart';

// 引入語音頁面
import 'package:user_interface/pages/voice_page.dart';
// AI 時事公告
import 'package:user_interface/widgets/ai_news_banner.dart';
//每週生成分享圖
import 'package:user_interface/pages/weekly_share_page.dart';

import 'package:shared_preferences/shared_preferences.dart';
class HomePage extends StatefulWidget {
  final List<Transaction> transactions;
  // 給外部 (MainAppShell) 呼叫用，通知它要處理 AI 分析
  final Function(String)? onAiAnalyzeRequest;

  // ★★★ 新增：刪除與編輯的回呼函式 (預留給 MainAppShell 接上資料庫使用) ★★★
  final Function(String id)? onDeleteTransaction;
  final Function(Transaction tx)? onEditTransaction;
  final String defaultCurrencyCode;

  const HomePage({
    super.key,
    required this.transactions,
    this.onAiAnalyzeRequest, // 接收外部傳入的處理函式
    this.onDeleteTransaction, // ★★★ 新增 ★★★
    this.onEditTransaction,   // ★★★ 新增 ★★★
    this.defaultCurrencyCode = CurrencyService.defaultCode,
  });

  @override
  HomePageState createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  DateTime _selectedDate = DateTime.now();

  // AI 短評相關狀態 (保留你的邏輯)
  String? _aiComment;
  bool _showAiComment = false;
  Timer? _timer;

  // ★★★ 新增：當前「上戰場」寵物的 emoji，會跟著 current_pet_key 改變 ★★★
  // 預設 🐶 是為了對應「蛋階段（尚未選寵物）」時後端預設用狗狗語氣講話，讓臉跟語氣一致
  String _currentPetEmoji = '🐶';

  // ★★★ 來自合併：動態分類相關變數 ★★★
  late Future<List<Map<String, dynamic>>> _quickExpenseFuture;

  // 使用者在設定頁為各分類設定的預算（分類名稱 -> 預算金額），給記帳城市算超支警告用
  Map<String, double> _categoryBudgets = {};

  String _currencyCode = CurrencyService.defaultCode;
  CurrencyDisplaySettings _currencySettings = CurrencyDisplaySettings.twd(); // ★ 合併自朋友版(C)：月總額換算成預設幣別用

  // ★ 合併自朋友版(C)：重讀預設幣別顯示設定（供 main_app_shell 透過 _homeKey 呼叫刷新）
  Future<void> reloadCurrencySettings() async {
    try {
      final settings = await CurrencyService.instance.loadDefaultDisplaySettings();
      if (!mounted) return;
      setState(() => _currencySettings = settings);
    } catch (_) {}
  }

  Future<void> _loadIdentity() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currencyCode = CurrencyService.codeFromSetting(
        prefs.getString('setting_currency_code') ?? CurrencyService.codeFromSetting(prefs.getString('setting_currency')),
      );
      if (!mounted) return;
      setState(() {
        _currencyCode = currencyCode;
      });
    } catch (_) {
      // 讀取失敗就用預設
    }
  }

  // ★★★ 新增：寵物 key -> emoji 對照表 (與 pet_page 的 _allPetTypes 完全一致，16 隻) ★★★
  static const Map<String, String> _petEmojiMap = {
    'dog': '🐶',
    'cat': '🐱',
    'parrot': '🦜',
    'sloth': '🦥',
    'fox': '🦊',
    'cute_dog': '🐕',
    'pomeranian': '🐩',
    // ★★★ 修改：改成貓狗 emoji（原本是骨頭/腳印/愛心/火箭/沙漏等非動物圖示）★★★
    'norm_dog': '🦮',
    'wagging_dog': '🐕',
    'lovely_cat': '😻',
    'blue_cat': '😼',
    'rocket_cat': '😸',
    'loader_cat': '🐈',
    'bear': '🐻',
    'bee': '🐝',
    'giraffe': '🦒',
  };

  // ★★★ 新增：從 SharedPreferences 讀取當前上場寵物，換成對應 emoji ★★★
  // 查不到 (蛋階段 / 尚未選寵物) 就用預設狗狗 emoji，與後端預設語氣一致
  Future<void> _loadCurrentPetEmoji() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final petKey = prefs.getString('current_pet_key') ?? 'dog';
      final emoji = _petEmojiMap[petKey] ?? '🐶';
      if (!mounted) return;
      setState(() {
        _currentPetEmoji = emoji;
      });
    } catch (_) {
      // 讀取失敗就沿用目前的 emoji，不做任何事
    }
  }

  @override
  void initState() {
    super.initState();

    // ★★★ 來自合併：初始化讀取分類
    _quickExpenseFuture = _loadQuickExpense();
    _currencyCode = widget.defaultCurrencyCode;
    _loadIdentity();
    reloadCurrencySettings(); // ★ 合併自朋友版(C)：初次載入預設幣別顯示設定
    _loadCategoryBudgets();
    // HomePage 被 IndexedStack 保留在記憶體裡不會重新 initState，
    // 設定頁存檔類別預算時靠這個監聽器即時重讀，不用等交易筆數變動才更新。
    CategoryBudgetService.revision.addListener(_loadCategoryBudgets);
    _loadCurrentPetEmoji(); // ★★★ 一開 App 先讀當前上場寵物的 emoji ★★★

    // ★★★ 畫面建立完成後，再檢查是否要跳出本週分享圖提醒
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndShowWeeklyShareReminder();
    });
  }
  Future<void> _checkAndShowWeeklyShareReminder() async {
    final now = DateTime.now();

    // 每週一跳出，如果你現在只是測試，可以先註解掉這行
    //if (now.weekday != DateTime.monday) return;

    final hasExpenseThisWeek = widget.transactions.any((tx) {
      if (tx.type != TransactionType.expense) return false;

      final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
      final start = DateTime(
        startOfWeek.year,
        startOfWeek.month,
        startOfWeek.day,
      );

      return !tx.date.isBefore(start);
    });

    if (!hasExpenseThisWeek) return;

    final prefs = await SharedPreferences.getInstance();
    final weekKey = _getWeekKey(now);
    final lastShownWeek = prefs.getString('last_weekly_share_reminder_week');

    if (lastShownWeek == weekKey) return;

    await prefs.setString('last_weekly_share_reminder_week', weekKey);

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: Row(
            children: [
              const Expanded(
                child: Text(
                  '本週支出小週報完成囉',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                },
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          content: const Text(
            '要不要生成一張可愛支出分享圖？可以下載到相簿，也可以分享到社群網站。',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: const Text('先不要'),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(dialogContext).pop();

                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => WeeklySharePage(
                      transactions: widget.transactions,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.image_rounded),
              label: const Text('生成分享圖'),
            ),
          ],
        );
      },
    );
  }

  String _getWeekKey(DateTime date) {
    final startOfWeek = date.subtract(Duration(days: date.weekday - 1));

    final monday = DateTime(
      startOfWeek.year,
      startOfWeek.month,
      startOfWeek.day,
    );

    return '${monday.year}-${monday.month.toString().padLeft(2, '0')}-${monday.day.toString().padLeft(2, '0')}';
  }

  // ★★★ 來自合併：當交易更新時，重新讀取分類 (因為可能剛解鎖新分類)
  @override
  void didUpdateWidget(covariant HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.defaultCurrencyCode != widget.defaultCurrencyCode) {
      setState(() => _currencyCode = widget.defaultCurrencyCode);
    }

    if (oldWidget.transactions.length != widget.transactions.length) {
      setState(() {
        _quickExpenseFuture = _loadQuickExpense();
        _loadIdentity();
        _loadCategoryBudgets();
      });
    }
  }

  // ★★★ 來自合併：讀取資料庫分類
  Future<List<Map<String, dynamic>>> _loadQuickExpense() {
    return DatabaseHelper.instance.getQuickCategories(type: 'expense');
  }

  Future<void> _loadCategoryBudgets() async {
    final budgets = await CategoryBudgetService.loadAll();
    if (!mounted) return;
    setState(() => _categoryBudgets = budgets);
  }

  // 給外部 (MainAppShell) 呼叫：顯示 AI 短評
  void showAiComment(String comment) {
    triggerAiComment(comment);
  }

  // 給外部呼叫的方法，用來觸發 AI 短評動畫 (保留你的邏輯)
  void triggerAiComment(String comment) {
    _loadCurrentPetEmoji(); // ★★★ 新增：跳短評前先重讀，確保臉是「當前上場寵物」(中途換寵物也會即時更新) ★★★
    setState(() {
      _aiComment = comment;
      _showAiComment = true;
    });

    // 8秒後自動消失
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 8), () {
      if (mounted) {
        setState(() {
          _showAiComment = false;
        });
      }
    });
  }

  // 處理語音按鈕點擊 (保留你的邏輯)
  void _onVoiceButtonPressed() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const VoicePage()),
    );

    if (result != null && result is Map && result['type'] == 'voice_input') {
      String text = result['text'];
      print("🎤 收到語音文字: $text");

      if (widget.onAiAnalyzeRequest != null) {
        widget.onAiAnalyzeRequest!(text);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("收到語音：$text (等待連接 AI)")),
        );
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    CategoryBudgetService.revision.removeListener(_loadCategoryBudgets);
    super.dispose();
  }

  void _presentDatePicker() async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(now.year - 1),
      lastDate: now,
    );
    if (pickedDate != null && pickedDate != _selectedDate) {
      setState(() {
        _selectedDate = pickedDate;
      });
    }
  }

  Widget _buildDateHeader(String date) {
    return Padding(
      padding: const EdgeInsets.only(top: 16.0, bottom: 8.0, left: 16.0),
      child: Text(
        date,
        style: const TextStyle(
            fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final monthlyTxs = widget.transactions.where((tx) {
      return tx.date.year == _selectedDate.year &&
          tx.date.month == _selectedDate.month;
    }).toList();

    double totalMonthIncome = monthlyTxs
        .where((tx) => tx.type == TransactionType.income)
        .fold(0.0, (sum, item) => sum + item.amount);

    double totalMonthExpense = monthlyTxs
        .where((tx) => tx.type == TransactionType.expense)
        .fold(0.0, (sum, item) => sum + item.amount);

    final selectedDay =
    DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);

    final filteredTxs = widget.transactions.where((tx) {
      final txDay = DateTime(tx.date.year, tx.date.month, tx.date.day);
      return !txDay.isAfter(selectedDay);
    }).toList();

    filteredTxs.sort((a, b) => b.date.compareTo(a.date));

    List<Widget> groupedListWidgets = [];
    String? lastDateHeader;

    for (var tx in filteredTxs) {
      String txDateString = DateFormat('yyyy / MM / dd').format(tx.date);
      if (txDateString != lastDateHeader) {
        groupedListWidgets.add(_buildDateHeader(txDateString));
        lastDateHeader = txDateString;
      }

      // ★★★ 修改：將整個 tx 物件傳給 _buildTransactionItem ★★★
      groupedListWidgets.add(_buildTransactionItem(
        tx,
        '${tx.type == TransactionType.income ? '+' : '-'}${CurrencyService.formatAmount(tx.originalAmount, tx.currency)}', // ★ 合併自朋友版(C)：每筆顯示原始幣別
        tx.type == TransactionType.expense ? Colors.red : Colors.green,
      ));
    }

    final double topPadding = MediaQuery.of(context).padding.top;

    return Stack(
      children: [
        // 1. 原本的頁面內容
        SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.only(
                    top: topPadding + 16.0, left: 16, right: 16),
                child: _buildHeader(totalMonthIncome, totalMonthExpense),
              ),
              // AI 時事公告
              AiNewsBanner(
                transactions: widget.transactions,
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.image_rounded),
                    label: const Text('生成本週可愛支出分享圖'),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => WeeklySharePage(
                            transactions: widget.transactions,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // ★★★ 這裡呼叫改寫後的分類區塊 ★★★
              _buildAccountSection(),

              const SizedBox(height: 24),
              if (groupedListWidgets.isEmpty)
                const Center(
                  child: Text(
                    '目前沒有交易紀錄',
                    style: TextStyle(color: Colors.grey, fontSize: 18),
                  ),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: groupedListWidgets,
                ),
              // 底部留白給浮動按鈕
              const SizedBox(height: 100),
            ],
          ),
        ),

        // 2. 右下角浮動區塊 (保留你的邏輯)
        Positioned(
          right: 16,
          bottom: 16,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // (A) 對話框 (只在觸發時顯示)
              if (_showAiComment)
                Container(
                  margin: const EdgeInsets.only(right: 8, bottom: 10),
                  padding: const EdgeInsets.all(12),
                  constraints: const BoxConstraints(maxWidth: 220),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(4),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      )
                    ],
                  ),
                  child: Text(
                    _aiComment ?? "",
                    style: const TextStyle(fontSize: 14, color: Colors.black87),
                  ),
                ),

              // (B) 搜尋/動物按鈕
              FloatingActionButton(
                heroTag: "search_btn",
                onPressed: () {
                  if (_showAiComment) {
                    setState(() => _showAiComment = false);
                  } else {
                    showSearch(
                      context: context,
                      delegate: TransactionSearchDelegate(widget.transactions, defaultCurrencyCode: _currencyCode),
                    );
                  }
                },
                backgroundColor: _showAiComment ? const Color(0xFFFFF59D) : Colors.blueAccent,
                child: _showAiComment
                    ? Text(_currentPetEmoji, style: const TextStyle(fontSize: 32)) // ★★★ 修改：改成當前上場寵物的 emoji (原本寫死 🦜) ★★★
                    : const Icon(Icons.search, color: Colors.white),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(double totalMonthIncome, double totalMonthExpense) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: _presentDatePicker,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  DateFormat('yyyy / MM 月').format(_selectedDate),
                  style: const TextStyle(
                      fontSize: 16,
                      color: Colors.grey,
                      fontWeight: FontWeight.bold),
                ),
                const Icon(Icons.arrow_drop_down, color: Colors.grey),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildIncomeExpense('收入',
                  '+${_currencySettings.format(totalMonthIncome)}', Colors.green), // ★ 合併自朋友版(C)：月總額換算預設幣別
              _buildIncomeExpense('支出',
                  '-${_currencySettings.format(totalMonthExpense)}', Colors.red),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildIncomeExpense(String label, String amount, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 14, color: Colors.grey)),
        const SizedBox(height: 4),
        SizedBox(
          width: 120, // 防止金額過長造成 overflow
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              amount,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
              maxLines: 1,
            ),
          ),
        ),
      ],
    );
  }

  // ★★★ 記帳城市輪播：取代原本的地塊 ListView/PageView ★★★
  Widget _buildAccountSection() {
    final monthlyTxs = widget.transactions.where((tx) {
      return tx.date.year == _selectedDate.year && tx.date.month == _selectedDate.month;
    }).toList();

    // 只蓋「主類」：先抓出（通用 + 身分）主類名單
    final mainNames = DatabaseHelper.instance.getMainNamesForType('expense');
    final mainSet = mainNames.toSet();

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _quickExpenseFuture,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const SizedBox(height: 260, child: Center(child: CircularProgressIndicator()));
        }
        if (snap.hasError) {
          return SizedBox(
            height: 260,
            child: Center(
              child: Text(
                '分類載入失敗\n請嘗試重啟 App',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade500),
              ),
            ),
          );
        }

        final rowsAll = snap.data ?? const [];
        if (rowsAll.isEmpty) {
          return SizedBox(
            height: 260,
            child: Center(
              child: Text('尚無可顯示分類', style: TextStyle(color: Colors.grey.shade500)),
            ),
          );
        }

        // ★★★ 【第三站：首頁營造廠的 VIP 名單查詢處】 ★★★
        // 改良：直接利用資料庫的 is_custom 欄位，精準抓出「自創/AI生成」的分類
        final customMainSet = rowsAll
            .where((e) => (e['is_custom'] as int? ?? 0) == 1)
            .map((e) => (e['name'] ?? '').toString())
            .toSet();

        // 幫所有的交易紀錄找家
        final expenseTotals = <String, double>{};
        for (final tx in monthlyTxs) {
          if (tx.type != TransactionType.expense) continue;
          final main = _inferMainExpense(tx.category, mainSet, customMainSet);
          expenseTotals[main] = (expenseTotals[main] ?? 0) + tx.amount;
        }

        // 智慧過濾法：只蓋獨立的自創大樓和主類大樓（跟原本地塊清單一致）
        final rows = rowsAll.where((row) {
          final name = (row['name'] ?? '').toString();
          return _inferMainExpense(name, mainSet, customMainSet) == name;
        }).toList();

        final expenses = rows
            .map((row) {
          final name = (row['name'] ?? '').toString();
          final amount = expenseTotals[name] ?? 0.0;
          final budget = _categoryBudgets[name] ?? 0.0;
          return CategoryExpense(
            id: name,
            name: name,
            amount: amount,
            budget: budget,
            baseColor: _colorForCategory(name),
          );
        })
        // 只顯示本月有花費、或使用者有幫它設定預算的類別，避免城市裡塞滿空地
            .where((e) => e.amount > 0 || e.budget > 0)
            .toList()
          ..sort((a, b) => b.amount.compareTo(a.amount));

        return CityExpenseCarousel(expensesFuture: Future.value(expenses));
      },
    );
  }

  // ===== 主類歸戶：把子類/自訂分類歸到某個主類，用來計算「主類建築高度」=====
  // ★★★ 修改：接收 customMainSet 來精準判斷是否為「自創主類」
  String _inferMainExpense(String name, Set<String> mainSet, Set<String> customMainSet) {
    // 1. 本身是內建主類 (例如: 飲食、交通) -> 直接獨立
    if (mainSet.contains(name)) return name;

    // 2. ★ 終極精準判斷：資料庫認證的自創分類 (is_custom == 1) -> 破例讓它獨立！
    if (customMainSet.contains(name)) return name;

    // 3. 剩下的一定是內建子類 (例如: 早餐、公車、手續費)，用字典乖乖幫它們歸戶
    String candidate = '其他支出';

    // 飲食
    if (name.contains('早餐') || name.contains('午餐') || name.contains('晚餐') ||
        name.contains('飲料') || name.contains('咖啡') || name.contains('宵夜') ||
        name.contains('零食') || name.contains('外送') || name.contains('聚餐')) {
      candidate = '飲食';
    }
    // 交通
    else if (name.contains('公車') || name.contains('捷運') || name.contains('火車') ||
        name.contains('高鐵') || name.contains('計程車') || name.contains('Uber') ||
        name.contains('加油') || name.contains('停車') || name.contains('維修')) {
      candidate = '交通';
    }
    // 生活用品
    else if (name.contains('超市') || name.contains('採買') || name.contains('衛生紙') ||
        name.contains('日用品') || name.contains('五金') || name.contains('百貨') ||
        name.contains('洗衣') || name.contains('清潔')) {
      candidate = '生活用品';
    }
    // 娛樂 / 社交
    else if (name.contains('電影') || name.contains('KTV') || name.contains('展覽') ||
        name.contains('表演') || name.contains('書') || name.contains('雜誌') ||
        name.contains('遊戲') || name.contains('串流')) {
      candidate = '娛樂';
    } else if (name.contains('請客') || name.contains('社交應酬') || name.contains('派對') || name.contains('送禮') || name.contains('禮物')) {
      candidate = '社交';
    }
    // 通訊網路 / 訂閱
    else if (name.contains('手機費') || name.contains('網路費')) {
      candidate = '通訊網路';
    } else if (name.contains('Netflix') || name.contains('Spotify') || name.contains('YouTube') ||
        name.contains('iCloud') || name.contains('Google Drive') || name.contains('Disney')) {
      candidate = '線上訂閱';
    }
    // 服飾美容
    else if (name.contains('衣') || name.contains('鞋') || name.contains('配件') ||
        name.contains('化妝') || name.contains('保養') || name.contains('剪髮') ||
        name.contains('美容') || name.contains('美甲') || name.contains('按摩')) {
      candidate = '服飾美容';
    }
    // 醫療健康
    else if (name.contains('看診') || name.contains('掛號') || name.contains('藥') ||
        name.contains('保健') || name.contains('健身') || name.contains('運動')) {
      candidate = '醫療健康';
    }
    // 住房
    else if (name.contains('房租') || name.contains('水電') || name.contains('瓦斯') || name.contains('管理費')) {
      candidate = '住房';
    }
    // 其他支出 (★補上手續費等)
    else if (name.contains('雜費') || name.contains('手續費') || name.contains('捐款') || name == '其他') {
      candidate = '其他支出';
    }
    // 學生
    else if (name.contains('學雜') || name.contains('參考書') || name.contains('課本') ||
        name.contains('補習') || name.contains('影印') || name.contains('文具')) {
      candidate = '學費與教材';
    } else if (name.contains('扭蛋') || name.contains('盲盒') || name.contains('公仔') || name.contains('周邊') || name.contains('課金')) {
      candidate = '小確幸';
    } else if (name.contains('生日') || name.contains('節日') || name.contains('伴手禮')) {
      candidate = '禮物與送禮';
    } else if (name.contains('遺失') || name.contains('弄丟') || name.contains('不見')) {
      candidate = '不見了';
    }
    // 上班族
    else if (name.contains('股票') || name.contains('基金') || name.contains('定期定額') || name.contains('扣款')) {
      candidate = '投資理財';
    } else if (name.contains('家具') || name.contains('家電') || name.contains('廚房') || name.contains('佈置')) {
      candidate = '家具家電';
    }
    // 家庭
    else if (name.contains('房貸') || name.contains('貸款') || name.contains('修繕') || name.contains('裝潢') || name.contains('房屋稅') || name.contains('地價稅')) {
      candidate = '房貸與修繕';
    } else if (name.contains('尿布') || name.contains('奶粉') || name.contains('安親') || name.contains('才藝') || name.contains('童書') || name.contains('玩具')) {
      candidate = '小孩教育';
    } else if (name.contains('保險') || name.contains('壽險') || name.contains('車險') || name.contains('儲蓄險') || name.contains('醫療險')) {
      candidate = '保險費用';
    } else if (name.contains('孝親') || name.contains('看護') || name.contains('長輩')) {
      candidate = '長輩支出';
    } else if (name.contains('機票') || name.contains('住宿') || name.contains('旅行團') || name.contains('旅遊')) {
      candidate = '家庭旅遊';
    }

    // 若這個候選主類本來就存在（依身分決定的主類清單），直接用
    if (mainSet.contains(candidate)) return candidate;

    // 若身分沒有某些「專屬主類」，就往更通用的主類歸戶
    const fallback = <String, List<String>>{
      '線上訂閱': ['娛樂', '通訊網路', '其他支出'],
      '小確幸': ['娛樂', '其他支出'],
      '禮物與送禮': ['社交', '其他支出'],
      '不見了': ['其他支出'],
      '投資理財': ['其他支出'],
      '家具家電': ['住房', '生活用品', '其他支出'],
      '房貸與修繕': ['住房', '其他支出'],
      '小孩教育': ['其他支出'],
      '保險費用': ['其他支出'],
      '長輩支出': ['其他支出'],
      '家庭旅遊': ['娛樂', '交通', '其他支出'],
      '學費與教材': ['其他支出'],
    };

    for (final fb in (fallback[candidate] ?? const <String>['其他支出'])) {
      if (mainSet.contains(fb)) return fb;
    }

    // 最後保底：回到「其他支出」或第一個主類
    if (mainSet.contains('其他支出')) return '其他支出';
    return mainSet.isNotEmpty ? mainSet.first : candidate;
  }

// ===== 顏色規則：常見主類給固定色，其餘用 hash 產生固定色 =====
  Color _colorForCategory(String label) {
    const fixed = {
      // 飲食
      '飲食': Colors.orange,
      '早餐': Colors.orange,
      '午餐': Colors.orange,
      '晚餐': Colors.orange,
      '宵夜': Colors.orange,
      '零食': Colors.orange,
      '外送': Colors.orange,
      '聚餐': Colors.orange,
      '飲料/咖啡': Colors.deepOrange,

      // 交通
      '交通': Colors.blue,
      '公車': Colors.blue,
      '捷運': Colors.blue,
      '火車/高鐵': Colors.indigo,
      '計程車/Uber': Colors.indigo,
      '加油': Colors.blueGrey,
      '停車費': Colors.blueGrey,
      '車輛維修': Colors.blueGrey,

      // 生活/住房
      '住房': Colors.brown,
      '房貸與修繕': Colors.brown,
      '水電瓦斯': Colors.brown,
      '房租': Colors.brown,
      '家具家電': Colors.brown,
      '生活用品': Colors.green,
      '超市採買': Colors.green,
      '衛生紙/日用品': Colors.green,
      '洗衣/清潔': Colors.green,
      '五金百貨': Colors.green,

      // 社交/娛樂
      '社交': Colors.purple,
      '請客': Colors.purple,
      '禮物與送禮': Colors.purple,
      '娛樂': Colors.pink,
      '小確幸': Colors.pink,
      '線上訂閱': Colors.pink,

      // 健康/美容
      '醫療健康': Colors.red,
      '服飾美容': Colors.teal,
      '剪髮/美容': Colors.teal,

      // 學生/工作/家庭
      '學費與教材': Colors.cyan,
      '投資理財': Colors.lightBlue,
      '小孩教育': Colors.cyan,

      // 其他
      '其他支出': Colors.grey,
      '不見了': Colors.grey,
    };

    if (fixed.containsKey(label)) return fixed[label]!;
    return _hashColor(label);
  }

  Color _hashColor(String s) {
    final palette = <Color>[
      Colors.orange,
      Colors.blue,
      Colors.green,
      Colors.purple,
      Colors.teal,
      Colors.indigo,
      Colors.red,
      Colors.brown,
      Colors.cyan,
      Colors.pink,
      Colors.blueGrey,
    ];
    int h = 0;
    for (final c in s.codeUnits) {
      h = ((h * 31) + c) & 0x7fffffff;
    }
    return palette[h % palette.length];
  }

  // ★★★ 修改：將傳入的參數改為 Transaction 物件，並加上 Dismissible 滑動功能 ★★★
  Widget _buildTransactionItem(Transaction tx, String amountString, Color amountColor) {
    return Dismissible(
      // 必須給予唯一的 Key，Flutter 才能追蹤哪一個物件被滑動了
      key: ValueKey('tx_${tx.id}'),
      direction: DismissDirection.horizontal, // 允許左右滑動

      // ★ 右滑露出的背景 (編輯 - 綠色)
      background: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
        decoration: BoxDecoration(
          color: Colors.green,
          borderRadius: BorderRadius.circular(15),
        ),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        child: const Icon(Icons.edit, color: Colors.white, size: 28),
      ),

      // ★ 左滑露出的背景 (刪除 - 紅色)
      secondaryBackground: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(15),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete, color: Colors.white, size: 28),
      ),

      // ★ 滑動時的邏輯判斷
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.endToStart) {
          // 左滑：彈出刪除確認視窗
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (BuildContext context) {
              return AlertDialog(
                title: const Text("確認刪除"),
                content: const Text("確定要刪除這筆記帳紀錄嗎？\n(刪除後無法復原)"),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text("取消", style: TextStyle(color: Colors.grey)),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    child: const Text("刪除", style: TextStyle(color: Colors.white)),
                  ),
                ],
              );
            },
          );
          if (confirmed != true) return false;

          // ★★★ 修正：在這裡真正執行刪除並「等待」結果，而不是交給 onDismissed 事後才做。
          // 原本的寫法是使用者一按「刪除」，Dismissible 就立刻把這一列從畫面上移除，
          // 真正呼叫後端刪除的動作卻是不等待、不處理錯誤地丟在 onDismissed 裡。
          // 一旦後端刪除失敗（例如網路不通、伺服器錯誤），這一列已經從畫面消失，
          // 但 _transactions 從未真的被移除，導致記帳城市跟總支出金額卡在刪除前的數字。
          if (widget.onDeleteTransaction == null) return true;
          try {
            await widget.onDeleteTransaction!(tx.id);
            return true;
          } catch (e) {
            if (!mounted) return false;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('刪除失敗，請檢查網路連線後再試一次：$e')),
            );
            return false; // 刪除失敗：讓這一列滑回原位，畫面才會跟資料保持一致
          }
        } else if (direction == DismissDirection.startToEnd) {
          // 右滑：編輯
          if (widget.onEditTransaction != null) {
            widget.onEditTransaction!(tx);
          }
          // 回傳 false 代表不把這個元件從畫面上移除 (只是叫出編輯視窗，讓它滑回原位)
          return false;
        }
        return false;
      },

      // 這是原本的交易紀錄 UI (完全沒動排版)
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
        child: Container(
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Colors.grey[200]!)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            child: Row(
              children: [
                Container(
                  width: 60,
                  // ★★★ 修正：分類名稱太長(例如 派對活動)會跳行，
                  //     改用 FittedBox 在同一行內自動縮小，不改變版面寬度。★★★
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      tx.category,
                      maxLines: 1,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                Container(
                  width: 70,
                  // ★★★ 修正：金額太長(例如 -NT$1,000)會跳行，
                  //     改用 FittedBox 在同一行內自動縮小，不改變版面寬度。★★★
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      amountString,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: amountColor,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    padding:
                    const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      tx.note.isEmpty ? '-' : tx.note,
                      style: TextStyle(fontSize: 16, color: Colors.grey[800]),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// 搜尋 Delegate (保留你的邏輯)
class TransactionSearchDelegate extends SearchDelegate {
  final List<Transaction> transactions;
  final String defaultCurrencyCode;

  TransactionSearchDelegate(this.transactions, {this.defaultCurrencyCode = CurrencyService.defaultCode});

  @override
  String get searchFieldLabel => '搜尋備註、分類、金額...';

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      IconButton(
        icon: const Icon(Icons.clear),
        onPressed: () => query = '',
      ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => close(context, null),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return _buildResultList();
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return _buildResultList();
  }

  Widget _buildResultList() {
    if (query.isEmpty) {
      return const Center(child: Text('請輸入關鍵字', style: TextStyle(color: Colors.grey)));
    }

    final results = transactions.where((tx) {
      final note = tx.note.toLowerCase();
      final category = tx.category.toLowerCase();
      final amount = tx.amount.toStringAsFixed(0);
      final q = query.toLowerCase();

      return note.contains(q) || category.contains(q) || amount.contains(q);
    }).toList();

    results.sort((a, b) => b.date.compareTo(a.date));

    if (results.isEmpty) {
      return const Center(child: Text('找不到相關紀錄 🐢'));
    }

    return ListView.builder(
      itemCount: results.length,
      padding: const EdgeInsets.all(16),
      itemBuilder: (context, index) {
        final tx = results[index];
        final dateStr = DateFormat('yyyy/MM/dd').format(tx.date);

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.blue[50],
              child: Icon(tx.categoryIcon, color: Colors.blue),
            ),
            title: Text(tx.category, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text("$dateStr\n${tx.note}", maxLines: 2, overflow: TextOverflow.ellipsis),
            isThreeLine: true,
            trailing: Text(
              '${tx.type == TransactionType.income ? '+' : '-'}${CurrencyService.formatAmount(tx.originalAmount, tx.currency)}', // ★ 合併自朋友版(C)：每筆顯示原始幣別
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: tx.type == TransactionType.expense ? Colors.red : Colors.green,
              ),
            ),
          ),
        );
      },
    );
  }
}