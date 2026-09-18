import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:user_interface/config/backend_config.dart';
import 'package:user_interface/models/transaction_model.dart';

class AiNewsBanner extends StatefulWidget {
  final List<Transaction> transactions;

  const AiNewsBanner({
    super.key,
    required this.transactions,
  });

  @override
  State<AiNewsBanner> createState() => _AiNewsBannerState();
}

class _AiNewsBannerState extends State<AiNewsBanner> {
  static const String _cacheKey = 'ai_news_banner_cached_messages';
  static const String _cacheTimeKey = 'ai_news_banner_cached_time';

  int _index = 0;

  Timer? _switchTimer;
  Timer? _refreshDebounce;

  List<String> _messages = [];

  bool _isFetching = false;
  int _lastTransactionLength = 0;

  @override
  void initState() {
    super.initState();

    _lastTransactionLength = widget.transactions.length;

    // 先讀取上一次成功的公告，有資料才顯示；沒有資料就完全不顯示公告區塊
    _restoreCachedMessages();

    // 背景更新公告；讀取中不顯示 loading，也不顯示失敗文字
    _loadNewsMessages();

    // 每 60 秒切換一則公告
    _switchTimer = Timer.periodic(
      const Duration(seconds: 60),
          (_) {
        if (!mounted || _messages.length <= 1) return;

        setState(() {
          _index = (_index + 1) % _messages.length;
        });
      },
    );
  }

  @override
  void didUpdateWidget(covariant AiNewsBanner oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.transactions.length != widget.transactions.length &&
        widget.transactions.length != _lastTransactionLength) {
      _lastTransactionLength = widget.transactions.length;

      // 避免新增一筆資料時短時間內重複打 API
      _refreshDebounce?.cancel();
      _refreshDebounce = Timer(const Duration(seconds: 2), () {
        _loadNewsMessages(forceRefresh: true);
      });
    }
  }

  Future<void> _restoreCachedMessages() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedText = prefs.getString(_cacheKey);

      if (cachedText == null || cachedText.trim().isEmpty) return;

      final decoded = jsonDecode(cachedText);

      if (decoded is! List) return;

      final cachedMessages = decoded
          .map((item) => item.toString())
          .where((text) => text.trim().isNotEmpty)
          .toList();

      if (cachedMessages.isEmpty) return;

      if (!mounted) return;

      setState(() {
        _messages = cachedMessages;
        _index = 0;
      });
    } catch (e) {
      debugPrint('AI 公告快取讀取失敗：$e');
    }
  }

  Future<void> _saveCachedMessages(List<String> messages) async {
    try {
      if (messages.isEmpty) return;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(messages));
      await prefs.setString(_cacheTimeKey, DateTime.now().toIso8601String());
    } catch (e) {
      debugPrint('AI 公告快取儲存失敗：$e');
    }
  }

  Future<String?> _waitForToken() async {
    final prefs = await SharedPreferences.getInstance();

    for (int i = 0; i < 5; i++) {
      final token = prefs.getString('jwt_token');

      if (token != null && token.trim().isNotEmpty) {
        return token;
      }

      await Future.delayed(const Duration(seconds: 1));
    }

    return null;
  }

  Future<void> _loadNewsMessages({bool forceRefresh = false}) async {
    if (_isFetching) return;

    _isFetching = true;

    try {
      final prefs = await SharedPreferences.getInstance();

      final token = await _waitForToken();
      final currentPet = prefs.getString('current_pet_key') ?? 'dog';
      final nickname = prefs.getString('user_nickname') ?? '使用者';

      debugPrint('AI 公告讀到的 token：$token');
      debugPrint('AI 公告目前寵物：$currentPet');
      debugPrint('AI 公告使用者暱稱：$nickname');

      if (token == null || token.trim().isEmpty) {
        debugPrint('AI 公告略過：尚未取得 token');
        return;
      }

      final uri = Uri.parse('${BackendConfig.baseUrl}/api/news-banner').replace(
        queryParameters: {
          'current_pet': currentPet,
          'nickname': nickname,
        },
      );

      debugPrint('AI 時事準備呼叫 API：$uri');

      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 45));

      debugPrint('AI 時事 status：${response.statusCode}');
      debugPrint('AI 時事 response：${response.body}');

      final dynamic decoded = jsonDecode(response.body);

      if (response.statusCode != 200 ||
          decoded is! Map<String, dynamic> ||
          !(decoded['status'] == 'success' || decoded['ok'] == true)) {
        debugPrint('AI 公告略過：後端回傳非成功狀態');
        return;
      }

      final loadedMessages = _parseMessages(decoded);

      if (loadedMessages.isEmpty) {
        debugPrint('AI 公告略過：沒有可顯示的公告內容');
        return;
      }

      await _saveCachedMessages(loadedMessages);

      if (!mounted) return;

      setState(() {
        _messages = loadedMessages;
        _index = 0;
      });
    } on TimeoutException catch (e) {
      // 超時只記錄，不顯示錯誤公告
      debugPrint('AI 公告讀取逾時：$e');
    } catch (e) {
      // 失敗只記錄，不顯示錯誤公告
      debugPrint('智慧公告 API 錯誤：$e');
    } finally {
      _isFetching = false;
    }
  }

  List<String> _parseMessages(Map<String, dynamic> decoded) {
    final dynamic rawItems = decoded['data']?['items'];
    final dynamic rawMessages = decoded['data']?['messages'];

    final List<String> result = [];

    // 新版格式：data.items
    if (rawItems is List) {
      for (final item in rawItems) {
        if (item is Map) {
          final topic = item['topic']?.toString().trim() ?? '理財提醒';
          final title = item['title']?.toString().trim() ?? '';
          final summary = item['summary']?.toString().trim() ?? '';

          String text = '';

          if (title.isNotEmpty && summary.isNotEmpty) {
            text = '【$topic】$title：$summary';
          } else if (summary.isNotEmpty) {
            text = '【$topic】$summary';
          } else if (title.isNotEmpty) {
            text = '【$topic】$title';
          }

          if (text.trim().isNotEmpty) {
            result.add(text);
          }
        } else {
          final text = item.toString().trim();
          if (text.isNotEmpty) {
            result.add(text);
          }
        }
      }
    }

    // 舊版格式：data.messages
    if (result.isEmpty && rawMessages is List) {
      result.addAll(
        rawMessages
            .map((item) => item.toString().trim())
            .where((text) => text.isNotEmpty),
      );
    }

    // 直接回傳 message
    if (result.isEmpty && decoded['message'] != null) {
      final message = decoded['message'].toString().trim();
      if (message.isNotEmpty) {
        result.add(message);
      }
    }

    return result;
  }

  @override
  void dispose() {
    _switchTimer?.cancel();
    _refreshDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 重點：讀取中、失敗、沒資料時，完全不顯示公告區塊
    if (_messages.isEmpty) {
      return const SizedBox.shrink();
    }

    final message = _messages[_index % _messages.length];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF0F5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFFFFB6C8),
          ),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.campaign_rounded,
              color: Color(0xFFFF6F9F),
              size: 22,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SizedBox(
                height: 22,
                child: MarqueeText(
                  key: ValueKey(message),
                  text: message,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MarqueeText extends StatefulWidget {
  final String text;

  const MarqueeText({
    super.key,
    required this.text,
  });

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText> {
  late final ScrollController _controller;
  Timer? _restartTimer;

  @override
  void initState() {
    super.initState();

    _controller = ScrollController();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startScroll();
    });
  }

  @override
  void didUpdateWidget(covariant MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.text != widget.text) {
      _restartTimer?.cancel();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_controller.hasClients) return;

        _controller.jumpTo(0);
        _startScroll();
      });
    }
  }

  Future<void> _startScroll() async {
    _restartTimer?.cancel();

    await Future.delayed(const Duration(seconds: 2));

    if (!mounted || !_controller.hasClients) return;

    final maxScroll = _controller.position.maxScrollExtent;

    if (maxScroll <= 0) return;

    await _controller.animateTo(
      maxScroll,
      duration: const Duration(seconds: 35),
      curve: Curves.linear,
    );

    if (!mounted || !_controller.hasClients) return;

    _restartTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted || !_controller.hasClients) return;

      _controller.jumpTo(0);
      _startScroll();
    });
  }

  @override
  void dispose() {
    _restartTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _controller,
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      child: Text(
        widget.text,
        maxLines: 1,
        softWrap: false,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Color(0xFF6B3A4A),
        ),
      ),
    );
  }
}