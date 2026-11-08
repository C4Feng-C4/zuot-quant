/// backtest.dart — 双策略回测引擎（忠实移植自 lib/backtest.js）
/// 策略一：日线波段T（次日开盘成交，T+1约束，含成本）
/// 策略二：日内分钟做T（VWAP轴，半仓滚动，当日闭环）
library;

import 'dart:math' as math;

import '../models.dart';
import 'indicators.dart';
import 'scoring.dart';

double get nan => double.nan;
bool _finite(double x) => x.isFinite;

double btRound(double x, [int d = 2]) {
  final p = math.pow(10, d).toDouble();
  return (x * p).roundToDouble() / p;
}

// ---- 绩效统计 ----
BacktestMetrics perfMetrics(List<Trade> trades, List<double> equity, [int tradingDays = 242]) {
  final n = trades.length;
  if (n == 0) return BacktestMetrics.empty;
  final wins = trades.where((t) => t.pnl > 0).toList();
  final losses = trades.where((t) => t.pnl <= 0).toList();
  final grossWin = wins.fold<double>(0, (a, t) => a + t.pnl);
  final grossLoss = losses.fold<double>(0, (a, t) => a + t.pnl).abs();
  final totalReturn = equity.isNotEmpty ? equity[equity.length - 1] / equity[0] - 1 : 0;
  final years = math.max(equity.length / tradingDays, 1 / 12);
  final annual = math.pow(1 + totalReturn, 1 / years) - 1;
  // 最大回撤
  double peak = equity.isNotEmpty ? equity[0] : 1;
  double mdd = 0;
  for (final v in equity) {
    if (v > peak) peak = v;
    final dd = (v - peak) / peak;
    if (dd < mdd) mdd = dd;
  }
  // 夏普（按每笔收益近似）
  final rets = trades.map((t) => t.pnl).toList();
  final mu = rets.fold<double>(0, (a, b) => a + b) / n;
  final sd = math.sqrt(rets.fold<double>(0, (a, b) => a + (b - mu) * (b - mu)) / n);
  final sharpe = sd > 0 ? (mu / sd) * math.sqrt(math.min(n, tradingDays).toDouble()) : 0;
  return BacktestMetrics(
    totalReturn: btRound(totalReturn * 100),
    annual: btRound(annual * 100),
    winRate: btRound(wins.length / n * 100, 1),
    trades: n,
    maxDrawdown: btRound(mdd * 100),
    sharpe: btRound(sharpe),
    profitFactor: grossLoss > 0 ? btRound(grossWin / grossLoss) : (grossWin > 0 ? 99 : 0),
    avgWin: wins.isNotEmpty ? btRound(grossWin / wins.length * 100) : 0,
    avgLoss: losses.isNotEmpty ? btRound(grossLoss / losses.length * 100) : 0,
  );
}

// ============ 策略一：日线波段T ============
class DailyParams {
  int signalThreshold; // |net|>=该值才行动（强信号）
  bool useWeak; // 是否用弱信号
  double stopLoss; // 止损5%
  double takeProfit; // 止盈12%
  double costRate;

  DailyParams({
    this.signalThreshold = 3,
    this.useWeak = false,
    this.stopLoss = 0.05,
    this.takeProfit = 0.12,
    this.costRate = 0.0016,
  });

  DailyParams copyWith({
    int? signalThreshold,
    bool? useWeak,
    double? stopLoss,
    double? takeProfit,
    double? costRate,
  }) =>
      DailyParams(
        signalThreshold: signalThreshold ?? this.signalThreshold,
        useWeak: useWeak ?? this.useWeak,
        stopLoss: stopLoss ?? this.stopLoss,
        takeProfit: takeProfit ?? this.takeProfit,
        costRate: costRate ?? this.costRate,
      );

  Map<String, dynamic> toJson() => {
        'signalThreshold': signalThreshold,
        'useWeak': useWeak,
        'stopLoss': stopLoss,
        'takeProfit': takeProfit,
        'costRate': costRate,
      };
}

BacktestResult backtestDailySwing(List<Bar> daily, ScoreConfig cfg, [DailyParams? paramsOverride]) {
  final p = (paramsOverride ?? DailyParams()).copyWith(costRate: cfg.costRate);
  final indicators = computeAll(daily);
  final trades = <Trade>[];
  final equity = <double>[1];
  int? posIdx; // 持仓 {entryIdx}
  double posPrice = 0;
  final thr = p.useWeak ? 1 : p.signalThreshold;

  for (int i = 1; i < daily.length - 1; i++) {
    final sig = genSignal(indicators, i, cfg);
    final execIdx = i + 1; // 次日成交
    final execPrice = daily[execIdx].open;
    if (!_finite(execPrice) || execPrice <= 0) continue;

    if (posIdx != null) {
      // 持仓中：检查止损止盈（用当日高低价触发，成交价用触发价近似）
      final bar = daily[execIdx];
      double? exitPrice;
      String? reason;
      if (bar.low <= posPrice * (1 - p.stopLoss)) {
        exitPrice = posPrice * (1 - p.stopLoss);
        reason = '止损';
      } else if (bar.high >= posPrice * (1 + p.takeProfit)) {
        exitPrice = posPrice * (1 + p.takeProfit);
        reason = '止盈';
      } else if ((sig.action == SignalAction.sell && sig.strength <= -thr) ||
          (sig.action == SignalAction.weakSell && p.useWeak && sig.strength <= -thr)) {
        exitPrice = execPrice;
        reason = '信号卖出';
      }
      if (exitPrice != null) {
        final pnl = (exitPrice - posPrice) / posPrice - p.costRate;
        trades.add(Trade(
          type: 'swing',
          buyTime: daily[posIdx].time,
          sellTime: bar.time,
          buyPrice: btRound(posPrice, 3),
          sellPrice: btRound(exitPrice, 3),
          pnl: btRound(pnl, 4),
          reason: reason!,
        ));
        equity.add(equity[equity.length - 1] * (1 + pnl));
        posIdx = null;
      }
    } else {
      // 空仓：买入信号
      if ((sig.action == SignalAction.buy && sig.strength >= thr) ||
          (sig.action == SignalAction.weakBuy && p.useWeak && sig.strength >= thr)) {
        posIdx = execIdx;
        posPrice = execPrice;
      }
    }
  }
  // 尾盘强平
  if (posIdx != null) {
    final last = daily[daily.length - 1];
    final pnl = (last.close - posPrice) / posPrice - p.costRate;
    trades.add(Trade(
      type: 'swing',
      buyTime: daily[posIdx].time,
      sellTime: last.time,
      buyPrice: btRound(posPrice, 3),
      sellPrice: btRound(last.close, 3),
      pnl: btRound(pnl, 4),
      reason: '期末强平',
    ));
    equity.add(equity[equity.length - 1] * (1 + pnl));
  }
  return BacktestResult(
    strategy: 'dailySwing',
    params: p.toJson(),
    metrics: perfMetrics(trades, equity),
    trades: trades,
    equity: equity,
  );
}

// ============ 策略二：日内分钟做T（半仓滚动）============
class IntradayParams {
  double buyBand; // 价格低于均价线0.6%买入（正T）/买回（反T）
  double sellBand; // 价格高于均价线0.8%卖出（反T）/止盈（正T）
  double targetPct; // 单次做T目标利润1.2%
  double stopPct; // 单次做T止损1.5%
  int maxTPerDay; // 单日最多做T次数
  double portion; // 每次动用底仓的50%（半仓滚动）
  double costRate; // 单次完整做T成本
  String direction; // 'positive'正T / 'negative'反T / 'auto'按当日开盘趋势

  IntradayParams({
    this.buyBand = 0.006,
    this.sellBand = 0.008,
    this.targetPct = 0.012,
    this.stopPct = 0.015,
    this.maxTPerDay = 3,
    this.portion = 0.5,
    this.costRate = 0.0016,
    this.direction = 'auto',
  });

  IntradayParams copyWith({
    double? buyBand,
    double? sellBand,
    double? targetPct,
    double? stopPct,
    int? maxTPerDay,
    double? portion,
    double? costRate,
    String? direction,
  }) =>
      IntradayParams(
        buyBand: buyBand ?? this.buyBand,
        sellBand: sellBand ?? this.sellBand,
        targetPct: targetPct ?? this.targetPct,
        stopPct: stopPct ?? this.stopPct,
        maxTPerDay: maxTPerDay ?? this.maxTPerDay,
        portion: portion ?? this.portion,
        costRate: costRate ?? this.costRate,
        direction: direction ?? this.direction,
      );

  Map<String, dynamic> toJson() => {
        'buyBand': buyBand,
        'sellBand': sellBand,
        'targetPct': targetPct,
        'stopPct': stopPct,
        'maxTPerDay': maxTPerDay,
        'portion': portion,
        'costRate': costRate,
        'direction': direction,
      };
}

BacktestResult backtestIntradayT(List<Bar> minuteBars, [IntradayParams? optsOverride]) {
  final p = optsOverride ?? IntradayParams();
  // 按日分组
  final byDay = <String, List<Bar>>{};
  for (final b in minuteBars) {
    final day = b.time.length >= 10 ? b.time.substring(0, 10) : b.time;
    (byDay[day] ??= <Bar>[]).add(b);
  }
  final trades = <Trade>[];
  final equity = <double>[1];
  final dailyPnl = <Map<String, dynamic>>[];

  for (final day in (byDay.keys.toList()..sort())) {
    final bars = byDay[day]!;
    if (bars.length < 8) continue; // 数据太少跳过
    final vwap = vwapLine(bars);
    // 当日方向：开盘半小时均价 vs 中位收盘（简化，与Web版一致）
    String dir = p.direction;
    if (dir == 'auto') {
      final openPrice = bars[0].open;
      final mid = bars[bars.length ~/ 2].close;
      dir = mid >= openPrice ? 'positive' : 'negative';
    }
    double? tEntryPrice;
    String? tEntryTime;
    bool tShort = false;
    int dayTCount = 0;
    double dayProfit = 0;

    for (int i = 1; i < bars.length; i++) {
      final price = bars[i].close;
      final v = vwap[i];
      if (!_finite(v) || v <= 0) continue;
      final dev = (price - v) / v; // 相对均价线乖离
      final isLast = i >= bars.length - 3; // 尾盘强平区

      if (tEntryPrice == null) {
        if (dayTCount >= p.maxTPerDay) continue;
        if (dir == 'positive') {
          // 正T：回踩均价线下方买入
          if (dev <= -p.buyBand) {
            tEntryPrice = price;
            tEntryTime = bars[i].time;
            tShort = false;
          }
        } else {
          // 反T：反抽均价线上方卖出（借底仓）
          if (dev >= p.sellBand) {
            tEntryPrice = price;
            tEntryTime = bars[i].time;
            tShort = true;
          }
        }
      } else {
        // 持仓中：判断平仓
        double? exit;
        String? reason;
        if (tShort) {
          // 反T：买回平仓（价格回落）
          final ret = (tEntryPrice - price) / tEntryPrice;
          if (ret >= p.targetPct) {
            exit = price;
            reason = '止盈买回';
          } else if (ret <= -p.stopPct) {
            exit = price;
            reason = '止损买回';
          } else if (dev <= -p.buyBand) {
            exit = price;
            reason = '回落买回';
          } else if (isLast) {
            exit = price;
            reason = '尾盘强平';
          }
        } else {
          // 正T：卖出平仓（价格反弹）
          final ret = (price - tEntryPrice) / tEntryPrice;
          if (ret >= p.targetPct) {
            exit = price;
            reason = '止盈卖出';
          } else if (ret <= -p.stopPct) {
            exit = price;
            reason = '止损卖出';
          } else if (dev >= p.sellBand) {
            exit = price;
            reason = '冲高卖出';
          } else if (isLast) {
            exit = price;
            reason = '尾盘强平';
          }
        }
        if (exit != null) {
          final rawRet = tShort ? (tEntryPrice - exit) / tEntryPrice : (exit - tEntryPrice) / tEntryPrice;
          final pnl = rawRet * p.portion - p.costRate * p.portion; // 仅动用 portion 仓位
          trades.add(Trade(
            type: 'intraday',
            dir: tShort ? '反T' : '正T',
            buyTime: tEntryTime!,
            sellTime: bars[i].time,
            buyPrice: btRound(tShort ? exit : tEntryPrice, 3),
            sellPrice: btRound(tShort ? tEntryPrice : exit, 3),
            pnl: btRound(pnl, 4),
            reason: reason!,
          ));
          dayProfit += pnl;
          equity.add(equity[equity.length - 1] * (1 + pnl));
          tEntryPrice = null;
          dayTCount++;
        }
      }
    }
    // 当日未平T仓强平
    if (tEntryPrice != null) {
      final exit = bars[bars.length - 1].close;
      final rawRet = tShort ? (tEntryPrice - exit) / tEntryPrice : (exit - tEntryPrice) / tEntryPrice;
      final pnl = rawRet * p.portion - p.costRate * p.portion;
      trades.add(Trade(
        type: 'intraday',
        dir: tShort ? '反T' : '正T',
        buyTime: tEntryTime!,
        sellTime: bars[bars.length - 1].time,
        buyPrice: btRound(tShort ? exit : tEntryPrice, 3),
        sellPrice: btRound(tShort ? tEntryPrice : exit, 3),
        pnl: btRound(pnl, 4),
        reason: '收盘强平',
      ));
      dayProfit += pnl;
      equity.add(equity[equity.length - 1] * (1 + pnl));
    }
    dailyPnl.add({'day': day, 'pnl': btRound(dayProfit, 4), 'tCount': dayTCount});
  }
  final result = BacktestResult(
    strategy: 'intradayT',
    params: p.toJson(),
    metrics: perfMetrics(trades, equity),
    trades: trades,
    equity: equity,
    dailyPnl: dailyPnl,
  );
  return result;
}
