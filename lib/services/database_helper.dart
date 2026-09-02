import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
// ★★★ 修改：隱藏 sqflite 的 Transaction，避免跟你的 model 衝突 ★★★
import 'package:sqflite/sqflite.dart' hide Transaction;
import 'package:flutter/material.dart'; // 為了使用 Icons

// ★★★ 新增：引入 Transaction Model (來自檔案 1) ★★★
import 'package:user_interface/models/transaction_model.dart';
import 'package:user_interface/services/mysql_api_service.dart';
// ★★★ 新增：引入 SharedPreferences 來抓取動態 ID ★★★
import 'package:shared_preferences/shared_preferences.dart';

/// SQLite 操作集中在這裡：
/// 1) 身分切換：只影響查詢範圍（all + 身分專屬）
/// 2) Home icon 顯示：改為讀取 [主類] + [home_unlocked 表]
/// 3) 子類解鎖規則：
///    - 預設(資料庫內建)分類：第一次記帳就顯示 icon
///    - 自動學習(新建)分類：累積 N 次才顯示 icon
class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  /// 目前使用者身分（DB 使用：student / worker / family）
  String _currentTargetGroup = 'student';

  // ====== Remote MySQL (via API) toggles ======
  // 寫入：本地 SQLite 照常寫，同步一份到 MySQL（老師要看的『連線』）
  static const bool kAlsoSyncToMySql = true;
  // 讀取：若想讓 App 直接從 MySQL 顯示資料，可改成 true（建議先關，避免網路/環境卡住）
  static const bool kReadFromMySql = false;

  // ★★★ 新增：動態獲取手機裡的真實 User ID ★★★
  Future<int> _getCurrentUserId() async {
    final prefs = await SharedPreferences.getInstance();
    final idStr = prefs.getString('user_id');
    if (idStr != null) {
      return int.tryParse(idStr) ?? 1;
    }
    return 1; // 保底機制
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('expense.db');
    return _database!;
  }

  // ========= 小工具 =========
  Future<bool> _tableExists(DatabaseExecutor db, String table) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
      [table],
    );
    return rows.isNotEmpty;
  }

  // ★★★ 新增：徹底清空本地端的所有記帳資料 ★★★
  Future<void> wipeAllLocalData() async {
    final db = await instance.database;
    // 把記帳明細表清空
    await db.delete('accounting_transactions');
    // 如果你有獨立存 tags 或 ai_notes 的表，也可以在這裡一併 db.delete 清空
    await db.delete('receipts');
    await db.delete('ai_notes');
    print("🧹 [Local DB] 本地所有記帳資料已徹底清空");
  }


  // ========= 你要的「主類名單」 (完整保留) =========
  // 這裡只用來：1) 首次啟動時把主類設成 visible  2) 排序主類顯示在前面
  static const Map<String, List<String>> _mainExpenseAll = {
    'all': [
      '飲食',
      '交通',
      '生活用品',
      '社交',
      '通訊網路',
      '服飾美容',
      '醫療健康',
      '住房',
      '娛樂',
      '其他支出',
    ],
    'student': [
      '學費與教材',
      '線上訂閱',
      '小確幸',
      '禮物與送禮',
      '不見了',
    ],
    'worker': [
      '投資理財',
      '家具家電',
    ],
    'family': [
      '房貸與修繕',
      '小孩教育',
      '保險費用',
      '長輩支出',
      '家庭旅遊',
    ],
  };

  static const Map<String, List<String>> _mainIncomeAll = {
    'all': [
      '薪水',
      '投資收益',
      '禮金',
      '其他收入',
    ],
    'student': [
      '零用錢',
      '打工收入',
      '獎學金',
    ],
    'worker': [
      '投資獲利',
    ],
    'family': [
      '被動收入',
      '退稅/補助',
    ],
  };

  // 初始化資料庫 (包含從 assets 複製)
  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    Future<void> copyFromAssets() async {
      print("🚀 正在從 assets 複製資料庫...");
      await Directory(dirname(path)).create(recursive: true);
      try {
        if (await File(path).exists()) {
          await File(path).delete();
        }
      } catch (_) {}
      final data = await rootBundle.load("assets/$filePath");
      final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      await File(path).writeAsBytes(bytes, flush: true);
      print("✅ 資料庫複製成功：$path");
    }

    Future<Database> openDbRW() async {
      // 先用一般方式開 DB；若遇到「唯讀(read-only)」就刪除重建
      // ★★★ 微調：將 singleInstance 改為 true 以避免並發鎖定問題 ★★★
      Database dbLocal = await openDatabase(path, version: 1, readOnly: false, singleInstance: true);
      try {
        // 真正做一次寫入測試
        await dbLocal.execute("CREATE TABLE IF NOT EXISTS __rw_probe (id INTEGER)");
        await dbLocal.execute("DROP TABLE IF EXISTS __rw_probe");
        return dbLocal;
      } catch (e) {
        final msg = e.toString().toLowerCase();
        if (msg.contains('read-only') || msg.contains('readonly') || msg.contains('locked')) {
          print("❌ 資料庫鎖定或唯讀，無法完成寫入測試: $e");
          await dbLocal.close();
          throw Exception('資料庫目前無法寫入（可能被其他程序鎖定），請關閉所有使用此 App 的視窗後重新啟動。');
        }
        rethrow;
      }
    }

    // A) 如果資料庫不存在：從 assets 複製
    final exists = await databaseExists(path);
    if (!exists) {
      try {
        await copyFromAssets();
      } catch (e) {
        print("❌ 複製資料庫失敗: $e");
        print("⚠️ 請檢查 pubspec.yaml 是否有宣告 assets/expense.db");
      }
    }

    // B) 開啟資料庫
    Database db = await openDbRW();

    // C) 防呆：確保 V2 主要表存在（不做任何刪庫動作，避免誤傷資料）
    try {
      final hasV2Cats = Sqflite.firstIntValue(await db.rawQuery(
        "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='accounting_categories'",
      )) ?? 0;
      final hasV2Tx = Sqflite.firstIntValue(await db.rawQuery(
        "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='accounting_transactions'",
      )) ?? 0;

      if (hasV2Cats == 0 || hasV2Tx == 0) {
        print("⚠️ 資料庫缺少 V2 表，將嘗試補齊 schema。");
        await _ensureSchema(db);
      }
    } catch (e) {
      print("⚠️ 檢查資料庫表失敗：$e");
    }

    // D) schema / bootstrap (這裡會建立新表)
    try {
      await _ensureSchema(db);
    } catch (e) {
      print("⚠️ [DB] schema 補齊失敗（略過）：$e");
    }

    try {
      await _maybeBootstrapVisibility(db);
    } catch (e) {
      print("❌ [DB] bootstrap 失敗: $e");
      await _fallbackMakeSomethingVisible(db);
    }

    return db;
  }

  Future<void> _fallbackMakeSomethingVisible(Database db) async {
    // 保底策略：只要讓主類至少能顯示
    try {
      await db.execute(
        "UPDATE accounting_categories SET is_visible = 1 WHERE target = 'all' AND level = 'main'",
      );
      print("✅ [DB] fallback：已將 target=all 的主類設為可見");
    } catch (e) {
      print("❌ [DB] fallback 也失敗：$e");
    }
  }

  // ========= schema / bootstrap =========


  Future<void> _ensureSchema(Database db) async {
    // 0) 解鎖名單表（永久存在）
    await db.execute("CREATE TABLE IF NOT EXISTS home_unlocked (name TEXT PRIMARY KEY)");
    print("✅ [DB] home_unlocked 表準備完成");

    // 1) 建立/補齊 V2 schema（Core + Accounting + Game）
    await _ensureV2Schema(db);

    // 2) 建立預設使用者（單機模式：user_id = 1）
    await _ensureDefaultUser(db);

    // 3) 若存在 legacy 舊表 → 先搬移到 V2（可重複執行，使用 ignore 避免重複）
    await _migrateLegacyToV2IfNeeded(db);

    // 4) 若搬完後 V2 分類仍為空 → 用程式 seed 主類
    await _seedDefaultCategoriesIfNeeded(db);

    // 5) 搬完後移除舊表（避免你看到兩套 transactions / categories 混在一起）
    await _dropLegacyTablesIfPresent(db);
  }



  // ==========================================
  // ★★★ V2: 你提供的新記帳 schema (Core + Accounting) ★★★
  // ==========================================

  Future<void> _ensureV2Schema(Database db) async {
    // Core
    await db.execute('''
      CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY,
        email TEXT UNIQUE,
        display_name TEXT,
        nickname TEXT,
        auth_provider TEXT,
        auth_uid TEXT,
        created_at TEXT
      )
    ''');

    // 向後相容：若 users 已存在但缺欄位，補上（避免 nickname / auth_* 寫不進去）
    final userCols = await db.rawQuery("PRAGMA table_info(users)");
    final userColNames = userCols.map((e) => (e['name'] ?? '').toString()).toSet();
    Future<void> ensureUserCol(String col, String ddl) async {
      if (!userColNames.contains(col)) {
        await db.execute("ALTER TABLE users ADD COLUMN $ddl");
      }
    }

    await ensureUserCol('email', 'email TEXT');
    await ensureUserCol('display_name', 'display_name TEXT');
    await ensureUserCol('nickname', 'nickname TEXT');
    await ensureUserCol('auth_provider', 'auth_provider TEXT');
    await ensureUserCol('auth_uid', 'auth_uid TEXT');
    await ensureUserCol('created_at', 'created_at TEXT');


    await db.execute('''
      CREATE TABLE IF NOT EXISTS user_settings (
        id INTEGER PRIMARY KEY,
        user_id INTEGER,
        scan_mode TEXT,
        is_voice_enabled INTEGER,
        last_sync_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS auth_providers (
        id INTEGER PRIMARY KEY,
        user_id INTEGER,
        provider_type TEXT,
        provider_uid TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS user_profile (
        user_id INTEGER PRIMARY KEY,
        updated_at TEXT,
        active_target TEXT,
        animal_persona TEXT
      )
    ''');

    // Accounting
    await db.execute('''
      CREATE TABLE IF NOT EXISTS accounting_categories (
        id INTEGER PRIMARY KEY,
        name TEXT,
        direction TEXT,
        target TEXT,
        level TEXT,
        parent_id INTEGER,
        icon_key TEXT,
        is_default INTEGER DEFAULT 1,
        is_custom INTEGER DEFAULT 0,
        is_visible INTEGER DEFAULT 0,
        usage_count INTEGER DEFAULT 0,
        created_by_user_id INTEGER,
        created_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS user_category_progress (
        user_id INTEGER,
        category_id INTEGER,
        usage_count INTEGER DEFAULT 0,
        unlocked_at TEXT,
        last_used_at TEXT,
        PRIMARY KEY (user_id, category_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS receipts (
        id INTEGER PRIMARY KEY,
        user_id INTEGER,
        capture_method TEXT,
        qrcode_raw TEXT,
        ocr_raw TEXT,
        parsed_json TEXT,
        merchant_tax_id TEXT,
        invoice_number TEXT,
        created_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS accounting_transactions (
        id INTEGER PRIMARY KEY,
        user_id INTEGER,
        receipt_id INTEGER,
        category_id INTEGER,
        ai_suggested_category_id INTEGER,
        amount REAL,
        currency TEXT,
        type TEXT,
        entry_method TEXT,
        source TEXT,
        merchant_name TEXT,
        note TEXT,
        date TEXT,
        ai_confidence REAL,
        is_confirmed INTEGER DEFAULT 0,
        main_category TEXT,
        created_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS transaction_items (
        id INTEGER PRIMARY KEY,
        transaction_id INTEGER,
        item_name TEXT,
        qty REAL,
        unit_price REAL,
        line_total REAL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ai_notes (
        id INTEGER PRIMARY KEY,
        transaction_id INTEGER,
        model TEXT,
        short_comment TEXT,
        items_summary TEXT,
        created_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS recurring_transactions (
        id INTEGER PRIMARY KEY,
        user_id INTEGER,
        direction TEXT,
        category_id INTEGER,
        amount REAL,
        currency TEXT,
        note TEXT,
        cadence TEXT,
        day_of_month INTEGER,
        day_of_week INTEGER,
        start_date TEXT,
        next_run_date TEXT,
        end_date TEXT,
        is_active INTEGER DEFAULT 1,
        created_at TEXT,
        updated_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS tags (
        id INTEGER PRIMARY KEY,
        user_id INTEGER,
        name TEXT,
        color TEXT,
        created_at TEXT,
        UNIQUE(user_id, name)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS transaction_tags (
        transaction_id INTEGER,
        tag_id INTEGER,
        PRIMARY KEY (transaction_id, tag_id)
      )
    ''');

    // Monopoly / Game (db designer 對齊；目前用不到也不影響)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS players (
        id INTEGER PRIMARY KEY,
        user_id INTEGER,
        money INTEGER,
        path_step INTEGER,
        jail_turns INTEGER,
        is_bankrupt INTEGER,
        character_type TEXT,
        active_pet_id INTEGER,
        equipped_item_id INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS game_logs (
        id INTEGER PRIMARY KEY,
        player_id INTEGER,
        event_type TEXT,
        message TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS block_groups (
        id INTEGER PRIMARY KEY,
        group_name TEXT,
        color_code TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS city_blocks (
        `index` INTEGER PRIMARY KEY,
        name TEXT,
        group_id INTEGER,
        base_cost INTEGER,
        level INTEGER,
        owner_id INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS chance_events (
        id INTEGER PRIMARY KEY,
        description TEXT,
        money_delta INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS pets (
        id INTEGER PRIMARY KEY,
        owner_id INTEGER,
        species_name TEXT,
        model_path TEXT,
        power INTEGER,
        speed INTEGER,
        experience INTEGER,
        name TEXT,
        level INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS friends (
        id INTEGER PRIMARY KEY,
        user_id INTEGER,
        friend_id INTEGER,
        status TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS items (
        id INTEGER PRIMARY KEY,
        item_name TEXT,
        price INTEGER,
        effect_type TEXT,
        icon_code TEXT,
        power_bonus INTEGER,
        speed_bonus INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS player_items (
        id INTEGER PRIMARY KEY,
        player_id INTEGER,
        item_id INTEGER,
        quantity INTEGER
      )
    ''');
  }

  Future<void> _ensureDefaultUser(Database db) async {
    // 單機模式：固定使用 user_id = 1
    final now = DateTime.now().toIso8601String();

    final existing = Sqflite.firstIntValue(
      await db.rawQuery("SELECT COUNT(*) FROM users WHERE id = 1"),
    ) ??
        0;
    if (existing == 0) {
      await db.insert('users', {
        'id': 1,
        'email': null,
        'display_name': 'local_user',
        'nickname': '使用者',
        'auth_provider': 'local',
        'auth_uid': 'local',
        'created_at': now,
      });
    }

    // user_settings（若需要）
    final settingsExisting = Sqflite.firstIntValue(
      await db.rawQuery("SELECT COUNT(*) FROM user_settings WHERE user_id = 1"),
    ) ??
        0;
    if (settingsExisting == 0) {
      await db.insert('user_settings', {
        'user_id': 1,
        'scan_mode': 'scan',
        'is_voice_enabled': 1,
        'last_sync_at': null,
      });
    }

    // auth_providers：至少要有 local（避免你看到空表）
    final authExisting = Sqflite.firstIntValue(
      await db.rawQuery(
        "SELECT COUNT(*) FROM auth_providers WHERE user_id = 1 AND provider_type = 'local'",
      ),
    ) ??
        0;
    if (authExisting == 0) {
      await db.insert(
        'auth_providers',
        {'user_id': 1, 'provider_type': 'local', 'provider_uid': 'local'},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }

    final profileExisting = Sqflite.firstIntValue(
      await db.rawQuery("SELECT COUNT(*) FROM user_profile WHERE user_id = 1"),
    ) ??
        0;
    if (profileExisting == 0) {
      await db.insert('user_profile', {
        'user_id': 1,
        'updated_at': now,
        'active_target': _currentTargetGroup,
        'animal_persona': null,
      });
    }
  }

  Future<void> _seedDefaultCategoriesIfNeeded(Database db) async {
    // 只在 V2 分類完全沒有資料時才 seed，避免干擾既有資料
    final v2Count = Sqflite.firstIntValue(
      await db.rawQuery("SELECT COUNT(*) FROM accounting_categories"),
    ) ??
        0;
    if (v2Count > 0) return;

    // 如果 legacy categories 存在且有資料，就不要 seed，交給 migration 去搬
    try {
      if (await _tableExists(db, 'categories')) {
        final legacyCount = Sqflite.firstIntValue(
          await db.rawQuery("SELECT COUNT(*) FROM categories"),
        ) ??
            0;
        if (legacyCount > 0) return;
      }
    } catch (_) {
      // ignore
    }

    final now = DateTime.now().toIso8601String();

    Future<void> insertMain({
      required String name,
      required String direction, // expense|income
      required String target, // all|student|worker|family
    }) async {
      final n = name.trim();
      if (n.isEmpty) return;
      await db.insert(
        'accounting_categories',
        {
          'name': n,
          'direction': direction,
          'target': target,
          'level': 'main',
          'parent_id': null,
          'icon_key': null,
          'is_default': 1,
          'is_custom': 0,
          'is_visible': 1,
          'usage_count': 0,
          'created_by_user_id': 1,
          'created_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }

    // Expense main
    for (final entry in _mainExpenseAll.entries) {
      final target = entry.key;
      for (final name in entry.value) {
        await insertMain(name: name, direction: 'expense', target: target);
      }
    }

    // Income main
    for (final entry in _mainIncomeAll.entries) {
      final target = entry.key;
      for (final name in entry.value) {
        await insertMain(name: name, direction: 'income', target: target);
      }
    }

    print("✅ [DB] V2 預設主類 seed 完成");
  }

  Future<void> _dropLegacyTablesIfPresent(Database db) async {
    // 只移除你明確指定的舊表，避免影響其他原本用好的東西
    for (final t in const ['transactions', 'categories']) {
      try {
        if (await _tableExists(db, t)) {
          await db.execute('DROP TABLE IF EXISTS $t');
          print("🧹 [DB] legacy table dropped: $t");
        }
      } catch (e) {
        print("⚠️ [DB] drop legacy table failed ($t): $e");
      }
    }
  }


  Future<void> _migrateLegacyToV2IfNeeded(Database db) async {
    final hasLegacyCats = await _tableExists(db, 'categories');
    final hasLegacyTx = await _tableExists(db, 'transactions');

    if (!hasLegacyCats && !hasLegacyTx) return;

    // 1) categories -> accounting_categories（可重複跑：ignore 避免重複）
    if (hasLegacyCats) {
      final rows = await db.query('categories');
      for (final r in rows) {
        final name = (r['name'] ?? '').toString();
        final type = (r['type'] ?? 'expense').toString();
        await db.insert(
          'accounting_categories',
          {
            'id': r['id'],
            'name': name,
            'direction': type,
            'target': (r['target_group'] ?? 'all'),
            'level': _isMainCategoryName(name, type) ? 'main' : 'sub',
            'parent_id': null,
            'icon_key': (r['icon_key'] ?? null),
            'is_default': 1,
            'is_custom': (r['is_custom'] ?? 0),
            'is_visible': (r['is_visible'] ?? 0),
            'usage_count': (r['usage_count'] ?? 0),
            'created_by_user_id': 1,
            'created_at': DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      print("✅ [DB] legacy categories -> accounting_categories 搬移完成");
    }

    // 2) transactions -> accounting_transactions（可重複跑：ignore 避免重複）
    if (hasLegacyTx) {
      // 若 categories 不存在，就不要 join（避免 SQL 失敗）
      final joinable = await _tableExists(db, 'categories');
      final txRows = await db.rawQuery(joinable
          ? '''
        SELECT t.*, c.name AS category_name, c.type AS category_type
        FROM transactions t
        LEFT JOIN categories c ON c.id = t.category_id
        ORDER BY t.id ASC
      '''
          : '''
        SELECT t.*
        FROM transactions t
        ORDER BY t.id ASC
      ''');

      for (final t in txRows) {
        final dynamic rawAmt = t['amount'];
        final double amount = (rawAmt is int)
            ? rawAmt.toDouble()
            : (rawAmt is double)
            ? rawAmt
            : double.tryParse(rawAmt?.toString() ?? '0') ?? 0.0;

        final String occurredAt = (t['transaction_date'] ?? '').toString();
        final String note = (t['note'] ?? '').toString();
        final dynamic catId = t['category_id'];

        final String catName = joinable ? (t['category_name'] ?? '').toString() : '';
        final String dir = joinable
            ? ((t['category_type'] ?? 'expense').toString())
            : (amount >= 0 ? 'expense' : 'income');

        final String? mainCat = (catName.isNotEmpty && _isMainCategoryName(catName, dir)) ? catName : null;

        await db.insert(
          'accounting_transactions',
          {
            'id': t['id'],
            'user_id': 1,
            'receipt_id': null,
            'category_id': catId,
            'ai_suggested_category_id': null,
            'amount': amount,
            'currency': 'TWD',
            'type': dir,
            'entry_method': (t['source_type'] ?? 'manual'),
            'source': (t['source_type'] ?? 'local'),
            'merchant_name': null,
            'note': note,
            'date': occurredAt,
            'ai_confidence': null,
            'is_confirmed': 1,
            'main_category': mainCat,
            'created_at': (t['created_at'] ?? DateTime.now().toIso8601String()),
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      print("✅ [DB] legacy transactions -> accounting_transactions 搬移完成");
    }
  }

  bool _isMainCategoryName(String name, String type) {
    final n = name.trim();
    if (n.isEmpty) return false;
    final map = (type == 'income') ? _mainIncomeAll : _mainExpenseAll;
    for (final entry in map.entries) {
      if (entry.value.contains(n)) return true;
    }
    return false;
  }

  Future<int?> _ensureAccountingCategoryIdByName({
    required Database db,
    required String name,
    required String direction, // expense|income
    required String target, // all|student|worker|family
    bool markAsCustom = false,
  }) async {
    final n = name.trim();
    if (n.isEmpty) return null;

    // 先優先找同 target 的，再找 all
    final rows = await db.rawQuery('''
      SELECT id FROM accounting_categories
      WHERE name = ? AND direction = ? AND (target = ? OR target = 'all')
      ORDER BY CASE WHEN target = ? THEN 0 ELSE 1 END
      LIMIT 1
    ''', [n, direction, target, target]);

    if (rows.isNotEmpty) {
      return rows.first['id'] as int?;
    }

    // 找不到就新增一個
    final id = await db.insert(
      'accounting_categories',
      {
        'name': n,
        'direction': direction,
        'target': target,
        'level': 'sub',
        'parent_id': null,
        'icon_key': null,
        'is_default': markAsCustom ? 0 : 1,
        'is_custom': markAsCustom ? 1 : 0,
        'is_visible': 0,
        'usage_count': 0,
        'created_by_user_id': 1,
        'created_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    // 若 ignore (回 0)，再查一次
    if (id == 0) {
      final rows2 = await db.rawQuery('''
        SELECT id FROM accounting_categories
        WHERE name = ? AND direction = ? AND (target = ? OR target = ? )
        ORDER BY CASE WHEN target = ? THEN 0 ELSE 1 END
        LIMIT 1
      ''', [n, direction, target, target, target]);
      if (rows2.isNotEmpty) return rows2.first['id'] as int?;
      return null;
    }

    return id;
  }

  Future<void> _touchUserCategoryProgress({
    required Database db,
    required int userId,
    required int categoryId,
    required bool unlocked,
  }) async {
    final now = DateTime.now().toIso8601String();
    final existing = await db.query(
      'user_category_progress',
      where: 'user_id = ? AND category_id = ?',
      whereArgs: [userId, categoryId],
      limit: 1,
    );

    if (existing.isEmpty) {
      await db.insert(
        'user_category_progress',
        {
          'user_id': userId,
          'category_id': categoryId,
          'usage_count': 1,
          'unlocked_at': unlocked ? now : null,
          'last_used_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return;
    }

    final current = (existing.first['usage_count'] as int?) ?? 0;
    await db.update(
      'user_category_progress',
      {
        'usage_count': current + 1,
        'unlocked_at': (unlocked && (existing.first['unlocked_at'] == null)) ? now : existing.first['unlocked_at'],
        'last_used_at': now,
      },
      where: 'user_id = ? AND category_id = ?',
      whereArgs: [userId, categoryId],
    );
  }

  DateTime? _tryParseAnyDate(String? s) {
    if (s == null) return null;
    final t = s.trim();
    if (t.isEmpty) return null;
    // 嘗試 ISO
    try {
      return DateTime.parse(t);
    } catch (_) {}

    // 嘗試 yyyy/MM/dd 或 yyyy-MM-dd
    final m = RegExp(r'^(\d{4})[\/-](\d{1,2})[\/-](\d{1,2})').firstMatch(t);
    if (m != null) {
      final y = int.tryParse(m.group(1)!);
      final mo = int.tryParse(m.group(2)!);
      final d = int.tryParse(m.group(3)!);
      if (y != null && mo != null && d != null) {
        return DateTime(y, mo, d);
      }
    }
    return null;
  }

  Future<int> insertAiTransaction({
    int userId = 1,
    required double amount,
    String currency = 'TWD',
    String direction = 'expense', // expense|income
    required String selectedMainCategory,
    required String selectedSubCategory,
    String? suggestedSubCategory,
    double? aiConfidence,
    String entryMethod = 'scan',
    String source = 'backend',
    String? merchantName,
    String? note,
    DateTime? occurredAt,
    String captureMethod = 'scan',
    String? rawInput,
    String? parsedJson,
    String? invoiceNumber,
    String? aiModel,
    String? aiShortComment,
    String? aiItemsSummary,
    List<String>? tags,
  }) async {
    final realUserId = await _getCurrentUserId();
    // ✅ MySQL：AI 記帳寫入 receipts / accounting_transactions / ai_notes / tags（透過 API）
    await MysqlApiService.instance.ensureSeeded(userId: realUserId, target: _currentTargetGroup);

    final id = await MysqlApiService.instance.createAiTransaction(
      userId: realUserId,
      target: _currentTargetGroup,
      amount: amount,
      currency: currency,
      direction: direction,
      selectedMainCategory: selectedMainCategory,
      selectedSubCategory: selectedSubCategory,
      suggestedSubCategory: suggestedSubCategory,
      aiConfidence: aiConfidence,
      entryMethod: entryMethod,
      source: source,
      merchantName: merchantName,
      note: note,
      occurredAt: occurredAt,
      captureMethod: captureMethod,
      rawInput: rawInput,
      parsedJson: parsedJson,
      invoiceNumber: invoiceNumber,
      aiModel: aiModel,
      aiShortComment: aiShortComment,
      aiItemsSummary: aiItemsSummary,
      tags: tags,
    );

    return id;
  }


  Future<void> _maybeBootstrapVisibility(Database db) async {
    // 這裡只用來標記 user_version；不再依賴 legacy categories。
    final v = Sqflite.firstIntValue(await db.rawQuery("PRAGMA user_version")) ?? 0;
    if (v >= 2) return;

    await db.transaction((txn) async {
      await txn.execute("PRAGMA user_version = 2");
    });

    print("✅ [DB] bootstrap 完成");
  }

  Future<void> _setMainVisible(
      DatabaseExecutor db, {
        required String targetGroup,
        required String type,
        required List<String> names,
      }) async {
    // 這個函式保留結構不刪除，但實際邏輯已移至 getQuickCategories
  }

  // ★ 修改：升級為 updateUserInfo，連同註冊方式一起更新
  Future<void> updateUserInfo(String nickname, String provider, {int userId = 1}) async {
    final n = nickname.trim();
    if (n.isEmpty) return;

    final realUserId = await _getCurrentUserId();
    try {
      await MysqlApiService.instance.updateUserInfo(
        userId: realUserId,
        nickname: n,
        provider: provider.isNotEmpty ? provider : 'local',
      );
    } catch (e) {
      print("⚠️ [MySQL] updateUserInfo 離線，略過: $e");
    }
  }

  // ========= 身分 =========

  Future<void> initializeUserIdentity(String identityCode) async {
    String dbTarget = identityCode;
    if (identityCode == 'u23') dbTarget = 'student';
    if (identityCode == 'a23_35') dbTarget = 'worker';
    if (identityCode == 'a35p') dbTarget = 'family';

    _currentTargetGroup = dbTarget;
    print("🔄 [MySQL] 目前身分：$identityCode -> $_currentTargetGroup");

    final realUserId = await _getCurrentUserId();
    // 後端不可用時靜默降級，離線仍可完成 Onboarding
    try {
      await MysqlApiService.instance.setUserIdentity(userId: realUserId, target: _currentTargetGroup);
    } catch (e) {
      print("⚠️ [MySQL] setUserIdentity 離線，略過: $e");
    }
    try {
      await MysqlApiService.instance.ensureSeeded(userId: realUserId, target: _currentTargetGroup);
    } catch (e) {
      print("⚠️ [MySQL] ensureSeeded 離線，略過: $e");
    }
  }

  List<String> getMainNamesForType(String type) {
    final result = <String>[];
    final seen = <String>{};

    if (type == 'expense') {
      final base = _mainExpenseAll['all'] ?? const <String>[];
      final extra = _mainExpenseAll[_currentTargetGroup] ?? const <String>[];
      for (final n in [...base, ...extra]) {
        if (seen.add(n)) result.add(n);
      }
      return result;
    }

    // income
    final base = _mainIncomeAll['all'] ?? const <String>[];
    final extra = _mainIncomeAll[_currentTargetGroup] ?? const <String>[];
    for (final n in [...base, ...extra]) {
      if (seen.add(n)) result.add(n);
    }
    return result;
  }

  // ========= 查詢 (修改重點：讀取新表 + 頻率排序) =========

  Future<List<Map<String, dynamic>>> getQuickCategories({required String type}) async {
    final realUserId = await _getCurrentUserId();
    // ✅ MySQL：首頁分類直接從 API 拿（依 is_visible=1）
    return await MysqlApiService.instance.fetchQuickCategories(
      userId: realUserId,
      direction: type,
      target: _currentTargetGroup,
    );
  }

  Future<List<Map<String, dynamic>>> getPickerCategories({required String type}) async {
    final realUserId = await _getCurrentUserId();
    // ✅ MySQL：分類選擇頁直接從 API 拿（含 main/sub、all+身分）
    return await MysqlApiService.instance.fetchPickerCategories(
      userId: realUserId,
      direction: type,
      target: _currentTargetGroup,
    );
  }

  Future<Map<String, dynamic>?> getCategoryByName(String name, {String? type}) async {
    final n = name.trim();
    if (n.isEmpty) return null;

    final dir = (type == null || type.isEmpty) ? 'expense' : type;

    final realUserId = await _getCurrentUserId();
    // ✅ MySQL：改成呼叫後端 API
    return await MysqlApiService.instance.fetchCategoryByName(
      userId: realUserId,
      name: n,
      direction: dir,
      target: _currentTargetGroup,
    );
  }

  // ========= 解鎖（MySQL 版本） =========
  /// 依「子類名稱」套用解鎖規則。
  /// - 內建分類：通常 1 次就解鎖
  /// - AI/自訂分類：可用 customUnlockThreshold（常見 5 次）
  ///
  /// 注意：這個函式必須存在，因為 main_app_shell.dart 會呼叫它。
  Future<Map<String, dynamic>> applyUnlockRuleForName({
    required String name,
    required String type,
    int customUnlockThreshold = 5,
    bool isUserCreated = false,
    int userId = 1,
  }) async {
    final n = name.trim();
    if (n.isEmpty) return {'unlocked': false};

    final realUserId = await _getCurrentUserId();
    // ✅ MySQL：交給後端統一處理 usage_count + is_visible + progress
    final unlocked = await MysqlApiService.instance.unlockCategory(
      userId: realUserId,
      name: n,
      direction: type,
      target: _currentTargetGroup,
      customUnlockThreshold: customUnlockThreshold,
      isUserCreated: isUserCreated,
    );

    return {'unlocked': unlocked};
  }

// ========= 解鎖 / 計數 (修改重點：內建分類也計數、顯示寫入新表) =========

  Future<int> incrementUsageCount(int categoryId) async {
    final db = await instance.database;
    final result = await db.query(
      'accounting_categories',
      columns: ['usage_count'],
      where: 'id = ?',
      whereArgs: [categoryId],
      limit: 1,
    );
    final currentCount =
    (result.isNotEmpty && result.first['usage_count'] != null) ? (result.first['usage_count'] as int) : 0;
    final newCount = currentCount + 1;
    await db.update('accounting_categories', {'usage_count': newCount}, where: 'id = ?', whereArgs: [categoryId]);
    return newCount;
  }

  // ★★★ 修改：現在「顯示」等於「寫入 home_unlocked 表」 ★★★
  Future<void> showCategory(String categoryName) async {
    final db = await instance.database;
    // 使用 INSERT OR IGNORE 避免重複報錯
    await db.execute(
        "INSERT OR IGNORE INTO home_unlocked (name) VALUES (?)",
        [categoryName]
    );
    print("🔓 已解鎖分類至首頁 (存入 home_unlocked): $categoryName");
  }

  Future<int> addNewCategory(String name, String type, int isVisible, {String? iconKey}) async {
    final n = name.trim();
    if (n.isEmpty) return 0;

    final realUserId = await _getCurrentUserId();
    // ✅ MySQL：新增自訂分類（sub），由後端寫入 accounting_categories
    final id = await MysqlApiService.instance.createCustomCategory(
      userId: realUserId,
      name: n,
      direction: type,
      target: _currentTargetGroup,
      parentId: null,
      iconKey: iconKey,
      isUserCreated: true,
    );
    return id;
  }


  Future<int> insertTransaction(Transaction tx) async {
    final realUserId = await _getCurrentUserId();
    // ✅ MySQL：交易直接寫入 MySQL（透過 API）
    await MysqlApiService.instance.ensureSeeded(userId: realUserId, target: _currentTargetGroup);

    final id = await MysqlApiService.instance.createManualTransaction(
      userId: realUserId,
      target: _currentTargetGroup,
      tx: tx,
    );
    return id;
  }

  Future<List<Transaction>> getAllTransactions() async {
    final realUserId = await _getCurrentUserId();
    // ✅ MySQL：交易列表直接從 MySQL 讀
    return await MysqlApiService.instance.fetchTransactions(userId: realUserId, limit: 500);
  }


// 3. 輔助函式：簡單圖示判斷 (僅供讀取時使用)
  IconData _guessIconByName(String name) {
    if (name.contains("食") || name.contains("餐") || name.contains("飲") || name.contains("零")) return Icons.fastfood_rounded;
    if (name.contains("車") || name.contains("油") || name.contains("交通")) return Icons.directions_bus_rounded;
    if (name.contains("衣") || name.contains("服") || name.contains("飾")) return Icons.checkroom_rounded;
    if (name.contains("樂") || name.contains("遊")) return Icons.sports_esports_rounded;
    if (name.contains("醫") || name.contains("藥")) return Icons.medical_services_rounded;
    if (name.contains("住") || name.contains("房") || name.contains("電") || name.contains("居")) return Icons.home_rounded;
    if (name.contains("學") || name.contains("書") || name.contains("課")) return Icons.school_rounded;
    return Icons.receipt_long_rounded;
  }

  // ==========================================
  // ★★★ 新增：為「第一筆開張」與「每日總結」提供資料查詢 ★★★
  // ==========================================

  /// 查詢指定日期（通常是今天）是否「有任何記帳紀錄」
  /// 回傳 true 代表有記過帳；回傳 false 代表一筆都沒有（適合觸發第一筆開張）
  Future<bool> hasTransactionsOnDate(DateTime date) async {
    final realUserId = await _getCurrentUserId();
    // ✅ MySQL：檢查某天是否有任何交易
    return await MysqlApiService.instance.hasTransactionsOnDate(userId: realUserId, date: date);
  }

  Future<Map<String, dynamic>> getSummaryForDate(DateTime date) async {
    final realUserId = await _getCurrentUserId();
    // ✅ MySQL：每日餓肚子統計（支出筆數與總額）交給後端 SQL 計算
    final res = await MysqlApiService.instance.fetchDailySummary(userId: realUserId, date: date);

    final count = int.tryParse(res['count']?.toString() ?? '0') ?? 0;
    final total = (res['total'] is num)
        ? (res['total'] as num).toDouble()
        : (double.tryParse(res['total']?.toString() ?? '0') ?? 0.0);

    return {'count': count, 'total': total};
  }



  // ==========================================
  // ★★★ 新增：刪除與更新交易紀錄的函式 ★★★
  // ==========================================

  /// 刪除指定的記帳紀錄
  Future<void> deleteTransaction(int id) async {
    final realUserId = await _getCurrentUserId();
    // ✅ MySQL：刪除交易
    await MysqlApiService.instance.deleteTransaction(id: id, userId: realUserId);
  }



  /// 更新已存在的記帳紀錄
  Future<void> updateTransaction(Transaction tx) async {
    final realUserId = await _getCurrentUserId();
    // ✅ MySQL：更新交易（含金額/日期/備註/分類）
    await MysqlApiService.instance.updateTransaction(
      userId: realUserId,
      target: _currentTargetGroup,
      tx: tx,
    );
  }
}