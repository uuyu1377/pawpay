import 'package:flutter/material.dart';

/// 預設配色 = 原本的品牌粉紅 #FF8FAB，也就是 HSL(345, 100%, 78%)。
const double kDefaultHue = 345;
const double kDefaultSat = 1.00;
const double kDefaultLight = 0.78;

/// 使用者在設定頁選的三個參數。
@immutable
class PaletteSpec {
  const PaletteSpec({
    this.hue = kDefaultHue,
    this.sat = kDefaultSat,
    this.light = kDefaultLight,
  });

  /// 色相 0–360
  final double hue;

  /// 飽和度 0–1。往左拉整體變灰、不刺眼；綠色、青色系尤其需要拉低，
  /// 不然 100% 飽和度看起來會像螢光筆。
  final double sat;

  /// 亮度 0–1。往左拉顏色變深、對比變強。
  final double light;

  PaletteSpec copyWith({double? hue, double? sat, double? light}) => PaletteSpec(
        hue: hue ?? this.hue,
        sat: sat ?? this.sat,
        light: light ?? this.light,
      );

  @override
  bool operator ==(Object other) =>
      other is PaletteSpec &&
      other.hue == hue &&
      other.sat == sat &&
      other.light == light;

  @override
  int get hashCode => Object.hash(hue, sat, light);
}

/// 設定頁的快速選色。每一組的飽和度、亮度都是手調過的 ——
/// 同樣的參數套在不同色相上不會一樣好看，綠色系要壓飽和度才不刺眼。
class PalettePreset {
  const PalettePreset(this.name, this.spec);
  final String name;
  final PaletteSpec spec;
}

const List<PalettePreset> kPalettePresets = <PalettePreset>[
  PalettePreset('粉紅', PaletteSpec(hue: 345, sat: 1.00, light: 0.78)),
  PalettePreset('珊瑚橘', PaletteSpec(hue: 14, sat: 0.88, light: 0.72)),
  PalettePreset('奶油黃', PaletteSpec(hue: 40, sat: 0.80, light: 0.66)),
  PalettePreset('抹茶綠', PaletteSpec(hue: 140, sat: 0.42, light: 0.60)),
  PalettePreset('湖水藍', PaletteSpec(hue: 196, sat: 0.60, light: 0.64)),
  PalettePreset('薰衣草', PaletteSpec(hue: 262, sat: 0.52, light: 0.72)),
];

/// 介面配色。
///
/// 重點：**所有顏色都從 PaletteSpec 的三個參數推導出來**，各角色之間的
/// 飽和度倍率與亮度偏移是寫死的。所以使用者怎麼調，顏色之間的相對關係
/// （對比、深淺、層級）都不變 —— 不會出現某個組合讓字讀不到。
///
/// 用法：`final p = AppPalette.of(context);` 然後 `p.accent`、`p.bg`……
/// 不要再在頁面裡寫 `Color(0xFF...)`，寫死的顏色不會跟著使用者的選擇變。
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.spec,
    required this.bg,
    required this.card,
    required this.ink,
    required this.ink2,
    required this.ink3,
    required this.line,
    required this.accent,
    required this.accentSoft,
    required this.accentInk,
  });

  final PaletteSpec spec;

  /// 頁面底色。帶一點色相的極淡色，不是純白。
  final Color bg;

  /// 卡片底色。固定白色，讓卡片從 bg 浮出來。
  final Color card;

  /// 主要文字。帶一點色相的近黑。
  final Color ink;

  /// 次要文字（說明、副標）
  final Color ink2;

  /// 最淡的文字（未選取的 tab、placeholder）
  final Color ink3;

  /// 分隔線、邊框
  final Color line;

  /// 重點色。按鈕、選中狀態、可點的東西。
  final Color accent;

  /// 重點色的淡底。banner、chip、圓形按鈕的內填色。
  final Color accentSoft;

  /// 放在 accentSoft 上的文字／圖示色，比 accent 深一階才讀得清楚。
  final Color accentInk;

  factory AppPalette.fromSpec(PaletteSpec s) {
    final h = s.hue % 360;
    final sat = s.sat.clamp(0.0, 1.0);
    final light = s.light.clamp(0.32, 0.92);
    Color c(double ss, double ll) => HSLColor.fromAHSL(
          1,
          h,
          ss.clamp(0.0, 1.0),
          ll.clamp(0.0, 1.0),
        ).toColor();

    return AppPalette(
      spec: PaletteSpec(hue: h, sat: sat, light: light),
      bg: c(sat * 0.40, 0.97),
      card: Colors.white,
      ink: c(sat * 0.14, 0.15),
      ink2: c(sat * 0.10, 0.50),
      ink3: c(sat * 0.12, 0.72),
      line: c(sat * 0.35, 0.92),
      accent: c(sat, light), // 預設參數下＝ #FF8FAB
      accentSoft: c(sat * 0.95, 0.95), // 預設參數下＝ #FFE8EE
      accentInk: c(sat * 0.80, (light * 0.55).clamp(0.28, 0.46)),
    );
  }

  factory AppPalette.fromHue(double hue) =>
      AppPalette.fromSpec(PaletteSpec(hue: hue));

  /// 語意色。這兩個**不跟著使用者的配色變** —— 收入永遠是綠的、超支永遠是紅的，
  /// 不然使用者選了紅色系，「收入」就會看起來像警告。
  static const Color good = Color(0xFF2E9E77);
  static const Color danger = Color(0xFFE5534B);

  /// 全 App 只用這三個圓角值。
  static const double rCard = 18;
  static const double rControl = 12;
  static const double rPill = 999;

  /// 卡片陰影。用重點色染一點而不是純黑，整體比較融合。
  List<BoxShadow> get cardShadow => [
        BoxShadow(
          color: accent.withOpacity(0.20),
          blurRadius: 10,
          offset: const Offset(0, 2),
        ),
      ];

  static AppPalette of(BuildContext context) =>
      Theme.of(context).extension<AppPalette>() ??
      AppPalette.fromSpec(const PaletteSpec());

  @override
  AppPalette copyWith({double? hue, double? sat, double? light}) =>
      AppPalette.fromSpec(spec.copyWith(hue: hue, sat: sat, light: light));

  /// 換配色時的過場。色相走最短路徑，不會繞一整圈彩虹。
  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    var d = other.spec.hue - spec.hue;
    if (d > 180) d -= 360;
    if (d < -180) d += 360;
    return AppPalette.fromSpec(PaletteSpec(
      hue: spec.hue + d * t,
      sat: spec.sat + (other.spec.sat - spec.sat) * t,
      light: spec.light + (other.spec.light - spec.light) * t,
    ));
  }
}

/// 用使用者選的參數組出 ThemeData。
///
/// `ColorScheme.fromSeed` 讓所有 Material 元件（按鈕、輸入框、對話框、開關、
/// SnackBar……）自動跟著換色，不用一個一個改。
ThemeData buildAppTheme(PaletteSpec spec) {
  final p = AppPalette.fromSpec(spec);
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: p.accent,
      brightness: Brightness.light,
    ),
    scaffoldBackgroundColor: p.bg,
    extensions: <ThemeExtension<dynamic>>[p],
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}
