import 'package:flutter/material.dart';
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
                      onPressed: () => _navigateToHome(context),
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