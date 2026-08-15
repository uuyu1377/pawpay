import 'package:flutter/material.dart';
import '../models/transaction_model.dart';

// ★★★ 來自合併：引入 DatabaseHelper，這樣才能讀取動態分類
import '../services/database_helper.dart';

/// 分類選擇頁：
/// 終極修復版：收入自創分類現在也會正確顯示在網格上，不再被藏起來
class TypePage extends StatefulWidget {
  final TransactionType transactionType;

  const TypePage({super.key, required this.transactionType});

  @override
  State<TypePage> createState() => _TypePageState();
}

class _TypePageState extends State<TypePage> {
  late Future<List<Map<String, dynamic>>> _future;

  // ★★★ 新增：自訂圖示快取對照表 (把資料庫的字串轉回圖示) ★★★
  final Map<String, String> _categoryIconKeys = {};

  // ★★★ 新增：預設的子分類清單，確保沒記帳前也能選子分類 ★★★
  final Map<String, List<String>> _defaultExpenseSubs = {
    '飲食': ['早餐', '午餐', '晚餐', '飲料/咖啡', '宵夜', '零食', '外送', '聚餐'],
    '交通': ['公車', '捷運', '火車/高鐵', '計程車/Uber', '加油', '停車費', '車輛維修'],
    '生活用品': ['超市採買', '衛生紙/日用品', '五金百貨', '洗衣/清潔'],
    '社交': ['請客', '社交應酬', '派對活動'],
    '娛樂': ['電影', 'KTV', '展覽/表演', '書籍/雜誌', '遊戲', '串流影音'],
    '通訊網路': ['手機費', '網路費'],
    '服飾美容': ['衣服/鞋子', '配件', '化妝品/保養品', '剪髮/美容', '美甲/按摩'],
    '醫療健康': ['看診掛號', '藥品', '保健食品', '運動/健身房'],
    '住房': ['房租', '水電費', '瓦斯費', '管理費'],
    '其他支出': ['雜費', '手續費', '捐款', '其他'],
    '學費與教材': ['學雜費', '參考書/課本', '補習班', '影印費', '文具'],
    '線上訂閱': ['Netflix', 'Spotify', 'YouTube Premium', 'iCloud/Google Drive', 'Disney+'],
    '小確幸': ['扭蛋', '盲盒', '公仔', '遊戲課金', '周邊商品'],
    '禮物與送禮': ['生日禮物', '節日送禮', '伴手禮'],
    '不見了': ['現金遺失', '物品遺失重買', '錢包弄丟'],
    '投資理財': ['股票買入', '基金申購', '定期定額扣款'],
    '家具家電': ['大型家具', '小家電', '廚房用具', '居家佈置'],
    '房貸與修繕': ['房屋貸款', '房屋修繕', '裝潢費用', '房屋稅/地價稅'],
    '小孩教育': ['學費', '安親班', '才藝課', '尿布奶粉', '玩具/童書'],
    '保險費用': ['壽險', '醫療險', '車險', '儲蓄險'],
    '長輩支出': ['孝親費', '長輩醫療', '長輩看護'],
    '家庭旅遊': ['機票住宿', '旅行團費', '全家出遊餐飲'],
  };

  final Map<String, List<String>> _defaultIncomeSubs = {
    '薪水': ['正職薪資', '年終獎金', '加班費'],
    '投資收益': ['股票股利', '基金配息', '價差獲利'],
    '禮金': ['紅包收入', '三節禮金'],
    '零用錢': ['父母給的', '長輩給的'],
    '打工收入': ['家教費', '工讀薪資', '校內工讀'],
    '獎學金': ['校內獎學金', '系上獎學金', '校外補助'],
    '投資獲利': ['短期操作獲利', '虛擬貨幣獲利'],
    '被動收入': ['房租收入', '銀行利息', '股息收入'],
    '退稅/補助': ['所得稅退稅', '育兒津貼', '租屋補助', '政府補助'],
    '其他收入': ['二手拍賣', '發票中獎', '退款'],
  };

  // ★★★ 新增：提供給使用者選擇的豐富圖示清單 ★★★
  final Map<String, IconData> _selectableIcons = {
    'star': Icons.star_rounded,
    'favorite': Icons.favorite_rounded,
    'shopping_cart': Icons.shopping_cart_rounded,
    'local_mall': Icons.local_mall_rounded,
    'card_giftcard': Icons.card_giftcard_rounded,
    'fastfood': Icons.fastfood_rounded,
    'local_cafe': Icons.local_cafe_rounded,
    'restaurant': Icons.restaurant_rounded,
    'icecream': Icons.icecream_rounded,
    'directions_car': Icons.directions_car_rounded,
    'train': Icons.train_rounded,
    'flight': Icons.flight_rounded,
    'local_gas_station': Icons.local_gas_station_rounded,
    'two_wheeler': Icons.two_wheeler_rounded,
    'medical_services': Icons.medical_services_rounded,
    'fitness_center': Icons.fitness_center_rounded,
    'pets': Icons.pets_rounded,
    'home': Icons.home_rounded,
    'chair': Icons.chair_rounded,
    'cleaning_services': Icons.cleaning_services_rounded,
    'sports_esports': Icons.sports_esports_rounded,
    'movie': Icons.movie_rounded,
    'music_note': Icons.music_note_rounded,
    'palette': Icons.palette_rounded,
    'camera_alt': Icons.camera_alt_rounded,
    'school': Icons.school_rounded,
    'menu_book': Icons.menu_book_rounded,
    'phone_iphone': Icons.phone_iphone_rounded,
    'work': Icons.work_rounded,
    'attach_money': Icons.attach_money_rounded,
    'savings': Icons.savings_rounded,
    'account_balance': Icons.account_balance_rounded,
    'groups': Icons.groups_rounded,
    'bolt': Icons.bolt_rounded,
    'lightbulb': Icons.lightbulb_rounded,
    'child_friendly': Icons.child_friendly_rounded,
  };

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final dbType = widget.transactionType == TransactionType.expense ? 'expense' : 'income';
    final rows = await DatabaseHelper.instance.getPickerCategories(type: dbType);

    // ★★★ 新增：把資料庫撈出來的 icon_key 存進快取字典 ★★★
    for (var row in rows) {
      if (row['icon_key'] != null && row['icon_key'].toString().isNotEmpty) {
        _categoryIconKeys[row['name'].toString()] = row['icon_key'].toString();
      }
    }

    return rows;
  }

  Future<void> _selectAndClose(String name) async {
    final icon = _iconForCategory(name);
    if (!mounted) return;
    Navigator.of(context).pop({'name': name, 'icon': icon});
  }

  // ★★★ 修改：升級新增自訂分類 (方案二：限制高度的圖示選擇區 + 滿版寬度) ★★★
  void _showAddCustomCategoryDialog(BuildContext context) {
    final TextEditingController _customCatController = TextEditingController();
    String _selectedIconKey = 'star'; // 預設選中星星

    showDialog(
      context: context,
      builder: (ctx) {
        // 使用 StatefulBuilder 來讓對話框內的圖示選擇能即時變色
        return StatefulBuilder(
            builder: (context, setStateDialog) {
              return AlertDialog(
                title: const Text("新增自訂分類"),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _customCatController,
                        decoration: const InputDecoration(
                          labelText: "分類名稱",
                          hintText: "例如：iphone、公仔...",
                          border: OutlineInputBorder(),
                        ),
                        autofocus: true,
                      ),
                      const SizedBox(height: 16),
                      const Text("選擇圖示", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87)),
                      const SizedBox(height: 10),
                      // ★★★ 方案二實作：限制高度的捲動方塊 + 強制左右撐滿 + 圖示放大 ★★★
                      Container(
                        width: double.infinity, // 強制寬度與上方輸入框切齊
                        height: 140, // ★★★ 微調高度，適應放大的圖示 ★★★
                        decoration: BoxDecoration(
                          color: Colors.grey[50], // 淡淡的底色區分區塊
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        padding: const EdgeInsets.all(8),
                        child: SingleChildScrollView(
                          child: Wrap(
                            alignment: WrapAlignment.center, // ★★★ 新增：讓圖示整體置中對齊 ★★★
                            spacing: 10, // ★★★ 稍微拉開間距 ★★★
                            runSpacing: 12, // ★★★ 稍微拉開間距 ★★★
                            children: _selectableIcons.entries.map((entry) {
                              final isSelected = entry.key == _selectedIconKey;
                              return InkWell(
                                onTap: () {
                                  setStateDialog(() {
                                    _selectedIconKey = entry.key;
                                  });
                                },
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  padding: const EdgeInsets.all(8), // ★★★ 內邊距稍微加大 ★★★
                                  decoration: BoxDecoration(
                                    color: isSelected ? Colors.blueAccent : Colors.transparent,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    entry.value,
                                    color: isSelected ? Colors.white : Colors.grey[600],
                                    size: 30, // ★★★ 圖示等比例放大 ★★★
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
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
                    onPressed: () async {
                      final newName = _customCatController.text.trim();
                      if (newName.isNotEmpty) {
                        final dbType = widget.transactionType == TransactionType.expense ? 'expense' : 'income';
                        // ★★★ 將選中的 icon_key 存入資料庫 ★★★
                        await DatabaseHelper.instance.addNewCategory(newName, dbType, 0, iconKey: _selectedIconKey);
                        Navigator.of(ctx).pop();
                        if (mounted) {
                          // 更新快取字典，讓剛創好的分類可以馬上顯示正確圖示
                          _categoryIconKeys[newName] = _selectedIconKey;
                          await _selectAndClose(newName);
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white),
                    child: const Text("新增"),
                  ),
                ],
              );
            }
        );
      },
    );
  }

  // ★★★ 核心修復：收入與支出的邏輯現在完全一致 ★★★
  String? _inferMain(String name, List<String> mainNames) {
    // 1. 本身就是主分類
    if (mainNames.contains(name)) return name;

    // 2. ===== Income (收入) =====
    if (widget.transactionType == TransactionType.income) {
      // 主要收入 (薪水)
      if (name == '正職薪資' || name == '年終獎金' || name == '加班費') return '薪水';

      // 投資與禮金 (投資收益, 禮金)
      if (name == '股票股利' || name == '基金配息' || name == '價差獲利') return '投資收益';
      if (name == '紅包收入' || name == '三節禮金') return '禮金';

      // 學生專屬
      if (name == '父母給的' || name == '長輩給的') return '零用錢';
      if (name == '家教費' || name == '工讀薪資' || name == '校內工讀') return '打工收入';
      if (name == '校內獎學金' || name == '系上獎學金' || name == '校外補助') return '獎學金';

      // 上班族專屬
      if (name == '短期操作獲利' || name == '虛擬貨幣獲利') return '投資獲利';

      // 家庭專屬 (被動與補助)
      if (name == '房租收入' || name == '銀行利息' || name == '股息收入') return '被動收入';
      if (name == '所得稅退稅' || name == '育兒津貼' || name == '租屋補助' || name == '政府補助') return '退稅/補助';

      // 其他 (解決預設分類問題)
      if (name == '其他收入' || name == '二手拍賣' || name == '發票中獎' || name == '退款') return '其他收入';

      // ★★★ 關鍵修改：如果是未知的自創收入，回傳 null (讓它變成孤兒顯示在網格)，而不是強制歸類到 "其他收入"
      return null;
    }

    // 3. ===== Expense (支出) =====

    // --- 通用分類 ---
    // 飲食
    if (['早餐', '午餐', '晚餐', '飲料/咖啡', '宵夜', '零食', '外送', '聚餐'].contains(name)) return '飲食';

    // 交通
    if (['公車', '捷運', '火車/高鐵', '計程車/Uber', '加油', '停車費', '車輛維修'].contains(name)) return '交通';

    // 生活用品
    if (['超市採買', '衛生紙/日用品', '五金百貨', '洗衣/清潔'].contains(name)) return '生活用品';

    // 社交
    if (['請客', '社交應酬', '派對活動'].contains(name)) return '社交';

    // 娛樂
    if (['電影', 'KTV', '展覽/表演', '書籍/雜誌', '遊戲', '串流影音'].contains(name)) return '娛樂';

    // 通訊網路
    if (['手機費', '網路費'].contains(name)) return '通訊網路';

    // 服飾美容
    if (['衣服/鞋子', '配件', '化妝品/保養品', '剪髮/美容', '美甲/按摩'].contains(name)) return '服飾美容';

    // 醫療健康
    if (['看診掛號', '藥品', '保健食品', '運動/健身房'].contains(name)) return '醫療健康';

    // 住房
    if (['房租', '水電費', '瓦斯費', '管理費'].contains(name)) return '住房';

    // 其他支出
    if (['雜費', '手續費', '捐款'].contains(name) || name == '其他') return '其他支出';

    // --- 學生專屬 ---
    if (['學雜費', '參考書/課本', '補習班', '影印費', '文具'].contains(name)) return '學費與教材';
    if (['Netflix', 'Spotify', 'YouTube Premium', 'iCloud/Google Drive', 'Disney+'].contains(name)) return '線上訂閱';
    if (['扭蛋', '盲盒', '公仔', '遊戲課金', '周邊商品'].contains(name)) return '小確幸';
    if (['生日禮物', '節日送禮', '伴手禮'].contains(name)) return '禮物與送禮';
    if (['現金遺失', '物品遺失重買', '錢包弄丟'].contains(name)) return '不見了';

    // --- 上班族專屬 ---
    if (['股票買入', '基金申購', '定期定額扣款'].contains(name)) return '投資理財';
    if (['大型家具', '小家電', '廚房用具', '居家佈置'].contains(name)) return '家具家電';

    // --- 家庭專屬 ---
    if (['房屋貸款', '房屋修繕', '裝潢費用', '房屋稅/地價稅'].contains(name)) return '房貸與修繕';
    if (['學費', '安親班', '才藝課', '尿布奶粉', '玩具/童書'].contains(name)) return '小孩教育';
    if (['壽險', '醫療險', '車險', '儲蓄險'].contains(name)) return '保險費用';
    if (['孝親費', '長輩醫療', '長輩看護'].contains(name)) return '長輩支出';
    if (['機票住宿', '旅行團費', '全家出遊餐飲'].contains(name)) return '家庭旅遊';

    // 支出未知的也回傳 null
    return null;
  }

  // ★★★ 顯示子分類選擇 BottomSheet ★★★
  Future<String?> _openPickerSheet({required String title, required List<String> names}) async {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        String q = '';
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final filtered = q.trim().isEmpty
                ? names
                : names.where((n) => n.toLowerCase().contains(q.trim().toLowerCase())).toList(growable: false);

            return SafeArea(
              child: DraggableScrollableSheet(
                expand: false,
                initialChildSize: 0.85,
                minChildSize: 0.5,
                maxChildSize: 0.95,
                builder: (context, scrollController) {
                  return Padding(
                    padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
                    child: Column(
                      children: [
                        const SizedBox(height: 8),
                        Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(999))),
                        const SizedBox(height: 12),
                        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: TextField(
                            decoration: InputDecoration(
                              prefixIcon: const Icon(Icons.search_rounded),
                              hintText: '搜尋分類…',
                              filled: true,
                              fillColor: Colors.grey[100],
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                            ),
                            onChanged: (v) => setSheetState(() => q = v),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: GridView.builder(
                            controller: scrollController,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 4,
                              childAspectRatio: 0.75,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                            ),
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final name = filtered[index];
                              final icon = _iconForCategory(name);
                              return InkWell(
                                onTap: () => Navigator.of(sheetContext).pop(name),
                                borderRadius: BorderRadius.circular(16),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(15)),
                                      child: Icon(icon, color: Colors.blueAccent, size: 28),
                                    ),
                                    const SizedBox(height: 6),
                                    Flexible(
                                      child: Text(
                                        name,
                                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                                        textAlign: TextAlign.center,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  // ★★★ 圖示完整對應 ★★★
  IconData _iconForCategory(String name) {
    // ★★★ 新增：優先檢查使用者自訂圖示 ★★★
    if (_categoryIconKeys.containsKey(name)) {
      final key = _categoryIconKeys[name];
      if (_selectableIcons.containsKey(key)) {
        return _selectableIcons[key]!;
      }
    }

    // ---- Income ----
    if (widget.transactionType == TransactionType.income) {
      if (name == '薪水' || name == '正職薪資' || name == '年終獎金' || name == '加班費') return Icons.attach_money_rounded;
      if (name == '投資收益' || name == '股票股利' || name == '基金配息' || name == '價差獲利' || name == '投資獲利' || name == '短期操作獲利' || name == '虛擬貨幣獲利') return Icons.trending_up_rounded;
      if (name == '禮金' || name == '紅包收入' || name == '三節禮金') return Icons.card_giftcard_rounded;
      if (name == '零用錢' || name == '父母給的' || name == '長輩給的') return Icons.savings_rounded;
      if (name == '打工收入' || name == '家教費' || name == '工讀薪資' || name == '校內工讀') return Icons.work_history_rounded;
      if (name == '獎學金' || name == '校內獎學金' || name == '系上獎學金' || name == '校外補助') return Icons.school_rounded;
      if (name == '被動收入' || name == '房租收入' || name == '銀行利息' || name == '股息收入') return Icons.account_balance_rounded;
      if (name == '退稅/補助' || name == '所得稅退稅' || name == '育兒津貼' || name == '租屋補助' || name == '政府補助') return Icons.payments_rounded;
      if (name == '其他收入' || name == '二手拍賣' || name == '發票中獎' || name == '退款') return Icons.reply_rounded;

      // ★★★ 關鍵修改：如果上面都沒對到 (自創收入)，回傳 ... 圖示，而不是 $ 符號
      return Icons.more_horiz_rounded;
    }

    // ---- Expense Main ----
    if (name == '飲食') return Icons.fastfood_rounded;
    if (name == '交通') return Icons.directions_bus_rounded;
    if (name == '生活用品') return Icons.cleaning_services_rounded;
    if (name == '社交') return Icons.groups_rounded;
    if (name == '娛樂') return Icons.sports_esports_rounded;
    if (name == '通訊網路') return Icons.wifi_rounded;
    if (name == '服飾美容') return Icons.checkroom_rounded;
    if (name == '醫療健康') return Icons.medical_services_rounded;
    if (name == '住房') return Icons.home_rounded;
    if (name == '其他支出') return Icons.more_horiz_rounded;

    if (name == '學費與教材') return Icons.school_rounded;
    if (name == '線上訂閱') return Icons.subscriptions_rounded;
    if (name == '小確幸') return Icons.redeem_rounded;
    if (name == '禮物與送禮') return Icons.card_giftcard_rounded;
    if (name == '不見了') return Icons.report_problem_rounded;

    if (name == '投資理財') return Icons.trending_up_rounded;
    if (name == '家具家電') return Icons.chair_rounded;

    if (name == '房貸與修繕') return Icons.house_rounded;
    if (name == '小孩教育') return Icons.child_care_rounded;
    if (name == '保險費用') return Icons.verified_user_rounded;
    if (name == '長輩支出') return Icons.elderly_rounded;
    if (name == '家庭旅遊') return Icons.flight_rounded;

    // ---- Expense Sub ----
    // 飲食
    if (name == '早餐') return Icons.bakery_dining_rounded;
    if (name == '午餐') return Icons.rice_bowl_rounded;
    if (name == '晚餐') return Icons.dinner_dining_rounded;
    if (name == '飲料/咖啡') return Icons.local_cafe_rounded;
    if (name == '宵夜') return Icons.nightlife_rounded;
    if (name == '零食') return Icons.cookie_rounded;
    if (name == '外送') return Icons.delivery_dining_rounded;
    if (name == '聚餐') return Icons.restaurant_rounded;

    // 交通
    if (name == '公車') return Icons.train_rounded;
    if (name == '捷運') return Icons.train_rounded;
    if (name == '火車/高鐵') return Icons.train_rounded;
    if (name == '計程車/Uber') return Icons.local_taxi_rounded;
    if (name == '加油') return Icons.local_gas_station_rounded;
    if (name == '停車費') return Icons.local_parking_rounded;
    if (name == '車輛維修') return Icons.build_rounded;

    // 生活用品
    if (name == '超市採買') return Icons.shopping_cart_rounded;
    if (name == '衛生紙/日用品') return Icons.local_mall_rounded;
    if (name == '五金百貨') return Icons.hardware_rounded;
    if (name == '洗衣/清潔') return Icons.cleaning_services_rounded;

    // 社交娛樂
    if (name == '請客') return Icons.groups_rounded;
    if (name == '社交應酬') return Icons.groups_rounded;
    if (name == '派對活動') return Icons.groups_rounded;
    if (name == '電影') return Icons.movie_rounded;
    if (name == 'KTV') return Icons.mic_rounded;
    if (name == '展覽/表演') return Icons.movie_rounded;
    if (name == '書籍/雜誌') return Icons.menu_book_rounded;
    if (name == '遊戲') return Icons.sports_esports_rounded;
    if (name == '串流影音') return Icons.subscriptions_rounded;
    if (name == 'Netflix') return Icons.subscriptions_rounded;
    if (name == 'Spotify') return Icons.subscriptions_rounded;
    if (name == 'YouTube Premium') return Icons.subscriptions_rounded;
    if (name == 'Disney+') return Icons.subscriptions_rounded;

    // 通訊與服飾
    if (name == '手機費') return Icons.wifi_rounded;
    if (name == '網路費') return Icons.wifi_rounded;
    if (name == '衣服/鞋子') return Icons.checkroom_rounded;
    if (name == '配件') return Icons.checkroom_rounded;
    if (name == '化妝品/保養品') return Icons.face_retouching_natural_rounded;
    if (name == '剪髮/美容') return Icons.face_retouching_natural_rounded;
    if (name == '美甲/按摩') return Icons.face_retouching_natural_rounded;

    // 醫療與居住
    if (name == '看診掛號') return Icons.medical_services_rounded;
    if (name == '藥品') return Icons.medical_services_rounded;
    if (name == '保健食品') return Icons.medical_services_rounded;
    if (name == '運動/健身房') return Icons.fitness_center_rounded;
    if (name == '房租') return Icons.home_rounded;
    if (name == '水電費') return Icons.lightbulb_rounded;
    if (name == '瓦斯費') return Icons.lightbulb_rounded;
    if (name == '管理費') return Icons.home_rounded;

    // 其他
    if (name == '雜費' || name == '手續費' || name == '捐款' || name == '其他') return Icons.more_horiz_rounded;

    // 學生專屬
    if (name == '學雜費') return Icons.account_balance_rounded;
    if (name == '參考書/課本') return Icons.book_rounded;
    if (name == '補習班') return Icons.school_rounded;
    if (name == '影印費') return Icons.print_rounded;
    if (name == '文具') return Icons.book_rounded;
    if (name == 'iCloud/Google Drive') return Icons.cloud_rounded;
    if (name == '扭蛋') return Icons.redeem_rounded;
    if (name == '盲盒') return Icons.redeem_rounded;
    if (name == '公仔') return Icons.redeem_rounded;
    if (name == '遊戲課金') return Icons.sports_esports_rounded;
    if (name == '周邊商品') return Icons.redeem_rounded;
    if (name == '生日禮物') return Icons.card_giftcard_rounded;
    if (name == '節日送禮') return Icons.card_giftcard_rounded;
    if (name == '伴手禮') return Icons.card_giftcard_rounded;
    if (name == '現金遺失') return Icons.report_problem_rounded;
    if (name == '物品遺失重買') return Icons.report_problem_rounded;
    if (name == '錢包弄丟') return Icons.report_problem_rounded;

    // 上班族專屬
    if (name == '股票買入') return Icons.trending_up_rounded;
    if (name == '基金申購') return Icons.trending_up_rounded;
    if (name == '定期定額扣款') return Icons.trending_up_rounded;
    if (name == '大型家具') return Icons.chair_rounded;
    if (name == '小家電') return Icons.chair_rounded;
    if (name == '廚房用具') return Icons.chair_rounded;
    if (name == '居家佈置') return Icons.chair_rounded;

    // 家庭專屬
    if (name == '房屋貸款') return Icons.house_rounded;
    if (name == '房屋修繕') return Icons.house_rounded;
    if (name == '裝潢費用') return Icons.house_rounded;
    if (name == '房屋稅/地價稅') return Icons.house_rounded;
    if (name == '學費') return Icons.school_rounded;
    if (name == '安親班') return Icons.palette_rounded;
    if (name == '才藝課') return Icons.palette_rounded;
    if (name == '尿布奶粉') return Icons.child_friendly_rounded;
    if (name == '玩具/童書') return Icons.child_friendly_rounded;
    if (name == '壽險') return Icons.verified_user_rounded;
    if (name == '醫療險') return Icons.verified_user_rounded;
    if (name == '車險') return Icons.verified_user_rounded;
    if (name == '儲蓄險') return Icons.verified_user_rounded;
    if (name == '孝親費') return Icons.elderly_rounded;
    if (name == '長輩醫療') return Icons.elderly_rounded;
    if (name == '長輩看護') return Icons.elderly_rounded;
    if (name == '機票住宿') return Icons.flight_rounded;
    if (name == '旅行團費') return Icons.flight_rounded;
    if (name == '全家出遊餐飲') return Icons.flight_rounded;

    // 自創的都用 ...
    return Icons.more_horiz_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.transactionType == TransactionType.expense ? '選擇支出類別' : '選擇收入類別';
    final dbType = widget.transactionType == TransactionType.expense ? 'expense' : 'income';

    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: '搜尋全部分類',
            icon: const Icon(Icons.search_rounded),
            onPressed: () async {
              final rows = await _future;
              final all = rows.map((e) => (e['name'] ?? '').toString()).where((s) => s.trim().isNotEmpty).toSet().toList(growable: true);
              all.sort();
              final picked = await _openPickerSheet(title: '搜尋全部分類', names: all);
              if (picked != null) {
                await _selectAndClose(picked);
              }
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.blueAccent,
        child: const Icon(Icons.add, color: Colors.white),
        onPressed: () {
          _showAddCustomCategoryDialog(context);
        },
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('載入失敗：${snap.error}', style: const TextStyle(color: Colors.red)));
          }
          final rows = snap.data ?? const [];
          if (rows.isEmpty) return const Center(child: Text('目前沒有可選分類'));

          final mainNames = DatabaseHelper.instance.getMainNamesForType(dbType);
          final mainSet = mainNames.toSet();

          final allNames = rows
              .map((e) => (e['name'] ?? '').toString())
              .where((s) => s.trim().isNotEmpty)
              .toSet()
              .toList(growable: true);

          final grouped = <String, List<String>>{};
          final orphans = <String>[];

          // ★★★ 新增：先載入完整的預設子分類清單 ★★★
          final defaultSubs = dbType == 'expense' ? _defaultExpenseSubs : _defaultIncomeSubs;
          for (final m in mainNames) {
            grouped[m] = List<String>.from(defaultSubs[m] ?? []);
          }

          for (final n in allNames) {
            final main = _inferMain(n, mainNames);

            if (main != null) {
              if (!grouped.containsKey(main)) grouped[main] = <String>[];
              // ★★★ 修正：避免子分類重複 ★★★
              if (!mainSet.contains(n) && !grouped[main]!.contains(n)) {
                grouped[main]!.add(n);
              }
            } else {
              // ★★★ 修正：避免孤兒重複 ★★★
              if (!orphans.contains(n)) {
                orphans.add(n);
              }
            }
          }

          final mains = <String>[];
          for (final m in mainNames) {
            if (allNames.contains(m) || (grouped.containsKey(m) && grouped[m]!.isNotEmpty)) {
              mains.add(m);
            }
          }
          orphans.sort();
          mains.addAll(orphans);

          for (final k in grouped.keys) {
            grouped[k]!.sort();
          }

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                child: Text(
                  '提示：先選主類，再挑子類。右上角可搜尋。',
                  style: TextStyle(color: Colors.grey[700], fontSize: 12.5),
                  textAlign: TextAlign.center,
                ),
              ),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    childAspectRatio: 0.75,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: mains.length,
                  itemBuilder: (context, index) {
                    final name = mains[index];
                    final icon = _iconForCategory(name);
                    final subs = grouped[name] ?? const <String>[];

                    return InkWell(
                      onTap: () async {
                        if (subs.isEmpty) {
                          await _selectAndClose(name);
                          return;
                        }

                        final candidates = <String>[name, ...subs];
                        final picked = await _openPickerSheet(title: '$name｜選擇子類', names: candidates);
                        if (picked != null) {
                          await _selectAndClose(picked);
                        }
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(15)),
                            child: Icon(icon, color: Colors.blueAccent, size: 28),
                          ),
                          const SizedBox(height: 6),
                          Flexible(
                            child: Text(
                              name,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}