import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/date_symbol_data_local.dart';

// ★★★ 新增：Firebase / Google 登入 ★★★
import 'package:firebase_core/firebase_core.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_line_sdk/flutter_line_sdk.dart'; // ★ 新增：LINE 登入
import 'firebase_options.dart'; // flutterfire configure 產生的檔案

// 引入頁面
import 'main_app_shell.dart';
import 'pages/login_page.dart';
import 'widgets/app_lock_gate.dart';
import 'services/notification_service.dart'; // ★ 合併自朋友版：遊戲/旅遊匯率提醒通知服務

// ★★★ 關鍵：必須引入掃描頁面，不然 App 找不到路 ★★★
import 'features/scan/unified_auto_scan_page_v2_yolo_modified.dart';

// ★★★ 新增：Google 登入用的 Web Client ID ★★★
// 取得方式：打開 android/app/google-services.json，找到 "oauth_client" 陣列裡
// "client_type": 3 的那一筆，它的 "client_id" (結尾是 .apps.googleusercontent.com) 就是這個值。
// 貼過來取代下面這串。(Android 上一定要提供，否則拿不到 Google 的 idToken)
const String kGoogleWebClientId =
    "873539268433-5mui352qlrd542cidk5i6jf7a3s8crcc.apps.googleusercontent.com";

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ★★★ 新增：初始化 Firebase ★★★
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // ★★★ 新增：初始化 Google 登入 (v7 必須先 initialize 一次) ★★★
  await GoogleSignIn.instance.initialize(
    serverClientId: kGoogleWebClientId,
  );

  // ★ 新增：初始化 LINE SDK（channelId = 你的 LINE Login channel 的 Channel ID）
  await LineSDK.instance.setup("2010784124");

  await initializeDateFormatting('zh_TW', null);

  // ★ 合併自朋友版：初始化通知服務並從偏好設定同步排程（每日記帳提醒／旅行結束切回預設幣別提醒）
  await NotificationService.instance.initialize();
  await NotificationService.instance.syncFromPreferences();

  final prefs = await SharedPreferences.getInstance();
  final bool isOnboarded = prefs.getBool('is_onboarded') ?? false;

  runApp(MyApp(
    startPage: isOnboarded ? const MainAppShell() : const LoginPage(),
    enableAppLock: isOnboarded,
  ));
}

class MyApp extends StatelessWidget {
  final Widget startPage;
  final bool enableAppLock;

  const MyApp({super.key, required this.startPage, required this.enableAppLock});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AI 記帳',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF8FAB),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      home: AppLockGate(
        enabledForThisStart: enableAppLock,
        child: startPage,
      ),

      // ★★★ 修正這裡：補齊所有的路由 ★★★
      routes: {
        '/home': (context) => const MainAppShell(),
        '/login': (context) => const LoginPage(),

        // 補回這兩行，按鈕才會動！
        '/scan': (context) => const UnifiedAutoScanPageV2(),
        '/scan/traditional': (context) => const UnifiedAutoScanPageV2(forceTraditional: true),
      },
    );
  }
}