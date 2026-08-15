import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:shared_preferences/shared_preferences.dart'; // ★★★ 新增：引入本地儲存庫 ★★★

import 'gacha_page.dart';
import 'playground_page.dart';
import 'package:user_interface/services/game_api_service.dart';

class PetPage extends StatefulWidget {
  const PetPage({super.key});

  @override
  State<PetPage> createState() => _PetPageState();
}

class _PetPageState extends State<PetPage> {
  int _petTokens = 0;
  bool _isLoading = true;
  final PageController _pageController = PageController(viewportFraction: 0.78);
  int _currentPage = 0;

  // All pet types
  static const List<Map<String, dynamic>> _allPetTypes = [
    // ── 原有 5 隻 ──────────────────────────────────────────────────────────
    {
      'key': 'dog',
      'name': '狗狗',
      'emoji': '🐶',
      'animation': 'assets/animations/Dog.json',
      'bgGradient': [Color(0xFFFFF8E1), Color(0xFFFFECB3)],
      'ringColor': Color(0xFFFFB300),
      'tagColor': Color(0xFFFF8F00),
    },
    {
      'key': 'cat',
      'name': '貓咪',
      'emoji': '🐱',
      'animation': 'assets/animations/Cat.json',
      'bgGradient': [Color(0xFFE3F2FD), Color(0xFFBBDEFB)],
      'ringColor': Color(0xFF42A5F5),
      'tagColor': Color(0xFF1E88E5),
    },
    {
      'key': 'parrot',
      'name': '鸚鵡',
      'emoji': '🦜',
      'animation': 'assets/animations/Parrot.json',
      'bgGradient': [Color(0xFFF3E5F5), Color(0xFFE1BEE7)],
      'ringColor': Color(0xFFAB47BC),
      'tagColor': Color(0xFF8E24AA),
    },
    {
      'key': 'sloth',
      'name': '樹懶',
      'emoji': '🦥',
      'animation': 'assets/animations/Sloth.json',
      'bgGradient': [Color(0xFFEFEBE9), Color(0xFFD7CCC8)],
      'ringColor': Color(0xFF8D6E63),
      'tagColor': Color(0xFF6D4C41),
    },
    {
      'key': 'fox',
      'name': '狐狸',
      'emoji': '🦊',
      'animation': 'assets/animations/Fox.json',
      'bgGradient': [Color(0xFFFBE9E7), Color(0xFFFFCCBC)],
      'ringColor': Color(0xFFFF5722),
      'tagColor': Color(0xFFE64A19),
    },
    // ── 新增：狗狗變體 ──────────────────────────────────────────────────────
    {
      'key': 'cute_dog',
      'name': '柴柴',
      'emoji': '🐕',
      'animation': 'assets/animations/Cute Doggy.json',
      'bgGradient': [Color(0xFFFFF3E0), Color(0xFFFFE0B2)],
      'ringColor': Color(0xFFFF8A65),
      'tagColor': Color(0xFFE64A19),
    },
    {
      'key': 'pomeranian',
      'name': '博美犬',
      'emoji': '🐩',
      'animation': 'assets/animations/Pomeranian Dog.json',
      'bgGradient': [Color(0xFFFCE4EC), Color(0xFFF8BBD9)],
      'ringColor': Color(0xFFEC407A),
      'tagColor': Color(0xFFC2185B),
    },
    {
      'key': 'norm_dog',
      'name': '諾姆犬',
      'emoji': '🦮', // ★ 修改：原本是骨頭 🦴
      'animation': 'assets/animations/Norm The Dog.json',
      'bgGradient': [Color(0xFFE8F5E9), Color(0xFFC8E6C9)],
      'ringColor': Color(0xFF66BB6A),
      'tagColor': Color(0xFF388E3C),
    },
    {
      'key': 'wagging_dog',
      'name': '甩尾狗',
      'emoji': '🐕', // ★ 修改：原本是腳印 🐾
      'animation': 'assets/animations/Wagging Dog.json',
      'bgGradient': [Color(0xFFE3F2FD), Color(0xFFBBDEFB)],
      'ringColor': Color(0xFF29B6F6),
      'tagColor': Color(0xFF0288D1),
    },
    // ── 新增：貓咪變體 ──────────────────────────────────────────────────────
    {
      'key': 'lovely_cat',
      'name': '愛心貓',
      'emoji': '😻', // ★ 修改：原本是愛心 💕
      'animation': 'assets/animations/Lovely cats.json',
      'bgGradient': [Color(0xFFFCE4EC), Color(0xFFF48FB1)],
      'ringColor': Color(0xFFE91E63),
      'tagColor': Color(0xFF880E4F),
    },
    {
      'key': 'blue_cat',
      'name': '工作貓',
      'emoji': '😼',
      'animation': 'assets/animations/Blue Working Cat.json',
      'bgGradient': [Color(0xFFE8EAF6), Color(0xFFC5CAE9)],
      'ringColor': Color(0xFF5C6BC0),
      'tagColor': Color(0xFF283593),
    },
    {
      'key': 'rocket_cat',
      'name': '火箭貓',
      'emoji': '😸', // ★ 修改：原本是火箭 🚀
      'animation': 'assets/animations/Cat in a rocket.json',
      'bgGradient': [Color(0xFFE0F2F1), Color(0xFFB2DFDB)],
      'ringColor': Color(0xFF26A69A),
      'tagColor': Color(0xFF00695C),
    },
    {
      'key': 'loader_cat',
      'name': '等待貓',
      'emoji': '🐈', // ★ 修改：原本是沙漏 ⏳
      'animation': 'assets/animations/Loader cat.json',
      'bgGradient': [Color(0xFFF3E5F5), Color(0xFFCE93D8)],
      'ringColor': Color(0xFFBA68C8),
      'tagColor': Color(0xFF6A1B9A),
    },
    // ── 新增：全新動物 ──────────────────────────────────────────────────────
    {
      'key': 'bear',
      'name': '熊熊',
      'emoji': '🐻',
      'animation': 'assets/animations/Bear Like.json',
      'bgGradient': [Color(0xFFEFEBE9), Color(0xFFBCAAA4)],
      'ringColor': Color(0xFF8D6E63),
      'tagColor': Color(0xFF4E342E),
    },
    {
      'key': 'bee',
      'name': '蜜蜂',
      'emoji': '🐝',
      'animation': 'assets/animations/Loading Flying Beee.json',
      'bgGradient': [Color(0xFFFFFDE7), Color(0xFFFFF9C4)],
      'ringColor': Color(0xFFFFD600),
      'tagColor': Color(0xFFF9A825),
    },
    {
      'key': 'giraffe',
      'name': '長頸鹿',
      'emoji': '🦒',
      'animation': 'assets/animations/Petite girafe.json',
      'bgGradient': [Color(0xFFFFF8E1), Color(0xFFFFECB3)],
      'ringColor': Color(0xFFFFCA28),
      'tagColor': Color(0xFFFF8F00),
    },
  ];

  // species_key -> pet data from API
  Map<String, Map<String, dynamic>> _unlockedPets = {};

  final List<Map<String, dynamic>> _foodShop = [
    {'name': '厚切牛排', 'price': 250, 'gain': 0.35, 'img': '🥩'},
    {'name': '炸豬排', 'price': 180, 'gain': 0.22, 'img': '🍱'},
    {'name': '問號罐頭', 'price': 110, 'gain': 0.0, 'img': '❓', 'isMystery': true},
    {'name': '蛋炒飯', 'price': 120, 'gain': 0.15, 'img': '🍛'},
    {'name': '鬆餅', 'price': 100, 'gain': 0.12, 'img': '🥞'},
    {'name': '鯖魚罐頭', 'price': 50, 'gain': 0.06, 'img': '🐟'},
  ];

  @override
  void initState() {
    super.initState();
    _loadPets();
  }

  Future<void> _loadPets() async {
    setState(() => _isLoading = true);
    try {
      final api = GameApiService.instance;
      // ★ 合併自朋友版：改讀獎勵錢包的「寵物代幣」，不再用大富翁 money。
      final wallet = await api.fetchRewardWallet();
      final pets = await api.fetchPets();
      if (!mounted) return;

      final unlockedMap = <String, Map<String, dynamic>>{};
      for (final pet in pets) {
        final key = (pet['icon_key'] ?? pet['species_name'] ?? 'dog').toString();
        unlockedMap[key] = {
          'id': int.tryParse(pet['id']?.toString() ?? '') ?? 0,
          'name': (pet['name'] ?? pet['species_name'] ?? '寵物').toString(),
          'satiety': (_toDouble(pet['satiety'], fallback: 0.45).clamp(0.0, 1.0) as num).toDouble(),
        };
      }

      setState(() {
        _petTokens = int.tryParse(wallet['pet_tokens']?.toString() ?? '') ?? 0;
        _unlockedPets = unlockedMap;
        _isLoading = false;
        // Jump to first unlocked pet if current page is locked
        if (unlockedMap.isNotEmpty && !unlockedMap.containsKey(_currentPetKey)) {
          final idx = _allPetTypes.indexWhere((p) => unlockedMap.containsKey(p['key']));
          if (idx >= 0) _currentPage = idx;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _unlockedPets = {
          'dog': {'id': 0, 'name': '離線小柴', 'satiety': 0.45},
        };
      });
      _showMsg('寵物資料庫連線失敗，顯示離線資料');
    }
  }

  String get _currentPetKey => _allPetTypes[_currentPage]['key'] as String;
  bool get _currentPetUnlocked => _unlockedPets.containsKey(_currentPetKey);
  Map<String, dynamic>? get _currentPetData => _unlockedPets[_currentPetKey];

  double _toDouble(dynamic v, {double fallback = 0.0}) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? fallback;
  }

  Future<void> _feedPet(Map<String, dynamic> food) async {
    if (!_currentPetUnlocked) return;
    final price = food['price'] as int;
    if (_petTokens < price) {
      _showMsg('寵物代幣不足！');
      return;
    }
    final petData = _currentPetData!;
    Map<String, dynamic>? spendResult;
    try {
      // ★ 合併自朋友版：先扣「寵物代幣」，不再扣大富翁地產資金。
      spendResult = await GameApiService.instance.spendGameReward(
        rewardType: 'pet_tokens',
        amount: price,
        source: 'pet_food',
      );
      // 原本 8000 的寵物 API 只負責飽食度；price=0 避免再扣一次 money。
      final result = await GameApiService.instance.feedPet(
        petId: petData['id'] as int,
        foodName: food['name'].toString(),
        price: 0,
        gain: (food['gain'] as num).toDouble(),
        isMystery: food['isMystery'] == true,
      );
      if (!mounted) return;
      setState(() {
        _petTokens = int.tryParse(spendResult?['pet_tokens']?.toString() ?? '') ?? (_petTokens - price);
        petData['satiety'] =
            (_toDouble(result['satiety'], fallback: petData['satiety'] as double).clamp(0.0, 1.0) as num)
                .toDouble();
      });
      _showMsg('${result['message'] ?? '餵食成功！'}（寵物代幣 -$price）');
    } catch (e) {
      // ★ 合併自朋友版：若代幣已扣、但寵物 API 後續失敗，就補回代幣，避免玩家白白損失。
      if (spendResult != null) {
        try {
          final refund = await GameApiService.instance.addPetTokens(
            amount: price,
            source: 'pet_food_refund',
          );
          if (mounted) {
            setState(() {
              _petTokens = int.tryParse(refund['pet_tokens']?.toString() ?? '') ?? (_petTokens + price);
            });
          }
        } catch (_) {}
      }
      _showMsg('餵食失敗，代幣未扣除；請確認 5000 與 8000 API 是否啟動');
    }
  }

  void _showMsg(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(m),
        duration: const Duration(milliseconds: 1800),
        behavior: SnackBarBehavior.floating,
        shape: const StadiumBorder(),
      ),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFFFF0F5), Color(0xFFFFF8DC)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: Colors.orange))
              : Column(
            children: [
              _buildTopBar(),
              const SizedBox(height: 2),
              _buildStatusBar(),
              const SizedBox(height: 2),
              Expanded(child: _buildPetCarousel()),
              _buildPageIndicator(),
              const SizedBox(height: 4),
              _buildShopArea(),
            ],
          ),
        ),
      ),
    );
  }

  // ── Top bar ────────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    final petType = _allPetTypes[_currentPage];
    final displayName = _currentPetUnlocked
        ? (_currentPetData!['name'] as String)
        : petType['name'] as String;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.8),
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Colors.pink.withOpacity(0.15), blurRadius: 8)],
              ),
              child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.brown, size: 16),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(petType['emoji'] as String, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 6),
              Text(
                displayName,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.brown),
              ),
              if (!_currentPetUnlocked) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(children: [
                    Icon(Icons.lock, color: Colors.grey, size: 11),
                    SizedBox(width: 2),
                    Text('未解鎖', style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
                  ]),
                ),
              ],
            ]),
          ),
          // 代幣
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.orange.withOpacity(0.3)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.monetization_on, color: Colors.orange, size: 15),
              const SizedBox(width: 4),
              Text('$_petTokens', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.brown)),
            ]),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () =>
                Navigator.push(context, MaterialPageRoute(builder: (_) => const GachaPage()))
                    .then((_) => _loadPets()),
            child: Container(
              width: 36, height: 36,
              decoration: const BoxDecoration(color: Color(0xFFF43F5E), shape: BoxShape.circle),
              child: const Icon(Icons.stars_rounded, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  // ── Status bar (satiety or locked notice) ─────────────────────────────────

  Widget _buildStatusBar() {
    final petType = _allPetTypes[_currentPage];
    final ringColor = petType['ringColor'] as Color;

    if (!_currentPetUnlocked) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.7),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.grey.withOpacity(0.2)),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Text('🔮', style: TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            Text(
              '前往扭蛋解鎖這隻寵物！',
              style: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ]),
        ),
      );
    }

    final sat = _currentPetData!['satiety'] as double;
    final satColor = sat > 0.7 ? const Color(0xFF4CAF50) : (sat > 0.35 ? Colors.orange : const Color(0xFFF44336));
    final satEmoji = sat > 0.7 ? '😊' : (sat > 0.35 ? '😐' : '😢');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.75),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: ringColor.withOpacity(0.25)),
          boxShadow: [BoxShadow(color: ringColor.withOpacity(0.1), blurRadius: 8)],
        ),
        child: Row(children: [
          Text(satEmoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          const Text('飽足感', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.brown)),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: sat,
                minHeight: 10,
                backgroundColor: Colors.grey[200],
                valueColor: AlwaysStoppedAnimation<Color>(satColor),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: satColor.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
            child: Text(
              '${(sat * 100).toInt()}%',
              style: TextStyle(color: satColor, fontWeight: FontWeight.bold, fontSize: 11),
            ),
          ),
        ]),
      ),
    );
  }

  // ── Pet carousel ──────────────────────────────────────────────────────────

  Widget _buildPetCarousel() {
    return PageView.builder(
      controller: _pageController,
      onPageChanged: (i) => setState(() => _currentPage = i),
      itemCount: _allPetTypes.length,
      itemBuilder: (context, index) {
        final isCenter = index == _currentPage;
        return AnimatedScale(
          scale: isCenter ? 1.0 : 0.86,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
          child: _buildPetCard(_allPetTypes[index], isCenter),
        );
      },
    );
  }

  Widget _buildPetCard(Map<String, dynamic> petType, bool isCenter) {
    final key = petType['key'] as String;
    final isUnlocked = _unlockedPets.containsKey(key);
    final gradientColors = petType['bgGradient'] as List<dynamic>;
    final ringColor = petType['ringColor'] as Color;
    final animPath = petType['animation'] as String;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Container(
        decoration: BoxDecoration(
          gradient: isUnlocked
              ? LinearGradient(
            colors: [gradientColors[0] as Color, gradientColors[1] as Color],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
              : LinearGradient(colors: [Colors.grey[100]!, Colors.grey[200]!]),
          borderRadius: BorderRadius.circular(32),
          border: isCenter
              ? Border.all(color: isUnlocked ? ringColor : Colors.grey[400]!, width: 2.5)
              : null,
          boxShadow: [
            BoxShadow(
              color: isUnlocked ? ringColor.withOpacity(0.28) : Colors.grey.withOpacity(0.18),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Lottie animation or grayscale preview
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 60),
              child: isUnlocked
                  ? Lottie.asset(animPath, fit: BoxFit.contain, animate: true)
                  : ColorFiltered(
                colorFilter: const ColorFilter.matrix([
                  0.2126, 0.7152, 0.0722, 0, 0,
                  0.2126, 0.7152, 0.0722, 0, 0,
                  0.2126, 0.7152, 0.0722, 0, 0,
                  0,      0,      0,      0.45, 0,
                ]),
                child: Lottie.asset(animPath, fit: BoxFit.contain, animate: false),
              ),
            ),

            // Lock overlay
            if (!isUnlocked)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(32),
                    color: Colors.white.withOpacity(0.15),
                  ),
                  child: Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.grey[600]!.withOpacity(0.80),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            )
                          ],
                        ),
                        child: const Icon(Icons.lock_rounded, color: Colors.white, size: 44),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.grey[700]!.withOpacity(0.75),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          '扭蛋解鎖',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ),
                    ]),
                  ),
                ),
              ),

            // Battle button + name tag row (unlocked pets only)
            if (isUnlocked)
              Positioned(
                bottom: 14,
                left: 14,
                right: 14,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: (petType['tagColor'] as Color).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: (petType['tagColor'] as Color).withOpacity(0.4)),
                      ),
                      child: Text(
                        _unlockedPets[key]!['name'] as String,
                        style: TextStyle(
                          color: petType['tagColor'] as Color,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () async {
                        final petData = _unlockedPets[key]!;
                        SelectedPet.set(
                          name: petData['name'] as String,
                          animationPath: petType['animation'] as String,
                          emoji: petType['emoji'] as String,
                          color: petType['ringColor'] as Color,
                        );

                        // ★★★ 新增：將選擇的寵物 Key 存入本地，讓 main_App_shell 讀取 ★★★
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setString('current_pet_key', key);

                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PlaygroundPage(
                              petName: petData['name'] as String,
                              petAnimationPath: petType['animation'] as String,
                              petEmoji: petType['emoji'] as String,
                              petColor: petType['ringColor'] as Color,
                              initialMapTheme: SelectedPet.lastMapTheme ?? MapTheme.taiwan,
                            ),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: (petType['tagColor'] as Color),
                        shape: const StadiumBorder(),
                        elevation: 3,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      ),
                      icon: const Icon(Icons.sports_kabaddi_rounded, size: 16),
                      label: const Text('上戰場', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Page indicator dots ───────────────────────────────────────────────────

  Widget _buildPageIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_allPetTypes.length, (i) {
        final isSelected = i == _currentPage;
        final petType = _allPetTypes[i];
        final isUnlocked = _unlockedPets.containsKey(petType['key']);
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: isSelected ? 28 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: isSelected
                ? (isUnlocked ? petType['ringColor'] as Color : Colors.grey[500])
                : Colors.grey[300],
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }

  // ── Food shop ─────────────────────────────────────────────────────────────

  Widget _buildShopArea() {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final petType = _allPetTypes[_currentPage];
    final ringColor = petType['ringColor'] as Color;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
      height: (_currentPetUnlocked ? 240 : 80) + bottomPad,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [BoxShadow(color: ringColor.withOpacity(0.12), blurRadius: 16, offset: const Offset(0, -4))],
      ),
      child: Column(children: [
        // 商店標題
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Row(children: [
            Text('🍽️', style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 6),
            Text(
              _currentPetUnlocked ? '餵食' : '餵食商店',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: ringColor),
            ),
          ]),
        ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.fromLTRB(12, 0, 12, bottomPad),
            child: _currentPetUnlocked ? _buildFoodGrid(ringColor) : _buildLockedShop(),
          ),
        ),
      ]),
    );
  }

  Widget _buildFoodGrid(Color accentColor) {
    return GridView.builder(
      // ★★★ 修正：原本設為 NeverScrollableScrollPhysics 導致食物清單無法上下滑動，
      //     下面的食物會被蓋住。改為可滑動（外層是 Expanded，高度已有限制）。★★★
      physics: const AlwaysScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 1.0,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: _foodShop.length,
      itemBuilder: (context, index) {
        final item = _foodShop[index];
        return InkWell(
          onTap: () => _feedPet(item),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.07),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: accentColor.withOpacity(0.2)),
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(item['img'].toString(), style: const TextStyle(fontSize: 26)),
              const SizedBox(height: 3),
              Text(
                item['name'].toString(),
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.monetization_on, color: Colors.orange, size: 11),
                const SizedBox(width: 2),
                Text('${item['price']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.brown)),
              ]),
            ]),
          ),
        );
      },
    );
  }

  Widget _buildLockedShop() {
    return Center(
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Text('🔒', style: TextStyle(fontSize: 20)),
        const SizedBox(width: 8),
        Text(
          '解鎖寵物後才能餵食～',
          style: TextStyle(color: Colors.grey[500], fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ]),
    );
  }
}