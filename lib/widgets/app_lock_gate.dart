import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App 鎖入口元件。
///
/// 設定頁會把開關與 4 位數密碼存在 SharedPreferences：
/// - setting_app_lock
/// - setting_app_passcode
///
/// 這個元件負責在 App 啟動與從背景回到前景時，真正擋住主畫面。
class AppLockGate extends StatefulWidget {
  final Widget child;
  final bool enabledForThisStart;

  const AppLockGate({
    super.key,
    required this.child,
    this.enabledForThisStart = true,
  });

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  bool _checking = true;
  bool _locked = false;
  String _pin = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadLockState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    if (state == AppLifecycleState.resumed) {
      _loadLockState(forceLock: true);
    }
  }

  Future<void> _loadLockState({bool forceLock = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = widget.enabledForThisStart && (prefs.getBool('setting_app_lock') ?? false);
    final passcode = prefs.getString('setting_app_passcode') ?? '';

    if (!mounted) return;
    setState(() {
      _checking = false;
      _pin = '';
      _error = null;
      _locked = enabled && RegExp(r'^\d{4}$').hasMatch(passcode);
    });
  }

  Future<void> _verify() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('setting_app_passcode') ?? '';
    if (_pin == saved) {
      HapticFeedback.lightImpact();
      if (!mounted) return;
      setState(() {
        _locked = false;
        _pin = '';
        _error = null;
      });
    } else {
      HapticFeedback.heavyImpact();
      if (!mounted) return;
      setState(() {
        _pin = '';
        _error = '密碼錯誤，請再試一次';
      });
    }
  }

  void _tapNumber(String value) {
    if (_pin.length >= 4) return;
    setState(() {
      _pin += value;
      _error = null;
    });
    if (_pin.length == 4) {
      Future<void>.delayed(const Duration(milliseconds: 120), _verify);
    }
  }

  void _backspace() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Stack(
      children: [
        widget.child,
        if (_locked) Positioned.fill(child: _buildLockScreen()),
      ],
    );
  }

  Widget _buildLockScreen() {
    return Material(
      color: const Color(0xFFFFF7FA),
      child: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(Icons.lock_rounded, size: 42, color: Color(0xFFFF8FAB)),
            ),
            const SizedBox(height: 22),
            const Text(
              'App 已鎖定',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              '請輸入 4 位數密碼解鎖',
              style: TextStyle(fontSize: 14, color: Colors.black54),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(4, (index) {
                final filled = index < _pin.length;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  width: 15,
                  height: 15,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: filled ? const Color(0xFFFF8FAB) : Colors.white,
                    border: Border.all(color: const Color(0xFFFF8FAB), width: 1.4),
                  ),
                );
              }),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 22,
              child: Text(
                _error ?? '',
                style: const TextStyle(color: Color(0xFFDC2626), fontSize: 13),
              ),
            ),
            const SizedBox(height: 18),
            _buildNumberPad(),
            const Spacer(),
          ],
        ),
      ),
    );
  }

  Widget _buildNumberPad() {
    final rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', 'back'],
    ];

    return Column(
      children: rows.map((row) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: row.map((item) {
              if (item.isEmpty) return const SizedBox(width: 72, height: 56);
              if (item == 'back') {
                return _padButton(
                  child: const Icon(Icons.backspace_outlined, color: Colors.black54),
                  onTap: _backspace,
                );
              }
              return _padButton(
                child: Text(item, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                onTap: () => _tapNumber(item),
              );
            }).toList(),
          ),
        );
      }).toList(),
    );
  }

  Widget _padButton({required Widget child, required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: Container(
          width: 72,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}
