import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:lottie/lottie.dart'; // Lottie 動畫套件

import 'package:user_interface/models/transaction_model.dart';
import 'package:user_interface/widgets/new_transaction_sheet.dart';
import 'package:user_interface/services/database_helper.dart';
import 'package:user_interface/services/game_api_service.dart'; // ★ 合併自朋友版(B 遊戲資金)
import 'package:user_interface/services/currency_service.dart';
import 'package:user_interface/services/notification_service.dart';

import 'pages/home_page.dart';
import 'pages/playground_page.dart';
import 'pages/setting_page.dart';
import 'pages/voice_page.dart';
import 'config/backend_config.dart';

import 'package:user_interface/services/local_ai_service.dart'; // 請確認路徑是否正確

enum ScanMode { auto, traditional }

class MainAppShell extends StatefulWidget {
  const MainAppShell({super.key});

  @override
  State<MainAppShell> createState() => _MainAppShellState();
}

class _MainAppShellState extends State<MainAppShell> {
  int _selectedIndex = 0;
  List<Transaction> _transactions = [];
  static const _kPrefKey = 'scan_mode';
  ScanMode _scanMode = ScanMode.auto;

  bool _isAnalyzing = false;

  // 首頁資料載入狀態
  bool _isAuthInitialized = false;
  // ★★★ 新增：記錄今天是否為第一筆記帳 ★★★
  bool _isFirstTransactionToday = false;

  String _userIdentity = "u23";
  String _userNickname = "使用者";
  String _currentPetKey = "dog"; // ★★★ 新增：當前上場的寵物 Key ★★★
  bool _useAiSuggestion = true;
  bool _dailyReminderEnabled = true;
  String _dailyReminderTime = "21:00";
  bool _monthlyBudgetReminderEnabled = true;
  int _monthlyBudgetAmount = 0;
  int _budgetThreshold = 90;
  String _currencyCode = 'TWD';
  CurrencyDisplaySettings _currencySettings = CurrencyDisplaySettings.twd(); // ★ 合併自朋友版(C)
  String? _pendingCurrencyCode; // ★ 合併自朋友版(C)：本次掃描/語音/記帳要用的幣別

  // ===== AI 暫存（用來把「掃描/語音原文、商家、發票、tags、AI摘要」寫進 V2 記帳表）=====
  String? _pendingEntryMethod; // scan | voice | manual(預留)
  String? _pendingRawInput; // QR/OCR/語音原文
  String? _pendingAiJson; // AI 回傳的 raw JSON（字串）
  String? _pendingMerchant;
  String? _pendingItemsSummary;
  String? _pendingInvoiceNumber;
  double? _pendingAiConfidence;
  String? _pendingSuggestedSubCategory;
  String? _pendingAiModel;
  DateTime? _pendingOccurredAt;
  List<String> _pendingTags = [];

  final GlobalKey<HomePageState> _homeKey = GlobalKey<HomePageState>();

  // 全部 16 隻寵物動畫清單（備用）
  static const List<String> _loadingAnimations = [
    'assets/animations/Dog.json',
    'assets/animations/Cat.json',
    'assets/animations/Fox.json',
    'assets/animations/Parrot.json',
    'assets/animations/Sloth.json',
    'assets/animations/Cute Doggy.json',
    'assets/animations/Pomeranian Dog.json',
    'assets/animations/Norm The Dog.json',
    'assets/animations/Wagging Dog.json',
    'assets/animations/Lovely cats.json',
    'assets/animations/Blue Working Cat.json',
    'assets/animations/Cat in a rocket.json',
    'assets/animations/Loader cat.json',
    'assets/animations/Bear Like.json',
    'assets/animations/Loading Flying Beee.json',
    'assets/animations/Petite girafe.json',
  ];

  // 發票圖片路徑
  final String _invoiceIconPath = 'assets/images/invoice_icon.png';

  // ★★★ 修正：完整分類表 (依照您的詳細清單更新，包含完整收入與支出) ★★★
  final Map<String, Map<String, dynamic>> _categoryData = {
    // ==========================================
    // 支出 - 1. 通用分類 (Target: All)
    // ==========================================
    "飲食": {
      "group": "all",
      "subs": ["早餐", "午餐", "晚餐", "飲料/咖啡", "宵夜", "零食", "外送", "聚餐"]
    },
    "交通": {
      "group": "all",
      "subs": ["公車", "捷運", "火車/高鐵", "計程車/Uber", "加油", "停車費", "車輛維修"]
    },
    "生活用品": {
      "group": "all",
      "subs": ["超市採買", "衛生紙/日用品", "五金百貨", "洗衣/清潔"]
    },
    "社交": {
      "group": "all",
      "subs": ["請客", "社交應酬", "派對活動"]
    },
    "娛樂": {
      "group": "all",
      "subs": ["電影", "KTV", "展覽/表演", "書籍/雜誌", "遊戲", "串流影音"]
    },
    "通訊網路": {
      "group": "all",
      "subs": ["手機費", "網路費"]
    },
    "服飾美容": {
      "group": "all",
      "subs": ["衣服/鞋子", "配件", "化妝品/保養品", "剪髮/美容", "美甲/按摩"]
    },
    "醫療健康": {
      "group": "all",
      "subs": ["看診掛號", "藥品", "保健食品", "運動/健身房"]
    },
    "住房": {
      "group": "all",
      "subs": ["房租", "水電費", "瓦斯費", "管理費"]
    },
    "其他支出": {
      "group": "all",
      "subs": ["雜費", "手續費", "捐款", "其他"]
    },

    // ==========================================
    // 支出 - 2. 學生專屬 (Target: Student)
    // ==========================================
    "學費與教材": {
      "group": "student",
      "subs": ["學雜費", "參考書/課本", "補習班", "影印費", "文具"]
    },
    "線上訂閱": {
      "group": "student",
      "subs": ["Netflix", "Spotify", "YouTube Premium", "iCloud/Google Drive", "Disney+"]
    },
    "小確幸": {
      "group": "student",
      "subs": ["扭蛋", "盲盒", "公仔", "遊戲課金", "周邊商品"]
    },
    "禮物與送禮": {
      "group": "student",
      "subs": ["生日禮物", "節日送禮", "伴手禮"]
    },
    "不見了": {
      "group": "student",
      "subs": ["現金遺失", "物品遺失重買", "錢包弄丟"]
    },

    // ==========================================
    // 支出 - 3. 上班族專屬 (Target: Worker)
    // ==========================================
    "投資理財": {
      "group": "worker",
      "subs": ["股票買入", "基金申購", "定期定額扣款"]
    },
    "家具家電": {
      "group": "worker",
      "subs": ["大型家具", "小家電", "廚房用具", "居家佈置"]
    },

    // ==========================================
    // 支出 - 4. 家庭專屬 (Target: Family)
    // ==========================================
    "房貸與修繕": {
      "group": "family",
      "subs": ["房屋貸款", "房屋修繕", "裝潢費用", "房屋稅/地價稅"]
    },
    "小孩教育": {
      "group": "family",
      "subs": ["學費", "安親班", "才藝課", "尿布奶粉", "玩具/童書"]
    },
    "保險費用": {
      "group": "family",
      "subs": ["壽險", "醫療險", "車險", "儲蓄險"]
    },
    "長輩支出": {
      "group": "family",
      "subs": ["孝親費", "長輩醫療", "長輩看護"]
    },
    "家庭旅遊": {
      "group": "family",
      "subs": ["機票住宿", "旅行團費", "全家出遊餐飲"]
    },

    // ==========================================
    // 收入 - 5. 通用分類 (Target: All)
    // ==========================================
    "薪水": {
      "group": "all",
      "subs": ["正職薪資", "年終獎金", "加班費"]
    },
    "投資收益": {
      "group": "all",
      "subs": ["股票股利", "基金配息", "價差獲利"]
    },
    "禮金": {
      "group": "all",
      "subs": ["紅包收入", "三節禮金"]
    },
    "其他收入": {
      "group": "all",
      "subs": ["二手拍賣", "發票中獎", "退款"]
    },

    // ==========================================
    // 收入 - 6. 學生專屬 (Target: Student)
    // ==========================================
    "零用錢": {
      "group": "student",
      "subs": ["父母給的", "長輩給的"]
    },
    "打工收入": {
      "group": "student",
      "subs": ["家教費", "工讀薪資", "校內工讀"]
    },
    "獎學金": {
      "group": "student",
      "subs": ["校內獎學金", "系上獎學金", "校外補助"]
    },

    // ==========================================
    // 收入 - 7. 上班族專屬 (Target: Worker)
    // ==========================================
    "投資獲利": {
      "group": "worker",
      "subs": ["短期操作獲利", "虛擬貨幣獲利"]
    },

    // ==========================================
    // 收入 - 8. 家庭專屬 (Target: Family)
    // ==========================================
    "被動收入": {
      "group": "family",
      "subs": ["房租收入", "銀行利息", "股息收入"]
    },
    "退稅/補助": {
      "group": "family",
      "subs": ["所得稅退稅", "育兒津貼", "租屋補助", "政府補助"]
    }
  };

  @override
  void initState() {
    super.initState();
    _loadScanMode();
    _loadUserProfile();
    // AI 公告需要 Token，背景取得，不阻塞首頁
    _getAuthToken();
    _loadData().then((_) {
      // 確保資料載入完畢後，再檢查是否要彈出總結
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkAndShowDailySummary();
        NotificationService.instance.syncFromPreferences(); // ★ 退役 DailyNotificationService，改用朋友版
        _checkDailyCheckInReward(); // ★ 合併自朋友版(B 遊戲資金)：每日簽到發扭蛋幣
        _refreshCurrencySettings(); // ★ 合併自朋友版(C)：載入預設幣別顯示設定
        _checkTravelCurrencyReturnReminder(); // ★ 合併自朋友版(C)：旅行結束提醒切回預設幣別
      });
    }).whenComplete(() {
      // ★★★ 修正：資料載入結束後（不論成功或失敗）把首頁 loading 關掉 ★★★
      // 之前沒有任何地方把 _isAuthInitialized 設成 true，導致首頁永遠轉圈。
      if (mounted) {
        setState(() {
          _isAuthInitialized = true;
        });
      }
    });
  }

  // ★★★ 新增：自動取得並儲存 JWT Token 的函式 ★★★
  Future<String?> _getAuthToken() async {
    final prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString('jwt_token');

    // 如果手機裡沒有 Token，就去跟後端拿一張新的
    if (token == null || token.isEmpty) {
      try {
        final url = Uri.parse('${BackendConfig.baseUrl}/api/login');
        // ★★★ 修改：從手機裡抓取我們在登入頁建立的真實 user_id ★★★
        String currentUserId = prefs.getString('user_id') ?? "unknown_user";

        final response = await http.post(
          url,
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({"user_id": currentUserId}),
        ).timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          final resJson = jsonDecode(response.body);
          token = resJson['token'];
          await prefs.setString('jwt_token', token!); // 存進手機裡
          debugPrint("✅ 成功獲取並儲存 JWT Token");
        } else {
          debugPrint("❌ 獲取 Token 失敗：狀態碼 ${response.statusCode}");
        }
      } catch (e) {
        debugPrint("❌ 獲取 Token 發生錯誤: $e");
      }
    }
    return token;
  }

  // ★★★ 新增：從本地記憶體撈出當日明細字串 ★★★
  String _getTransactionsTextForDate(DateTime date) {
    String dateString = "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
    List<String> items = [];

    for (var tx in _transactions) {
      String txDateStr = "${tx.date.year}-${tx.date.month.toString().padLeft(2, '0')}-${tx.date.day.toString().padLeft(2, '0')}";
      if (txDateStr == dateString && tx.type == TransactionType.expense) {
        String notePart = tx.note.isNotEmpty ? "(${tx.note})" : "";
        items.add("${tx.category} ${_formatMoney(tx.amount)} $notePart");
      }
    }

    if (items.isEmpty) return "無紀錄";
    return items.join("\n");
  }

  // ★★★ 修改：每日總結檢查核心邏輯 (永遠結算昨天) ★★★
  Future<void> _checkAndShowDailySummary() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();

    // 1. 新手保護期判斷
    final todayStr = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
    String? firstOpenDate = prefs.getString('first_open_date');
    if (firstOpenDate == null) {
      // 第一次打開 App，記錄今天，且不顯示任何總結
      await prefs.setString('first_open_date', todayStr);
      return;
    }

    // 2. 決定「結算日」是哪一天 (永遠結算完整的「昨天」)
    DateTime targetDate = now.subtract(const Duration(days: 1));
    String displayDayText = "昨天";

    final targetDateStr = "${targetDate.year}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.day.toString().padLeft(2, '0')}";

    // 新手保護期二次防呆：如果要結算的日子比註冊日還早，就不結算
    if (targetDateStr.compareTo(firstOpenDate) < 0) {
      return;
    }

    // 3. 檢查是否已經看過這個日期的總結了
    String? lastSummaryDate = prefs.getString('last_summary_date');
    if (lastSummaryDate == targetDateStr) {
      return; // 看過了，不打擾
    }

    // 4. 去資料庫撈這天的總花費與筆數
    final summary = await DatabaseHelper.instance.getSummaryForDate(targetDate);
    final count = summary['count'] as int;
    final total = summary['total'] as double;

    // 5. 準備彈窗的基本元素
    String dialogTitle = "$displayDayText理財任務結算";

    // 0 筆：直接顯示生氣狗，不呼叫 AI
    if (count == 0) {
      if (mounted) {
        showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) {
              return _buildSummaryDialog(
                ctx: ctx,
                title: dialogTitle,
                lottieAsset: 'assets/animations/Angry Dog.json',
                total: total,
                count: count,
                dialogText: "氣噗噗！$displayDayText都沒看到主人來記帳，寵物餓肚子等很久了...明天不准忘記！",
                isLoading: false,
              );
            }
        );
      }
      await prefs.setString('last_summary_date', targetDateStr);
      return;
    }

    // > 0 筆：呼叫 AI，使用外部變數管理狀態，避免 StatefulBuilder 無限重置
    String currentDialogText = "正在拿著計算機，幫你結算$displayDayText的每一筆帳單，稍等我一下喔...";
    bool isAiLoading = true;
    bool hasCalledApi = false; // ★★★ 新增：API 防護鎖，確保只發送一次 ★★★
    String lottieAsset = (count <= 2) ? 'assets/animations/Angry Dog.json' : 'assets/animations/Happy Dog.json';

    if (mounted) {
      showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) {
            return StatefulBuilder(
                builder: (context, setStateDialog) {
                  // ★★★ 修正：如果正在載入，且「還沒呼叫過 API」，才啟動 API 呼叫 ★★★
                  if (isAiLoading && !hasCalledApi) {
                    hasCalledApi = true; // 立刻上鎖，防止畫圖工人瘋狂重複呼叫
                    _fetchAiSummary(targetDate, total, displayDayText, _currentPetKey).then((aiResult) {
                      if (mounted) {
                        setStateDialog(() {
                          currentDialogText = aiResult;
                          isAiLoading = false;
                        });
                      }
                    });
                  }

                  return _buildSummaryDialog(
                    ctx: ctx,
                    title: dialogTitle,
                    lottieAsset: lottieAsset,
                    total: total,
                    count: count,
                    dialogText: currentDialogText,
                    isLoading: isAiLoading,
                  );
                }
            );
          }
      );
    }

    // 7. 記錄已經看過
    await prefs.setString('last_summary_date', targetDateStr);
  }

  // ★★★ 新增：呼叫後端 AI 進行總結的獨立函式 ★★★
  Future<String> _fetchAiSummary(DateTime date, double totalAmount, String dateText, String currentPet) async {
    try {
      final token = await _getAuthToken(); // ★ 1. 拿出 Token
      final transactionsText = _getTransactionsTextForDate(date);
      final url = Uri.parse('${BackendConfig.baseUrl}/summary');

      final response = await http.post(
        url,
        headers: {
          "Content-Type": "application/json",
          if (token != null) "Authorization": "Bearer $token", // ★ 2. 夾在 Header 送出
        },
        body: jsonEncode({
          "transactions_text": transactionsText,
          "total_amount": totalAmount,
          "user_input": "我是$_userNickname",
          "date_text": dateText,
          "current_pet": currentPet // ★★★ 新增：傳遞寵物參數 ★★★
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final resJson = jsonDecode(response.body);
        return resJson['comment'] ?? "太神啦！$dateText記了好多筆，幫你把總帳單算清楚囉！";
      } else {
        return "計算機好像壞掉了，總之$dateText辛苦啦！";
      }
    } catch (e) {
      print("AI Summary Error: $e");
      return "算數算到睡著了，總之$dateText辛苦啦！";
    }
  }

  // ★★★ 新增：獨立抽出 Dialog UI，方便 StatefulBuilder 更新 ★★★
  Widget _buildSummaryDialog({
    required BuildContext ctx,
    required String title,
    required String lottieAsset,
    required double total,
    required int count,
    required String dialogText,
    required bool isLoading,
  }) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.amber),
            ),
            const SizedBox(height: 16),

            // Lottie 動畫區
            SizedBox(
              height: 150,
              child: Lottie.asset(lottieAsset, fit: BoxFit.contain),
            ),
            const SizedBox(height: 16),

            // 總金額顯示
            Text(
              "總花費 ${_formatMoney(total)}",
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
            ),
            Text(
              "記帳筆數：$count 筆",
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 20),

            // 狗狗台詞區 (對話氣泡感)
            Container(
              padding: const EdgeInsets.all(12),
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: isLoading
                  ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2)
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      dialogText,
                      style: const TextStyle(fontSize: 14, height: 1.5),
                      textAlign: TextAlign.left,
                    ),
                  ),
                ],
              )
                  : Text(
                dialogText,
                style: const TextStyle(fontSize: 14, height: 1.5),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 20),

            // 確認按鈕 (載入中時反灰不能按)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isLoading ? Colors.grey : Colors.black,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: isLoading ? null : () {
                  Navigator.of(ctx).pop();
                },
                child: const Text("摸摸牠的頭，明天繼續努力"),
              ),
            )
          ],
        ),
      ),
    );
  }

  String _todayKey(DateTime date) {
    return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
  }

  String _monthKey(DateTime date) {
    return "${date.year}-${date.month.toString().padLeft(2, '0')}";
  }

  TimeOfDay _parseReminderTime(String text) {
    final parts = text.split(':');
    return TimeOfDay(
      hour: int.tryParse(parts.first) ?? 21,
      minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
    );
  }

  bool _isAfterTime(DateTime now, TimeOfDay time) {
    if (now.hour > time.hour) return true;
    if (now.hour == time.hour && now.minute >= time.minute) return true;
    return false;
  }

  String _money(num value) {
    final text = value.round().toString();
    return text.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
          (match) => ',',
    );
  }

  String _formatMoney(num value, {String? currencyCode, bool showSign = false, bool isIncome = false}) {
    return CurrencyService.format(
      value,
      currencyCode: (currencyCode == null || currencyCode.trim().isEmpty) ? _currencyCode : currencyCode,
      showSign: showSign,
      isIncome: isIncome,
    );
  }

  Future<void> _checkInAppDailyReminder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool('setting_daily_reminder') ?? _dailyReminderEnabled;
      if (!enabled) return;

      final now = DateTime.now();
      final reminderTime = _parseReminderTime(prefs.getString('setting_daily_reminder_time') ?? _dailyReminderTime);
      if (!_isAfterTime(now, reminderTime)) return;

      final today = _todayKey(now);
      if (prefs.getString('last_daily_reminder_date') == today) return;

      final hasRecord = await DatabaseHelper.instance.hasTransactionsOnDate(now);
      if (hasRecord) return;

      await prefs.setString('last_daily_reminder_date', today);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('今天還沒有記帳紀錄，要不要補登一下？'),
          duration: Duration(seconds: 4),
        ),
      );
    } catch (e) {
      debugPrint('每日提醒檢查失敗：$e');
    }
  }

  // ★★★★★ 以下為合併自朋友版(C 旅遊幣別)：刷新顯示設定 / 旅行結束提醒 / 掃描偵測幣別 ★★★★★
  Future<void> _refreshCurrencySettings() async {
    try {
      final settings = await CurrencyService.instance.loadDefaultDisplaySettings();
      if (!mounted) return;
      setState(() => _currencySettings = settings);
    } catch (e) {
      debugPrint('匯率設定讀取失敗：$e');
    }
  }

  Future<void> _checkTravelCurrencyReturnReminder() async {
    try {
      final expired = await CurrencyService.instance.isTravelCurrencyExpired();
      if (!expired || !mounted) return;

      final prefs = await SharedPreferences.getInstance();
      final today = _todayKey(DateTime.now());
      if (prefs.getString('last_travel_currency_return_prompt') == today) return;
      await prefs.setString('last_travel_currency_return_prompt', today);

      final defaultCode = await CurrencyService.instance.getDefaultCurrencyCode();
      final defaultLabel = CurrencyService.labelForCode(defaultCode);

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('旅行幣別期間已結束'),
          content: Text('要切回你的預設幣別「$defaultLabel」嗎？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('稍後'),
            ),
            ElevatedButton(
              onPressed: () async {
                await CurrencyService.instance.disableTravelCurrency();
                await NotificationService.instance.cancelTravelReturnReminder();
                await _refreshCurrencySettings();
                _homeKey.currentState?.reloadCurrencySettings();
                if (mounted) Navigator.of(ctx).pop();
              },
              child: const Text('切回預設'),
            ),
          ],
        ),
      );
    } catch (e) {
      debugPrint('旅行幣別提醒失敗：$e');
    }
  }

  String? _detectCurrencyFromText(String? text) {
    final raw = (text ?? '').toUpperCase();
    if (raw.contains('TWD') || raw.contains('NT\$') || raw.contains('新台幣')) return 'TWD';
    if (raw.contains('JPY') || raw.contains('日圓') || raw.contains('日元')) return 'JPY';
    if (raw.contains('KRW') || raw.contains('韓圓') || raw.contains('韓元')) return 'KRW';
    if (raw.contains('USD') || raw.contains('US\$') || raw.contains('美元')) return 'USD';
    if (raw.contains('CNY') || raw.contains('人民幣')) return 'CNY';
    return null;
  }

  String get _pendingCurrencySymbol =>
      CurrencyService.symbolForCode(_pendingCurrencyCode ?? 'TWD');

  // ★★★★★ 以下為合併自朋友版(B 遊戲資金)：每日簽到、發票號碼解析、記帳發獎勵 ★★★★★
  Future<void> _checkDailyCheckInReward() async {
    try {
      final result = await GameApiService.instance.dailyCheckIn();
      final earned = int.tryParse(result['earned_gacha_coins']?.toString() ?? '0') ?? 0;
      final streak = int.tryParse(result['login_streak']?.toString() ?? '0') ?? 0;
      if (earned <= 0 || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('連續登入第 $streak 天，獲得扭蛋幣 +$earned'),
          duration: const Duration(milliseconds: 1800),
        ),
      );
    } catch (e) {
      debugPrint('連續登入獎勵失敗：$e');
    }
  }

  String _normalizeInvoiceNumber(String? raw) {
    final text = (raw ?? '').toUpperCase();
    final compact = text.replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final match = RegExp(r'[A-Z]{2}\d{8}').firstMatch(compact);
    return match?.group(0) ?? '';
  }

  String _extractInvoiceNumberFromText(String? text) {
    final raw = (text ?? '').toUpperCase();
    if (raw.trim().isEmpty) return '';

    // 一般 OCR：AB12345678 / AB-12345678 / AB 12345678
    final spaced = RegExp(r'([A-Z])\s*([A-Z])[\s-]*(\d{8})')
        .firstMatch(raw);
    if (spaced != null) {
      return '${spaced.group(1)}${spaced.group(2)}${spaced.group(3)}';
    }

    // 電子發票 QR 原文通常也會直接包含 2 碼英文字母 + 8 碼數字。
    return _normalizeInvoiceNumber(raw);
  }

  // ★★★ 新增：發票號碼「強化版」辨識，解決 OCR 抓不到號碼導致沒有地產資金的問題 ★★★
  // 台灣發票號碼固定格式：2 碼英文字母 + 8 碼數字。
  // 這裡把 OCR 常見的英數誤判修正回來（例如 5 被讀成 S、B 被讀成 8）。
  // allowLetterFix=false 時只修「後 8 碼」，誤判風險低；
  // allowLetterFix=true 只用在位置已經確定的來源（QR 左碼、發票號碼關鍵字那一行）。
  String _fixInvoiceCandidate(String candidate, {bool allowLetterFix = false}) {
    if (candidate.length != 10) return '';
    const Map<String, String> toLetter = {
      '0': 'O', '1': 'I', '2': 'Z', '5': 'S', '6': 'G', '8': 'B',
    };
    const Map<String, String> toDigit = {
      'O': '0', 'D': '0', 'Q': '0', 'I': '1', 'L': '1', 'Z': '2',
      'S': '5', 'G': '6', 'B': '8', 'T': '7',
    };
    String head = candidate.substring(0, 2);
    if (allowLetterFix) {
      head = head.split('').map((c) => toLetter[c] ?? c).join();
    }
    final String tail =
    candidate.substring(2).split('').map((c) => toDigit[c] ?? c).join();
    if (!RegExp(r'^[A-Z]{2}$').hasMatch(head)) return '';
    if (!RegExp(r'^\d{8}$').hasMatch(tail)) return '';
    return '$head$tail';
  }

  // 在一行文字裡用滑動視窗找 10 碼候選（不把整份 OCR 壓成一整串，避免跨行接出假號碼）
  String _scanLineForInvoice(String line, {bool allowLetterFix = false}) {
    final compact = line.replaceAll(RegExp(r'[^A-Z0-9]'), '');
    for (int i = 0; i + 10 <= compact.length; i++) {
      final fixed = _fixInvoiceCandidate(compact.substring(i, i + 10),
          allowLetterFix: allowLetterFix);
      if (fixed.isNotEmpty) return fixed;
    }
    return '';
  }

  // 排除「日期」被誤認成發票號碼（例如 DATE 2023-10-09 → TE20231009）
  bool _looksLikeDate(String line) {
    return RegExp(r'(19|20)\d{2}\s*[-/年]\s*\d{1,2}\s*[-/月]\s*\d{1,2}').hasMatch(line) ||
        line.contains('DATE') ||
        line.contains('日期');
  }

  String _extractInvoiceNumberSmart(String? text) {
    final raw = (text ?? '').toUpperCase();
    if (raw.trim().isEmpty) return '';

    // 來源 1：電子發票 QR 左碼 —— 前 10 碼依規格就是發票號碼，最可靠。
    final qr = RegExp(r'\[EINV_LEFT_QR\]\s*(\S{10})').firstMatch(raw);
    if (qr != null) {
      final fixed = _fixInvoiceCandidate(qr.group(1)!, allowLetterFix: true);
      if (fixed.isNotEmpty) return fixed;
    }

    final lines = raw.split('\n');

    // 來源 2：帶有「發票號碼 / INVOICE」關鍵字的那幾行（位置明確，允許完整修正）。
    for (final line in lines) {
      if (line.contains('發票號碼') ||
          line.contains('發票號') ||
          line.contains('INVOICE')) {
        final fixed = _scanLineForInvoice(line, allowLetterFix: true);
        if (fixed.isNotEmpty) return fixed;
      }
    }

    // 來源 3：逐行嚴格比對（前 2 碼必須本來就是英文字母，避免把電話/統編誤認成發票）。
    //         同時跳過看起來是日期的行，避免 DATE 2023-10-09 被拼成 TE20231009。
    for (final line in lines) {
      if (_looksLikeDate(line)) continue;
      final fixed = _scanLineForInvoice(line);
      if (fixed.isNotEmpty) return fixed;
    }

    // 找不到就回空字串（寧可沒有，也不要抓到假號碼）。
    return '';
  }

  // ★★★ 新增：解析「這張發票自己的開立日期」，找不到就回空字串（備註就不顯示括號）★★★
  // 來源 1：電子發票 QR 左碼第 11~17 碼為開立日期（民國年 3 碼 + 月 2 碼 + 日 2 碼），最可靠。
  // 來源 2：AI 給的 date 欄位，需能解析成合理日期才採用。
  String _resolveInvoiceDateText(String? aiDate, String? rawScanText) {
    // 來源 1：QR 左碼
    final raw = (rawScanText ?? '').toUpperCase();
    final qr = RegExp(r'\[EINV_LEFT_QR\]\s*(\S+)').firstMatch(raw);
    if (qr != null) {
      final code = qr.group(1)!;
      if (code.length >= 17) {
        final rocDate = code.substring(10, 17);
        if (RegExp(r'^\d{7}$').hasMatch(rocDate)) {
          final year = int.parse(rocDate.substring(0, 3)) + 1911;
          final month = int.parse(rocDate.substring(3, 5));
          final day = int.parse(rocDate.substring(5, 7));
          if (month >= 1 && month <= 12 && day >= 1 && day <= 31) {
            return '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
          }
        }
      }
    }

    // 來源 2：AI 的 date 欄位
    final text = (aiDate ?? '').trim();
    if (text.isEmpty) return '';
    DateTime? parsed;
    try {
      parsed = DateTime.parse(text);
    } catch (_) {
      final m = RegExp(r'^(\d{4})[\/-](\d{1,2})[\/-](\d{1,2})').firstMatch(text);
      if (m != null) {
        final y = int.tryParse(m.group(1)!);
        final mo = int.tryParse(m.group(2)!);
        final d = int.tryParse(m.group(3)!);
        if (y != null && mo != null && d != null) {
          parsed = DateTime(y, mo, d);
        }
      }
    }
    if (parsed == null) return '';
    // 年份明顯不合理（例如 1970、2099）就不顯示，避免把亂數日期印在備註上。
    final nowYear = DateTime.now().year;
    if (parsed.year < 2000 || parsed.year > nowYear + 1) return '';
    return _todayKey(parsed);
  }

  String _resolveInvoiceNumber(String? aiValue, String? rawScanText) {
    // ★★★ 修改：先用強化版從掃描原文（QR 左碼 / OCR 逐行）辨識，
    //     因為它比 AI 猜的更可靠；找不到才退回 AI 給的欄位。★★★
    final fromScan = _extractInvoiceNumberSmart(rawScanText);
    if (fromScan.isNotEmpty) return fromScan;
    return _normalizeInvoiceNumber(aiValue);
  }

  Future<String> _grantGamificationRewards({
    required String entryMethod,
    required double amount,
    required bool isIncome,
    String? invoiceNumber,
  }) async {
    final messages = <String>[];
    if (isIncome) return '';

    final normalizedInvoice = _normalizeInvoiceNumber(invoiceNumber);
    final isVerifiedInvoice = entryMethod == 'scan' && normalizedInvoice.isNotEmpty;
    bool duplicateInvoiceReward = false;

    // 1) 依記帳來源發放資源。
    try {
      if (isVerifiedInvoice) {
        final requested = amount.round();
        if (requested > 0) {
          final result = await GameApiService.instance.addLandFundFromInvoice(
            amount: requested,
            invoiceNumber: normalizedInvoice,
          );
          final actuallyEarned = int.tryParse(result['earned']?.toString() ?? '0') ?? 0;
          final duplicate = result['duplicate'] == true;
          duplicateInvoiceReward = duplicate;
          if (actuallyEarned > 0) {
            messages.add('地產資金 +$actuallyEarned');
          } else if (duplicate) {
            messages.add('此發票已領過地產資金');
          }
        }
      } else if (entryMethod == 'scan') {
        // ★★★ 修正：掃描到發票、但沒讀出發票號碼時（例如 QR 沒掃到、改走 OCR）的備援。
        //     沒有發票號碼就無法辨識同一張發票、擋不掉重複領取，所以不發地產資金；
        //     改發寵物代幣，避免「明明有記帳卻完全沒有任何獎勵」。★★★
        await GameApiService.instance.addPetTokens(amount: 1, source: 'scan_accounting');
        messages.add('寵物代幣 +1');
      } else if (entryMethod == 'manual') {
        await GameApiService.instance.addPetTokens(amount: 1, source: 'manual_accounting');
        messages.add('寵物代幣 +1');
      } else if (entryMethod == 'voice') {
        await GameApiService.instance.addPetTokens(amount: 1, source: 'voice_accounting');
        messages.add('寵物代幣 +1');
      }
    } catch (e) {
      debugPrint('遊戲化獎勵失敗：$e');
    }

    // 2) 每一筆支出都記入任務進度；任務獎勵改由任務中心完成後領取，
    //    不再用手機本機日期偷偷自動發幣，避免重裝 App 重複領取。
    try {
      if (!duplicateInvoiceReward) {
        await GameApiService.instance.recordMissionEvent(
          source: entryMethod,
          isInvoice: isVerifiedInvoice,
        );

        // ★★★ 新增：記完進度後查一次任務，若有「已達成但還沒領」的任務就提醒使用者 ★★★
        try {
          final missions = await GameApiService.instance.fetchMissions();
          final claimable = missions.where((m) =>
          m['completed'] == true && m['claimed'] != true).length;
          if (claimable > 0) {
            messages.add('任務達成 $claimable 項，可到任務中心領扭蛋幣');
          }
        } catch (e) {
          debugPrint('任務達成檢查失敗：$e');
        }
      }
    } catch (e) {
      debugPrint('任務進度同步失敗：$e');
    }

    return messages.isEmpty ? '' : '｜${messages.join('、')}';
  }

  Future<void> _checkMonthlyBudgetAfterSave({required bool isIncome}) async {
    if (isIncome) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool('setting_monthly_budget_reminder') ?? _monthlyBudgetReminderEnabled;
      final budget = prefs.getInt('setting_monthly_budget_amount') ?? _monthlyBudgetAmount;
      // ★★★ 修正：門檻固定 90%，不再讀使用者自選值（原本可自選 70/80/90/100%
      //     會跟固定的三級提醒衝突，設定頁的下拉選單已移除）。★★★
      const int threshold = 90;
      if (!enabled || budget <= 0) return;

      final now = DateTime.now();
      final spent = _transactions
          .where((tx) =>
      tx.type == TransactionType.expense &&
          tx.date.year == now.year &&
          tx.date.month == now.month)
          .fold<double>(0, (sum, tx) => sum + tx.amount.abs());

      final percent = spent / budget * 100;

      // ★★★ 修改：三級判斷 (50 聰明版 / threshold[預設90] / 100) ★★★
      // - 100：一到就跳
      // - threshold(預設90)：一到就跳
      // - 50：只有「已花比例 > 時間比例」(代表真的花太快) 才跳，避免月初繳房租就誤觸
      final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
      final timeRatio = now.day / daysInMonth * 100;
      int level = 0;
      if (percent >= 100) {
        level = 100;
      } else if (percent >= threshold) {
        level = threshold;
      } else if (percent >= 50 && percent > timeRatio) {
        level = 50;
      }
      if (level == 0) return;

      final key = 'last_budget_alert_level_${_monthKey(now)}';
      final lastLevel = prefs.getInt(key) ?? 0;
      if (lastLevel >= level) return;
      await prefs.setInt(key, level);

      if (!mounted) return;
      // ★★★ 修改：改成呼叫「AI 消費洞察彈窗」(拿不到網路會自動退回原本的制式文字) ★★★
      await _showSpendingInsightDialog(
        level: level,
        spent: spent,
        budget: budget.toDouble(),
        percent: percent,
      );
    } catch (e) {
      debugPrint('月底預算提醒檢查失敗：$e');
    }
  }

  // ★★★ 新增：AI 消費洞察彈窗 (跨門檻時跳出，進度條 + 當前寵物語氣的洞察) ★★★
  // 拿不到網路 / API 失敗時，會自動退回原本的制式文字，不會壞掉。
  Future<void> _showSpendingInsightDialog({
    required int level,
    required double spent,
    required double budget,
    required double percent,
  }) async {
    // 準備「斷網備用文字」(等同原本的制式提醒)
    final String fallbackMsg = level >= 100
        ? '本月已花 ${_formatMoney(spent)}，已超過預算 ${_formatMoney(budget)}。'
        : '本月已花 ${_formatMoney(spent)}，已達預算 ${percent.round()}%。';

    String aiComment = '';

    try {
      final token = await _getAuthToken(); // ★ 拿 Token
      final url = Uri.parse('${BackendConfig.baseUrl}/api/spending-insight');

      final response = await http.post(
        url,
        headers: {
          "Content-Type": "application/json",
          if (token != null) "Authorization": "Bearer $token",
        },
        body: jsonEncode({
          "monthly_budget": budget,
          "current_pet": _currentPetKey, // ★ 帶入當前上場寵物
          "level": level,                // ★ 帶入門檻級別 (50/90/100)
        }),
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final resJson = jsonDecode(response.body);
        if (resJson['data'] != null && resJson['data']['ai_comment'] != null) {
          aiComment = resJson['data']['ai_comment'].toString();
        }
      }
    } catch (e) {
      print("Spending Insight Error: $e");
    }

    if (!mounted) return;

    // 標題依門檻級別變化 (50=健檢 / 中間=警告 / 100=超支)
    final String title = level >= 100
        ? '月底預算已超過'
        : (level <= 50 ? '月中消費健檢' : '月底預算警告');

    // 進度條比例 (超過 100% 就填滿)
    final double barValue = (percent / 100).clamp(0.0, 1.0);

    // 進度條顏色 (依級別)
    final Color barColor = level >= 100
        ? Colors.red
        : (level <= 50 ? Colors.green : Colors.orange);

    // 顯示內容：有 AI 就用 AI 洞察，否則退回制式文字
    final String bodyText = aiComment.isNotEmpty ? aiComment : fallbackMsg;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 進度條
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: barValue,
                minHeight: 12,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(barColor),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '本月已花 ${_formatMoney(spent)} / 預算 ${_formatMoney(budget)}（${percent.round()}%）',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            // 寵物語氣洞察 (對話氣泡感)
            Container(
              padding: const EdgeInsets.all(12),
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              // ★★★ 修改：左邊加上「當前上場寵物的 emoji」，看起來像那隻寵物在講話 ★★★
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _getCurrentPetEmoji(),
                    style: const TextStyle(fontSize: 24),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      bodyText,
                      style: const TextStyle(fontSize: 14, height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('知道了')),
        ],
      ),
    );
  }

  Future<void> _loadData() async {
    final data = await DatabaseHelper.instance.getAllTransactions();

    // ★★★ 新增：判斷今天是否為第一筆 ★★★
    final hasTodayRecord = await DatabaseHelper.instance.hasTransactionsOnDate(DateTime.now());

    if (mounted) {
      setState(() {
        _transactions = data;
        _isFirstTransactionToday = !hasTodayRecord; // 如果沒有紀錄，這就是第一筆
      });
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

  Future<void> _loadRuntimeSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final identity = prefs.getString('user_identity') ?? "u23";
    if (!mounted) return;
    setState(() {
      _userIdentity = identity;
      _userNickname = prefs.getString('user_nickname') ?? "使用者";
      _currentPetKey = prefs.getString('current_pet_key') ?? "dog"; // ★★★ 新增：讀取當前寵物 ★★★
      _useAiSuggestion = prefs.getBool('setting_ai_suggestion') ?? true;
      _dailyReminderEnabled = prefs.getBool('setting_daily_reminder') ?? true;
      _dailyReminderTime = prefs.getString('setting_daily_reminder_time') ?? "21:00";
      _monthlyBudgetReminderEnabled = prefs.getBool('setting_monthly_budget_reminder') ?? true;
      _monthlyBudgetAmount = prefs.getInt('setting_monthly_budget_amount') ?? _defaultBudgetForIdentity(identity);
      _budgetThreshold = prefs.getInt('setting_budget_threshold') ?? 90;
      _currencyCode = CurrencyService.codeFromSetting(prefs.getString('setting_currency_code') ?? CurrencyService.codeFromSetting(prefs.getString('setting_currency')));
    });
  }

  Future<void> _loadUserProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final identity = prefs.getString('user_identity') ?? "u23";
    setState(() {
      _userIdentity = identity;
      _userNickname = prefs.getString('user_nickname') ?? "使用者";
      _currentPetKey = prefs.getString('current_pet_key') ?? "dog"; // ★★★ 新增：讀取當前寵物 ★★★
      _useAiSuggestion = prefs.getBool('setting_ai_suggestion') ?? true;
      _dailyReminderEnabled = prefs.getBool('setting_daily_reminder') ?? true;
      _dailyReminderTime = prefs.getString('setting_daily_reminder_time') ?? "21:00";
      _monthlyBudgetReminderEnabled = prefs.getBool('setting_monthly_budget_reminder') ?? true;
      _monthlyBudgetAmount = prefs.getInt('setting_monthly_budget_amount') ?? _defaultBudgetForIdentity(identity);
      _budgetThreshold = prefs.getInt('setting_budget_threshold') ?? 90;
      _currencyCode = CurrencyService.codeFromSetting(prefs.getString('setting_currency_code') ?? CurrencyService.codeFromSetting(prefs.getString('setting_currency')));
    });
    await DatabaseHelper.instance.initializeUserIdentity(_userIdentity);

    // ★★★ 新增：從快取抓取註冊方式，並同步寫入深層 SQLite 資料庫 ★★★
    String authProvider = prefs.getString('auth_provider') ?? "local";
    await DatabaseHelper.instance.updateUserInfo(_userNickname, authProvider);
  }

  Future<void> _loadScanMode() async {
    final sp = await SharedPreferences.getInstance();
    final m = sp.getString(_kPrefKey);
    setState(() {
      _scanMode = (m == 'traditional') ? ScanMode.traditional : ScanMode.auto;
    });
  }

  Future<void> _toggleScanMode() async {
    final next = (_scanMode == ScanMode.auto) ? ScanMode.traditional : ScanMode.auto;
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kPrefKey, next == ScanMode.traditional ? 'traditional' : 'auto');
    setState(() => _scanMode = next);
  }

  Future<void> _goScan() async {
    final routeName = _scanMode == ScanMode.auto ? '/scan' : '/scan/traditional';
    final result = await Navigator.of(context).pushNamed(routeName);
    if (result != null && result is String && result.isNotEmpty) {
      await _handleScanResult(result);
    }
  }

  Future<void> _onVoiceBtnPressed() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const VoicePage()),
    );
    if (result != null && result is Map && result['type'] == 'voice_input') {
      String text = result['text'];
      await _handleVoiceAnalysis(text);
    }
  }

  Future<void> _handleVoiceAnalysis(String voiceText) async {
    await _refreshCurrentPetKey(); // ★ 新增：確保動畫用的是目前上場的寵物
    setState(() => _isAnalyzing = true);
    _pendingEntryMethod = 'voice';
    _pendingRawInput = voiceText;
    _pendingCurrencyCode = await CurrencyService.instance.getActiveCurrencyCode(); // ★ 合併自朋友版(C)

    try {
      final token = await _getAuthToken(); // ★ 1. 拿出 Token
      final url = Uri.parse('${BackendConfig.baseUrl}/classify');
      final now = DateTime.now();
      String timeStr = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";

      final response = await http.post(
        url,
        headers: {
          "Content-Type": "application/json",
          if (token != null) "Authorization": "Bearer $token", // ★ 2. 夾在 Header 送出
        },
        body: jsonEncode({
          "scanned_content": "",
          "user_input": voiceText,
          "identity": _userIdentity,
          "current_time": timeStr,
          "current_pet": _currentPetKey // ★★★ 新增：傳遞寵物參數 ★★★
        }),
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final resJson = jsonDecode(response.body);
        _processAiResponse(resJson);
      } else {
        if (mounted) _showErrorSnackBar('AI 分析失敗: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) _showErrorSnackBar('連線錯誤: $e');
    } finally {
      if (mounted) setState(() => _isAnalyzing = false);
    }
  }

  Future<void> _handleScanResult(String scannedText) async {
    await _refreshCurrentPetKey(); // ★ 新增：確保動畫用的是目前上場的寵物
    setState(() => _isAnalyzing = true);
    _pendingEntryMethod = 'scan';
    _pendingRawInput = scannedText;
    _pendingCurrencyCode = await CurrencyService.instance.getActiveCurrencyCode(); // ★ 合併自朋友版(C)

    try {
      final token = await _getAuthToken(); // ★ 1. 拿出 Token
      final url = Uri.parse('${BackendConfig.baseUrl}/classify');
      final now = DateTime.now();
      String timeStr = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";

      final response = await http.post(
        url,
        headers: {
          "Content-Type": "application/json",
          if (token != null) "Authorization": "Bearer $token", // ★ 2. 夾在 Header 送出
        },
        body: jsonEncode({
          "scanned_content": scannedText,
          "user_input": "我是$_userNickname",
          "identity": _userIdentity,
          "current_time": timeStr,
          "current_pet": _currentPetKey // ★★★ 新增：傳遞寵物參數 ★★★
        }),
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final resJson = jsonDecode(response.body);
        _processAiResponse(resJson);
      } else {
        if (mounted) _showErrorSnackBar('AI 分析失敗: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) _showErrorSnackBar('連線錯誤: $e');
    } finally {
      if (mounted) setState(() => _isAnalyzing = false);
    }
  }

  void _processAiResponse(dynamic resJson) {
    final data = resJson['data'];
    double amount = data['amount'] != null ? (data['amount'] as num).toDouble() : 0.0;
    String mainCat = data['matched_main_category'] ?? "";
    String subCat = data['matched_sub_category'] ?? "";

    // ★★★ 終極完整版：AI 翻譯蒟蒻 (字詞校正防呆) ★★★
    // 解決 AI 偷懶省略字，導致預設分類被誤認為自創 (is_custom=1) 的問題
    final s = subCat.trim().toLowerCase(); // 轉小寫並去空白，防呆更徹底

    // 1. 飲食 / 交通
    if (s == '飲料' || s == '咖啡' || s == '手搖飲') subCat = '飲料/咖啡';
    if (s == '火車' || s == '高鐵' || s == '台鐵') subCat = '火車/高鐵';
    if (s == '計程車' || s == 'uber' || s == '叫車') subCat = '計程車/Uber';

    // 2. 生活用品
    if (s == '衛生紙' || s == '日用品') subCat = '衛生紙/日用品';
    if (s == '洗衣' || s == '清潔' || s == '洗衣服') subCat = '洗衣/清潔';
    if (s == '五金' || s == '百貨' || s == '五金行') subCat = '五金百貨';

    // 3. 娛樂 / 社交
    if (s == '展覽' || s == '表演' || s == '看展') subCat = '展覽/表演';
    if (s == '書籍' || s == '雜誌' || s == '買書') subCat = '書籍/雜誌';
    if (s == '串流' || s == '影音') subCat = '串流影音';

    // 4. 服飾美容 / 醫療
    if (s == '衣服' || s == '鞋子' || s == '買衣服' || s == '買鞋') subCat = '衣服/鞋子';
    if (s == '化妝品' || s == '保養品' || s == '化妝' || s == '保養') subCat = '化妝品/保養品';
    if (s == '剪髮' || s == '美容' || s == '理髮' || s == '做臉') subCat = '剪髮/美容';
    if (s == '美甲' || s == '按摩' || s == '做指甲') subCat = '美甲/按摩';
    if (s == '看診' || s == '掛號' || s == '門診' || s == '看病') subCat = '看診掛號';

    // 5. 學生專屬
    if (s == '參考書' || s == '課本') subCat = '參考書/課本';
    if (s == 'icloud' || s == 'google drive' || s == '雲端') subCat = 'iCloud/Google Drive';
    if (s == 'disney' || s == 'disney+' || s == '迪士尼') subCat = 'Disney+';
    if (s == '遊戲' || s == '課金' || s == '遊戲儲值') subCat = '遊戲課金';
    if (s == '物品遺失' || s == '遺失重買' || s == '重買') subCat = '物品遺失重買';

    // 6. 家庭專屬
    if (s == '房屋稅' || s == '地價稅' || s == '繳稅') subCat = '房屋稅/地價稅';
    if (s == '尿布' || s == '奶粉') subCat = '尿布奶粉';
    if (s == '玩具' || s == '童書') subCat = '玩具/童書';
    if (s == '機票' || s == '住宿' || s == '訂房' || s == '飯店') subCat = '機票住宿';
    if (s == '長輩醫療' || s == '長輩看診') subCat = '長輩醫療';
    if (s == '全家出遊' || s == '出遊餐飲') subCat = '全家出遊餐飲';

    // 7. 收入 (預防萬一)
    if (s == '退稅' || s == '補助') subCat = '退稅/補助';

    // --- 翻譯蒟蒻結束 ---
    String comment = data['comment'] ?? "";
    String merchant = data['merchant'] ?? "";
    String itemsSummary = data['items_summary'] ?? "";
    // ★ 合併自朋友版(B)：正規化 + 從掃描原文備援抓發票號碼，讓「掃描發票→地產資金」更可靠
    // ★★★ 修正：只有「掃描」才從原文找發票號碼；語音記帳沒有發票，
    //     只採用 AI 明確給的 invoice_number 欄位，避免掃到日期等欄位拼出假號碼。★★★
    String invoiceNum = (_pendingEntryMethod == 'scan')
        ? _resolveInvoiceNumber(data['invoice_number']?.toString(), _pendingRawInput)
        : _normalizeInvoiceNumber(data['invoice_number']?.toString());
    String date = data['date'] ?? "";

    // ===== 暫存 AI 回傳內容：之後按下「確認」時會寫入 V2 記帳表（receipts / ai_notes / tags）=====
    try {
      _pendingAiJson = jsonEncode(resJson);
    } catch (_) {
      _pendingAiJson = null;
    }
    _pendingMerchant = merchant;
    _pendingItemsSummary = itemsSummary;
    _pendingInvoiceNumber = invoiceNum;
    // ★ 合併自朋友版(C)：AI 幣別優先，其次掃描原文偵測，發票視為 TWD，否則沿用目前的
    final aiCurrency = CurrencyService.tryNormalizeCode(data['currency']?.toString());
    final textCurrency = _detectCurrencyFromText(_pendingRawInput);
    _pendingCurrencyCode = aiCurrency ?? textCurrency ?? (invoiceNum.isNotEmpty ? 'TWD' : (_pendingCurrencyCode ?? 'TWD'));
    _pendingSuggestedSubCategory = subCat;
    _pendingAiModel = (data['model'] ?? resJson['model'] ?? '').toString();

    final confRaw = data['confidence'] ?? data['ai_confidence'];
    _pendingAiConfidence = confRaw is num ? confRaw.toDouble() : double.tryParse(confRaw?.toString() ?? '');

    // date 可能是 yyyy-MM-dd / yyyy/MM/dd / ISO
    DateTime? parsedOccurredAt;
    if (date.trim().isNotEmpty) {
      try {
        parsedOccurredAt = DateTime.parse(date.trim());
      } catch (_) {
        final m = RegExp(r'^(\d{4})[\/-](\d{1,2})[\/-](\d{1,2})').firstMatch(date.trim());
        if (m != null) {
          final y = int.tryParse(m.group(1)!);
          final mo = int.tryParse(m.group(2)!);
          final d = int.tryParse(m.group(3)!);
          if (y != null && mo != null && d != null) {
            parsedOccurredAt = DateTime(y, mo, d);
          }
        }
      }
    }
    final DateTime _nowForDateCheck = DateTime.now();

    // ★★★ 新增：語音記帳先從「使用者講的話」解析日期(昨天/前天/X月X日/X/X)，有講就用講的那天 ★★★
    if (_pendingEntryMethod == 'voice') {
      final DateTime? spokenDate = _parseChineseDateFromText(_pendingRawInput ?? '');
      if (spokenDate != null) {
        parsedOccurredAt = spokenDate;
      }
    }

    // ★★★ 防呆：AI 有時亂編過期年份的日期(例如 2023)。解析失敗、或年份跟今天差超過 1 年 → 退回今天。★★★
    if (parsedOccurredAt == null ||
        (parsedOccurredAt.year - _nowForDateCheck.year).abs() > 1) {
      parsedOccurredAt = _nowForDateCheck;
    }

    // ★★★ 修改：掃描發票 → 發票日期若是「當月」就用發票日期；否則(舊發票/亂填)用今天(掃描當天) ★★★
    if (_pendingEntryMethod == 'scan') {
      final bool sameMonth = parsedOccurredAt.year == _nowForDateCheck.year &&
          parsedOccurredAt.month == _nowForDateCheck.month;
      if (!sameMonth) {
        parsedOccurredAt = _nowForDateCheck;
      }
    }

    _pendingOccurredAt = parsedOccurredAt;

    // tags
    final rawTags = data['tags'] ?? [];
    if (rawTags is List) {
      _pendingTags = rawTags.map((e) => e.toString()).toList();
    } else {
      _pendingTags = [];
    }

    List<dynamic> tagsList = data['tags'] ?? [];
    String tagsStr = tagsList.join(" ");
    if (tagsStr.isNotEmpty) {
      tagsStr = "🔍 $tagsStr";
    }

    String displayNote = "";
    if (merchant.isNotEmpty && !merchant.contains("未知")) {
      displayNote += "【$merchant】\n";
    }
    if (itemsSummary.isNotEmpty) {
      displayNote += "🛒 $itemsSummary\n";
    }
    if (tagsStr.isNotEmpty) {
      displayNote += "$tagsStr\n";
    }
    // ★★★ 修改：備註括號裡顯示「這張發票自己的開立日期」；
    //     找不到可信的發票日期時就只顯示發票號碼，不顯示括號。
    //     註：這裡只影響「備註文字」，不影響 _pendingOccurredAt（實際記帳日）的判斷規則。★★★
    final String invoiceDateText = _resolveInvoiceDateText(date, _pendingRawInput);
    if (invoiceNum.isNotEmpty) {
      displayNote += invoiceDateText.isNotEmpty
          ? "🧾 $invoiceNum ($invoiceDateText)"
          : "🧾 $invoiceNum";
    }

    // ★★★ 核心修改：判斷是不是收入，呼叫不同的彈窗 ★★★
    List<String> incomeMainCategories = ["薪水", "投資收益", "禮金", "其他收入", "零用錢", "打工收入", "獎學金", "投資獲利", "被動收入", "退稅/補助"];
    bool isIncome = incomeMainCategories.contains(mainCat) || mainCat == '收入' || subCat.contains('薪水') || subCat.contains('退稅');

    // 設定頁的「AI 分類建議」關閉時：保留 AI 抓到的金額、商家與備註，但分類交給使用者手動確認。
    if (!_useAiSuggestion) {
      mainCat = isIncome ? '其他收入' : '其他支出';
      subCat = isIncome ? '退款' : '其他';
      _pendingSuggestedSubCategory = null;
    }

    if (mounted) {
      if (isIncome) {
        // 防呆校正：就算後端主分類偷懶，我們也幫它強制冠上一個預設收入類別
        if (mainCat.isEmpty || mainCat == '其他支出' || mainCat == '收入') mainCat = '其他收入';
        _showIncomeConfirmationDialog(amount, subCat, mainCat, displayNote.trim(), comment);
      } else {
        _showConfirmationDialog(amount, subCat, mainCat, displayNote.trim(), comment);
      }
    }
  }

  void _showErrorSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  // ★★★ 原本的確認視窗 (負責處理支出) ★★★
  void _showConfirmationDialog(double initAmount, String initSub, String initMain, String initNote, String aiComment) {
    final amountController = TextEditingController(text: initAmount.toStringAsFixed(0));
    final noteController = TextEditingController(text: initNote);

    String selectedMain = initMain;
    String selectedSub = initSub;

    // 支出清單的所有主分類
    List<String> expenseMains = ["飲食", "交通", "生活用品", "社交", "娛樂", "通訊網路", "服飾美容", "醫療健康", "住房", "其他支出", "學費與教材", "線上訂閱", "小確幸", "禮物與送禮", "不見了", "投資理財", "家具家電", "房貸與修繕", "小孩教育", "保險費用", "長輩支出", "家庭旅遊"];

    // 1. 如果 AI 給的主分類不在我們的清單裡，歸類到「其他支出」
    if (!expenseMains.contains(selectedMain)) {
      selectedMain = "其他支出";
    }

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
            builder: (context, setStateDialog) {

              // 根據身份過濾主分類 (排除收入類別)
              List<String> validMainCategories = [];
              _categoryData.forEach((key, value) {
                if (!expenseMains.contains(key)) return; // 只顯示支出

                String group = value['group'];
                bool show = false;
                if (group == 'all') show = true;
                else if (_userIdentity == 'u23' && group == 'student') show = true;
                else if (_userIdentity == 'a23_35' && group == 'worker') show = true;
                else if (_userIdentity == 'a35p' && group == 'family') show = true;

                if (show) validMainCategories.add(key);
              });

              if (!validMainCategories.contains(selectedMain) && validMainCategories.isNotEmpty) {
                selectedMain = validMainCategories[0];
                selectedSub = (_categoryData[selectedMain]?["subs"] as List)[0];
              }

              List<String> currentSubList = List<String>.from(_categoryData[selectedMain]?["subs"] ?? []);

              // ★★★ 如果 AI 的子分類 (例如 "飲料/咖啡") 在清單裡，就直接選中 ★★★
              // 如果不在清單裡 (AI自創)，就暫時加進去，並選中
              if (!currentSubList.contains(selectedSub)) {
                currentSubList.insert(0, selectedSub);
              } else {
                currentSubList.remove(selectedSub);
                currentSubList.insert(0, selectedSub);
              }

              return AlertDialog(
                title: const Text("✨ AI 分析結果確認"),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("分類", style: TextStyle(fontSize: 12, color: Colors.grey)),
                      const SizedBox(height: 8),

                      Row(
                        children: [
                          // 左邊：主分類 Dropdown
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: selectedMain,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: '主分類',
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              ),
                              items: validMainCategories.map((String value) {
                                return DropdownMenuItem<String>(
                                  value: value,
                                  child: Text(value, style: const TextStyle(fontSize: 14)),
                                );
                              }).toList(),
                              onChanged: (String? newValue) {
                                if (newValue != null) {
                                  setStateDialog(() {
                                    selectedMain = newValue;
                                    selectedSub = (_categoryData[selectedMain]?["subs"] as List)[0];
                                  });
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          // 右邊：子分類 Dropdown
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: selectedSub,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: '子分類',
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              ),
                              items: currentSubList.map((String value) {
                                return DropdownMenuItem<String>(
                                  value: value,
                                  child: Text(value, style: const TextStyle(fontSize: 14)),
                                );
                              }).toList(),
                              onChanged: (String? newValue) {
                                if (newValue != null) {
                                  setStateDialog(() {
                                    selectedSub = newValue;
                                  });
                                }
                              },
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      const Text("金額", style: TextStyle(fontSize: 12, color: Colors.grey)),
                      TextField(
                        controller: amountController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(prefixText: "$_pendingCurrencySymbol "), // ★ 合併自朋友版(C)
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),

                      const Text("備註", style: TextStyle(fontSize: 12, color: Colors.grey)),
                      TextField(
                        controller: noteController,
                        maxLines: 4,
                        decoration: const InputDecoration(border: OutlineInputBorder()),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text("取消"),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      final finalAmount = double.tryParse(amountController.text) ?? initAmount;
                      final finalNote = noteController.text;
                      Navigator.of(ctx).pop();
                      _saveAIResult(finalAmount, selectedSub, selectedMain, finalNote, aiComment); // 預設是支出
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.black, foregroundColor: Colors.white),
                    child: const Text("確認儲存"),
                  ),
                ],
              );
            }
        );
      },
    );
  }

  // ★★★ 全新設計：專屬收入的確認視窗 (支援動態主分類) ★★★
  void _showIncomeConfirmationDialog(double initAmount, String initSub, String initMain, String initNote, String aiComment) {
    final amountController = TextEditingController(text: initAmount.toStringAsFixed(0));
    final noteController = TextEditingController(text: initNote);

    String selectedMain = initMain;
    String selectedSub = initSub;

    // 收入清單的所有主分類
    List<String> incomeMains = ["薪水", "投資收益", "禮金", "其他收入", "零用錢", "打工收入", "獎學金", "投資獲利", "被動收入", "退稅/補助"];

    // 1. 如果 AI 給的主分類不在我們的清單裡，歸類到「其他收入」
    if (!incomeMains.contains(selectedMain)) {
      selectedMain = "其他收入";
    }

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
            builder: (context, setStateDialog) {

              // 根據身份過濾主分類 (只顯示收入類別)
              List<String> validIncomeCategories = [];
              _categoryData.forEach((key, value) {
                if (!incomeMains.contains(key)) return; // 只顯示收入

                String group = value['group'];
                bool show = false;
                if (group == 'all') show = true;
                else if (_userIdentity == 'u23' && group == 'student') show = true;
                else if (_userIdentity == 'a23_35' && group == 'worker') show = true;
                else if (_userIdentity == 'a35p' && group == 'family') show = true;

                if (show) validIncomeCategories.add(key);
              });

              if (!validIncomeCategories.contains(selectedMain) && validIncomeCategories.isNotEmpty) {
                // 如果目前的選擇不在過濾後的清單裡，優先選其他收入，沒有就選第一個
                selectedMain = validIncomeCategories.firstWhere((cat) => cat == "其他收入", orElse: () => validIncomeCategories[0]);
                selectedSub = (_categoryData[selectedMain]?["subs"] as List)[0];
              }

              List<String> currentSubList = List<String>.from(_categoryData[selectedMain]?["subs"] ?? []);

              // 如果 AI 自創的收入分類不在我們的清單裡，就暫時加進去
              if (!currentSubList.contains(selectedSub)) {
                if (selectedSub.trim().isEmpty) {
                  selectedSub = currentSubList[0];
                } else {
                  currentSubList.insert(0, selectedSub);
                }
              } else {
                currentSubList.remove(selectedSub);
                currentSubList.insert(0, selectedSub);
              }

              return AlertDialog(
                // 專屬綠色標題
                title: const Text("💰 收入進帳確認", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("分類", style: TextStyle(fontSize: 12, color: Colors.grey)),
                      const SizedBox(height: 8),

                      Row(
                        children: [
                          // 左邊：主分類 Dropdown (只有過濾後的收入可以選)
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: selectedMain,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: '主分類',
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              ),
                              items: validIncomeCategories.map((String value) {
                                return DropdownMenuItem<String>(
                                  value: value,
                                  child: Text(value, style: const TextStyle(fontSize: 14)),
                                );
                              }).toList(),
                              onChanged: (String? newValue) {
                                if (newValue != null) {
                                  setStateDialog(() {
                                    selectedMain = newValue;
                                    selectedSub = (_categoryData[selectedMain]?["subs"] as List)[0];
                                  });
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          // 右邊：子分類 Dropdown
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: selectedSub,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: '子分類',
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              ),
                              items: currentSubList.map((String value) {
                                return DropdownMenuItem<String>(
                                  value: value,
                                  child: Text(value, style: const TextStyle(fontSize: 14)),
                                );
                              }).toList(),
                              onChanged: (String? newValue) {
                                if (newValue != null) {
                                  setStateDialog(() {
                                    selectedSub = newValue;
                                  });
                                }
                              },
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      const Text("金額", style: TextStyle(fontSize: 12, color: Colors.grey)),
                      TextField(
                        controller: amountController,
                        keyboardType: TextInputType.number,
                        // 加號提示這是一筆進帳
                        decoration: InputDecoration(prefixText: "+ $_pendingCurrencySymbol "), // ★ 合併自朋友版(C)
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.green),
                      ),
                      const SizedBox(height: 16),

                      const Text("備註", style: TextStyle(fontSize: 12, color: Colors.grey)),
                      TextField(
                        controller: noteController,
                        maxLines: 4,
                        decoration: const InputDecoration(border: OutlineInputBorder()),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text("取消"),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      final finalAmount = double.tryParse(amountController.text) ?? initAmount;
                      final finalNote = noteController.text;
                      Navigator.of(ctx).pop();
                      // ★★★ 關鍵：呼叫儲存時，加入 isIncome: true 參數 ★★★
                      _saveAIResult(finalAmount, selectedSub, selectedMain, finalNote, aiComment, isIncome: true);
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                    child: const Text("確認存入"),
                  ),
                ],
              );
            }
        );
      },
    );
  }

  // ★★★ AI 記帳 (加入 isIncome 判斷方向) ★★★

  Future<void> _saveAIResult(double amount, String subCat, String mainCat, String note, String aiComment, {bool isIncome = false}) async {
    try {
      // 根據我們從彈窗傳進來的狀態，決定資料庫寫入方向
      String dbType = isIncome ? 'income' : 'expense';

      // ★★★ 新增：同一張發票只能記一次，避免重複新增交易 + 重複領地產資金 ★★★
      final String dupInvoiceNumber = _normalizeInvoiceNumber(_pendingInvoiceNumber);
      if (dupInvoiceNumber.isNotEmpty) {
        bool alreadyRecorded = false;
        try {
          alreadyRecorded = await GameApiService.instance.hasInvoiceReward(
            invoiceNumber: dupInvoiceNumber,
          );
        } catch (e) {
          debugPrint('發票重複檢查（後端）失敗，改用本地紀錄判斷：$e');
        }
        if (!alreadyRecorded) {
          // 後端問不到時的備援：看看目前已載入的交易備註裡有沒有同一張發票
          alreadyRecorded =
              _transactions.any((tx) => tx.note.contains(dupInvoiceNumber));
        }
        if (alreadyRecorded) {
          // 清掉暫存，避免下一筆沿用到這張發票
          _pendingAiJson = null;
          _pendingMerchant = null;
          _pendingItemsSummary = null;
          _pendingInvoiceNumber = null;
          _pendingCurrencyCode = null;
          _pendingAiConfidence = null;
          _pendingSuggestedSubCategory = null;
          _pendingAiModel = null;
          _pendingOccurredAt = null;
          _pendingTags = [];

          // ★★★ 修改：改用橘底提示列（警告色），不再跳出需要按確認的浮窗 ★★★
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('⚠️ 發票 $dupInvoiceNumber 已經記過帳了，這次沒有重複新增'),
                backgroundColor: Colors.orange,
                duration: const Duration(milliseconds: 2500),
              ),
            );
          }
          return;
        }
      }

      // 1) --- 分類解鎖邏輯（沿用舊版） ---
      if (subCat.trim().isNotEmpty) {
        bool isDefaultCategory = false;

        // 檢查是否為「預設分類」 (因為現在 _categoryData 包含所有分類，直接掃描即可)
        _categoryData.forEach((key, value) {
          if ((value['subs'] as List).contains(subCat.trim())) {
            isDefaultCategory = true;
          }
        });

        // ★★★ 規則：AI 記帳，預設分類 -> 1次解鎖； 非預設(AI自創) -> 5次解鎖 ★★★
        int threshold = isDefaultCategory ? 1 : 5;
        // ★★★ 修正：預設分類解鎖「主類」，AI自創分類才解鎖「子類(視為主類)」 ★★★
        String unlockName = isDefaultCategory ? mainCat.trim() : subCat.trim();

        // ※ 這裡會自動：不存在就補一筆 categories（is_custom=1），並累加 usage_count
        await DatabaseHelper.instance.applyUnlockRuleForName(
          name: unlockName,
          type: dbType, // ★ 改用動態變數
          customUnlockThreshold: threshold,
        );
      }

      // 2) --- 寫入「V2 記帳表」(accounting_transactions / receipts / ai_notes / tags) ---
      final entry = _pendingEntryMethod ?? 'scan';
      final rawInput = _pendingRawInput;
      final tags = _pendingTags;

      await DatabaseHelper.instance.insertAiTransaction(
        amount: amount,
        currency: _pendingCurrencyCode ?? _currencyCode, // ★ 合併自朋友版(C)：用本次掃描/語音幣別
        direction: dbType, // ★ 改用動態變數，解決原本寫死 'expense' 的問題
        selectedMainCategory: mainCat,
        selectedSubCategory: subCat,
        suggestedSubCategory: _pendingSuggestedSubCategory,
        aiConfidence: _pendingAiConfidence,
        entryMethod: entry,
        captureMethod: entry,
        source: 'backend',
        merchantName: _pendingMerchant,
        note: note,
        occurredAt: _pendingOccurredAt ?? DateTime.now(),
        rawInput: rawInput,
        parsedJson: _pendingAiJson,
        invoiceNumber: _pendingInvoiceNumber,
        aiModel: _pendingAiModel,
        aiShortComment: aiComment,
        aiItemsSummary: _pendingItemsSummary,
        tags: tags,
      );

      // 3) 重新讀取交易資料（避免 UI/DB 不同步）
      await _loadData();
      await _checkMonthlyBudgetAfterSave(isIncome: isIncome);
      await NotificationService.instance.syncFromPreferences(); // ★ 退役 DailyNotificationService，改用朋友版
      // ★ 合併自朋友版(B 遊戲資金)：掃描發票→地產資金；語音→寵物代幣；並記入任務進度
          {
        final rewardMessage = await _grantGamificationRewards(
          entryMethod: entry,
          amount: amount,
          isIncome: isIncome,
          invoiceNumber: _pendingInvoiceNumber,
        );
        if (mounted && rewardMessage.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('記帳完成$rewardMessage'), duration: const Duration(milliseconds: 1500)),
          );
        }
      }

      // 4) 觸發動物講話 (沿用你的原本功能)
      if (aiComment.isNotEmpty && _selectedIndex == 0) {
        _homeKey.currentState?.triggerAiComment(aiComment);
      } else if (aiComment.isNotEmpty && _homeKey.currentState != null) {
        _homeKey.currentState!.showAiComment(aiComment);
      }

      // 5) 清掉暫存（避免下一筆沿用）
      _pendingAiJson = null;
      _pendingMerchant = null;
      _pendingItemsSummary = null;
      _pendingInvoiceNumber = null;
      _pendingCurrencyCode = null; // ★ 合併自朋友版(C)
      _pendingAiConfidence = null;
      _pendingSuggestedSubCategory = null;
      _pendingAiModel = null;
      _pendingOccurredAt = null;
      _pendingTags = [];

      // 6) Snackbar
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isIncome ? '✅ 收入已存入' : '✅ 記帳完成'),
            backgroundColor: Colors.green,
            duration: const Duration(milliseconds: 1500),
          ),
        );
      }
    } catch (e) {
      print("資料庫操作錯誤: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ 記帳失敗：$e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  IconData _mapCategoryToIcon(String mainCategory, [String subCategory = ""]) {
    bool isDefaultCategory = false;

    if (_categoryData.containsKey(mainCategory)) {
      final subs = List<String>.from(_categoryData[mainCategory]!['subs']);
      if (subs.contains(subCategory) || subCategory.isEmpty) {
        isDefaultCategory = true;
      }
    }

    if (!isDefaultCategory) {
      return Icons.more_horiz_rounded;
    }

    String key = "$mainCategory $subCategory";

    if (key.contains("食") || key.contains("餐") || key.contains("飲") || key.contains("零")) return Icons.fastfood_rounded;
    if (key.contains("衣") || key.contains("飾") || key.contains("鞋")) return Icons.checkroom_rounded;
    if (key.contains("行") || key.contains("交通") || key.contains("車") || key.contains("油")) return Icons.directions_bus_rounded;
    if (key.contains("育") || key.contains("學") || key.contains("書") || key.contains("課")) return Icons.school_rounded;
    if (key.contains("樂") || key.contains("娛") || key.contains("遊") || key.contains("影")) return Icons.sports_esports_rounded;
    if (key.contains("醫") || key.contains("藥") || key.contains("健")) return Icons.medical_services_rounded;
    if (key.contains("住") || key.contains("房") || key.contains("水電") || key.contains("瓦斯")) return Icons.home_rounded;
    if (key.contains("3C") || key.contains("電") || key.contains("機")) return Icons.devices_rounded;

    return Icons.receipt_long_rounded;
  }

  // ★★★ 手動記帳 (手動一律 1 次解鎖，觸發通關密語！) ★★★
  void _addTransaction(Transaction tx) async {
    await _refreshCurrentPetKey(); // ★ 新增：確保動畫與台詞用的是目前上場的寵物
    // ★★★ 修正：如果是今天第一筆，只去後端拿台詞，不要彈出確認視窗覆蓋分類！ ★★★
    if (_isFirstTransactionToday) {
      setState(() {
        _isAnalyzing = true;
        _pendingEntryMethod = 'manual';
      });

      // ★★★ 修正：動態判斷手動記帳第一筆的防呆動物台詞 (精準對應 16 隻) ★★★
      String aiComment = "汪！早安主人！今天的第一筆帳，幫你旺旺開張！";
      switch (_currentPetKey) {
        case 'cat': aiComment = "喵～早安！今天的第一筆帳，本喵幫你記下了！"; break;
        case 'fox': aiComment = "呵呵，早安呀！今天第一筆開銷，幫你精打細算囉。"; break;
        case 'parrot': aiComment = "早安！早安！第一筆帳！第一筆帳！"; break;
        case 'sloth': aiComment = "早...安...第...一...筆..."; break;
        case 'cute_dog': aiComment = "哇！！早安！第一筆帳！太棒啦！！"; break;
        case 'pomeranian': aiComment = "早安呀～今天的第一筆開銷，人家幫你記好囉～"; break;
        case 'norm_dog': aiComment = "喔，早安。第一筆帳記好了，就這樣。"; break;
        case 'wagging_dog': aiComment = "早安！！太棒啦！第一筆帳！搖搖搖！"; break;
        case 'lovely_cat': aiComment = "早安♡ 第一筆帳記好了，今天也要開開心心喔～"; break;
        case 'blue_cat': aiComment = "早安。今日首筆數據已記錄，請繼續保持效率。"; break;
        case 'rocket_cat': aiComment = "早安！啟動引擎！今天的第一筆帳，衝向星際！"; break;
        case 'loader_cat': aiComment = "早安...等待是一種智慧，第一筆帳已落實。"; break;
        case 'bear': aiComment = "哼唧...早安...第一筆帳記好了，有蜂蜜嗎？"; break;
        case 'bee': aiComment = "嗡！早安！第一筆帳記錄完畢，效率提升！"; break;
        case 'giraffe': aiComment = "早安...從高處看，這是今天的第一筆帳呢。"; break;
        case 'dog':
        default: aiComment = "汪！早安主人！今天的第一筆帳，狗狗幫你旺旺開張！"; break;
      }

      try {
        final token = await _getAuthToken(); // ★ 1. 拿出 Token
        final url = Uri.parse('${BackendConfig.baseUrl}/classify');
        final now = DateTime.now();
        String timeStr = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";

        final response = await http.post(
          url,
          headers: {
            "Content-Type": "application/json",
            if (token != null) "Authorization": "Bearer $token", // ★ 2. 夾在 Header 送出
          },
          body: jsonEncode({
            "scanned_content": "",
            "user_input": "手動記帳：買了${tx.category}，花了${_formatMoney(tx.amount)}。備註：${tx.note}",
            "identity": _userIdentity,
            "current_time": timeStr,
            "current_pet": _currentPetKey // ★★★ 新增：傳遞寵物參數 ★★★
          }),
        ).timeout(const Duration(seconds: 15));

        if (response.statusCode == 200) {
          final resJson = jsonDecode(response.body);
          if (resJson['data'] != null && resJson['data']['comment'] != null) {
            aiComment = resJson['data']['comment'];
          }
        }
      } catch (e) {
        print("Manual AI Error: $e");
      }

      if (mounted) {
        setState(() {
          _isAnalyzing = false;
        });
      }

      // ★★★ 關鍵修正：直接存入使用者原本選好的 tx，完全不理會 AI 猜的分類！ ★★★
      await DatabaseHelper.instance.insertTransaction(tx);

      final name = tx.category.trim();
      if (name.isNotEmpty) {
        final dbType = tx.type == TransactionType.expense ? 'expense' : 'income';

        // ★★★ 修正：判斷手動記帳的分類是「預設子類」還是「自創分類」 ★★★
        bool isDefaultCategory = false;
        String foundMainCategory = name; // 預設用自己當主類

        _categoryData.forEach((key, value) {
          if ((value['subs'] as List).contains(name)) {
            isDefaultCategory = true;
            foundMainCategory = key; // 找到對應的老大 (例如: 飲食)
          }
        });

        // 預設子類 -> 解鎖老大(foundMainCategory)
        // 自創分類 -> 解鎖自己(name)
        String unlockName = isDefaultCategory ? foundMainCategory : name;

        await DatabaseHelper.instance.applyUnlockRuleForName(
          name: unlockName,
          type: dbType,
          customUnlockThreshold: 1,
          isUserCreated: !isDefaultCategory, // 只有非預設才是真正自創
        );
      }

      await _loadData();
      await _checkMonthlyBudgetAfterSave(isIncome: tx.type == TransactionType.income);
      await NotificationService.instance.syncFromPreferences(); // ★ 退役 DailyNotificationService，改用朋友版
      // ★ 合併自朋友版(B 遊戲資金)：手動記帳→寵物代幣；並記入任務進度
          {
        final rewardMessage = await _grantGamificationRewards(
          entryMethod: 'manual',
          amount: tx.amount,
          isIncome: tx.type == TransactionType.income,
        );
        if (mounted && rewardMessage.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('記帳完成$rewardMessage'), duration: const Duration(milliseconds: 1500)),
          );
        }
      }

      // 在首頁直接秀出這句剛向 AI 要來的台詞
      String commentToShow = tx.note.isNotEmpty ? "${tx.note}\n$aiComment" : aiComment;
      if (_selectedIndex == 0) {
        _homeKey.currentState?.triggerAiComment(commentToShow);
      }
      return;
    }

    // 1. 寫入資料庫
    await DatabaseHelper.instance.insertTransaction(tx);

    // ★★★ 規則：手動記帳，觸發 isUserCreated: true，一律 1 次解鎖！★★★
    final name = tx.category.trim();
    if (name.isNotEmpty) {
      final dbType = tx.type == TransactionType.expense ? 'expense' : 'income';

      // ★★★ 修正：判斷手動記帳的分類是「預設子類」還是「自創分類」 ★★★
      bool isDefaultCategory = false;
      String foundMainCategory = name; // 預設用自己當主類

      _categoryData.forEach((key, value) {
        if ((value['subs'] as List).contains(name)) {
          isDefaultCategory = true;
          foundMainCategory = key; // 找到對應的老大 (例如: 飲食)
        }
      });

      // 預設子類 -> 解鎖老大(foundMainCategory)
      // 自創分類 -> 解鎖自己(name)
      String unlockName = isDefaultCategory ? foundMainCategory : name;

      await DatabaseHelper.instance.applyUnlockRuleForName(
        name: unlockName,
        type: dbType,
        customUnlockThreshold: 1,
        isUserCreated: !isDefaultCategory, // 只有非預設才是真正自創
      );
    }

    // 2. 重新讀取資料庫，確保 UI 同步 (加入朋友的防呆)
    await _loadData();
    await _checkMonthlyBudgetAfterSave(isIncome: tx.type == TransactionType.income);
    await NotificationService.instance.syncFromPreferences(); // ★ 退役 DailyNotificationService，改用朋友版
    // ★ 合併自朋友版(B 遊戲資金)：手動記帳→寵物代幣；並記入任務進度
        {
      final rewardMessage = await _grantGamificationRewards(
        entryMethod: 'manual',
        amount: tx.amount,
        isIncome: tx.type == TransactionType.income,
      );
      if (mounted && rewardMessage.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('記帳完成$rewardMessage'), duration: const Duration(milliseconds: 1500)),
        );
      }
    }

    // 3. 準備動物要講的話 (本地金句)
    // ★★★ 修改：傳入當前上場寵物，讓斷網金句也用「你選的那隻」講話，而非隨機 ★★★
    String localQuote = LocalAiService.getRandomComment(tx.category, petKey: _currentPetKey);
    String commentToShow = "";

    if (tx.note.isNotEmpty) {
      commentToShow = "${tx.note}\n$localQuote";
    } else {
      commentToShow = localQuote;
    }

    // 4. 觸發動物講話
    if (_selectedIndex == 0) {
      _homeKey.currentState?.triggerAiComment(commentToShow);
    }
  }

  // ★★★ 新增：處理刪除交易紀錄 (滑動刪除) ★★★
  Future<void> _deleteTransaction(String id) async {
    // ★ 解開註解：正式從資料庫刪除
    await DatabaseHelper.instance.deleteTransaction(int.parse(id));

    // 暫時先在畫面上移除，讓你立刻看到左滑刪除的效果
    setState(() {
      _transactions.removeWhere((tx) => tx.id == id);
    });
  }

  // ★★★ 新增：處理編輯交易紀錄 (滑動編輯) ★★★
  void _editTransaction(Transaction tx) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        return NewTransactionSheet(
          // ★ 解開註解：把舊資料傳入表單
          initialTransaction: tx,
          onAddTransaction: (updatedTx) async {
            // ★ 解開註解：呼叫更新並重新載入資料
            await DatabaseHelper.instance.updateTransaction(updatedTx);
            await _loadData();
          },
        );
      },
    );
  }

  void _onItemTapped(int index) {
    _loadRuntimeSettings();
    if (index == 0) {
      // ★ 合併自朋友版(C)：切回首頁時刷新旅遊/預設幣別顯示
      _refreshCurrencySettings();
      _homeKey.currentState?.reloadCurrencySettings();
    }
    setState(() {
      _selectedIndex = index;
    });
  }

  void _openAddTransactionSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        return NewTransactionSheet(onAddTransaction: _addTransaction);
      },
    );
  }

  void _navigateToPage(Widget page) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => page),
    );
  }

  // ★★★ 大富翁不再是 BottomNavigationBar 的 Tab，改為獨立全螢幕頁面 ★★★
  // ★★★ 新增：重讀「目前上場的寵物」。
  //     寵物頁是從大富翁頁 push 開啟的，返回時不會觸發 _onItemTapped，
  //     若不主動重讀，_currentPetKey 會停在舊的，導致 AI 分析動畫還是舊寵物。★★★
  Future<void> _refreshCurrentPetKey() async {
    final prefs = await SharedPreferences.getInstance();
    final key = prefs.getString('current_pet_key') ?? "dog";
    if (!mounted || key == _currentPetKey) return;
    setState(() {
      _currentPetKey = key;
    });
  }

  void _openPlayground() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const PlaygroundPage()),
    );
    // ★ 新增：從大富翁／寵物頁返回後重讀設定，讓上場寵物立即同步
    await _loadRuntimeSettings();
  }

  // ★★★ 新增：條件判斷觸發特定寵物動畫與文字 (16隻對應防呆映射) ★★★
  // ★★★ 新增：當前上場寵物的 emoji (跟 pet_page 的 16 隻一致)，給預算浮窗顯示用 ★★★
  // ★★★ 新增：從中文語音文字裡解析日期 (昨天/前天/大前天/X月X日/X月X號/X/X)，解析不到回 null ★★★
  DateTime? _parseChineseDateFromText(String text) {
    if (text.trim().isEmpty) return null;
    final now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);

    // 1) 相對日期詞 (先判斷「大前天」再判斷「前天」，避免被包含關係誤判)
    if (text.contains('大前天')) return today.subtract(const Duration(days: 3));
    if (text.contains('前天')) return today.subtract(const Duration(days: 2));
    if (text.contains('昨天')) return today.subtract(const Duration(days: 1));
    if (text.contains('今天')) return today;

    // 2) X月X日 / X月X號
    final m1 = RegExp(r'(\d{1,2})\s*月\s*(\d{1,2})\s*[日號]?').firstMatch(text);
    if (m1 != null) {
      final mo = int.tryParse(m1.group(1)!);
      final d = int.tryParse(m1.group(2)!);
      if (mo != null && d != null && mo >= 1 && mo <= 12 && d >= 1 && d <= 31) {
        return DateTime(now.year, mo, d);
      }
    }

    // 3) X/X 或 X-X (視為 月/日)
    final m2 = RegExp(r'(?<!\d)(\d{1,2})[\/-](\d{1,2})(?!\d)').firstMatch(text);
    if (m2 != null) {
      final mo = int.tryParse(m2.group(1)!);
      final d = int.tryParse(m2.group(2)!);
      if (mo != null && d != null && mo >= 1 && mo <= 12 && d >= 1 && d <= 31) {
        return DateTime(now.year, mo, d);
      }
    }

    return null;
  }

  String _getCurrentPetEmoji() {
    switch (_currentPetKey) {
      case 'dog': return '🐶';
      case 'cat': return '🐱';
      case 'parrot': return '🦜';
      case 'sloth': return '🦥';
      case 'fox': return '🦊';
      case 'cute_dog': return '🐕';
      case 'pomeranian': return '🐩';
    // ★★★ 修改：原本這幾隻用的是骨頭/腳印/愛心/火箭/沙漏等「非動物」emoji，
    //     改成對應的貓狗 emoji，視覺上一致一點。★★★
      case 'norm_dog': return '🦮';
      case 'wagging_dog': return '🐕';
      case 'lovely_cat': return '😻';
      case 'blue_cat': return '😼';
      case 'rocket_cat': return '😸';
      case 'loader_cat': return '🐈';
      case 'bear': return '🐻';
      case 'bee': return '🐝';
      case 'giraffe': return '🦒';
      default: return '🐶';
    }
  }

  Map<String, String> _getPetAnimationConfig() {
    String defaultAnimAsset = 'assets/animations/Dog.json';

    // 精準對應 16 隻寵物的動畫檔案
    switch (_currentPetKey) {
      case 'dog': defaultAnimAsset = 'assets/animations/Dog.json'; break;
      case 'cat': defaultAnimAsset = 'assets/animations/Cat.json'; break;
      case 'fox': defaultAnimAsset = 'assets/animations/Fox.json'; break;
      case 'parrot': defaultAnimAsset = 'assets/animations/Parrot.json'; break;
      case 'sloth': defaultAnimAsset = 'assets/animations/Sloth.json'; break;
      case 'cute_dog': defaultAnimAsset = 'assets/animations/Cute Doggy.json'; break;
      case 'pomeranian': defaultAnimAsset = 'assets/animations/Pomeranian Dog.json'; break;
      case 'norm_dog': defaultAnimAsset = 'assets/animations/Norm The Dog.json'; break;
      case 'wagging_dog': defaultAnimAsset = 'assets/animations/Wagging Dog.json'; break;
      case 'lovely_cat': defaultAnimAsset = 'assets/animations/Lovely cats.json'; break;
      case 'blue_cat': defaultAnimAsset = 'assets/animations/Blue Working Cat.json'; break;
      case 'rocket_cat': defaultAnimAsset = 'assets/animations/Cat in a rocket.json'; break;
      case 'loader_cat': defaultAnimAsset = 'assets/animations/Loader cat.json'; break;
      case 'bear': defaultAnimAsset = 'assets/animations/Bear Like.json'; break;
      case 'bee': defaultAnimAsset = 'assets/animations/Loading Flying Beee.json'; break;
      case 'giraffe': defaultAnimAsset = 'assets/animations/Petite girafe.json'; break;
      default: defaultAnimAsset = 'assets/animations/Dog.json'; break;
    }

    // ★★★ 最高優先級：每日第一筆開張大吉 ★★★
    if (_isFirstTransactionToday) {
      return {
        'asset': defaultAnimAsset,
        'text': '早安主人！今天第一筆帳幫你開張！'
      };
    }

    // 優先級 2：深夜時段 23:00~04:59
    final hour = DateTime.now().hour;
    if (hour >= 23 || hour < 5) {
      return {
        'asset': defaultAnimAsset,
        'text': '這麼晚還在花錢，勉強幫你記著。'
      };
    }

    // ★★★ 優先級 3 與 4 修正：靠 [MODE] 標籤百分百精準判斷 ★★★
    if (_pendingEntryMethod == 'scan') {
      // 如果回傳的字串包含 E_INVOICE_QR，代表它沒有呼叫 OCR，是直接抓出條碼
      if (_pendingRawInput != null && _pendingRawInput!.contains('[MODE] E_INVOICE_QR')) {
        return {
          'asset': defaultAnimAsset,
          'text': '呵呵，這種簡單的條碼，你的錢包沒有秘密...'
        };
      } else {
        // 否則，不管是傳統還是電子，只要是被相機 "拍照" (回傳了明細長文字)
        return {
          'asset': defaultAnimAsset,
          'text': '這張明細好複雜...慢慢算...'
        };
      }
    }

    // 優先級 5：語音輸入統一
    if (_pendingEntryMethod == 'voice') {
      return {
        'asset': defaultAnimAsset,
        'text': '聽到了！正在幫你翻譯成帳單...'
      };
    }

    // 防呆預設值
    return {
      'asset': defaultAnimAsset,
      'text': '寵物幫你算錢中，請稍候...'
    };
  }

  @override
  Widget build(BuildContext context) {
    final scanLabel = '掃描（${_scanMode == ScanMode.auto ? '自動' : '傳統'}）';

    return Stack(
      children: [
        Scaffold(
          body: IndexedStack(
            index: _selectedIndex,
            children: [
              // ★★★ 把剛寫好的回呼函式接上 HomePage ★★★
              _isAuthInitialized
                  ? HomePage(
                key: _homeKey,
                transactions: _transactions,
                onAiAnalyzeRequest: _handleVoiceAnalysis,
                onDeleteTransaction: _deleteTransaction,
                onEditTransaction: _editTransaction,
                defaultCurrencyCode: _currencyCode,
              )
                  : const Center(
                child: CircularProgressIndicator(),
              ),
              const SettingPage(),
            ],
          ),

          bottomNavigationBar: Container(
            padding: const EdgeInsets.only(bottom: 16.0, top: 8.0),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.2),
                  spreadRadius: 2,
                  blurRadius: 8,
                  offset: const Offset(0, -3),
                ),
              ],
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildActionButton(Icons.add_circle, '記帳', _openAddTransactionSheet),
                    _buildActionButton(Icons.mic, '語音', _onVoiceBtnPressed),
                    _buildActionButton(Icons.qr_code_scanner, scanLabel, _goScan),
                    _buildActionButton(Icons.casino_rounded, '大富翁', _openPlayground),
                  ],
                ),
                const SizedBox(height: 8),

                BottomNavigationBar(
                  items: const <BottomNavigationBarItem>[
                    BottomNavigationBarItem(
                      icon: Icon(Icons.home_rounded),
                      label: 'Home',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.settings_rounded),
                      label: 'Settings',
                    ),
                  ],
                  currentIndex: _selectedIndex,
                  selectedItemColor: const Color(0xFFFF8FAB),
                  unselectedItemColor: Colors.grey.shade400,
                  onTap: _onItemTapped,
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  type: BottomNavigationBarType.fixed,
                ),
              ],
            ),
          ),
        ),

        // ★★★ 呼叫你原本超可愛的餵食動畫 Overlay ★★★
        if (_isAnalyzing)
          Builder(
              builder: (context) {
                // 在這裡呼叫我們新寫的判斷邏輯
                final animConfig = _getPetAnimationConfig();
                return Container(
                  color: Colors.black.withOpacity(0.85), // 深色半透明遮罩
                  child: Center(
                    child: _FeedingAnimationOverlay(
                      lottieAsset: animConfig['asset']!,
                      invoiceAsset: _invoiceIconPath,
                      loadingText: animConfig['text']!, // 傳入動態文字
                    ),
                  ),
                );
              }
          ),
      ],
    );
  }

  Widget _buildActionButton(IconData icon, String label, VoidCallback onPressed) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(30),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 46, height: 46,
              decoration: BoxDecoration(
                color: const Color(0xFFFFE4EE),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFFF8FAB).withOpacity(0.5), width: 1.5),
              ),
              child: Icon(icon, size: 24, color: const Color(0xFFFF8FAB)),
            ),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFFFF8FAB), fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

// ==============================================================
// ★★★ 保留你的：循環播放發票飛入的動畫 Overlay ★★★
// ==============================================================
class _FeedingAnimationOverlay extends StatefulWidget {
  final String lottieAsset;
  final String invoiceAsset;
  final String loadingText; // ★★★ 新增：接收動態文字 ★★★

  const _FeedingAnimationOverlay({
    required this.lottieAsset,
    required this.invoiceAsset,
    required this.loadingText, // ★★★ 新增：接收動態文字 ★★★
  });

  @override
  State<_FeedingAnimationOverlay> createState() => _FeedingAnimationOverlayState();
}

class _FeedingAnimationOverlayState extends State<_FeedingAnimationOverlay> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // 設定動畫控制器，循環播放 (Duration 為發票飛一次的時間)
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2), // 2秒飛一次
    )..repeat(); // 讓它一直重複
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 250,
          height: 250,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 1. 底層：Lottie 動物動畫
              if (widget.lottieAsset.isNotEmpty)
                Positioned.fill(
                  child: Lottie.asset(
                    widget.lottieAsset,
                    fit: BoxFit.contain,
                  ),
                )
              else
                const CircularProgressIndicator(color: Colors.white),

              // 2. 上層：循環飛入的發票
              AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  // 計算動畫值：從底端 (-100) 飛到嘴邊 (60)
                  // 使用 Curves.easeInOut 讓飛行更順暢
                  final curvedValue = Curves.easeInOut.transform(_controller.value);
                  final bottomPos = -100 + (160 * curvedValue);

                  // 在快要結束時 (0.8~1.0) 讓發票變透明，看起來像被吃掉
                  final opacity = _controller.value > 0.8 ? (1.0 - _controller.value) * 5 : 1.0;

                  return Positioned(
                    bottom: bottomPos,
                    child: Opacity(
                      opacity: opacity.clamp(0.0, 1.0),
                      child: child!,
                    ),
                  );
                },
                child: Image.asset(
                  widget.invoiceAsset,
                  width: 60,
                  height: 60,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // ★★★ 修正：改用 widget.loadingText 動態顯示文字，並置中縮小字體 ★★★
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0),
          child: Text(
            widget.loadingText,
            textAlign: TextAlign.center, // 讓多行文字置中，看起來更整齊
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16, // 把字體從 18 縮小到 16
              fontWeight: FontWeight.bold,
              decoration: TextDecoration.none, // 關鍵：移除黃色底線
            ),
          ),
        ),
      ],
    );
  }
}