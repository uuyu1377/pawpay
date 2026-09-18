import 'dart:math' as math;

/// 某一天在特定經緯度的日出/日落時間（本地時間）。
class SolarTimes {
  final DateTime sunrise;
  final DateTime sunset;
  const SolarTimes({required this.sunrise, required this.sunset});
}

/// 目前的天空狀態：白天/晚上，以及在「日出→日落」或「日落→隔天日出」區間中的進度 (0~1)。
/// progress 用來把太陽/月亮沿著天空的弧線定位：0 在剛升起，1 在剛落下。
class SkyState {
  final bool isDaytime;
  final double progress;
  const SkyState({required this.isDaytime, required this.progress});
}

/// 用經典的日出日落公式（美國海軍天文台簡化版）純算，不需要打 API、不需要網路。
/// 只要給經緯度跟日期，就能算出當天的日出/日落時間。
class SolarTimeService {
  // 官方日出日落基準角：90°+50'，包含大氣折射與太陽視半徑的修正。
  static const double _zenith = 90.833;

  static SolarTimes calculate(DateTime localDate, double latitude, double longitude) {
    return SolarTimes(
      sunrise: _calcTime(localDate, latitude, longitude, isSunrise: true),
      sunset: _calcTime(localDate, latitude, longitude, isSunrise: false),
    );
  }

  static SkyState skyStateFor(DateTime now, double latitude, double longitude) {
    final today = calculate(DateTime(now.year, now.month, now.day), latitude, longitude);

    if (now.isAfter(today.sunrise) && now.isBefore(today.sunset)) {
      final totalDay = today.sunset.difference(today.sunrise).inSeconds;
      final elapsed = now.difference(today.sunrise).inSeconds;
      final progress = totalDay <= 0 ? 0.5 : (elapsed / totalDay).clamp(0.0, 1.0);
      return SkyState(isDaytime: true, progress: progress);
    }

    late final DateTime prevSunset;
    late final DateTime nextSunrise;
    if (now.isBefore(today.sunrise)) {
      // 凌晨、還沒日出：上一次日落是昨天的
      final yesterday = now.subtract(const Duration(days: 1));
      final y = calculate(DateTime(yesterday.year, yesterday.month, yesterday.day), latitude, longitude);
      prevSunset = y.sunset;
      nextSunrise = today.sunrise;
    } else {
      // 已經日落：下一次日出是明天的
      final tomorrow = now.add(const Duration(days: 1));
      final t = calculate(DateTime(tomorrow.year, tomorrow.month, tomorrow.day), latitude, longitude);
      prevSunset = today.sunset;
      nextSunrise = t.sunrise;
    }

    final totalNight = nextSunrise.difference(prevSunset).inSeconds;
    final elapsed = now.difference(prevSunset).inSeconds;
    final progress = totalNight <= 0 ? 0.5 : (elapsed / totalNight).clamp(0.0, 1.0);
    return SkyState(isDaytime: false, progress: progress);
  }

  static DateTime _calcTime(DateTime date, double lat, double lon, {required bool isSunrise}) {
    final n = _dayOfYear(date);
    final lngHour = lon / 15.0;
    final t = isSunrise ? n + ((6 - lngHour) / 24) : n + ((18 - lngHour) / 24);

    final m = (0.9856 * t) - 3.289;
    var l = m + (1.916 * _sinDeg(m)) + (0.020 * _sinDeg(2 * m)) + 282.634;
    l = _normalize(l, 360);

    var ra = _rad2deg(math.atan(0.91764 * _tanDeg(l)));
    ra = _normalize(ra, 360);
    final lQuadrant = (l / 90).floor() * 90.0;
    final raQuadrant = (ra / 90).floor() * 90.0;
    ra = ra + (lQuadrant - raQuadrant);
    ra /= 15;

    final sinDec = 0.39782 * _sinDeg(l);
    final cosDec = math.cos(math.asin(sinDec));

    final cosH = (_cosDeg(_zenith) - (sinDec * _sinDeg(lat))) / (cosDec * _cosDeg(lat));
    // 高緯度可能永晝/永夜導致超出定義域，夾住避免 NaN（台灣緯度不會遇到，但防呆一下）。
    final cosHClamped = cosH.clamp(-1.0, 1.0);

    var h = isSunrise ? 360 - _rad2deg(math.acos(cosHClamped)) : _rad2deg(math.acos(cosHClamped));
    h /= 15;

    final localT = h + ra - (0.06571 * t) - 6.622;
    final utRaw = localT - lngHour;
    // 事件對應的 UTC 時刻，實際可能落在「這個本地日期」的前一天或後一天的 UTC 曆日
    // （例如台灣 +8 時區的日出，換算成 UTC 一定是前一天晚上）。用「日出/日落名目時刻」
    // （6 點或 18 點減掉經度時差）來判斷該往哪個方向借位，比直接對 utRaw 取商更準，
    // 因為時角/賦時差的修正頂多幾分鐘，不會讓借位方向反過來。
    final nominalHour = isSunrise ? (6 - lngHour) : (18 - lngHour);
    final dayShift = (nominalHour / 24).floor();
    final ut = _normalize(utRaw, 24);

    final utcBase = DateTime.utc(date.year, date.month, date.day).add(Duration(days: dayShift));
    return utcBase.add(Duration(milliseconds: (ut * 3600 * 1000).round())).toLocal();
  }

  static int _dayOfYear(DateTime date) {
    return date.difference(DateTime(date.year, 1, 1)).inDays + 1;
  }

  static double _normalize(double value, double max) {
    var v = value % max;
    if (v < 0) v += max;
    return v;
  }

  static double _deg2rad(double d) => d * math.pi / 180;
  static double _rad2deg(double r) => r * 180 / math.pi;
  static double _sinDeg(double d) => math.sin(_deg2rad(d));
  static double _cosDeg(double d) => math.cos(_deg2rad(d));
  static double _tanDeg(double d) => math.tan(_deg2rad(d));
}
