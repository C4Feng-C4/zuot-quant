/// indicators.dart — 技术指标引擎（忠实移植自 lib/indicators.js）
/// 公式口径：同花顺/通达信/talib 一致；warmup 期填 double.nan
library;

import 'dart:math' as math;

import '../models.dart';

double get nan => double.nan;

bool _finite(double x) => x.isFinite;

/// ---- 基础统计 ----
double sumAt(List<double> arr, int i, int n) {
  // arr[i-n+1..i] 求和；越界或含非有限值 → NaN
  double s = 0;
  for (int k = i - n + 1; k <= i; k++) {
    if (k < 0 || !_finite(arr[k])) return nan;
    s += arr[k];
  }
  return s;
}

double meanAt(List<double> arr, int i, int n) {
  final s = sumAt(arr, i, n);
  return _finite(s) ? s / n : nan;
}

double stdAt(List<double> arr, int i, int n) {
  // 样本标准差
  final m = meanAt(arr, i, n);
  if (!_finite(m)) return nan;
  double v = 0;
  for (int k = i - n + 1; k <= i; k++) v += (arr[k] - m) * (arr[k] - m);
  return math.sqrt(v / (n - 1));
}

/// ---- 简单移动平均 ----
List<double> MA(List<double> arr, int n) {
  final out = List<double>.filled(arr.length, nan);
  for (int i = n - 1; i < arr.length; i++) out[i] = meanAt(arr, i, n);
  return out;
}

/// ---- 指数移动平均（通达信口径 alpha=2/(n+1)）----
List<double> EMA(List<double> arr, int n) {
  final out = List<double>.filled(arr.length, nan);
  final alpha = 2 / (n + 1);
  double? prev;
  for (int i = 0; i < arr.length; i++) {
    final v = arr[i];
    if (!_finite(v)) {
      out[i] = prev ?? nan;
      continue;
    }
    prev = prev == null ? v : alpha * v + (1 - alpha) * prev;
    out[i] = prev;
  }
  return out;
}

/// ---- 真实波幅 TR ----
List<double> TR(List<double> high, List<double> low, List<double> close) {
  final out = List<double>.filled(high.length, nan);
  for (int i = 0; i < high.length; i++) {
    if (i == 0) {
      out[i] = high[i] - low[i];
      continue;
    }
    final pc = close[i - 1];
    out[i] = math.max(high[i] - low[i], math.max((high[i] - pc).abs(), (low[i] - pc).abs()));
  }
  return out;
}

/// ---- ATR（Wilder 平滑，等价 RMA）----
List<double> ATR(List<double> high, List<double> low, List<double> close, [int n = 14]) {
  final tr = TR(high, low, close);
  final out = List<double>.filled(high.length, nan);
  double? prev;
  for (int i = 0; i < tr.length; i++) {
    if (!_finite(tr[i])) continue;
    if (prev == null) {
      if (i >= n - 1) {
        double s = 0;
        int cnt = 0;
        for (int k = i - n + 1; k <= i; k++) {
          if (_finite(tr[k])) {
            s += tr[k];
            cnt++;
          }
        }
        if (cnt == n) {
          prev = s / n;
          out[i] = prev;
        }
      }
    } else {
      prev = (prev * (n - 1) + tr[i]) / n;
      out[i] = prev;
    }
  }
  return out;
}

/// ---- RSI（Wilder 平滑）----
List<double> RSI(List<double> close, [int n = 14]) {
  final out = List<double>.filled(close.length, nan);
  double? avgUp;
  double? avgDn;
  for (int i = 1; i < close.length; i++) {
    final ch = close[i] - close[i - 1];
    final up = math.max(ch, 0);
    final dn = math.max(-ch, 0);
    if (avgUp == null) {
      if (i >= n) {
        double su = 0, sd = 0;
        for (int k = i - n + 1; k <= i; k++) {
          final c = close[k] - close[k - 1];
          su += math.max(c, 0);
          sd += math.max(-c, 0);
        }
        avgUp = su / n;
        avgDn = sd / n;
        out[i] = avgDn == 0 ? 100 : 100 - 100 / (1 + avgUp / avgDn);
      }
    } else {
      avgUp = (avgUp * (n - 1) + up) / n;
      // avgDn 与 avgUp 成对赋值，此处必非 null；显式 ?? 0 只为通过空安全（avgUp==null 不提升 avgDn）
      avgDn = ((avgDn ?? 0) * (n - 1) + dn) / n;
      out[i] = avgDn == 0 ? 100 : 100 - 100 / (1 + avgUp / avgDn);
    }
  }
  return out;
}

/// ---- 通达信 SMA(X,N,M) = (M*X + (N-M)*Y') / N ----
List<double> SMA_CN(List<double> arr, int n, int m) {
  final out = List<double>.filled(arr.length, nan);
  double? prev;
  for (int i = 0; i < arr.length; i++) {
    final v = arr[i];
    if (!_finite(v)) {
      out[i] = prev ?? nan; // prev 可能尚未赋值（首元素即 NaN），补默认值过空安全
      continue;
    }
    prev = prev == null ? v : (m * v + (n - m) * prev) / n;
    out[i] = prev;
  }
  return out;
}

class KdjResult {
  final List<double> k;
  final List<double> d;
  final List<double> j;
  KdjResult(this.k, this.d, this.j);
}

/// ---- KDJ（通达信口径 N=9,M1=3,M2=3）----
KdjResult KDJ(List<double> high, List<double> low, List<double> close, {int n = 9, int m1 = 3, int m2 = 3}) {
  final len = close.length;
  final rsv = List<double>.filled(len, nan);
  for (int i = 0; i < len; i++) {
    if (i < n - 1) continue;
    double hh = -double.infinity, ll = double.infinity;
    for (int k = i - n + 1; k <= i; k++) {
      hh = math.max(hh, high[k]);
      ll = math.min(ll, low[k]);
    }
    rsv[i] = hh == ll ? 50 : (close[i] - ll) / (hh - ll) * 100;
  }
  final K = SMA_CN(rsv, m1, 1);
  final D = SMA_CN(K, m2, 1);
  final J = List<double>.generate(len, (i) => (_finite(K[i]) && _finite(D[i])) ? 3 * K[i] - 2 * D[i] : nan);
  return KdjResult(K, D, J);
}

class MacdResult {
  final List<double> dif;
  final List<double> dea;
  final List<double> hist;
  MacdResult(this.dif, this.dea, this.hist);
}

/// ---- MACD（12,26,9）----
MacdResult MACD(List<double> close, {int fast = 12, int slow = 26, int signal = 9}) {
  final ef = EMA(close, fast);
  final es = EMA(close, slow);
  final dif = List<double>.generate(close.length, (i) => (_finite(ef[i]) && _finite(es[i])) ? ef[i] - es[i] : nan);
  final dea = EMA(dif, signal);
  final hist = List<double>.generate(dif.length, (i) => (_finite(dif[i]) && _finite(dea[i])) ? (dif[i] - dea[i]) * 2 : nan);
  return MacdResult(dif, dea, hist);
}

class BollResult {
  final List<double> mid;
  final List<double> upper;
  final List<double> lower;
  final List<double> width;
  BollResult(this.mid, this.upper, this.lower, this.width);
}

/// ---- 布林带 BOLL（20,2）----
BollResult BOLL(List<double> close, {int n = 20, double k = 2}) {
  final mid = MA(close, n);
  final upper = List<double>.filled(close.length, nan);
  final lower = List<double>.filled(close.length, nan);
  final width = List<double>.filled(close.length, nan);
  for (int i = n - 1; i < close.length; i++) {
    final sd = stdAt(close, i, n);
    if (!_finite(sd) || !_finite(mid[i])) continue;
    upper[i] = mid[i] + k * sd;
    lower[i] = mid[i] - k * sd;
    width[i] = mid[i] != 0 ? (upper[i] - lower[i]) / mid[i] : nan;
  }
  return BollResult(mid, upper, lower, width);
}

/// ---- ADX（Wilder, 14）标准算法 ----
List<double> ADX(List<double> high, List<double> low, List<double> close, [int n = 14]) {
  final len = close.length;
  final out = List<double>.filled(len, nan);
  if (len < n + 1) return out;
  final pdm = List<double>.filled(len, 0);
  final ndm = List<double>.filled(len, 0);
  final tr = List<double>.filled(len, 0);
  for (int i = 1; i < len; i++) {
    final upMove = high[i] - high[i - 1];
    final dnMove = low[i - 1] - low[i];
    pdm[i] = (upMove > dnMove && upMove > 0) ? upMove : 0;
    ndm[i] = (dnMove > upMove && dnMove > 0) ? dnMove : 0;
    tr[i] = math.max(high[i] - low[i], math.max((high[i] - close[i - 1]).abs(), (low[i] - close[i - 1]).abs()));
  }
  // 第一步：前 n 个 TR/DM 求和作为 Wilder 平滑初值（索引 1..n）
  double atrS = 0, pdmS = 0, ndmS = 0;
  for (int k = 1; k <= n; k++) {
    atrS += tr[k];
    pdmS += pdm[k];
    ndmS += ndm[k];
  }
  final dxArr = <double>[];
  double calcDX() {
    if (atrS == 0) return 0;
    final pdi = 100 * pdmS / atrS;
    final ndi = 100 * ndmS / atrS;
    return (pdi + ndi) == 0 ? 0 : 100 * (pdi - ndi).abs() / (pdi + ndi);
  }

  dxArr.add(calcDX()); // 对应索引 n
  out[n] = nan; // ADX 尚未成形
  // 第二步：继续 Wilder 平滑并收集 DX，直到凑够 n 个 DX 求初始 ADX
  for (int i = n + 1; i < len; i++) {
    atrS = atrS - atrS / n + tr[i];
    pdmS = pdmS - pdmS / n + pdm[i];
    ndmS = ndmS - ndmS / n + ndm[i];
    final dx = calcDX();
    if (dxArr.length < n) {
      dxArr.add(dx);
      if (dxArr.length == n) {
        double adx = dxArr.reduce((a, b) => a + b) / n;
        out[i] = adx;
        // 后续用 Wilder 平滑
        for (int j = i + 1; j < len; j++) {
          atrS = atrS - atrS / n + tr[j];
          pdmS = pdmS - pdmS / n + pdm[j];
          ndmS = ndmS - ndmS / n + ndm[j];
          adx = (adx * (n - 1) + calcDX()) / n;
          out[j] = adx;
        }
        break;
      }
    }
  }
  return out;
}

/// ---- 量比 = 当日成交量 / MA(volume, n)（简化口径，与Web版一致）----
List<double> volumeRatio(List<double> volume, [int n = 5]) {
  final ma = MA(volume, n);
  return List<double>.generate(volume.length, (i) => (_finite(ma[i]) && ma[i] > 0) ? volume[i] / ma[i] : nan);
}

/// ---- 历史波动率（对数收益率滚动标准差）----
List<double> volatility(List<double> close, {int n = 20, bool annualize = false}) {
  final lr = List<double>.generate(close.length,
      (i) => (i > 0 && close[i - 1] > 0 && close[i] > 0) ? math.log(close[i] / close[i - 1]) : nan);
  final out = List<double>.filled(close.length, nan);
  for (int i = n; i < close.length; i++) {
    final sd = stdAt(lr, i, n);
    out[i] = (annualize && _finite(sd)) ? sd * math.sqrt(242) : sd;
  }
  return out;
}

/// ---- 分时均价线（黄线）= 累计成交额 / 累计成交量 ----
List<double> vwapLine(List<Bar> bars) {
  double cumAmt = 0, cumVol = 0;
  return List<double>.generate(bars.length, (i) {
    final b = bars[i];
    cumAmt += b.amount.isFinite ? b.amount : b.close * b.volume;
    cumVol += b.volume;
    return cumVol > 0 ? cumAmt / cumVol : nan;
  });
}

/// ---- 均线多头/空头排列 ----
String maAlignment(List<double> close, int i) {
  // 返回 'bull'(多头) / 'bear'(空头) / 'mix'
  final ma5 = meanAt(close, i, 5);
  final ma10 = meanAt(close, i, 10);
  final ma20 = meanAt(close, i, 20);
  if (!(_finite(ma5) && _finite(ma10) && _finite(ma20))) return 'mix';
  if (ma5 > ma10 && ma10 > ma20) return 'bull';
  if (ma5 < ma10 && ma10 < ma20) return 'bear';
  return 'mix';
}

/// 指标参数（与 Web 版 computeAll(bars, opts) 的 n.* 对应）
class IndicatorOpts {
  final int ma5, ma10, ma20, ma60;
  final int atr, rsi;
  final int kdjN, kdjM1, kdjM2;
  final int macdFast, macdSlow, macdSignal;
  final int bollN;
  final double bollK;
  final int adx;
  final int volRatioN;
  final int volN;

  IndicatorOpts({
    this.ma5 = 5,
    this.ma10 = 10,
    this.ma20 = 20,
    this.ma60 = 60,
    this.atr = 14,
    this.rsi = 14,
    this.kdjN = 9,
    this.kdjM1 = 3,
    this.kdjM2 = 3,
    this.macdFast = 12,
    this.macdSlow = 26,
    this.macdSignal = 9,
    this.bollN = 20,
    this.bollK = 2,
    this.adx = 14,
    this.volRatioN = 5,
    this.volN = 20,
  });

  factory IndicatorOpts.fromMap(Map<String, dynamic> n) => IndicatorOpts(
        ma5: (n['ma5'] as int?) ?? 5,
        ma10: (n['ma10'] as int?) ?? 10,
        ma20: (n['ma20'] as int?) ?? 20,
        ma60: (n['ma60'] as int?) ?? 60,
        atr: (n['atr'] as int?) ?? 14,
        rsi: (n['rsi'] as int?) ?? 14,
        kdjN: (n['kdjN'] as int?) ?? 9,
        kdjM1: (n['kdjM1'] as int?) ?? 3,
        kdjM2: (n['kdjM2'] as int?) ?? 3,
        macdFast: (n['macdFast'] as int?) ?? 12,
        macdSlow: (n['macdSlow'] as int?) ?? 26,
        macdSignal: (n['macdSignal'] as int?) ?? 9,
        bollN: (n['bollN'] as int?) ?? 20,
        bollK: (n['bollK'] as num?)?.toDouble() ?? 2,
        adx: (n['adx'] as int?) ?? 14,
        volRatioN: (n['volRatioN'] as int?) ?? 5,
        volN: (n['volN'] as int?) ?? 20,
      );
}

/// 全部指标序列（字段为数组）
class IndicatorResult {
  final List<double> open, high, low, close, volume, amount;
  final List<String> time;
  final List<double> ma5, ma10, ma20, ma60;
  final List<double> atr14, rsi14, adx14, volRatio, vol20;
  final KdjResult kdj;
  final MacdResult macd;
  final BollResult boll;
  final List<double> vwap;

  IndicatorResult({
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
    required this.amount,
    required this.time,
    required this.ma5,
    required this.ma10,
    required this.ma20,
    required this.ma60,
    required this.atr14,
    required this.rsi14,
    required this.adx14,
    required this.volRatio,
    required this.vol20,
    required this.kdj,
    required this.macd,
    required this.boll,
    required this.vwap,
  });
}

/// ---- 一次性计算 K线全部指标 ----
IndicatorResult computeAll(List<Bar> bars, [IndicatorOpts? opts]) {
  final n = opts ?? IndicatorOpts();
  final open = bars.map((b) => b.open).toList();
  final high = bars.map((b) => b.high).toList();
  final low = bars.map((b) => b.low).toList();
  final close = bars.map((b) => b.close).toList();
  final volume = bars.map((b) => b.volume).toList();
  final amount = bars.map((b) => b.amount).toList();
  return IndicatorResult(
    open: open,
    high: high,
    low: low,
    close: close,
    volume: volume,
    amount: amount,
    time: bars.map((b) => b.time).toList(),
    ma5: MA(close, n.ma5),
    ma10: MA(close, n.ma10),
    ma20: MA(close, n.ma20),
    ma60: MA(close, n.ma60),
    atr14: ATR(high, low, close, n.atr),
    rsi14: RSI(close, n.rsi),
    kdj: KDJ(high, low, close, n: n.kdjN, m1: n.kdjM1, m2: n.kdjM2),
    macd: MACD(close, fast: n.macdFast, slow: n.macdSlow, signal: n.macdSignal),
    boll: BOLL(close, n: n.bollN, k: n.bollK),
    adx14: ADX(high, low, close, n.adx),
    volRatio: volumeRatio(volume, n.volRatioN),
    vol20: volatility(close, n: n.volN),
    vwap: vwapLine(bars),
  );
}
