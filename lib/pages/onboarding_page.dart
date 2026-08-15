import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 用於震動
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart'; // 用於音效

import '../main_app_shell.dart';
import '../services/database_helper.dart'; // 確保路徑正確

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  // === 狀態管理 ===
  String? _selectedIdentity; // 選中的身分代碼
  bool _isDropped = false; // 是否已經完成拖曳
  bool _isLoading = false; // 載入中
  final TextEditingController _nicknameController = TextEditingController();
  final TextEditingController _budgetController = TextEditingController();
  final AudioPlayer _audioPlayer = AudioPlayer();

  // === 身分選項設定 (使用內建 Icon) ===
  final List<Map<String, dynamic>> _zones = [
    {
      'code': 'u23',
      'label': '學生/新鮮人',
      'icon': Icons.school_rounded,
      'color': Colors.green,
      'bg': Colors.green.shade50,
    },
    {
      'code': 'a23_35',
      'label': '上班族',
      'icon': Icons.business_center_rounded,
      'color': Colors.blue,
      'bg': Colors.blue.shade50,
    },
    {
      'code': 'a35p',
      'label': '家庭/資產',
      'icon': Icons.house_rounded,
      'color': Colors.orange,
      'bg': Colors.orange.shade50,
    },
  ];

  @override
  void dispose() {
    _nicknameController.dispose();
    _budgetController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  // === 音效播放 ===
  Future<void> _playSuccessSound() async {
    try {
      await _audioPlayer.stop();
      await _audioPlayer.play(AssetSource('sounds/done.mp3'));
    } catch (e) {
      debugPrint('音效播放失敗: $e');
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

  // === 完成設定 (邏輯完全保留) ===
  Future<void> _finishSetup() async {
    final nickname = _nicknameController.text.trim();
    if (nickname.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請告訴我們該如何稱呼您 (´・ω・`)')),
      );
      return;
    }

    final budget = int.tryParse(_budgetController.text.trim().replaceAll(',', ''))
        ?? _defaultBudgetForIdentity(_selectedIdentity ?? 'u23');

    if (budget <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請設定大於 0 的月底預算，之後也可以在設定頁修改。')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 1. 初始化資料庫
      if (_selectedIdentity != null) {
        await DatabaseHelper.instance.initializeUserIdentity(_selectedIdentity!);
      }

      // 2. 儲存設定
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_identity', _selectedIdentity ?? 'u23');
      await prefs.setString('user_nickname', nickname);
      await prefs.setBool('is_onboarded', true);
      await prefs.setInt('setting_monthly_budget_amount', budget);
      await prefs.setBool('setting_monthly_budget_reminder', true);
      await prefs.setInt('setting_budget_threshold', 90);
      await prefs.setBool('setting_beginner_tips', true);

      if (!mounted) return;

      // 3. 進入主畫面
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const MainAppShell()),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('設定失敗: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("選擇您的生活模式"),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 18),
      ),
      // ★★★ 修正點 1：使用 LayoutBuilder + ConstrainedBox 解決黃線與錯位問題 ★★★
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              // 讓內容至少有螢幕這麼高，鍵盤彈出時則可以滑動
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Column(
                    children: [
                      const SizedBox(height: 20),

                      // === 上半部：生活圈 (Drop Zones) ===
                      // 這裡不使用 Fixed Height，改用 Spacer 自動分配
                      _buildZoneArea(),

                      // 佔位符，把上下兩塊撐開
                      const Spacer(),

                      // === 下半部：主角 或 輸入框 ===
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 500),
                        child: _isDropped ? _buildNicknameInputArea() : _buildPlayerArea(),
                      ),

                      const SizedBox(height: 40), // 底部留白
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // === 區域 1：三個生活圈 (拖曳目標) ===
  Widget _buildZoneArea() {
    if (_isDropped) {
      // 如果選好了，顯示選中結果
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 40), // 稍微往下推一點
          _buildSelectedZoneDisplay(),
          const SizedBox(height: 24),
          const Text(
            "身分確認成功！",
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87),
          ),
        ],
      );
    }

    // 尚未選擇時的佈局
    return Column(
      children: [
        // 第一排：學生
        _buildDragTarget(_zones[0]),

        const SizedBox(height: 20),
        const Opacity(
          opacity: 0.5,
          child: Text(
            "將頭像拖曳至符合的生活圈",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
        ),
        const SizedBox(height: 20),

        // 第二排：上班族 & 家庭
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildDragTarget(_zones[1]),
            _buildDragTarget(_zones[2]),
          ],
        ),
      ],
    );
  }

  // 建立單個拖曳目標
  Widget _buildDragTarget(Map<String, dynamic> zone) {
    return DragTarget<String>(
      onWillAccept: (data) {
        HapticFeedback.selectionClick();
        return true;
      },
      onAccept: (data) async {
        _playSuccessSound();
        HapticFeedback.heavyImpact();

        setState(() {
          _selectedIdentity = zone['code'];
          _budgetController.text = _defaultBudgetForIdentity(zone['code']).toString();
          _isDropped = true;
        });
      },
      builder: (context, candidateData, rejectedData) {
        final isHovering = candidateData.isNotEmpty;

        return AnimatedScale(
          scale: isHovering ? 1.15 : 1.0,
          duration: const Duration(milliseconds: 200),
          child: Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: isHovering ? zone['bg'] : Colors.white,
              shape: BoxShape.circle,
              border: Border.all(
                color: isHovering ? zone['color'] : Colors.grey.shade300,
                width: isHovering ? 3 : 2,
              ),
              boxShadow: isHovering
                  ? [BoxShadow(color: (zone['color'] as Color).withOpacity(0.4), blurRadius: 15, spreadRadius: 2)]
                  : [],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  zone['icon'],
                  size: 40,
                  color: isHovering ? zone['color'] : Colors.grey.shade400,
                ),
                const SizedBox(height: 8),
                Text(
                  zone['label'],
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isHovering ? zone['color'] : Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ★★★ 修正點 2：選定後的樣式優化 ★★★
  // 不再是醜醜的疊加，而是直接變成「染上該顏色的人臉」，看起來更融合
  Widget _buildSelectedZoneDisplay() {
    final zone = _zones.firstWhere((z) => z['code'] == _selectedIdentity);
    final themeColor = zone['color'] as Color;

    return Container(
      width: 160,
      height: 160,
      decoration: BoxDecoration(
        color: zone['bg'], // 淡淡的背景色
        shape: BoxShape.circle,
        border: Border.all(color: themeColor, width: 4), // 該生活圈的主題色邊框
        boxShadow: [BoxShadow(color: themeColor.withOpacity(0.3), blurRadius: 20)],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 直接顯示染上該顏色的人臉，代表「我融入了這個生活圈」
          Icon(Icons.face_rounded, size: 80, color: themeColor),
          const SizedBox(height: 8),
          // 下方顯示該生活圈名稱，確認沒選錯
          Text(
            zone['label'],
            style: TextStyle(color: themeColor, fontWeight: FontWeight.bold, fontSize: 16),
          )
        ],
      ),
    );
  }

  // === 區域 2-A：主角 (可拖曳的人頭) ===
  Widget _buildPlayerArea() {
    return Draggable<String>(
      data: 'avatar',
      feedback: const Material(
        color: Colors.transparent,
        child: Icon(Icons.face_rounded, size: 90, color: Colors.black),
      ),
      childWhenDragging: const Opacity(
        opacity: 0.2,
        child: Icon(Icons.face_rounded, size: 80, color: Colors.black),
      ),
      onDragStarted: () {
        HapticFeedback.mediumImpact();
      },
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: Colors.purple.withOpacity(0.2), blurRadius: 20, spreadRadius: 5)
                ]
            ),
            child: const Icon(Icons.face_rounded, size: 80, color: Colors.black87),
          ),
          const SizedBox(height: 12),
          const Text("按住頭像，拖曳去上方", style: TextStyle(color: Colors.purple, fontWeight: FontWeight.bold)),
          const Icon(Icons.touch_app_rounded, color: Colors.purple, size: 20),
        ],
      ),
    );
  }

  // === 區域 2-B：暱稱輸入框 ===
  Widget _buildNicknameInputArea() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            "最後一步",
            style: TextStyle(fontSize: 14, color: Colors.grey, letterSpacing: 1.2),
          ),
          const SizedBox(height: 8),
          const Text(
            "我們該如何稱呼您？",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            "順便設定月底預算，之後才能提醒你快超支了。",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _nicknameController,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              hintText: '例如：小明、Alice...',
              filled: true,
              fillColor: Colors.grey.shade100,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(30),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _budgetController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.savings_rounded),
              labelText: '月底預算',
              suffixText: '元 / 月',
              helperText: '可先用預設值，之後到設定頁調整',
              filled: true,
              fillColor: Colors.grey.shade100,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            ),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _finishSetup,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                elevation: 5,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
              child: const Text("開啟記帳旅程 🚀", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}