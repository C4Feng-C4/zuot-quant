/// scoring.dart — 做T适配度多因子打分模型 + 买卖信号 + 做T方向建议
/// 忠实移植自 lib/scoring.js（DEFAULT_CONFIG 42 项参数一一对应）
library;

import '../models.dart';
import 'indicators.dart';

double get nan => double.nan;
bool _finite(double x) => x.isFinite;

/// 默认配置（可优化参数）——与 Web 版 DEFAULT_CONFIG 完全一致
class ScoreConfig {
  // 回看窗口
  int ampWindow; // 振幅/换手/成交额 平均窗口（近N日）
  int liqWindow; // 流动性平均窗口
  // 因子权重（合计100）
  Map<String, int> weights;
  // 振幅理想区间（%）[下限, 满分起, 满分止, 上限]
  List<double> ampIdeal;
  // 换手率理想区间（%）
  List<double> turnoverIdeal;
  // 成交额门槛（元）
  double amountFull; // ≥5亿满分
  double amountMin; // <1亿低分
  // 相对ATR（ATR/价格 %）理想区间
  List<double> atrIdeal;
  // 量比理想区间
  List<double> volRatioIdeal;
  // ADX 趋势阈值
  int adxTrend;
  int adxWeak;
  // RSI 超买超卖
  int rsiOversold;
  int rsiOverbought;
  // KDJ 超买超卖
  int kdjOversold;
  int kdjOverbought;
  // 硬过滤
  bool excludeST;
  bool excludeBJ; // 排除北交所（30%涨跌幅规则不同）
  double minPrice; // 最低价格（低价股剔除）
  double minAmount; // 最低日均成交额5000万
  int minListDays; // 上市不足60日剔除
  double zombieTurnover; // 换手<1%且振幅<1% → 僵尸股剔除
  double zombieAmplitude;
  double overheatedTurnover; // 换手>20% 过度投机降分
  double overheatedAmplitude; // 振幅>9% 过度投机降分
  // 交易成本（回测用）
  double costRate; // 单次完整做T成本0.16%
  // 高价股加分阈值
  double highPriceBonus;

  ScoreConfig({
    this.ampWindow = 10,
    this.liqWindow = 5,
    Map<String, int>? weights,
    List<double>? ampIdeal,
    List<double>? turnoverIdeal,
    this.amountFull = 5e8,
    this.amountMin = 1e8,
    List<double>? atrIdeal,
    List<double>? volRatioIdeal,
    this.adxTrend = 25,
    this.adxWeak = 20,
    this.rsiOversold = 30,
    this.rsiOverbought = 70,
    this.kdjOversold = 20,
    this.kdjOverbought = 80,
    this.excludeST = true,
    this.excludeBJ = true,
    this.minPrice = 2,
    this.minAmount = 5e7,
    this.minListDays = 60,
    this.zombieTurnover = 1,
    this.zombieAmplitude = 1,
    this.overheatedTurnover = 20,
    this.overheatedAmplitude = 9,
    this.costRate = 0.0016,
    this.highPriceBonus = 5,
  })  : weights = weights ??
            <String, int>{
              'amplitude': 20,
              'liquidity': 20,
              'volatility': 15,
              'trend': 15,
              'oscillation': 15,
              'volume': 10,
              'character': 5,
            },
        ampIdeal = ampIdeal ?? <double>[3, 5, 8, 12],
        turnoverIdeal = turnoverIdeal ?? <double>[2, 3, 15, 20],
        atrIdeal = atrIdeal ?? <double>[1.5, 2.5, 6, 9],
        volRatioIdeal = volRatioIdeal ?? <double>[1.0, 1.2, 6, 10];

  ScoreConfig copy() => ScoreConfig(
        ampWindow: ampWindow,
        liqWindow: liqWindow,
        weights: Map<String, int>.from(weights),
        ampIdeal: List<double>.from(ampIdeal),
        turnoverIdeal: List<double>.from(turnoverIdeal),
        amountFull: amountFull,
        amountMin: amountMin,
        atrIdeal: List<double>.from(atrIdeal),
        volRatioIdeal: List<double>.from(volRatioIdeal),
        adxTrend: adxTrend,
        adxWeak: adxWeak,
        rsiOversold: rsiOversold,
        rsiOverbought: rsiOverbought,
        kdjOversold: kdjOversold,
        kdjOverbought: kdjOverbought,
        excludeST: excludeST,
        excludeBJ: excludeBJ,
        minPrice: minPrice,
        minAmount: minAmount,
        minListDays: minListDays,
        zombieTurnover: zombieTurnover,
        zombieAmplitude: zombieAmplitude,
        overheatedTurnover: overheatedTurnover,
        overheatedAmplitude: overheatedAmplitude,
        costRate: costRate,
        highPriceBonus: highPriceBonus,
      );

  Map<String, dynamic> toJson() => {
        'ampWindow': ampWindow,
        'liqWindow': liqWindow,
        'weights': weights,
        'ampIdeal': ampIdeal,
        'turnoverIdeal': turnoverIdeal,
        'amountFull': amountFull,
        'amountMin': amountMin,
        'atrIdeal': atrIdeal,
        'volRatioIdeal': volRatioIdeal,
        'adxTrend': adxTrend,
        'adxWeak': adxWeak,
        'rsiOversold': rsiOversold,
        'rsiOverbought': rsiOverbought,
        'kdjOversold': kdjOversold,
        'kdjOverbought': kdjOverbought,
        'excludeST': excludeST,
        'excludeBJ': excludeBJ,
        'minPrice': minPrice,
        'minAmount': minAmount,
        'minListDays': minListDays,
        'zombieTurnover': zombieTurnover,
        'zombieAmplitude': zombieAmplitude,
        'overheatedTurnover': overheatedTurnover,
        'overheatedAmplitude': overheatedAmplitude,
        'costRate': costRate,
        'highPriceBonus': highPriceBonus,
      };

  static ScoreConfig fromJson(Map<String, dynamic> j) {
    final d = ScoreConfig();
    d.ampWindow = (j['ampWindow'] as num?)?.toInt() ?? d.ampWindow;
    d.liqWindow = (j['liqWindow'] as num?)?.toInt() ?? d.liqWindow;
    if (j['weights'] is Map) {
      d.weights = (j['weights'] as Map).map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
    }
    if (j['ampIdeal'] is List) d.ampIdeal = (j['ampIdeal'] as List).map((e) => (e as num).toDouble()).toList();
    if (j['turnoverIdeal'] is List) d.turnoverIdeal = (j['turnoverIdeal'] as List).map((e) => (e as num).toDouble()).toList();
    if (j['atrIdeal'] is List) d.atrIdeal = (j['atrIdeal'] as List).map((e) => (e as num).toDouble()).toList();
    if (j['volRatioIdeal'] is List) d.volRatioIdeal = (j['volRatioIdeal'] as List).map((e) => (e as num).toDouble()).toList();
    d.amountFull = (j['amountFull'] as num?)?.toDouble() ?? d.amountFull;
    d.amountMin = (j['amountMin'] as num?)?.toDouble() ?? d.amountMin;
    d.adxTrend = (j['adxTrend'] as num?)?.toInt() ?? d.adxTrend;
    d.adxWeak = (j['adxWeak'] as num?)?.toInt() ?? d.adxWeak;
    d.rsiOversold = (j['rsiOversold'] as num?)?.toInt() ?? d.rsiOversold;
    d.rsiOverbought = (j['rsiOverbought'] as num?)?.toInt() ?? d.rsiOverbought;
    d.kdjOversold = (j['kdjOversold'] as num?)?.toInt() ?? d.kdjOversold;
    d.kdjOverbought = (j['kdjOverbought'] as num?)?.toInt() ?? d.kdjOverbought;
    d.excludeST = (j['excludeST'] as bool?) ?? d.excludeST;
    d.excludeBJ = (j['excludeBJ'] as bool?) ?? d.excludeBJ;
    d.minPrice = (j['minPrice'] as num?)?.toDouble() ?? d.minPrice;
    d.minAmount = (j['minAmount'] as num?)?.toDouble() ?? d.minAmount;
    d.minListDays = (j['minListDays'] as num?)?.toInt() ?? d.minListDays;
    d.zombieTurnover = (j['zombieTurnover'] as num?)?.toDouble() ?? d.zombieTurnover;
    d.zombieAmplitude = (j['zombieAmplitude'] as num?)?.toDouble() ?? d.zombieAmplitude;
    d.overheatedTurnover = (j['overheatedTurnover'] as num?)?.toDouble() ?? d.overheatedTurnover;
    d.overheatedAmplitude = (j['overheatedAmplitude'] as num?)?.toDouble() ?? d.overheatedAmplitude;
    d.costRate = (j['costRate'] as num?)?.toDouble() ?? d.costRate;
    d.highPriceBonus = (j['highPriceBonus'] as num?)?.toDouble() ?? d.highPriceBonus;
    return d;
  }
}

// ============ 梯形隶属函数 ============
// 值落在[fullLo,fullHi]得满分，[lo,hi]外得0，线性过渡
double trapezoid(double x, double lo, double fullLo, double fullHi, double hi) {
  if (!_finite(x)) return 0;
  if (x <= lo || x >= hi) return 0;
  if (x >= fullLo && x <= fullHi) return 100;
  if (x < fullLo) return 100 * (x - lo) / (fullLo - lo);
  return 100 * (hi - x) / (hi - fullHi);
}

/// 越大越好（有上限饱和）
double risingScore(double x, double lo, double hi) {
  if (!_finite(x)) return 0;
  if (x <= lo) return 0;
  if (x >= hi) return 100;
  return 100 * (x - lo) / (hi - lo);
}

double clamp(double v, [double a = 0, double b = 100]) => v < a ? a : (v > b ? b : v);

double avgD(List<double> arr) {
  final f = arr.where((v) => v.isFinite).toList();
  return f.isNotEmpty ? f.reduce((a, b) => a + b) / f.length : nan;
}

double round2(double x) => _finite(x) ? (x * 100).roundToDouble() / 100 : nan;
double round1(double x) => _finite(x) ? (x * 10).roundToDouble() / 10 : nan;

// ============ 硬过滤：返回 {pass, reason} ============
class FilterResult {
  final bool pass;
  final String? reason;
  final double ampAvg;
  final double toAvg;
  final double amtAvg;
  FilterResult(this.pass, this.reason, this.ampAvg, this.toAvg, this.amtAvg);
}

FilterResult hardFilter(StockSnap stock, List<Bar> daily, ScoreConfig cfg) {
  final name = stock.name;
  if (cfg.excludeST && RegExp(r'ST|退|\*ST').hasMatch(name)) {
    return FilterResult(false, 'ST/退市风险', nan, nan, nan);
  }
  final code = stock.code;
  if (cfg.excludeBJ && RegExp(r'^(4|8|92)').hasMatch(code)) {
    return FilterResult(false, '北交所(规则不同)', nan, nan, nan);
  }
  final price = stock.price > 0 ? stock.price : (daily.isNotEmpty ? daily[daily.length - 1].close : 0);
  if (price < cfg.minPrice) return FilterResult(false, '低价股(<${cfg.minPrice}元)', nan, nan, nan);
  if (daily.length < cfg.minListDays) return FilterResult(false, '上市不足${cfg.minListDays}日', nan, nan, nan);
  // 近N日均振幅/换手/成交额
  final recent = tail(daily, cfg.ampWindow);
  final ampAvg = avgD(recent.map((b) => b.amplitude).toList());
  final toAvg = avgD(recent.map((b) => b.turnover ?? nan).where((x) => _finite(x) && x > 0).toList());
  final amtAvg = avgD(tail(daily, cfg.liqWindow).map((b) => b.amount).toList());
  if (_finite(amtAvg) && amtAvg < cfg.minAmount) return FilterResult(false, '流动性差(成交额<5000万)', nan, nan, nan);
  // 僵尸股：换手<1% 且 振幅<1%
  if (_finite(toAvg) && _finite(ampAvg) && toAvg < cfg.zombieTurnover && ampAvg < cfg.zombieAmplitude) {
    return FilterResult(false, '僵尸股(换手<1%且振幅<1%)', nan, nan, nan);
  }
  return FilterResult(true, null, ampAvg, toAvg, amtAvg);
}

// ============ 各因子打分（0-100）============
double scoreAmplitude(double ampAvg, ScoreConfig cfg) {
  final lo = cfg.ampIdeal[0], fl = cfg.ampIdeal[1], fh = cfg.ampIdeal[2], hi = cfg.ampIdeal[3];
  var s = trapezoid(ampAvg, lo, fl, fh, hi);
  // 过度投机惩罚：振幅>overheatedAmplitude 降分
  if (_finite(ampAvg) && ampAvg > cfg.overheatedAmplitude) s *= 0.5;
  return clamp(s);
}

double scoreLiquidity(double amtAvg, double toAvg, ScoreConfig cfg) {
  final amtScore = risingScore(amtAvg, cfg.amountMin, cfg.amountFull);
  final lo = cfg.turnoverIdeal[0], fl = cfg.turnoverIdeal[1], fh = cfg.turnoverIdeal[2], hi = cfg.turnoverIdeal[3];
  var toScore = trapezoid(toAvg, lo, fl, fh, hi);
  if (_finite(toAvg) && toAvg > cfg.overheatedTurnover) toScore *= 0.5; // 过度换手降分
  return clamp(0.6 * amtScore + 0.4 * toScore);
}

double scoreVolatility(double atrPct, ScoreConfig cfg) {
  final lo = cfg.atrIdeal[0], fl = cfg.atrIdeal[1], fh = cfg.atrIdeal[2], hi = cfg.atrIdeal[3];
  return clamp(trapezoid(atrPct, lo, fl, fh, hi));
}

double scoreTrend(List<Bar> daily, IndicatorResult indicators, int i, ScoreConfig cfg) {
  // 均线排列 + ADX + 站稳5日线
  final align = maAlignment(indicators.close, i);
  final adx = indicators.adx14[i];
  final close = indicators.close[i];
  final ma5 = indicators.ma5[i];
  final ma20 = indicators.ma20[i];
  double s = 50; // 基准
  if (align == 'bull') {
    s += 25;
  } else if (align == 'bear') {
    s -= 15;
  }
  if (_finite(adx)) {
    if (adx > cfg.adxTrend) {
      s += 20; // 趋势明确
    } else if (adx < cfg.adxWeak) {
      s -= 10; // 无趋势
    }
  }
  if (_finite(close) && _finite(ma5)) s += close >= ma5 ? 10 : -10; // 站稳5日线
  if (_finite(close) && _finite(ma20)) s += close >= ma20 ? 5 : -5;
  return clamp(s);
}

double scoreOscillation(IndicatorResult indicators, int i, ScoreConfig cfg) {
  // 做T最理想环境=震荡市；超买超卖提供反转做T机会
  final rsi = indicators.rsi14[i];
  final upper = indicators.boll.upper;
  final lower = indicators.boll.lower;
  double bollPos = 0.5;
  if (!_finite(upper[i]) || !_finite(lower[i]) || upper[i] == lower[i]) {
    bollPos = 0.5;
  } else {
    bollPos = (indicators.close[i] - lower[i]) / (upper[i] - lower[i]);
  }
  final K = indicators.kdj.k[i];
  final D = indicators.kdj.d[i];
  double s = 50;
  // RSI 中性区(40-60)=震荡适合做T；超卖/超买=反转机会也加分
  if (_finite(rsi)) {
    if (rsi >= 40 && rsi <= 60) {
      s += 20; // 震荡区
    } else if (rsi <= cfg.rsiOversold) {
      s += 25; // 超卖→正T低吸机会
    } else if (rsi >= cfg.rsiOverbought) {
      s += 15; // 超买→反T高抛机会
    } else {
      s += 5;
    }
  }
  // 布林带中部=震荡；触及上下轨=反转机会
  if (bollPos > 0.3 && bollPos < 0.7) {
    s += 15;
  } else if (bollPos <= 0.05 || bollPos >= 0.95) {
    s += 10;
  }
  // KDJ 超买超卖
  if (_finite(K) && _finite(D)) {
    if (K < cfg.kdjOversold && D < cfg.kdjOversold) {
      s += 10;
    } else if (K > cfg.kdjOverbought && D > cfg.kdjOverbought) {
      s += 8;
    }
  }
  // 布林带宽度适中（太窄=无波动空间，太宽=单边）
  final w = indicators.boll.width[i];
  if (_finite(w)) {
    if (w > 0.05 && w < 0.25) {
      s += 10; // 带宽5%-25%适合做T
    } else if (w <= 0.03) {
      s -= 15; // 极度收窄无空间
    }
  }
  return clamp(s);
}

double scoreVolume(double volRatio, ScoreConfig cfg) {
  final lo = cfg.volRatioIdeal[0], fl = cfg.volRatioIdeal[1], fh = cfg.volRatioIdeal[2], hi = cfg.volRatioIdeal[3];
  return clamp(trapezoid(volRatio, lo, fl, fh, hi));
}

double scoreCharacter(StockSnap stock, List<Bar> daily, ScoreConfig cfg) {
  double s = 50;
  final price = stock.price > 0 ? stock.price : (daily.isNotEmpty ? daily[daily.length - 1].close : 0);
  // 高价股更适合做T（同样价差百分比小，易成交）
  if (price >= cfg.highPriceBonus) s += 20;
  if (price >= 20) s += 10;
  // 深市无过户费，略加分
  if (RegExp(r'^(0|3)').hasMatch(stock.code)) s += 5;
  // 近60日涨停次数（股性活跃）——涨幅>9.5%计一次
  final recent = tail(daily, 60);
  int limitUps = 0;
  for (final b in recent) {
    if (_finite(b.chgPct) && b.chgPct > 9.5) limitUps++;
  }
  s += (limitUps * 5).clamp(0, 20).toDouble();
  return clamp(s);
}

// ============ 综合打分 ============
ScoreResult scoreStock(StockSnap stock, List<Bar> daily, [ScoreConfig? cfgOverride]) {
  final cfg = cfgOverride ?? ScoreConfig();
  // 若日线缺少换手率且有流通股本，则用 成交量/流通股本 推算（新浪日线不含换手）
  if (stock.floatShares > 0) {
    for (final b in daily) {
      if ((b.turnover == null || !b.turnover!.isFinite || b.turnover == 0) && b.volume.isFinite) {
        b.turnover = b.volume / stock.floatShares * 100;
      }
    }
  }
  final filt = hardFilter(stock, daily, cfg);
  if (!filt.pass) {
    return ScoreResult(code: stock.code, name: stock.name, pass: false, reason: filt.reason, score: 0);
  }
  final ampAvg = filt.ampAvg, toAvg = filt.toAvg, amtAvg = filt.amtAvg;
  final indicators = computeAll(daily);
  final i = daily.length - 1;
  final atrPct = (_finite(indicators.atr14[i]) && indicators.close[i] > 0)
      ? indicators.atr14[i] / indicators.close[i] * 100
      : nan;

  final factors = <String, double>{
    'amplitude': scoreAmplitude(ampAvg, cfg),
    'liquidity': scoreLiquidity(amtAvg, toAvg, cfg),
    'volatility': scoreVolatility(atrPct, cfg),
    'trend': scoreTrend(daily, indicators, i, cfg),
    'oscillation': scoreOscillation(indicators, i, cfg),
    'volume': scoreVolume(indicators.volRatio[i], cfg),
    'character': scoreCharacter(stock, daily, cfg),
  };
  final w = cfg.weights;
  final wSum = w.values.fold<int>(0, (a, b) => a + b).toDouble();
  final wSumSafe = wSum == 0 ? 1.0 : wSum;
  double total = 0;
  for (final k in w.keys) {
    total += (factors[k] ?? 0) * (w[k] ?? 0).toDouble();
  }
  total = total / wSumSafe;

  // 做T方向建议
  final align = maAlignment(indicators.close, i);
  final aboveMa5 = indicators.close[i] >= indicators.ma5[i];
  TDirection direction;
  String dirLabel;
  if (align == 'bull' && aboveMa5) {
    direction = TDirection.positive;
    dirLabel = directionLabel(direction);
  } else if (align == 'bear' || !aboveMa5) {
    direction = TDirection.negative;
    dirLabel = directionLabel(direction);
  } else {
    direction = TDirection.both;
    dirLabel = directionLabel(direction);
  }

  // 买卖信号
  final signal = genSignal(indicators, i, cfg);

  final bollRange = indicators.boll.upper[i] - indicators.boll.lower[i];
  return ScoreResult(
    code: stock.code,
    name: stock.name,
    pass: true,
    price: stock.price > 0 ? stock.price : indicators.close[i],
    score: (total * 10).roundToDouble() / 10,
    factors: factors.map((k, v) => MapEntry(k, v.round())),
    metrics: <String, double>{
      'ampAvg': round2(ampAvg),
      'toAvg': round2(toAvg),
      'amtAvg': _finite(amtAvg) ? (amtAvg / 1e8 * 100).round() / 100 : nan, // 亿
      'atrPct': round2(atrPct),
      'rsi': round1(indicators.rsi14[i]),
      'adx': round1(indicators.adx14[i]),
      'volRatio': round2(indicators.volRatio[i]),
      'bollPos': _finite(bollRange) && bollRange != 0
          ? round2((indicators.close[i] - indicators.boll.lower[i]) / bollRange)
          : nan,
      'align': align == 'bull' ? 1 : (align == 'bear' ? -1 : 0),
    },
    direction: direction,
    directionLabelText: dirLabel,
    signal: signal,
  );
}

// ============ 买卖信号（日线波段T）============
Signal genSignal(IndicatorResult indicators, int i, ScoreConfig cfg) {
  if (i < 1) return Signal(SignalAction.hold, 0, 0, 0, <String>[]);
  final reasons = <String>[];
  int buy = 0, sell = 0;
  final rsi = indicators.rsi14[i], rsiP = indicators.rsi14[i - 1];
  final K = indicators.kdj.k[i], D = indicators.kdj.d[i], KP = indicators.kdj.k[i - 1], DP = indicators.kdj.d[i - 1];
  final dif = indicators.macd.dif[i], dea = indicators.macd.dea[i], difP = indicators.macd.dif[i - 1], deaP = indicators.macd.dea[i - 1];
  final close = indicators.close[i], ma5 = indicators.ma5[i], low = indicators.low[i];
  final bollLow = indicators.boll.lower[i], bollUp = indicators.boll.upper[i];

  // RSI 超卖回升
  if (_finite(rsi) && rsi < cfg.rsiOversold) {
    buy += 2;
    reasons.add('RSI超卖(${round1(rsi)})');
  } else if (_finite(rsi) && rsi > cfg.rsiOverbought) {
    sell += 2;
    reasons.add('RSI超买(${round1(rsi)})');
  }
  // KDJ 金叉/死叉（低位金叉更可靠）
  if (_finite(K) && _finite(D) && _finite(KP) && _finite(DP)) {
    if (KP <= DP && K > D) {
      buy += K < 30 ? 3 : 2;
      reasons.add('KDJ金叉' + (K < 30 ? '(低位)' : ''));
    }
    if (KP >= DP && K < D) {
      sell += K > 70 ? 3 : 2;
      reasons.add('KDJ死叉' + (K > 70 ? '(高位)' : ''));
    }
  }
  // MACD 金叉/死叉
  if (_finite(dif) && _finite(dea) && _finite(difP) && _finite(deaP)) {
    if (difP <= deaP && dif > dea) {
      buy += 2;
      reasons.add('MACD金叉');
    }
    if (difP >= deaP && dif < dea) {
      sell += 2;
      reasons.add('MACD死叉');
    }
  }
  // 回踩5日线不破（正T买点）
  if (_finite(close) && _finite(ma5) && _finite(low)) {
    if (low <= ma5 * 1.01 && close >= ma5) {
      buy += 2;
      reasons.add('回踩5日线企稳');
    }
    if (close > ma5 * 1.05) {
      sell += 1;
      reasons.add('远离5日线(乖离大)');
    }
  }
  // 布林带轨道
  if (_finite(bollLow) && close <= bollLow * 1.005) {
    buy += 2;
    reasons.add('触及布林下轨');
  }
  if (_finite(bollUp) && close >= bollUp * 0.995) {
    sell += 2;
    reasons.add('触及布林上轨');
  }

  final net = buy - sell;
  SignalAction action = SignalAction.hold;
  if (net >= 3) {
    action = SignalAction.buy;
  } else if (net <= -3) {
    action = SignalAction.sell;
  } else if (net >= 1) {
    action = SignalAction.weakBuy;
  } else if (net <= -1) {
    action = SignalAction.weakSell;
  }
  return Signal(action, net, buy, sell, reasons);
}
