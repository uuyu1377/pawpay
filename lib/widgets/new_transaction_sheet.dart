import 'dart:async'; // 用於 Timer (僅用於飛入動畫)
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 用於 HapticFeedback
import 'package:intl/intl.dart';
// 🔥 音效套件
import 'package:audioplayers/audioplayers.dart';

// 使用相對路徑匯入
import '../models/transaction_model.dart';
import '../pages/type_page.dart';
import '../services/currency_service.dart';

class NewTransactionSheet extends StatefulWidget {
  final Function(Transaction) onAddTransaction;
  // ★★★ 新增：接收要編輯的舊紀錄 (如果是新增記帳，這個值會是 null) ★★★
  final Transaction? initialTransaction;

  const NewTransactionSheet({
    super.key,
    required this.onAddTransaction,
    this.initialTransaction, // ★★★ 新增 ★★★
  });

  @override
  State<NewTransactionSheet> createState() => _NewTransactionSheetState();
}

class _NewTransactionSheetState extends State<NewTransactionSheet> with TickerProviderStateMixin {
  // 1. 狀態變數
  TransactionType _selectedType = TransactionType.expense;
  final _noteController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  String _selectedCategory = '飲食';
  IconData _selectedIcon = Icons.fastfood_rounded;
  String _currencyCode = CurrencyService.defaultCode;
  bool _isForeignCard = false;
  double _foreignFeeRate = 0.015;
  ExchangeRateQuote? _exchangeQuote;
  bool _isLoadingExchangeRate = false;
  String? _exchangeRateError;
  bool _isSubmitting = false;

  // 2. 金額與輸入法變數
  double _totalAmount = 0;
  final List<double> _history = [];

  // 模式切換開關
  bool _isNumpadMode = false;
  String _numpadString = '0';

  // 拖曳數鈔專用變數
  double _dragAccumulator = 0.0;

  // 3. 音效
  final AudioPlayer _audioPlayer = AudioPlayer();

  // 4. 動畫相關
  final List<FlyingItem> _flyingItems = [];
  final GlobalKey _targetKey = GlobalKey();

  // ★★★ 新增：初始化時判斷是否有傳入舊資料 (編輯模式) ★★★
  @override
  void initState() {
    super.initState();
    if (widget.initialTransaction != null) {
      final tx = widget.initialTransaction!;
      _selectedType = tx.type;
      _noteController.text = tx.note;
      _selectedDate = tx.date;
      _selectedCategory = tx.category;
      _selectedIcon = tx.categoryIcon;
      _totalAmount = tx.originalAmount; // ★ 合併自朋友版(C)：編輯時顯示原始金額（原始幣別）
      _numpadString = _formatAmount(_totalAmount);
      _currencyCode = tx.currency.trim().isEmpty ? CurrencyService.defaultCode : tx.currency.trim();
      _isForeignCard = tx.isForeignCard;
      if (tx.foreignFeeRate > 0) _foreignFeeRate = tx.foreignFeeRate;
      _refreshExchangeQuote();
    } else {
      _loadDefaultCurrency();
    }
  }

  Future<void> _loadDefaultCurrency() async {
    // ★ 合併自朋友版(C)：新記帳預設用「當前有效幣別」（旅行期間即旅行幣別）
    final code = await CurrencyService.instance.getActiveCurrencyCode();
    if (!mounted) return;
    setState(() => _currencyCode = code);
    await _refreshExchangeQuote();
  }

  Future<void> _refreshExchangeQuote() async {
    if (_currencyCode == 'TWD') {
      if (!mounted) return;
      setState(() {
        _exchangeQuote = null;
        _exchangeRateError = null;
        _isForeignCard = false;
      });
      return;
    }

    if (mounted) {
      setState(() {
        _isLoadingExchangeRate = true;
        _exchangeRateError = null;
      });
    }
    try {
      final quote = await CurrencyService.instance.getTwdQuote(_currencyCode);
      if (!mounted) return;
      setState(() => _exchangeQuote = quote);
    } catch (e) {
      if (!mounted) return;
      setState(() => _exchangeRateError = e.toString().replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => _isLoadingExchangeRate = false);
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _noteController.dispose();
    super.dispose();
  }

  // ==========================
  // 原有的邏輯 (日期與分類)
  // ==========================

  void _presentDatePicker() async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 1),
      lastDate: now,
    );
    if (pickedDate == null) return;
    setState(() {
      _selectedDate = pickedDate;
    });
  }

  void _presentCategoryPicker() async {
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (context) => TypePage(transactionType: _selectedType),
      ),
    );

    if (result != null) {
      setState(() {
        _selectedCategory = result['name'];
        _selectedIcon = result['icon'];
      });
    }
  }

  // ==========================
  // ★★★ 核心邏輯 (滑動數鈔) ★★★
  // ==========================

  // 加入金額
  void _addAmount(int amount, GlobalKey buttonKey, {bool isDrag = false}) {
    setState(() {
      double rawSum = _totalAmount + amount;
      if (rawSum < 0) rawSum = 0;

      _totalAmount = double.parse(rawSum.toStringAsFixed(2));
      _history.add(amount.toDouble());
      _numpadString = _formatAmount(_totalAmount);
    });

    _playMoneySound(amount);

    // 震動回饋
    if (isDrag) {
      HapticFeedback.lightImpact(); // 拖曳時輕震動
    } else {
      HapticFeedback.mediumImpact(); // 單點時重一點
    }

    // 只有單點時才飛動畫，拖曳時不飛
    if (!isDrag) {
      _triggerFlyingAnimation(amount, buttonKey);
    }
  }

  // 處理拖曳手勢
  void _handleDragUpdate(DragUpdateDetails details, int amount, GlobalKey btnKey) {
    _dragAccumulator -= details.delta.dy;
    const double threshold = 30.0; // 每移動 30px 算一次

    // 向上 (加錢)
    while (_dragAccumulator >= threshold) {
      _addAmount(amount, btnKey, isDrag: true);
      _dragAccumulator -= threshold;
    }

    // 向下 (減錢/後悔)
    while (_dragAccumulator <= -threshold) {
      _addAmount(-amount, btnKey, isDrag: true);
      _dragAccumulator += threshold;
    }
  }

  Future<void> _playMoneySound(int amount) async {
    try {
      await _audioPlayer.stop();
      if (amount.abs() >= 100) {
        await _audioPlayer.play(AssetSource('sounds/money.mp3'));
      } else {
        await _audioPlayer.play(AssetSource('sounds/coin.mp3'));
      }
    } catch (e) {
      // 忽略錯誤
    }
  }

  // 復原上一步
  void _undo() {
    if (_isNumpadMode) {
      _onNumpadTapped('<-');
    } else {
      if (_history.isNotEmpty) {
        setState(() {
          double last = _history.removeLast();
          double rawSum = _totalAmount - last;
          if (rawSum < 0) rawSum = 0;
          _totalAmount = double.parse(rawSum.toStringAsFixed(2));
          _numpadString = _formatAmount(_totalAmount);
        });
        HapticFeedback.mediumImpact();
      }
    }
  }

  // 清除全部
  void _clearAll() {
    setState(() {
      _totalAmount = 0;
      _history.clear();
      _numpadString = '0';
    });
    HapticFeedback.heavyImpact();
  }

  String _formatAmount(double amount) {
    if (amount % 1 == 0) {
      return amount.toInt().toString();
    }
    return amount.toString();
  }

  // ==========================
  // 傳統鍵盤邏輯
  // ==========================

  void _toggleInputMode() {
    setState(() {
      _isNumpadMode = !_isNumpadMode;
      if (_isNumpadMode) {
        _numpadString = _formatAmount(_totalAmount);
      } else {
        _history.clear();
      }
    });
    HapticFeedback.selectionClick();
  }

  void _onNumpadTapped(String value) {
    setState(() {
      if (value == '<-') {
        if (_numpadString.length > 1) {
          _numpadString = _numpadString.substring(0, _numpadString.length - 1);
        } else {
          _numpadString = '0';
        }
      } else if (value == '.') {
        if (!_numpadString.contains('.')) {
          _numpadString += '.';
        }
      } else {
        if (_numpadString == '0') {
          _numpadString = value;
        } else {
          if (_numpadString.length < 12) {
            _numpadString += value;
          }
        }
      }

      _totalAmount = double.tryParse(_numpadString) ?? 0;
    });
    HapticFeedback.lightImpact();
  }

  // ==========================
  // 動畫邏輯
  // ==========================

  void _triggerFlyingAnimation(int amount, GlobalKey buttonKey) {
    if (_flyingItems.length > 8) return;

    final RenderBox? buttonBox = buttonKey.currentContext?.findRenderObject() as RenderBox?;
    final RenderBox? targetBox = _targetKey.currentContext?.findRenderObject() as RenderBox?;

    if (buttonBox != null && targetBox != null) {
      final buttonPos = buttonBox.localToGlobal(Offset.zero);
      final targetPos = targetBox.localToGlobal(Offset.zero);

      final RenderBox? stackBox = context.findRenderObject() as RenderBox?;
      if (stackBox == null) return;

      final buttonLocal = stackBox.globalToLocal(buttonPos);
      final targetLocal = stackBox.globalToLocal(targetPos);

      final newItem = FlyingItem(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        amount: amount,
        startPos: buttonLocal,
        endPos: Offset(targetLocal.dx + targetBox.size.width / 2, targetLocal.dy + targetBox.size.height / 2),
        onComplete: (id) {
          if (mounted) {
            setState(() {
              _flyingItems.removeWhere((item) => item.id == id);
            });
          }
        },
      );

      setState(() {
        _flyingItems.add(newItem);
      });
    }
  }

  Future<void> _submitData() async {
    if (_isSubmitting) return;
    final enteredNote = _noteController.text;

    if (_totalAmount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("請輸入金額")),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    ExchangeRateQuote? quote = _exchangeQuote;
    if (_currencyCode != 'TWD' && quote == null) {
      try {
        quote = await CurrencyService.instance.getTwdQuote(_currencyCode);
      } catch (e) {
        if (!mounted) return;
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('目前無法取得匯率：${e.toString().replaceFirst('Bad state: ', '')}')),
        );
        return;
      }
    }

    final exchangeRate = quote?.twdPerUnit ?? 1.0;
    final baseAmountTwd = _totalAmount * exchangeRate;
    final appliesCardFee = _selectedType == TransactionType.expense &&
        _currencyCode != 'TWD' &&
        _isForeignCard;
    final feeAmountTwd = appliesCardFee ? baseAmountTwd * _foreignFeeRate : 0.0;

    final newTx = Transaction(
      // ★★★ 修改：如果是編輯模式，就保留原本的 ID；如果是新增，才產生新 ID ★★★
      id: widget.initialTransaction?.id ?? DateTime.now().toString(),
      note: enteredNote,
      amount: baseAmountTwd + feeAmountTwd,
      originalAmount: _totalAmount, // ★ 合併自朋友版(C)：原始輸入金額（原始幣別）
      date: _selectedDate,
      category: _selectedCategory,
      categoryIcon: _selectedIcon,
      type: _selectedType,
      currency: widget.initialTransaction?.currency ?? _currencyCode,
      isForeignCard: appliesCardFee,
      foreignFeeRate: appliesCardFee ? _foreignFeeRate : 0,
      foreignFeeAmountTwd: feeAmountTwd,
      exchangeRateToTwd: exchangeRate,
      exchangeRateSource: quote?.source ?? 'TWD',
      exchangeRateType: quote?.rateType ?? '基準幣別',
      exchangeRateDate: quote?.rateDate,
    );

    // ★ 修卡頓：先「觸發」存檔（含後續重新載入/獎勵/教練都在背景跑），不 await 它們完成就關閉表單。
    //   原本 `await Future.sync(...)` 會等整條網路後續跑完才關表單，導致「確認記帳」一直轉圈、要手動滑掉。
    widget.onAddTransaction(newTx);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Widget _buildForeignCardSection() {
    if (_currencyCode == 'TWD' || _selectedType != TransactionType.expense) {
      return const SizedBox.shrink();
    }

    final baseTwd = _totalAmount * (_exchangeQuote?.twdPerUnit ?? 0);
    final feeTwd = _isForeignCard ? baseTwd * _foreignFeeRate : 0.0;
    final quote = _exchangeQuote;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F8FF),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFD7E6FF)),
      ),
      child: Column(
        children: [
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: _isForeignCard,
            onChanged: (value) => setState(() => _isForeignCard = value),
            title: const Text('國外刷卡', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('預估值會計入支出，實際金額仍依發卡行入帳為準'),
            secondary: const Icon(Icons.credit_card_rounded, color: Color(0xFF3569B7)),
          ),
          if (_isForeignCard) ...[
            const Divider(height: 18),
            Row(
              children: [
                const Expanded(child: Text('手續費率（依發卡行調整）')),
                DropdownButton<double>(
                  value: _foreignFeeRate,
                  underline: const SizedBox.shrink(),
                  items: const [0.01, 0.015, 0.02, 0.025, 0.03]
                      .map((rate) => DropdownMenuItem(
                    value: rate,
                    child: Text('${(rate * 100).toStringAsFixed(rate == 0.015 || rate == 0.025 ? 1 : 0)}%'),
                  ))
                      .toList(),
                  onChanged: (rate) {
                    if (rate != null) setState(() => _foreignFeeRate = rate);
                  },
                ),
              ],
            ),
          ],
          const SizedBox(height: 4),
          if (_isLoadingExchangeRate)
            const LinearProgressIndicator(minHeight: 2)
          else if (_exchangeRateError != null)
            Row(
              children: [
                Expanded(child: Text(_exchangeRateError!, style: const TextStyle(color: Colors.red, fontSize: 12))),
                TextButton(onPressed: _refreshExchangeQuote, child: const Text('重試')),
              ],
            )
          else if (quote != null)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '1 $_currencyCode ≈ NT\$${quote.twdPerUnit.toStringAsFixed(4)}\n'
                      '${quote.source}・${quote.rateType}・${quote.rateDate}${quote.isStale ? '（快取）' : ''}\n'
                      '${_isForeignCard ? '預估手續費 NT\$${feeTwd.toStringAsFixed(0)}，入帳約 NT\$${(baseTwd + feeTwd).toStringAsFixed(0)}' : '換算約 NT\$${baseTwd.toStringAsFixed(0)}'}',
                  style: TextStyle(fontSize: 12, height: 1.5, color: Colors.blueGrey[700]),
                ),
              ),
        ],
      ),
    );
  }

  InputDecoration _buildInputDecoration({required String hint, IconData? icon}) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: icon != null ? Icon(icon, color: Colors.grey) : null,
      filled: true,
      fillColor: Colors.grey[100],
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
    );
  }

  // ==========================
  // UI 建構
  // ==========================

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Padding(
          padding: EdgeInsets.only(
            top: 16,
            left: 20,
            right: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 10,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. Toggle
                ToggleButtons(
                  isSelected: [
                    _selectedType == TransactionType.expense,
                    _selectedType == TransactionType.income,
                  ],
                  onPressed: (index) {
                    setState(() {
                      _selectedType = (index == 0)
                          ? TransactionType.expense
                          : TransactionType.income;

                      if (_selectedType == TransactionType.expense) {
                        _selectedCategory = '飲食';
                        _selectedIcon = Icons.fastfood_rounded;
                      } else {
                        _selectedCategory = '薪水';
                        _selectedIcon = Icons.attach_money_rounded;
                      }
                    });
                  },
                  borderRadius: BorderRadius.circular(15),
                  constraints: const BoxConstraints(minHeight: 36, minWidth: 80),
                  selectedColor: Colors.white,
                  fillColor: _selectedType == TransactionType.expense
                      ? Colors.redAccent
                      : Colors.green,
                  children: const [Text('支出'), Text('收入')],
                ),
                const SizedBox(height: 12),

                // 2. 金額顯示
                Container(
                  key: _targetKey,
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _selectedType == TransactionType.expense ? Icons.remove : Icons.add,
                        color: _selectedType == TransactionType.expense ? Colors.red : Colors.green,
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      Text(CurrencyService.symbolForCode(_currencyCode), style: TextStyle(fontSize: 24, color: Colors.grey[600])),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TweenAnimationBuilder<int>(
                          tween: IntTween(begin: 0, end: _totalAmount.toInt()),
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOut,
                          builder: (context, value, child) {
                            return Text(
                              (_totalAmount % 1 == 0)
                                  ? value.toString()
                                  : _totalAmount.toString(),
                              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                              textAlign: TextAlign.right,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                // 3. 輸入與選擇
                SizedBox(
                  height: 45,
                  child: TextField(
                    controller: _noteController,
                    decoration: _buildInputDecoration(hint: '備註 (可選)', icon: Icons.note_alt_outlined),
                  ),
                ),
                const SizedBox(height: 10),

                InkWell(
                  onTap: _presentCategoryPicker,
                  child: Container(
                    height: 45,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(15)),
                    child: Row(
                      children: [
                        Icon(_selectedIcon, color: Colors.blueAccent, size: 22),
                        const SizedBox(width: 12),
                        Expanded(child: Text(_selectedCategory, style: const TextStyle(fontSize: 15))),
                        const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                InkWell(
                  onTap: _presentDatePicker,
                  child: Container(
                    height: 45,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(15)),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today_outlined, color: Colors.grey, size: 22),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            DateFormat('yyyy / MM / dd').format(_selectedDate),
                            style: const TextStyle(fontSize: 15),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                _buildForeignCardSection(),
                if (_currencyCode != 'TWD' && _selectedType == TransactionType.expense)
                  const SizedBox(height: 12),

                // 4. 工具列
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildToolButton(
                          icon: Icons.refresh_rounded,
                          label: "歸零",
                          onTap: _clearAll,
                          color: Colors.redAccent
                      ),

                      InkWell(
                        onTap: _toggleInputMode,
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                              color: Colors.grey[200],
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.grey.shade300)
                          ),
                          child: Row(
                            children: [
                              Icon(_isNumpadMode ? Icons.wallet : Icons.keyboard_alt_outlined, size: 16, color: Colors.blueGrey),
                              const SizedBox(width: 6),
                              Text(
                                  _isNumpadMode ? "錢包" : "鍵盤",
                                  style: const TextStyle(fontSize: 12, color: Colors.blueGrey, fontWeight: FontWeight.bold)
                              ),
                            ],
                          ),
                        ),
                      ),

                      _buildToolButton(
                          icon: Icons.undo_rounded,
                          label: "復原",
                          onTap: _undo,
                          color: Colors.orangeAccent
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // 5. 鍵盤區塊
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.grey.shade200),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
                  ),
                  child: _isNumpadMode
                      ? _buildNumpad()
                      : _buildMoneyWallet(),
                ),
                const SizedBox(height: 16),

                // 6. 確認按鈕
                GestureDetector(
                  onTap: _isSubmitting ? null : _submitData,
                  child: Container(
                    width: double.infinity,
                    height: 50,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF69F0AE), Color(0xFF00E676)],
                      ),
                      borderRadius: BorderRadius.circular(15),
                      boxShadow: [
                        BoxShadow(color: const Color(0xFF00E676).withOpacity(0.4), blurRadius: 8, offset: const Offset(0, 4))
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_isSubmitting)
                          const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        else
                          const Icon(Icons.check_circle_outline, color: Colors.white, size: 24),
                        const SizedBox(width: 8),
                        // ★★★ 修改：根據是否為編輯模式切換文字 ★★★
                        Text(
                          widget.initialTransaction != null ? "儲存修改" : "確認記帳",
                          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),

        // 飛入動畫
        ..._flyingItems.map((item) => _buildFlyingWidget(item)).toList(),
      ],
    );
  }

  // ==========================
  // 鍵盤組件
  // ==========================

  Widget _buildMoneyWallet() {
    return Column(
      children: [
        // ★★★ 修正後的提示文字 ★★★
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.touch_app, size: 14, color: Colors.grey),
              SizedBox(width: 4),
              Text("點擊 +1", style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
              SizedBox(width: 16),
              Icon(Icons.swap_vert, size: 14, color: Colors.grey),
              SizedBox(width: 4),
              // ↓ 這裡改了！
              Text("上下拖曳數鈔", style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
        ),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildMoneyButton(1000, const Color(0xFF4A90E2), isBill: true),
            _buildMoneyButton(500, const Color(0xFF8D6E63), isBill: true),
            _buildMoneyButton(100, const Color(0xFFE57373), isBill: true),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildMoneyButton(50, const Color(0xFFFFD54F)),
            _buildMoneyButton(10, const Color(0xFFB0BEC5)),
            _buildMoneyButton(5, const Color(0xFFA1887F)),
            _buildMoneyButton(1, const Color(0xFFA1887F), size: 50),
          ],
        ),
      ],
    );
  }

  Widget _buildNumpad() {
    const spacing = SizedBox(width: 10, height: 10);
    return Column(
      children: [
        Row(
          children: [
            _buildNumpadBtn('1'), spacing, _buildNumpadBtn('2'), spacing, _buildNumpadBtn('3'),
          ],
        ),
        spacing,
        Row(
          children: [
            _buildNumpadBtn('4'), spacing, _buildNumpadBtn('5'), spacing, _buildNumpadBtn('6'),
          ],
        ),
        spacing,
        Row(
          children: [
            _buildNumpadBtn('7'), spacing, _buildNumpadBtn('8'), spacing, _buildNumpadBtn('9'),
          ],
        ),
        spacing,
        Row(
          children: [
            _buildNumpadBtn('.'),
            spacing,
            _buildNumpadBtn('0'),
            spacing,
            _buildNumpadBtn('<-', icon: Icons.backspace_outlined),
          ],
        ),
      ],
    );
  }

  // ★★★ 核心修改：拖曳數鈔 (VerticalDrag) ★★★
  Widget _buildMoneyButton(int amount, Color color, {bool isBill = false, double size = 60}) {
    final GlobalKey btnKey = GlobalKey();

    return GestureDetector(
      key: btnKey,
      onTap: () => _addAmount(amount, btnKey),

      // ★ 手指按下時，重置距離
      onVerticalDragStart: (_) => _dragAccumulator = 0.0,
      // ★ 手指移動時，計算累積距離
      onVerticalDragUpdate: (details) => _handleDragUpdate(details, amount, btnKey),

      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Container(
            width: isBill ? 80 : size,
            height: isBill ? 45 : size,
            decoration: BoxDecoration(
              color: color,
              shape: isBill ? BoxShape.rectangle : BoxShape.circle,
              borderRadius: isBill ? BorderRadius.circular(8) : null,
              boxShadow: [
                BoxShadow(color: color.withOpacity(0.4), blurRadius: 3, offset: const Offset(0, 2))
              ],
              border: Border.all(color: Colors.white.withOpacity(0.3), width: 1.5),
            ),
            child: Center(
              child: Text(
                "$amount",
                style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16, fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ),
          // ★★★ 視覺引導：向上箭頭 ★★★
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.keyboard_arrow_up, size: 16, color: Colors.white38),
          )
        ],
      ),
    );
  }

  Widget _buildNumpadBtn(String value, {IconData? icon}) {
    return Expanded(
      child: InkWell(
        onTap: () => _onNumpadTapped(value),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: icon != null
              ? Icon(icon, color: Colors.black87)
              : Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87)),
        ),
      ),
    );
  }

  Widget _buildToolButton({required IconData icon, required String label, required VoidCallback onTap, required Color color}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildFlyingWidget(FlyingItem item) {
    return FlyingMoneyAnim(item: item, onComplete: () => item.onComplete(item.id));
  }
}

// ------------------------------
// 動畫類別 (不變)
// ------------------------------

class FlyingItem {
  final String id;
  final int amount;
  final Offset startPos;
  final Offset endPos;
  final Function(String) onComplete;

  FlyingItem({required this.id, required this.amount, required this.startPos, required this.endPos, required this.onComplete});
}

class FlyingMoneyAnim extends StatefulWidget {
  final FlyingItem item;
  final VoidCallback onComplete;

  const FlyingMoneyAnim({super.key, required this.item, required this.onComplete});

  @override
  State<FlyingMoneyAnim> createState() => _FlyingMoneyAnimState();
}

class _FlyingMoneyAnimState extends State<FlyingMoneyAnim> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _positionAnim;
  late Animation<double> _scaleAnim;
  late Animation<double> _opacityAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _positionAnim = Tween<Offset>(begin: widget.item.startPos, end: widget.item.endPos).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.5).animate(_controller);
    _opacityAnim = Tween<double>(begin: 1.0, end: 0.0).animate(CurvedAnimation(parent: _controller, curve: const Interval(0.8, 1.0)));
    _controller.forward().then((_) => widget.onComplete());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isBill = widget.item.amount >= 100;
    final Color color = _getColorForAmount(widget.item.amount);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Positioned(
          left: _positionAnim.value.dx,
          top: _positionAnim.value.dy,
          child: Opacity(
            opacity: _opacityAnim.value,
            child: Transform.scale(
              scale: _scaleAnim.value,
              child: Container(
                width: isBill ? 70 : 52,
                height: isBill ? 38 : 52,
                decoration: BoxDecoration(
                  color: color,
                  shape: isBill ? BoxShape.rectangle : BoxShape.circle,
                  borderRadius: isBill ? BorderRadius.circular(8) : null,
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10)],
                ),
                child: Center(
                  child: Text("${widget.item.amount}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Color _getColorForAmount(int amount) {
    switch (amount) {
      case 1000: return const Color(0xFF4A90E2);
      case 500: return const Color(0xFF8D6E63);
      case 100: return const Color(0xFFE57373);
      case 50: return const Color(0xFFFFD54F);
      case 10: return const Color(0xFFB0BEC5);
      case 5: return const Color(0xFFA1887F);
      default: return const Color(0xFFA1887F);
    }
  }
}