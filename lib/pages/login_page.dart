import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // ★ 新增：手機號碼輸入框要用 FilteringTextInputFormatter 限制只能打數字
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart'; // ★ 新增：用來儲存使用者 ID
import 'dart:math'; // ★★★ 新增這行：用來產生隨機數字字串 ★★★

// ★★★ 新增：Firebase 登入服務 ★★★
import '../services/firebase_auth_service.dart';
import '../services/line_auth_service.dart'; // ★ 新增：LINE 登入服務

// 1. ★ 修正路徑 ★
// 假設 main_app_shell.dart 在 lib/ 底下
// 而 login_page.dart 在 lib/pages/ 底下
// 我們用 ../ 回到上一層 (lib)，然後找到 main_app_shell.dart
import '../main_app_shell.dart';
import 'onboarding_page.dart';
import '../theme/app_palette.dart';
import '../widgets/paw_toy_widgets.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  // ★★★ 新增：email / 密碼 輸入框控制器 + loading 狀態 ★★★
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // 輔助函式：用來處理所有登入按鈕的跳轉
  // ★ 修改：改成 async 遞迴執行，在跳轉前先建立並儲存使用者的專屬 ID
  // (Apple / 手機 / LINE 目前仍走這個「虛擬帳號」流程)
  void _navigateToHome(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    String? currentUserId = prefs.getString('user_id');

    // 如果這支手機還沒有 ID，就幫他自動生成一個專屬的 (模擬真實註冊/登入)
    if (currentUserId == null || currentUserId.isEmpty) {
      // ★ 修正：MySQL 的 id 只能吃整數，所以我們產生一組 9 位數的隨機純數字字串
      String newUserId = (Random().nextInt(900000000) + 100000000).toString();
      await prefs.setString('user_id', newUserId);
      debugPrint("✅ 建立純數字新帳號 ID: $newUserId");
    } else {
      debugPrint("✅ 歡迎回來，登入現有帳號 ID: $currentUserId");
    }

    // ★ 修改：改成跳轉到 OnboardingPage
    if (context.mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const OnboardingPage()),
      );
    }
  }

  // ★★★ 新增：登入成功後跳轉 (user_id / jwt 已由後端回傳並存好，不再另外生 ID) ★★★
  void _goToOnboarding() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => const OnboardingPage()),
    );
  }

  // ★★★ 新增：顯示錯誤訊息 ★★★
  void _showMessage(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ★★★ 新增：Email + 密碼 登入 (Continue 按鈕) ★★★
  Future<void> _handleEmailLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      _showMessage('請輸入 email 和密碼');
      return;
    }
    if (password.length < 6) {
      _showMessage('密碼至少要 6 個字'); // Firebase 的最低要求
      return;
    }

    setState(() => _isLoading = true);
    try {
      final idToken =
      await FirebaseAuthService.signInOrRegisterEmail(email, password);
      await FirebaseAuthService.exchangeTokenWithBackend(idToken);
      _goToOnboarding();
    } catch (e) {
      // ★★★ 新增：如果是「已註冊但密碼不對」，直接問要不要寄重設密碼信 ★★★
      if (e.toString().contains('已經註冊過了')) {
        await _showPasswordResetDialog(email);
      } else {
        _showMessage('登入失敗：$e');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ★★★ 新增：忘記密碼 → 寄重設密碼信 ★★★
  Future<void> _showPasswordResetDialog(String email) async {
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('密碼不正確'),
        content: Text('「$email」已經註冊過了，但密碼不正確。\n要寄一封重設密碼的信到這個信箱嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('重新輸入密碼'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('寄重設信'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await FirebaseAuthService.sendPasswordResetEmail(email);
      _showMessage('已寄出重設密碼信，請到信箱收信（記得看垃圾信匣）');
    } catch (e) {
      _showMessage('寄送失敗：$e');
    }
  }

  // ★★★ 新增：Google 登入 ★★★
  Future<void> _handleGoogleLogin() async {
    setState(() => _isLoading = true);
    try {
      final idToken = await FirebaseAuthService.signInWithGoogle();
      await FirebaseAuthService.exchangeTokenWithBackend(idToken);
      _goToOnboarding();
    } catch (e) {
      _showMessage('Google 登入失敗：$e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ★★★ 新增：LINE 登入 ★★★
  Future<void> _handleLineLogin() async {
    setState(() => _isLoading = true);
    try {
      final accessToken = await LineAuthService.signInWithLine();
      await LineAuthService.exchangeTokenWithBackend(accessToken);
      _goToOnboarding();
    } catch (e) {
      _showMessage('LINE 登入失敗：$e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ★★★ 新增：目前登記在 Firebase 的測試手機號碼 + 對應驗證碼，方便自己測試時自動帶入 ★★★
  // 上線前記得把這裡清空或移除，避免正式版也帶到測試驗證碼
  static const Map<String, String> _devTestPhoneCodes = {
    '+886912345678': '123456',
  };

  // ★★★ 新增：手機號碼登入 - 入口，先彈出對話框讓使用者輸入手機號碼 ★★★
  // ★ 改成固定顯示 +886 國碼 (目前只開放台灣門號)，使用者只需要打後面的數字
  Future<void> _handlePhoneLogin() async {
    final phoneController = TextEditingController();
    final phoneNumber = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('輸入手機號碼'),
        content: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 14),
              child: Text(
                '+886',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: phoneController,
                autofocus: true,
                keyboardType: TextInputType.phone,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly], // ★ 只能打數字
                decoration: const InputDecoration(
                  hintText: '0912345678',
                  helperText: '開頭的 0 可打可不打，兩種都可以', // ★ 提示文字改短，避免被框住
                  helperMaxLines: 2,
                  helperStyle: TextStyle(fontSize: 13),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              // ★ 不管使用者打 0912345678 還是 912345678，統一去掉開頭的 0 再接上 +886
              var digits = phoneController.text.trim();
              if (digits.startsWith('0')) digits = digits.substring(1);
              Navigator.of(ctx).pop('+886$digits');
            },
            child: const Text('發送驗證碼'),
          ),
        ],
      ),
    );
    if (phoneNumber == null || phoneNumber == '+886') return;

    setState(() => _isLoading = true);
    try {
      await FirebaseAuthService.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        onCodeSent: (verificationId) async {
          // ★ 驗證碼送出後先關掉 loading，讓使用者可以輸入驗證碼
          if (mounted) setState(() => _isLoading = false);
          await _showSmsCodeDialog(verificationId, phoneNumber);
        },
        onFailed: (error) {
          // ★ 新增：印出完整錯誤到 debug console，之後回報問題時可以直接複製這行訊息
          debugPrint('❌ 手機登入失敗（發送驗證碼階段）：$error');
          if (mounted) setState(() => _isLoading = false);
          _showMessage('手機登入失敗：$error');
        },
        onAutoVerified: (idToken) async {
          // ★ 少數 Android 手機可以自動讀簡訊，不用使用者輸入就直接完成登入
          try {
            await FirebaseAuthService.exchangeTokenWithBackend(idToken);
            _goToOnboarding();
          } catch (e) {
            debugPrint('❌ 自動驗證後，換後端 token 失敗：$e');
            _showMessage('登入失敗：$e');
          } finally {
            if (mounted) setState(() => _isLoading = false);
          }
        },
      );
    } catch (e) {
      debugPrint('❌ 手機登入拋出例外（發送驗證碼階段）：$e');
      if (mounted) setState(() => _isLoading = false);
      _showMessage('手機登入失敗：$e');
    }
  }

  // ★★★ 新增：手機號碼登入 - 第二步，彈出對話框讓使用者輸入收到的簡訊驗證碼 ★★★
  // ★ 改成多帶一個 phoneNumber 參數，如果是自己登記的測試門號，就自動帶入測試驗證碼
  Future<void> _showSmsCodeDialog(String verificationId, String phoneNumber) async {
    final codeController =
    TextEditingController(text: _devTestPhoneCodes[phoneNumber] ?? '');
    if (!mounted) return;
    final smsCode = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('輸入簡訊驗證碼'),
        content: TextField(
          controller: codeController,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly], // ★ 只能打數字
          decoration: const InputDecoration(hintText: '123456'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(codeController.text.trim()),
            child: const Text('確認登入'),
          ),
        ],
      ),
    );
    if (smsCode == null || smsCode.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final idToken = await FirebaseAuthService.signInWithSmsCode(
        verificationId: verificationId,
        smsCode: smsCode,
      );
      await FirebaseAuthService.exchangeTokenWithBackend(idToken);
      _goToOnboarding();
    } catch (e) {
      // ★ 新增：印出完整錯誤到 debug console，方便抓「按確認登入沒反應」這類問題的真正原因
      debugPrint('❌ 驗證碼登入失敗（確認登入階段）：$e');
      _showMessage('驗證碼錯誤或登入失敗：$e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Scaffold(
      backgroundColor: p.bg,
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [p.accentSoft, pawToyCream, p.bg], stops: const [0, .46, 1],
        )),
        child: SafeArea(child: Stack(children: [
          LayoutBuilder(builder: (context, box) => SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            child: Center(child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AutofillGroup(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.pets_rounded, size: 20, color: p.accentInk),
                  const SizedBox(width: 8),
                  Text('PAWPAY', style: TextStyle(color: p.accentInk,
                    fontSize: 19, letterSpacing: 3.5, fontWeight: FontWeight.w900)),
                ]),
                const SizedBox(height: 10),
                Center(child: SizedBox(width: box.maxHeight < 620 ? 200 : 240,
                  child: const PawCapsuleStage(open: false))),
                const SizedBox(height: 8),
                Text('把日常，存成小幸福', textAlign: TextAlign.center,
                  style: TextStyle(color: p.ink, fontSize: 25, fontWeight: FontWeight.w800, height: 1.3)),
                const SizedBox(height: 8),
                Text('記下每一筆，和寵物一起慢慢長大。', textAlign: TextAlign.center,
                  style: TextStyle(color: p.ink2, fontSize: 13, height: 1.5)),
                const SizedBox(height: 26),
                PawToyCard(padding: const EdgeInsets.fromLTRB(22, 24, 22, 26),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text('歡迎來到 PAWPAY', style: TextStyle(color: p.ink, fontSize: 20, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Text('登入或建立帳號，開始你的記帳旅程',
                      style: TextStyle(color: p.ink2, fontSize: 12, height: 1.5)),
                    const SizedBox(height: 22),
                    TextField(
                      controller: _emailController,
                      enabled: !_isLoading,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.email],
                      autocorrect: false,
                      style: TextStyle(color: p.ink),
                      decoration: _fieldDecoration(p, '電子郵件', 'email@domain.com', Icons.mail_outline_rounded),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _passwordController,
                      enabled: !_isLoading,
                      obscureText: _obscurePassword,
                      autofillHints: const [AutofillHints.password],
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) { if (!_isLoading) _handleEmailLogin(); },
                      style: TextStyle(color: p.ink),
                      decoration: _fieldDecoration(p, '密碼', '至少 6 個字', Icons.lock_outline_rounded).copyWith(
                        suffixIcon: IconButton(
                          tooltip: _obscurePassword ? '顯示密碼' : '隱藏密碼',
                          onPressed: _isLoading ? null : () => setState(() => _obscurePassword = !_obscurePassword),
                          icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                            size: 20, color: p.accentInk),
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    PawToyButton(label: '登入 / 建立帳號',
                      onPressed: _isLoading ? null : _handleEmailLogin, icon: Icons.arrow_forward_rounded),
                    const SizedBox(height: 26),
                    Row(children: [
                      Expanded(child: Divider(color: p.line)),
                      Padding(padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text('或使用其他方式', style: TextStyle(color: p.ink2, fontSize: 12))),
                      Expanded(child: Divider(color: p.line)),
                    ]),
                    const SizedBox(height: 14),
                    _buildSocialButton(context, text: '使用 Google 登入', icon: FontAwesomeIcons.google,
                      color: const Color(0xFF4285F4), onPressed: _isLoading ? null : _handleGoogleLogin),
                    const SizedBox(height: 10),
                    _buildSocialButton(context, text: '使用 Apple 登入', icon: FontAwesomeIcons.apple,
                      color: p.ink, onPressed: _isLoading ? null : () => _navigateToHome(context)),
                    const SizedBox(height: 10),
                    _buildSocialButton(context, text: '使用 LINE 登入', icon: FontAwesomeIcons.line,
                      color: const Color(0xFF06A84F), onPressed: _isLoading ? null : _handleLineLogin),
                    const SizedBox(height: 10),
                    _buildSocialButton(context, text: '使用手機號碼登入', icon: FontAwesomeIcons.phoneFlip,
                      color: p.accentInk, onPressed: _isLoading ? null : _handlePhoneLogin),
                  ]),
                ),
                const SizedBox(height: 24),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.favorite_rounded, color: p.accentInk, size: 12),
                  const SizedBox(width: 6),
                  Flexible(child: Text('每一點累積，都值得被好好收藏', textAlign: TextAlign.center,
                    style: TextStyle(color: p.ink2, fontSize: 11))),
                ]),
              ])),
            )),
          )),
          if (_isLoading) ...[
            ModalBarrier(dismissible: false, color: p.ink.withValues(alpha: .18)),
            Center(child: Semantics(liveRegion: true, label: '登入中，請稍候',
              child: PawToyCard(padding: const EdgeInsets.all(26),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  CircularProgressIndicator(color: p.accentInk, strokeWidth: 3),
                  const SizedBox(height: 16),
                  Text('正在準備你的旅程…', style: TextStyle(color: p.ink, fontWeight: FontWeight.w600)),
                ]),
              ),
            )),
          ],
        ])),
      ),
    );
  }

  InputDecoration _fieldDecoration(AppPalette p, String label, String hint, IconData icon) => InputDecoration(
    labelText: label, hintText: hint, floatingLabelBehavior: FloatingLabelBehavior.always,
    labelStyle: TextStyle(color: p.accentInk, fontWeight: FontWeight.w600),
    hintStyle: TextStyle(color: p.ink2, fontSize: 13),
    prefixIcon: Icon(icon, color: p.accentInk, size: 20),
    filled: true, fillColor: Color.lerp(p.bg, Colors.white, .45),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: p.line)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: p.accentInk, width: 1.5)),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
  );

  Widget _buildSocialButton(BuildContext context, {required String text, required IconData icon,
    required Color color, required VoidCallback? onPressed}) {
    final p = AppPalette.of(context);
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: .8), foregroundColor: p.ink,
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
        side: BorderSide(color: p.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: Row(children: [
        SizedBox(width: 24, child: Icon(icon, size: 19, color: color)),
        const SizedBox(width: 12),
        Expanded(child: Text(text, textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
        const SizedBox(width: 8),
        Icon(Icons.chevron_right_rounded, color: p.ink3, size: 18),
      ]),
    );
  }
}
