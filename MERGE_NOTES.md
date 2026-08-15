# 記帳 + 大富翁合併說明

這份 Flutter 專案以原本已連 MySQL 的記帳 App 為基底，加入大富翁完整頁面與 MySQL API 串接。

## 新增 / 修改重點

### 新增頁面
- `lib/pages/gacha_page.dart`：扭蛋頁，抽中寵物會寫入 MySQL `pets`。
- `lib/pages/monster_page.dart`：公會討伐頁，攻擊紀錄寫入 MySQL `game_logs`。

### 修改頁面
- `lib/pages/playground_page.dart`：大富翁主頁，玩家金錢、位置、地產等級、地產擁有者會同步到 MySQL。
- `lib/pages/pet_page.dart`：寵物列表與餵食功能改為呼叫後端。
- `lib/pages/add_friend_page.dart`：好友搜尋與加入改為呼叫後端。

### 新增服務
- `lib/services/game_api_service.dart`：集中管理 `/game/*` API。

### iOS 權限
- `ios/Runner/Info.plist` 補上相機、麥克風、語音辨識描述。

## 使用前請確認

1. 先啟動 MySQL + FastAPI 後端。
2. 若用 Android 真機，請修改：
   - `lib/config/backend_config.dart`
   - `serverIp` 改成電腦在同一 Wi-Fi 下的 IP。
3. 若用 Android Emulator，請將：
   - `BackendConfig.androidEmulator = true`
4. 執行：
   - `flutter pub get`
   - `flutter run`

## 後端要同步更新

請同時使用這次提供的 `merged_myapp_backend_mysql_api`，因為大富翁的 API 是新增在 FastAPI 後端的 `/game/*` 路由。
