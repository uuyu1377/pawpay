import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/backend_config.dart';

/// ★★★ 新增：Firebase 登入服務 ★★★
/// Google 登入與 Email/密碼 登入，最後都會拿到「Firebase ID Token」，
/// 再把它送到後端 /api/auth/firebase，換回內部 9 位數 user_id + JWT。
/// 存的 key 跟原本一模一樣 (user_id / jwt_token)，所以其他功能不用改就能沿用。
class FirebaseAuthService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  /// 用 Google 登入 → 回傳 Firebase ID Token (失敗會 throw)
  /// 注意：google_sign_in v7 的新流程 —— 先 authenticate 拿身分，再 authorizeScopes 拿 token。
  static Future<String> signInWithGoogle() async {
    final GoogleSignInAccount googleUser =
    await GoogleSignIn.instance.authenticate();

    // 取得 email / profile 權限，順便拿 accessToken
    final clientAuth = await googleUser.authorizationClient
        .authorizeScopes(['email', 'profile']);

    final credential = GoogleAuthProvider.credential(
      idToken: googleUser.authentication.idToken,
      accessToken: clientAuth.accessToken,
    );

    await _auth.signInWithCredential(credential);

    final idToken = await _auth.currentUser?.getIdToken();
    if (idToken == null) {
      throw Exception('無法取得 Firebase ID Token (Google)');
    }
    return idToken;
  }

  /// 用 Email + 密碼 登入；如果帳號還不存在就自動註冊一個 → 回傳 Firebase ID Token
  static Future<String> signInOrRegisterEmail(
      String email, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
    } on FirebaseAuthException catch (e) {
      // 找不到帳號 / 憑證不符 → 視為新使用者，幫他註冊
      if (e.code == 'user-not-found' || e.code == 'invalid-credential') {
        // ★★★ 修正：Firebase 開啟「防帳號列舉」後，密碼打錯也會回 invalid-credential，
        //     會被上面誤判成新使用者而去註冊，結果拿到 email-already-in-use。
        //     這裡補上判斷：若註冊時發現 email 已存在，代表是「已註冊但密碼不對」。★★★
        try {
          await _auth.createUserWithEmailAndPassword(
              email: email, password: password);
        } on FirebaseAuthException catch (e2) {
          if (e2.code == 'email-already-in-use') {
            throw Exception('這個 email 已經註冊過了，但密碼不正確。請重新輸入密碼，或用「忘記密碼」重設。');
          }
          rethrow;
        }
      } else {
        rethrow; // 其他錯誤 (密碼太弱、email 格式錯…) 往上丟給頁面顯示
      }
    }

    final idToken = await _auth.currentUser?.getIdToken();
    if (idToken == null) {
      throw Exception('無法取得 Firebase ID Token (Email)');
    }
    return idToken;
  }

  /// 把 Firebase ID Token 送到後端 → 換回內部 user_id + JWT，並存進手機
  static Future<void> exchangeTokenWithBackend(String idToken) async {
    final url = Uri.parse('${BackendConfig.baseUrl}/api/auth/firebase');
    final response = await http
        .post(
      url,
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"id_token": idToken}),
    )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      throw Exception('後端登入失敗 (${response.statusCode})：${response.body}');
    }

    final resJson = jsonDecode(response.body);
    final String? token = resJson['token'];
    final String? userId = resJson['user_id']?.toString();
    if (token == null || userId == null) {
      throw Exception('後端回傳格式不正確');
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_id', userId); // ★ 內部數字 id
    await prefs.setString('jwt_token', token); // ★ 跟原本相同的 key，其他功能直接沿用
  }

  /// ★★★ 新增：寄送重設密碼信 (忘記密碼用) ★★★
  static Future<void> sendPasswordResetEmail(String email) async {
    await _auth.sendPasswordResetEmail(email: email);
  }

  /// ★★★ 新增：手機號碼登入 - 第一步，發送簡訊驗證碼 ★★★
  /// 手機驗證要分兩步：先送出驗證碼、使用者輸入後再驗證，所以用 callback 方式處理：
  /// - onCodeSent：驗證碼已送出，把 verificationId 存起來，等使用者輸入
  /// - onAutoVerified：極少數 Android 手機可以自動讀取簡訊，直接完成登入，不用使用者輸入
  /// - onFailed：號碼格式錯誤、簡訊配額用完 (例如 Spark 免付費方案未開通帳單) 等等
  /// phoneNumber 記得要帶國碼，例如台灣門號要傳 '+886912345678'
  static Future<void> verifyPhoneNumber({
    required String phoneNumber,
    required void Function(String verificationId) onCodeSent,
    required void Function(String error) onFailed,
    required void Function(String idToken) onAutoVerified,
  }) async {
    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: (PhoneAuthCredential credential) async {
        try {
          await _auth.signInWithCredential(credential);
          final idToken = await _auth.currentUser?.getIdToken();
          if (idToken != null) {
            onAutoVerified(idToken);
          }
        } catch (e) {
          onFailed('自動驗證失敗：$e');
        }
      },
      verificationFailed: (FirebaseAuthException e) {
        // ★ 新增：把完整的錯誤代碼印出來，方便判斷是不是少了 SHA-1 指紋這類設定問題
        // ignore: avoid_print
        print('❌ FirebaseAuth verifyPhoneNumber 失敗：code=${e.code}, message=${e.message}');
        onFailed(e.message ?? '手機驗證失敗 (${e.code})');
      },
      codeSent: (String verificationId, int? resendToken) {
        onCodeSent(verificationId);
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        // 逾時沒自動抓到簡訊，維持讓使用者手動輸入驗證碼即可，這裡不用特別處理
      },
    );
  }

  /// ★★★ 新增：手機號碼登入 - 第二步，用使用者輸入的簡訊驗證碼完成登入 → 回傳 Firebase ID Token ★★★
  static Future<String> signInWithSmsCode({
    required String verificationId,
    required String smsCode,
  }) async {
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );
    await _auth.signInWithCredential(credential);

    final idToken = await _auth.currentUser?.getIdToken();
    if (idToken == null) {
      throw Exception('無法取得 Firebase ID Token (Phone)');
    }
    return idToken;
  }

  /// 登出 (Google + Firebase 都清掉)
  static Future<void> signOut() async {
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {}
    await _auth.signOut();
  }
}