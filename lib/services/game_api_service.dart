import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart'; // ★ 合併自朋友版：讀取登入 user_id / jwt
import 'package:user_interface/config/backend_config.dart';

/// 大富翁 / 寵物 / 好友功能的 MySQL API 服務。
///
/// App 不直接連 MySQL，而是透過 FastAPI：
/// Flutter -> /game/* API -> MySQL。
class GameApiService {
  GameApiService._();
  static final GameApiService instance = GameApiService._();

  static String get baseUrl {
    if (kIsWeb) return 'http://localhost:${BackendConfig.mysqlApiPort}';
    if (Platform.isAndroid) {
      if (BackendConfig.androidEmulator) {
        return 'http://10.0.2.2:${BackendConfig.mysqlApiPort}';
      }
      return BackendConfig.mysqlApiBaseUrl;
    }
    return 'http://localhost:${BackendConfig.mysqlApiPort}';
  }

  // ★ 合併自朋友版：AI/遡區端（OCR）base URL
  static String get aiBaseUrl {
    if (kIsWeb) return 'http://localhost:${BackendConfig.ocrPort}';
    if (Platform.isAndroid) {
      if (BackendConfig.androidEmulator) {
        return 'http://10.0.2.2:${BackendConfig.ocrPort}';
      }
      return BackendConfig.baseUrl;
    }
    return 'http://localhost:${BackendConfig.ocrPort}';
  }

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 3),
      receiveTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 10),
      headers: {'Content-Type': 'application/json'},
    ),
  );

  Future<Map<String, dynamic>> fetchGameState({
    int userId = 1,
    required String theme,
  }) async {
    final res = await _dio.get(
      '$baseUrl/game/state',
      queryParameters: {'user_id': userId, 'theme': theme},
    );
    return _asMap(res.data);
  }

  Future<void> updatePlayerState({
    int userId = 1,
    int localId = 0,
    required int money,
    required int pathStep,
    int jailTurns = 0,
    bool isBankrupt = false,
    required String theme,
  }) async {
    await _dio.put(
      '$baseUrl/game/player',
      data: {
        'user_id': userId,
        'local_id': localId,
        'money': money,
        'path_step': pathStep,
        'jail_turns': jailTurns,
        'is_bankrupt': isBankrupt,
        'theme': theme,
      },
    );
  }

  Future<void> updateBlockState({
    int userId = 1,
    required String theme,
    required int index,
    required String name,
    required int baseCost,
    required String blockType,
    required double positionDx,
    required double positionDy,
    required int level,
    int? ownerLocalId,
  }) async {
    await _dio.put(
      '$baseUrl/game/block',
      data: {
        'user_id': userId,
        'theme': theme,
        'index': index,
        'name': name,
        'base_cost': baseCost,
        'block_type': blockType,
        'position_dx': positionDx,
        'position_dy': positionDy,
        'level': level,
        'owner_local_id': ownerLocalId,
      },
    );
  }

  Future<void> addGameLog({
    int userId = 1,
    required String eventType,
    required String message,
  }) async {
    await _dio.post(
      '$baseUrl/game/logs',
      data: {'user_id': userId, 'event_type': eventType, 'message': message},
    );
  }

  Future<int> fetchPlayerMoney({int userId = 1}) async {
    final res = await _dio.get('$baseUrl/game/player', queryParameters: {'user_id': userId});
    final data = _asMap(res.data);
    return _asInt(data['money'], fallback: 0);
  }

  Future<List<Map<String, dynamic>>> fetchPets({int userId = 1}) async {
    final res = await _dio.get('$baseUrl/game/pets', queryParameters: {'user_id': userId});
    return _asListOfMaps(res.data);
  }

  Future<Map<String, dynamic>> feedPet({
    int userId = 1,
    required int petId,
    required String foodName,
    required int price,
    required double gain,
    bool isMystery = false,
  }) async {
    final res = await _dio.post(
      '$baseUrl/game/pets/$petId/feed',
      data: {
        'user_id': userId,
        'food_name': foodName,
        'price': price,
        'gain': gain,
        'is_mystery': isMystery,
      },
    );
    return _asMap(res.data);
  }

  Future<Map<String, dynamic>> gachaDraw({int userId = 1, int cost = 10}) async {
    final res = await _dio.post('$baseUrl/game/gacha/draw', data: {'user_id': userId, 'cost': cost});
    return _asMap(res.data);
  }

  Future<List<Map<String, dynamic>>> fetchFriends({int userId = 1}) async {
    final res = await _dio.get('$baseUrl/game/friends', queryParameters: {'user_id': userId});
    return _asListOfMaps(res.data);
  }

  Future<List<Map<String, dynamic>>> fetchLeaderboard({int userId = 1}) async {
    final res = await _dio.get('$baseUrl/game/leaderboard', queryParameters: {'user_id': userId});
    return _asListOfMaps(res.data);
  }

  Future<List<Map<String, dynamic>>> fetchRecommendedFriends({int userId = 1}) async {
    final res = await _dio.get('$baseUrl/game/friends/recommended', queryParameters: {'user_id': userId});
    return _asListOfMaps(res.data);
  }

  Future<List<Map<String, dynamic>>> searchUsers({int userId = 1, required String query}) async {
    final res = await _dio.get('$baseUrl/game/users/search', queryParameters: {'user_id': userId, 'q': query});
    return _asListOfMaps(res.data);
  }

  Future<void> addFriend({int userId = 1, required int friendId}) async {
    await _dio.post('$baseUrl/game/friends', data: {'user_id': userId, 'friend_id': friendId});
  }

  // ★★★ 新增：查詢「別人送給我、我還沒回應」的好友邀請 ★★★
  Future<List<Map<String, dynamic>>> fetchFriendRequests({int userId = 1}) async {
    final res = await _dio.get('$baseUrl/game/friends/requests', queryParameters: {'user_id': userId});
    return _asListOfMaps(res.data);
  }

  // ★★★ 新增：接受或拒絕一筆好友邀請。action 只能是 'accept' 或 'reject' ★★★
  Future<void> respondFriendRequest({
    int userId = 1,
    required int fromUserId,
    required String action,
  }) async {
    await _dio.post(
      '$baseUrl/game/friends/respond',
      data: {'user_id': userId, 'from_user_id': fromUserId, 'action': action},
    );
  }

  Future<Map<String, dynamic>> fetchMonsterStatus({int userId = 1}) async {
    final res = await _dio.get('$baseUrl/game/monster/status', queryParameters: {'user_id': userId});
    return _asMap(res.data);
  }

  Future<Map<String, dynamic>> attackMonster({int userId = 1}) async {
    final res = await _dio.post('$baseUrl/game/monster/attack', data: {'user_id': userId});
    return _asMap(res.data);
  }

  // ★★★★★ 以下為合併自朋友版（遠戲資金 / 獠劵 / 任務），均為新增，未動你現有方法 ★★★★★
  Future<String> _resolveUserId([Object? explicitUserId]) async {
    if (explicitUserId != null && explicitUserId.toString().trim().isNotEmpty) {
      return explicitUserId.toString().trim();
    }
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('user_id')?.trim();
    return (saved != null && saved.isNotEmpty) ? saved : '1';
  }

  // ★★★ 新增：公開版本，回傳 int 型別，給大富翁棋盤 (fetchGameState / updatePlayerState) 用 ★★★
  // 原本這兩個函式的 userId 參數預設寫死是 1，導致所有帳號共用同一份大富翁進度。
  // 呼叫這個方法可以拿到真正登入的 user_id，沒登入或讀不到才會退回 1。
  Future<int> resolveCurrentUserId() async {
    final idStr = await _resolveUserId();
    return int.tryParse(idStr) ?? 1;
  }

  Future<Options> _authOptions() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    return Options(
      headers: {
        'Content-Type': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      },
    );
  }

  Future<Map<String, dynamic>> addGameReward({
    Object? userId,
    required String rewardType, // land_fund | pet_tokens | gacha_coins
    required int amount,
    required String source,
    String? note,
    String? referenceKey,
  }) async {
    final uid = await _resolveUserId(userId);
    final res = await _dio.post(
      '$aiBaseUrl/api/game/reward',
      data: {
        'user_id': uid,
        'reward_type': rewardType,
        'amount': amount,
        'source': source,
        'note': note,
        'reference_key': referenceKey,
      },
      options: await _authOptions(),
    );
    return _asMap(res.data);
  }

  Future<Map<String, dynamic>> spendGameReward({
    Object? userId,
    required String rewardType, // pet_tokens | gacha_coins
    required int amount,
    required String source,
  }) async {
    final uid = await _resolveUserId(userId);
    final res = await _dio.post(
      '$aiBaseUrl/api/game/spend',
      data: {
        'user_id': uid,
        'reward_type': rewardType,
        'amount': amount,
        'source': source,
      },
      options: await _authOptions(),
    );
    return _asMap(res.data);
  }

  Future<Map<String, dynamic>> addLandFundFromInvoice({
    Object? userId,
    required int amount,
    String? invoiceNumber,
  }) {
    return addGameReward(
      userId: userId,
      rewardType: 'land_fund',
      amount: amount,
      source: 'invoice_scan',
      note: invoiceNumber == null ? null : 'invoice:$invoiceNumber',
      referenceKey: invoiceNumber == null ? null : 'invoice:${invoiceNumber.toUpperCase()}',
    );
  }

  Future<bool> hasInvoiceReward({
    Object? userId,
    required String invoiceNumber,
  }) async {
    final uid = await _resolveUserId(userId);
    final res = await _dio.get(
      '$aiBaseUrl/api/game/invoice-status',
      queryParameters: {
        'user_id': uid,
        'invoice_number': invoiceNumber,
      },
      options: await _authOptions(),
    );
    final data = _asMap(res.data);
    return data['already_rewarded'] == true;
  }

  /// 在真正寫入交易前先向全域發票表取得短效占用，避免不同使用者同時存入同一張發票。
  Future<Map<String, dynamic>> claimInvoice({
    Object? userId,
    required String invoiceNumber,
  }) async {
    final uid = await _resolveUserId(userId);
    final options = (await _authOptions()).copyWith(
      validateStatus: (status) => status != null && status < 500,
    );
    final res = await _dio.post(
      '$aiBaseUrl/api/invoices/claim',
      data: {'user_id': uid, 'invoice_number': invoiceNumber},
      options: options,
    );
    final data = _asMap(res.data);
    if (res.statusCode == 409) return {...data, 'status': 'duplicate'};
    if ((res.statusCode ?? 500) >= 400) {
      throw StateError(data['message']?.toString() ?? '無法驗證發票是否重複');
    }
    return data;
  }

  Future<void> finalizeInvoiceClaim({
    Object? userId,
    required String invoiceNumber,
    required String claimToken,
    required int transactionId,
  }) async {
    final uid = await _resolveUserId(userId);
    await _dio.post(
      '$aiBaseUrl/api/invoices/finalize',
      data: {
        'user_id': uid,
        'invoice_number': invoiceNumber,
        'claim_token': claimToken,
        'transaction_id': transactionId,
      },
      options: await _authOptions(),
    );
  }

  Future<void> releaseInvoiceClaim({
    Object? userId,
    required String invoiceNumber,
    required String claimToken,
  }) async {
    final uid = await _resolveUserId(userId);
    await _dio.post(
      '$aiBaseUrl/api/invoices/release',
      data: {
        'user_id': uid,
        'invoice_number': invoiceNumber,
        'claim_token': claimToken,
      },
      options: await _authOptions(),
    );
  }

  Future<Map<String, dynamic>> addPetTokens({
    Object? userId,
    required int amount,
    required String source,
  }) {
    return addGameReward(
      userId: userId,
      rewardType: 'pet_tokens',
      amount: amount,
      source: source,
    );
  }

  Future<Map<String, dynamic>> addGachaCoins({
    Object? userId,
    required int amount,
    required String source,
  }) {
    return addGameReward(
      userId: userId,
      rewardType: 'gacha_coins',
      amount: amount,
      source: source,
    );
  }

  Future<Map<String, dynamic>> dailyCheckIn({Object? userId}) async {
    final uid = await _resolveUserId(userId);
    final res = await _dio.post(
      '$aiBaseUrl/api/game/daily-checkin',
      data: {'user_id': uid},
      options: await _authOptions(),
    );
    return _asMap(res.data);
  }

  Future<Map<String, dynamic>> fetchRewardWallet({Object? userId}) async {
    final uid = await _resolveUserId(userId);
    final res = await _dio.get(
      '$aiBaseUrl/api/game/wallet',
      queryParameters: {'user_id': uid},
      options: await _authOptions(),
    );
    return _asMap(res.data);
  }

  Future<Map<String, dynamic>> fetchPetChoiceState({Object? userId}) async {
    final uid = await _resolveUserId(userId);
    final res = await _dio.get(
      '$aiBaseUrl/api/game/pet-choice',
      queryParameters: {'user_id': uid},
      options: await _authOptions(),
    );
    return _asMap(res.data);
  }

  Future<Map<String, dynamic>> purchasePetChoiceTicket({Object? userId}) async {
    final uid = await _resolveUserId(userId);
    final res = await _dio.post(
      '$aiBaseUrl/api/game/pet-choice/purchase',
      data: {'user_id': uid, 'package_id': 'pet_ticket_200'},
      options: await _authOptions(),
    );
    return _asMap(res.data);
  }

  Future<Map<String, dynamic>> redeemPetChoiceTicket({
    Object? userId,
    required String speciesKey,
  }) async {
    final uid = await _resolveUserId(userId);
    final res = await _dio.post(
      '$aiBaseUrl/api/game/pet-choice/redeem',
      data: {'user_id': uid, 'species_key': speciesKey},
      options: await _authOptions(),
    );
    return _asMap(res.data);
  }

  Future<List<Map<String, dynamic>>> fetchRewardLogs({
    Object? userId,
    int limit = 50,
  }) async {
    final uid = await _resolveUserId(userId);
    final res = await _dio.get(
      '$aiBaseUrl/api/game/reward-logs',
      queryParameters: {'user_id': uid, 'limit': limit},
      options: await _authOptions(),
    );
    final data = _asMap(res.data);
    return _asListOfMaps(data['logs']);
  }

  Future<Map<String, dynamic>> recordMissionEvent({
    Object? userId,
    required String source,
    required bool isInvoice,
    String eventType = 'expense_recorded',
    double? amountTwd,
    String? category,
    DateTime? occurredAt,
    String? uniqueHint,
  }) async {
    final uid = await _resolveUserId(userId);
    final res = await _dio.post(
      '$aiBaseUrl/api/game/mission-event',
      data: {
        'user_id': uid,
        'event_type': eventType,
        'source': source,
        'is_invoice': isInvoice,
        if (amountTwd != null) 'amount_twd': amountTwd,
        if (category != null) 'category': category,
        if (occurredAt != null) 'occurred_at': occurredAt.toIso8601String(),
        if (uniqueHint != null && uniqueHint.isNotEmpty) 'unique_hint': uniqueHint,
      },
      options: await _authOptions(),
    );
    return _asMap(res.data);
  }

  Future<Map<String, dynamic>> recordReportView({Object? userId}) {
    return recordMissionEvent(
      userId: userId,
      source: 'weekly_report',
      isInvoice: false,
      eventType: 'report_viewed',
    );
  }

  Future<Map<String, dynamic>> setMonthlyBudget({
    Object? userId,
    required double amount,
  }) async {
    final uid = await _resolveUserId(userId);
    final res = await _dio.post(
      '$aiBaseUrl/api/game/monthly-budget',
      data: {'user_id': uid, 'amount': amount},
      options: await _authOptions(),
    );
    return _asMap(res.data);
  }

  Future<List<Map<String, dynamic>>> fetchMissions({Object? userId}) async {
    final uid = await _resolveUserId(userId);
    final res = await _dio.get(
      '$aiBaseUrl/api/game/missions',
      queryParameters: {'user_id': uid},
      options: await _authOptions(),
    );
    final data = _asMap(res.data);
    return _asListOfMaps(data['missions']);
  }

  Future<Map<String, dynamic>> claimMission({
    Object? userId,
    required String missionId,
  }) async {
    final uid = await _resolveUserId(userId);
    final res = await _dio.post(
      '$aiBaseUrl/api/game/missions/$missionId/claim',
      data: {'user_id': uid},
      options: await _authOptions(),
    );
    return _asMap(res.data);
  }

  Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map) return Map<String, dynamic>.from(data);
    return <String, dynamic>{};
  }

  List<Map<String, dynamic>> _asListOfMaps(dynamic data) {
    if (data is! List) return <Map<String, dynamic>>[];
    return data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  int _asInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }
}