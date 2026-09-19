import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 用於震動
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart'; // 用於音效

import '../main_app_shell.dart';
import '../services/database_helper.dart'; // 確保路徑正確
import '../services/game_api_service.dart';
import '../theme/app_palette.dart';
import '../widgets/paw_toy_widgets.dart';

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
  bool _isDragging = false;
  String? _pendingIdentity; // 接住扭蛋後短暫顯示選中的生活圈
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

      // 同步到後端，供「首次設定月預算」與「當月花費在預算內」任務判定。
      try {
        await GameApiService.instance.setMonthlyBudget(amount: budget.toDouble());
      } catch (e) {
        debugPrint('新手預算任務同步失敗：$e');
      }

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
    final p = AppPalette.of(context);
    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(backgroundColor: p.accentSoft, elevation: 0,
        foregroundColor: p.accentInk, centerTitle: true,
        title: Text('PAWPAY', style: TextStyle(color: p.accentInk,
          fontSize: 17, letterSpacing: 3, fontWeight: FontWeight.w800))),
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter,
          end: Alignment.bottomCenter, colors: [p.accentSoft, pawToyCream, p.bg])),
        child: SafeArea(child: _isLoading
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              CircularProgressIndicator(color: p.accentInk), const SizedBox(height: 18),
              Text('正在準備你的記帳旅程…', style: TextStyle(color: p.ink)),
            ]))
          : !_isDropped
            ? _buildDragSelectionArea()
            : SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 32),
              child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Center(child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: .75),
                      borderRadius: BorderRadius.circular(20)),
                    child: Text(_isDropped ? '02 / 02 · 專屬小檔案' : '01 / 02 · 你的生活模式',
                      style: TextStyle(color: p.accentInk, fontSize: 11, fontWeight: FontWeight.w700)),
                  )),
                  const SizedBox(height: 20),
                  Text(_isDropped ? '身分確認成功！' : '每種生活，都有小幸福', textAlign: TextAlign.center,
                    style: TextStyle(color: p.ink, fontSize: 24, fontWeight: FontWeight.w800, height: 1.35)),
                  const SizedBox(height: 8),
                  Text(_isDropped ? '再認識你一點，就能出發囉。' : '選擇你的生活模式，讓記帳更貼近你。',
                    textAlign: TextAlign.center, style: TextStyle(color: p.ink2, fontSize: 13, height: 1.5)),
                  const SizedBox(height: 18),
                  _buildSelectedZoneDisplay(),
                  const SizedBox(height: 24),
                  _buildNicknameInputArea(),
                ]),
              )),
            ),
        ),
      ),
    );
  }

  // 身分一定由拖曳放入生活圈選取，保留原本專題的互動設計。
  Future<void> _chooseIdentity(Map<String, dynamic> zone) async {
    if (_isDropped || _isLoading || _pendingIdentity != null) return;
    final code = zone['code'] as String;
    setState(() {
      _isDragging = false;
      _pendingIdentity = code;
    });
    _playSuccessSound();
    HapticFeedback.heavyImpact();
    // 先讓小貓出現在接住它的生活圈，再進入原有的設定表單。
    if (!MediaQuery.of(context).disableAnimations) {
      await Future<void>.delayed(const Duration(milliseconds: 520));
    }
    if (!mounted) return;
    setState(() {
      _selectedIdentity = code;
      _budgetController.text = _defaultBudgetForIdentity(code).toString();
      _isDropped = true;
      _pendingIdentity = null;
    });
  }

  Widget _buildDragSelectionArea() {
    final p = AppPalette.of(context);
    return LayoutBuilder(builder: (context, viewport) {
      final compact = viewport.maxHeight < 640;
      final showSubtitle = viewport.maxHeight >= 520;
      return SingleChildScrollView(
        // 拖曳期間維持生活圈的位置，避免畫面跟著手指上下捲動。
        physics: _isDragging || _pendingIdentity != null
            ? const NeverScrollableScrollPhysics() : null,
        padding: EdgeInsets.fromLTRB(20, compact ? 12 : 20, 20, compact ? 16 : 28),
        child: Center(child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: .75),
                borderRadius: BorderRadius.circular(20)),
              child: Text('01 / 02 · 你的生活模式',
                style: TextStyle(color: p.accentInk, fontSize: 11, fontWeight: FontWeight.w700)),
            )),
            SizedBox(height: compact ? 12 : 18),
            Text('把小貓帶進你的生活圈', textAlign: TextAlign.center,
              style: TextStyle(color: p.ink, fontSize: compact ? 22 : 25,
                fontWeight: FontWeight.w800, height: 1.3)),
            if (showSubtitle) ...[
              const SizedBox(height: 8),
              Text('每種生活，都有值得收藏的小幸福。', textAlign: TextAlign.center,
                style: TextStyle(color: p.ink2, fontSize: 12, height: 1.5)),
            ],
            SizedBox(height: compact ? 14 : 24),
            _buildZoneArea(compact: compact),
            SizedBox(height: compact ? 8 : 18),
            _buildPlayerArea(compact: compact),
          ]),
        )),
      );
    });
  }

  Widget _buildZoneArea({required bool compact}) {
    return LayoutBuilder(builder: (context, box) {
      final available = (box.maxWidth - 24) / 2;
      final preferred = compact ? 100.0 : 124.0;
      final diameter = available < preferred ? available : preferred;
      // 回到原本上方一圈、下方兩圈的生活圈配置。
      return Center(child: SizedBox(width: diameter * 2 + 24,
        child: Column(children: [
          _buildDragTarget(_zones[0], diameter: diameter),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            _buildDragTarget(_zones[1], diameter: diameter),
            _buildDragTarget(_zones[2], diameter: diameter),
          ]),
        ]),
      ));
    });
  }

  Widget _buildDragTarget(Map<String, dynamic> zone, {required double diameter}) {
    final p = AppPalette.of(context);
    final code = zone['code'] as String;
    final tint = Color.lerp(zone['color'] as Color, pawToyCream, .68)!;
    final duration = MediaQuery.of(context).disableAnimations
        ? Duration.zero : const Duration(milliseconds: 180);
    return Semantics(label: '${zone['label']}生活圈，將小貓扭蛋拖曳到這裡',
      child: DragTarget<String>(
        key: ValueKey('identity-target-$code'),
        onWillAcceptWithDetails: (details) {
          final allowed = details.data == 'avatar' && !_isDropped &&
              !_isLoading && _pendingIdentity == null;
          if (allowed) HapticFeedback.selectionClick();
          return allowed;
        },
        onAcceptWithDetails: (details) {
          if (details.data == 'avatar') _chooseIdentity(zone);
        },
        builder: (context, candidates, rejected) {
          final hovering = candidates.isNotEmpty;
          final received = _pendingIdentity == code;
          final active = hovering || received;
          return SizedBox(width: diameter, height: diameter + 8,
            child: AnimatedScale(scale: active ? 1.05 : 1, duration: duration,
              curve: Curves.easeOutCubic,
              child: AnimatedContainer(
                duration: duration,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: [Colors.white, Color.lerp(pawToyCream, tint, active ? .82 : .38)!, tint],
                    stops: const [0, .48, 1]),
                  border: Border.all(color: active ? p.accentInk.withValues(alpha: .7) : Colors.white,
                    width: active ? 2.5 : 3),
                  boxShadow: [
                    BoxShadow(color: Color.lerp(tint, pawToyTrim, .55)!, offset: const Offset(0, 5)),
                    BoxShadow(color: (active ? p.accent : p.accentInk).withValues(alpha: active ? .30 : .10),
                      blurRadius: active ? 24 : 14, spreadRadius: active ? 3 : 0,
                      offset: const Offset(0, 8)),
                  ],
                ),
                // 圓圈扣除邊框與內距後，再依實際寬、高縮放整組內容。
                // 只縮放個別文字的寬度，無法避免手機字型較高時的底部溢出。
                child: LayoutBuilder(builder: (context, contentBox) {
                  return FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.center,
                    child: SizedBox(
                      width: contentBox.maxWidth,
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        SizedBox(height: diameter * .38,
                          child: AnimatedSwitcher(duration: duration,
                            child: received
                              ? SizedBox(key: const ValueKey('received'), width: diameter * .63,
                                  child: const PawCapsuleStage(open: false))
                              : Icon(zone['icon'] as IconData, key: const ValueKey('waiting'),
                                  size: diameter * .28, color: p.accentInk),
                          ),
                        ),
                        const SizedBox(height: 3),
                        FittedBox(fit: BoxFit.scaleDown,
                          child: Text(zone['label'] as String,
                            style: TextStyle(color: p.ink, fontSize: 13, fontWeight: FontWeight.w800))),
                        const SizedBox(height: 3),
                        FittedBox(fit: BoxFit.scaleDown,
                          child: Text(received ? '接住你了！' : (hovering ? '放開，選擇我' : '拖曳到這裡'),
                            style: TextStyle(color: active ? p.accentInk : p.ink2,
                              fontSize: 10, fontWeight: active ? FontWeight.w700 : FontWeight.w500))),
                      ]),
                    ),
                  );
                }),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSelectedZoneDisplay() {
    final p = AppPalette.of(context);
    final zone = _zones.firstWhere((z) => z['code'] == _selectedIdentity);
    return Column(children: [
      const SizedBox(width: 210, child: PawCapsuleStage(imagePath: 'assets/pets/cat.png')),
      Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20),
          border: Border.all(color: p.line)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.check_circle_rounded, color: p.accentInk, size: 18),
          const SizedBox(width: 8),
          Flexible(child: Text(zone['label'] as String,
            style: TextStyle(color: p.ink, fontWeight: FontWeight.w700))),
        ]),
      ),
    ]);
  }

  Widget _buildPlayerArea({required bool compact}) {
    final p = AppPalette.of(context);
    final width = compact ? 112.0 : 150.0;
    const feedbackWidth = 140.0;
    final toy = SizedBox(width: width, child: const PawCapsuleStage(open: false));
    final waitingForConfirmation = _pendingIdentity != null;
    return Column(children: [
      Semantics(label: '小貓扭蛋，按住並拖曳到上方符合你的生活圈',
        child: Draggable<String>(
          key: const ValueKey('identity-avatar'),
          data: 'avatar', maxSimultaneousDrags: waitingForConfirmation ? 0 : 1,
          rootOverlay: true,
          // 視覺中心和命中位置一起上移，讓手指不會遮住目標圈。
          dragAnchorStrategy: (_, __, ___) => const Offset(feedbackWidth / 2, feedbackWidth / 1.4 / 2),
          feedbackOffset: const Offset(0, -26),
          feedback: Transform.translate(offset: const Offset(0, -26),
            child: const Material(color: Colors.transparent,
              child: SizedBox(width: feedbackWidth, child: PawCapsuleStage(open: false)))),
          childWhenDragging: Opacity(opacity: .18, child: toy),
          onDragStarted: () {
            HapticFeedback.mediumImpact();
            setState(() => _isDragging = true);
          },
          onDragEnd: (_) {
            if (mounted) setState(() => _isDragging = false);
          },
          child: Opacity(opacity: waitingForConfirmation ? .18 : 1, child: toy),
        ),
      ),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(waitingForConfirmation ? Icons.check_circle_rounded : Icons.touch_app_rounded,
          size: 16, color: p.accentInk),
        const SizedBox(width: 6),
        Flexible(child: Text(
          waitingForConfirmation ? '找到你的生活圈囉！' : (_isDragging ? '移進生活圈，放開就選好了' : '按住小貓扭蛋，拖到上方生活圈'),
          textAlign: TextAlign.center,
          style: TextStyle(color: p.accentInk, fontSize: 12,
            fontWeight: FontWeight.w600, height: 1.5),
        )),
      ]),
    ]);
  }

  Widget _buildNicknameInputArea() {
    final p = AppPalette.of(context);
    InputDecoration decoration(String label, IconData icon) => InputDecoration(
      labelText: label, prefixIcon: Icon(icon, color: p.accentInk),
      floatingLabelBehavior: FloatingLabelBehavior.always,
      labelStyle: TextStyle(color: p.accentInk), filled: true, fillColor: p.bg,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: p.line)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: p.accentInk)),
      contentPadding: const EdgeInsets.symmetric(vertical: 17, horizontal: 16),
    );
    return PawToyCard(padding: const EdgeInsets.all(22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('我們該如何稱呼你？', style: TextStyle(color: p.ink, fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text('設定暱稱與月底預算，開始累積你的小幸福。', style: TextStyle(color: p.ink2, fontSize: 12, height: 1.6)),
        const SizedBox(height: 24),
        TextField(controller: _nicknameController, textInputAction: TextInputAction.next,
          style: TextStyle(color: p.ink, fontWeight: FontWeight.w600),
          decoration: decoration('暱稱', Icons.person_outline_rounded).copyWith(hintText: '例如：小明、Alice…')),
        const SizedBox(height: 20),
        TextField(controller: _budgetController, keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: TextStyle(color: p.ink, fontWeight: FontWeight.w600),
          decoration: decoration('月底預算', Icons.savings_outlined).copyWith(
            suffixText: '元 / 月', helperText: '之後也可以到設定頁調整', helperMaxLines: 2)),
        const SizedBox(height: 26),
        PawToyButton(label: '開啟記帳旅程', onPressed: _finishSetup, icon: Icons.arrow_forward_rounded),
      ]),
    );
  }
}
