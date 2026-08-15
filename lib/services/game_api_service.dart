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

  Future<Map<String, dynamic>> gachaDraw({int userId = 1, int cost = 100}) async {
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

  Future<void> recordMissionEvent({
    Object? userId,
    required String source,
    required bool isInvoice,
  }) async {
    final uid = await _resolveUserId(userId);
    await _dio.post(
      '$aiBaseUrl/api/game/mission-event',
      data: {
        'user_id': uid,
        'event_type': 'expense_recorded',
        'source': source,
        'is_invoice': isInvoice,
      },
      options: await _authOptions(),
    );
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