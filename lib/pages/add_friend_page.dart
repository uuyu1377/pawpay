import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:user_interface/services/game_api_service.dart';

class AddFriendPage extends StatefulWidget {
  const AddFriendPage({super.key});

  @override
  State<AddFriendPage> createState() => _AddFriendPageState();
}

class _AddFriendPageState extends State<AddFriendPage>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  late TabController _tabController;

  bool _isLoading = true;
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _friends = [];

  int _myUserId = 1;
  String _myNickname = '我';

  // Scanner state
  bool _scanning = false;
  bool _scanProcessing = false;
  MobileScannerController? _scannerController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadMyId();
    _loadRecommended();
  }

  Future<void> _loadMyId() async {
    final prefs = await SharedPreferences.getInstance();
    final idStr = prefs.getString('user_id');
    final id = (idStr != null ? int.tryParse(idStr) : null) ?? 1;
    final nick = prefs.getString('user_nickname') ?? prefs.getString('nickname') ?? '我';
    if (mounted) setState(() { _myUserId = id; _myNickname = nick; });
  }

  Future<void> _loadRecommended() async {
    setState(() => _isLoading = true);
    try {
      final api = GameApiService.instance;
      final results = await Future.wait([api.fetchFriends(), api.fetchRecommendedFriends()]);
      if (!mounted) return;
      setState(() { _friends = results[0]; _users = results[1]; _isLoading = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _search() async {
    final q = _searchController.text.trim();
    if (q.isEmpty) { await _loadRecommended(); return; }
    setState(() => _isLoading = true);
    try {
      final users = await GameApiService.instance.searchUsers(query: q);
      if (!mounted) return;
      setState(() { _users = users; _isLoading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _snack('搜尋失敗：$e');
    }
  }

  Future<void> _addFriendByUser(Map<String, dynamic> user) async {
    final id = int.tryParse(user['id']?.toString() ?? '') ?? 0;
    if (id <= 0) return;
    await _addFriendById(id, label: (user['nickname'] ?? user['display_name'] ?? 'ID $id').toString());
    await _loadRecommended();
  }

  Future<void> _addFriendById(int id, {String? label}) async {
    try {
      await GameApiService.instance.addFriend(friendId: id);
      if (!mounted) return;
      _snack('已送出好友邀請${label != null ? '給 $label' : ''}！');
    } catch (e) {
      if (!mounted) return;
      _snack('新增好友失敗：$e');
    }
  }

  bool _isFriend(int id) =>
      _friends.any((f) => int.tryParse(f['friend_id']?.toString() ?? '') == id ||
                          int.tryParse(f['id']?.toString() ?? '') == id);

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── QR scanner ─────────────────────────────────────────────────────────────

  void _startScan() {
    _scannerController?.dispose();
    _scannerController = MobileScannerController(autoStart: true, torchEnabled: false);
    setState(() { _scanning = true; _scanProcessing = false; });
  }

  void _stopScan() {
    _scannerController?.dispose();
    _scannerController = null;
    if (mounted) setState(() { _scanning = false; _scanProcessing = false; });
  }

  void _handleScanDetect(BarcodeCapture capture) {
    if (_scanProcessing) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null) return;

    const prefix = 'petapp_friend:';
    if (!raw.startsWith(prefix)) {
      _snack('這不是好友 QR Code');
      return;
    }
    final idStr = raw.substring(prefix.length);
    final friendId = int.tryParse(idStr);
    if (friendId == null || friendId <= 0) {
      _snack('QR Code 格式錯誤');
      return;
    }
    if (friendId == _myUserId) {
      _snack('不能加自己為好友 😅');
      return;
    }

    setState(() => _scanProcessing = true);
    _stopScan();
    _addFriendById(friendId).then((_) {
      if (mounted) {
        _tabController.animateTo(0); // switch to search tab
        _loadRecommended();
      }
    });
  }

  // ── build ───────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    _scannerController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF5F5),
      appBar: AppBar(
        title: const Text('新增好友', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.brown)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.brown,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.pink,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.pink,
          onTap: (i) { if (i != 1 && _scanning) _stopScan(); },
          tabs: const [
            Tab(icon: Icon(Icons.search), text: '搜尋'),
            Tab(icon: Icon(Icons.qr_code_scanner), text: '掃描'),
            Tab(icon: Icon(Icons.qr_code_2), text: '我的碼'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _buildSearchTab(),
          _buildScannerTab(),
          _buildMyQrTab(),
        ],
      ),
    );
  }

  // ── Tab 0: 搜尋 ─────────────────────────────────────────────────────────────

  Widget _buildSearchTab() {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                hintText: '輸入好友 ID 或名稱',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: _search,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.pink,
              foregroundColor: Colors.white,
              shape: const StadiumBorder(),
              elevation: 0,
            ),
            child: const Text('搜尋'),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            _searchController.text.isEmpty ? '推薦好友' : '搜尋結果',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.brown),
          ),
        ),
      ),
      const SizedBox(height: 4),
      Expanded(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Colors.pink))
            : _users.isEmpty
                ? const Center(child: Text('目前沒有符合的使用者', style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 80),
                    itemCount: _users.length,
                    itemBuilder: (_, i) {
                      final user = _users[i];
                      final id = int.tryParse(user['id']?.toString() ?? '') ?? 0;
                      final added = _isFriend(id);
                      final name = (user['nickname'] ?? user['display_name'] ?? '玩家 $id').toString();
                      final color = Colors.primaries[name.hashCode.abs() % Colors.primaries.length];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: color.withOpacity(0.15),
                            child: Text(name.isNotEmpty ? name.substring(0, 1) : '?',
                                style: TextStyle(color: color, fontWeight: FontWeight.bold)),
                          ),
                          title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.brown)),
                          subtitle: Text('ID: $id${user['email'] != null ? ' • ${user['email']}' : ''}',
                              style: const TextStyle(fontSize: 12)),
                          trailing: ElevatedButton(
                            onPressed: added ? null : () => _addFriendByUser(user),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: added ? Colors.grey[200] : Colors.pink,
                              foregroundColor: added ? Colors.grey : Colors.white,
                              shape: const StadiumBorder(),
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                            ),
                            child: Text(added ? '已加入' : '加入'),
                          ),
                        ),
                      );
                    },
                  ),
      ),
    ]);
  }

  // ── Tab 1: 掃描 ─────────────────────────────────────────────────────────────

  Widget _buildScannerTab() {
    return Column(children: [
      const SizedBox(height: 20),
      if (!_scanning) ...[
        const Spacer(),
        const Icon(Icons.qr_code_scanner, size: 80, color: Colors.pink),
        const SizedBox(height: 16),
        const Text('掃描好友的 QR Code', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.brown)),
        const SizedBox(height: 8),
        const Text('對準好友手機上的個人 QR Code 即可加為好友',
            style: TextStyle(color: Colors.grey, fontSize: 13), textAlign: TextAlign.center),
        const SizedBox(height: 32),
        ElevatedButton.icon(
          onPressed: _startScan,
          icon: const Icon(Icons.camera_alt_rounded),
          label: const Text('開啟相機掃描'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.pink,
            foregroundColor: Colors.white,
            shape: const StadiumBorder(),
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
            textStyle: const TextStyle(fontSize: 16),
          ),
        ),
        const Spacer(),
      ] else ...[
        Expanded(
          child: Stack(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: MobileScanner(
                controller: _scannerController!,
                onDetect: _handleScanDetect,
              ),
            ),
            // 掃描框
            Center(
              child: Container(
                width: 220, height: 220,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.pink, width: 3),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            if (_scanProcessing)
              const Center(child: CircularProgressIndicator(color: Colors.white)),
            // 取消按鈕
            Positioned(
              bottom: 24, left: 0, right: 0,
              child: Center(
                child: ElevatedButton.icon(
                  onPressed: _stopScan,
                  icon: const Icon(Icons.close),
                  label: const Text('取消'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black54,
                    foregroundColor: Colors.white,
                    shape: const StadiumBorder(),
                  ),
                ),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 8),
      ],
    ]);
  }

  // ── Tab 2: 我的 QR Code ─────────────────────────────────────────────────────

  Widget _buildMyQrTab() {
    final qrData = 'petapp_friend:$_myUserId';
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(children: [
        const SizedBox(height: 8),
        const Text('我的好友 QR Code',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.brown)),
        const SizedBox(height: 6),
        Text('讓好友掃描這個碼來加你',
            style: TextStyle(color: Colors.grey[600], fontSize: 13)),
        const SizedBox(height: 28),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: Colors.pink.withOpacity(0.12), blurRadius: 16, offset: const Offset(0, 4))],
          ),
          child: Column(children: [
            // 頭像
            Container(
              width: 60, height: 60,
              decoration: BoxDecoration(
                color: Colors.pink.shade50,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.pink.shade200, width: 2),
              ),
              child: Center(
                child: Text(
                  _myNickname.isNotEmpty ? _myNickname.substring(0, 1).toUpperCase() : '?',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.pink.shade400),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(_myNickname,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.brown)),
            Text('ID: $_myUserId', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
            const SizedBox(height: 20),
            QrImageView(
              data: qrData,
              version: QrVersions.auto,
              size: 200,
              eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Color(0xFF4A2E2E)),
              dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Color(0xFF4A2E2E)),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.pink.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                qrData,
                style: TextStyle(fontSize: 11, color: Colors.grey[500], fontFamily: 'monospace'),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 24),
        Text('📲 請好友切換到「掃描」頁，對準此 QR Code',
            style: TextStyle(color: Colors.grey[600], fontSize: 13),
            textAlign: TextAlign.center),
      ]),
    );
  }
}
