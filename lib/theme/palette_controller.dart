import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_palette.dart';

/// 使用者選的介面配色（色相／飽和度／亮度），存在 SharedPreferences。
///
/// `main.dart` 用 ValueListenableBuilder 監聽這個 notifier，
/// 所以 `update()` 一呼叫，整個 App 的顏色就會跟著換（MaterialApp 會做過場動畫）。
class PaletteController extends ValueNotifier<PaletteSpec> {
  PaletteController._() : super(const PaletteSpec());

  static final PaletteController instance = PaletteController._();

  static const String _keyHue = 'ui_hue';
  static const String _keySat = 'ui_sat';
  static const String _keyLight = 'ui_light';

  /// App 啟動時讀一次。沒設定過就用預設的粉紅。
  Future<void> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      value = PaletteSpec(
        hue: sp.getDouble(_keyHue) ?? kDefaultHue,
        sat: sp.getDouble(_keySat) ?? kDefaultSat,
        light: sp.getDouble(_keyLight) ?? kDefaultLight,
      );
    } catch (_) {
      value = const PaletteSpec();
    }
  }

  /// 改配色。
  ///
  /// [persist] 為 false 時只更新畫面不寫檔 —— 拉滑桿的過程中用這個，
  /// 放手時才真正存下來，避免一次拖曳寫上百次 SharedPreferences。
  Future<void> update(PaletteSpec spec, {bool persist = true}) async {
    final next = PaletteSpec(
      hue: spec.hue % 360,
      sat: spec.sat.clamp(0.0, 1.0),
      light: spec.light.clamp(0.32, 0.92),
    );
    if (value != next) value = next;
    if (!persist) return;
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setDouble(_keyHue, next.hue);
      await sp.setDouble(_keySat, next.sat);
      await sp.setDouble(_keyLight, next.light);
    } catch (_) {
      // 寫入失敗不影響當次使用，下次啟動會退回上一個成功存下的值
    }
  }

  /// 回到預設的品牌粉紅
  Future<void> reset() => update(const PaletteSpec());
}
