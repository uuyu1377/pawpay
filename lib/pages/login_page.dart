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

  // ... (檔案的其餘部分保持不變) ...
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        // ★★★ 新增：用 Stack 疊一層 loading 遮罩 ★★★
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 40),
                    const Text(
                      '建立帳號',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '輸入電子郵件以註冊',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 32),
                    TextField(
                      controller: _emailController, // ★ 新增：接上控制器
                      decoration: InputDecoration(
                        hintText: 'email@domain.com',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Colors.grey[200],
                        contentPadding: const EdgeInsets.symmetric(
                            vertical: 16, horizontal: 20),
                      ),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 12),
                    // ★★★ 新增：密碼輸入框 ★★★
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: InputDecoration(
                        hintText: '密碼 (至少 6 個字)',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Colors.grey[200],
                        contentPadding: const EdgeInsets.symmetric(
                            vertical: 16, horizontal: 20),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Continue 按鈕 → ★ 改接 Email 登入
                    ElevatedButton(
                      onPressed: _isLoading ? null : _handleEmailLogin,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Continue',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 30),
                    Row(
                      children: [
                        const Expanded(child: Divider(color: Colors.grey)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: Text(
                            'or',
                            style: TextStyle(color: Colors.grey[600], fontSize: 16),
                          ),
                        ),
                        const Expanded(child: Divider(color: Colors.grey)),
                      ],
                    ),
                    const SizedBox(height: 30),

                    // Google, Apple, LINE, Phone 按鈕
                    _buildSocialButton(
                      context,
                      text: '使用 Google 登入',
                      icon: FontAwesomeIcons.google,
                      color: Colors.white,
                      textColor: Colors.black,
                      onPressed: _isLoading ? null : _handleGoogleLogin, // ★ 改接 Google 登入
                    ),
                    const SizedBox(height: 8),
                    _buildSocialButton(
                      context,
                      text: '使用 Apple 登入',
                      icon: FontAwesomeIcons.apple,
                      color: Colors.black,
                      textColor: Colors.white,
                      onPressed: () => _navigateToHome(context),
                    ),
                    const SizedBox(height: 12),
                    _buildSocialButton(
                      context,
                      text: '使用 LINE 登入',
                      icon: FontAwesomeIcons.line,
                      color: const Color(0xFF00C300),
                      textColor: Colors.white,
                      onPressed: _isLoading ? null : _handleLineLogin, // ★ 改接真正的 LINE 登入
                    ),
                    const SizedBox(height: 12),
                    _buildSocialButton(
                      context,
                      text: '使用手機號碼登入',
                      icon: FontAwesomeIcons.phoneFlip,
                      color: Colors.grey[200]!,
                      textColor: Colors.black,
                      onPressed: _isLoading ? null : _handlePhoneLogin, // ★ 改接真正的手機驗證登入
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),

            // ★★★ 新增：登入中的 loading 遮罩 ★★★
            if (_isLoading)
              Container(
                color: Colors.black54,
                child: const Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSocialButton(
      BuildContext context, {
        required String text,
        required IconData icon,
        required Color color,
        required Color textColor,
        required VoidCallback? onPressed, // ★ 改成可為 null (loading 時停用)
      }) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: textColor,
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: color == Colors.white
              ? const BorderSide(color: Colors.grey)
              : BorderSide.none,
        ),
        elevation: 0,
      ),
      icon: Icon(icon, size: 20),
      label: Text(
        text,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    );
  }
}