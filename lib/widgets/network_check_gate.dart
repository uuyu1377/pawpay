import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../theme/app_palette.dart';

/// ★ 新增：網路連線檢查。
///
/// 我們的 App 記帳同步、AI 分析、好友、大富翁都要連後端，
/// 所以在「打開 App」以及「從背景切回 App」時檢查一次網路，
/// 沒有網路就在畫面最上層跳出提醒，請使用者開啟 Wi-Fi 或行動數據。
///
/// - 放在 MaterialApp.builder 裡，登入頁、首頁、任何頁面都蓋得到。
/// - 不需要額外套件(不用 pub get)，用 dart:io 的 DNS 查詢判斷能不能上網。
/// - 提醒出現期間每 5 秒自動重新檢查，網路一恢復提醒就自己消失。
/// - 使用者可以按「先不要」暫時關掉，下次打開 / 切回 App 會再檢查。
class NetworkCheckGate extends StatefulWidget {
  final Widget child;

  const NetworkCheckGate({super.key, required this.child});

  @override
  State<NetworkCheckGate> createState() => _NetworkCheckGateState();
}

class _NetworkCheckGateState extends State<NetworkCheckGate> with WidgetsBindingObserver {
  // 用來測試能不能上網的網域，第一個查不到會試下一個
  static const List<String> _probeHosts = ['google.com', 'www.cloudflare.com'];

  bool _offline = false;
  bool _checking = false;
  Timer? _retryTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // App 一打開就檢查一次
    _checkConnection();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _retryTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    // 從背景切回 App 時再檢查一次(使用者可能剛去開網路)
    if (state == AppLifecycleState.resumed) {
      _checkConnection();
    }
  }

  Future<bool> _hasInternet() async {
    // Web 版沒有 dart:io 的 DNS 查詢，直接當作有網路，不擋畫面
    if (kIsWeb) return true;
    for (final host in _probeHosts) {
      try {
        final result = await InternetAddress.lookup(host).timeout(const Duration(seconds: 4));
        if (result.isNotEmpty && result.first.rawAddress.isNotEmpty) {
          return true;
        }
      } catch (_) {
        // 這個網域查不到，換下一個試試
      }
    }
    return false;
  }

  Future<void> _checkConnection() async {
    if (_checking) return;
    _checking = true;
    if (mounted) setState(() {});

    final online = await _hasInternet();
    _checking = false;
    if (!mounted) return;

    setState(() {
      _offline = !online;
    });

    if (online) {
      _retryTimer?.cancel();
      _retryTimer = null;
    } else {
      // 沒網路時每 5 秒自動再檢查，恢復連線提醒就自己消失
      _retryTimer ??= Timer.periodic(const Duration(seconds: 5), (_) => _checkConnection());
    }
  }

  void _dismiss() {
    _retryTimer?.cancel();
    _retryTimer = null;
    setState(() {
      _offline = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_offline) _buildOfflineReminder(context),
      ],
    );
  }

  Widget _buildOfflineReminder(BuildContext context) {
    final accent = AppPalette.of(context).accent;

    return Positioned.fill(
      child: Material(
        color: Colors.black.withOpacity(0.55),
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 16, offset: const Offset(0, 6)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.wifi_off_rounded, size: 38, color: accent),
                ),
                const SizedBox(height: 16),
                const Text(
                  '沒有網路連線',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.brown),
                ),
                const SizedBox(height: 10),
                Text(
                  '我們的 App 需要連上網路才能同步記帳、使用 AI 分析、好友和大富翁。\n\n請開啟 Wi-Fi 或行動數據，連上後這個提醒會自動消失。',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, height: 1.5, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _checking ? null : _checkConnection,
                    icon: _checking
                        ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                        : const Icon(Icons.refresh_rounded),
                    label: Text(_checking ? '檢查中...' : '重新檢查'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: accent.withOpacity(0.6),
                      disabledForegroundColor: Colors.white,
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: _dismiss,
                  child: Text('先不要', style: TextStyle(color: Colors.grey.shade600)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}