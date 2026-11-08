/// optimize.dart — 参数自优化 / 验证改进闭环（忠实移植自 lib/optimize.js）
/// 网格搜索 + Walk-Forward 样本外验证，杜绝过拟合
library;

import '../models.dart';
import 'backtest.dart';
import 'scoring.dart';

double get nan => double.nan;
bool _finite(double x) => x.isFinite;

double optRound(double x, [int d = 4]) {
  final m = [1, 10, 100, 1000, 10000, 100000][d.clamp(0, 5)];
  return (x * m).roundToDouble() / m;
}

/// ---- 生成参数网格（笛卡尔积）----
List<Map<String, dynamic>> cartesian(Map<String, List<dynamic>> obj) {
  final keys = obj.keys.toList();
  var combos = <Map<String, dynamic>>[{}];
  for (final k in keys) {
    final next = <Map<String, dynamic>>[];
    for (final c in combos) {
      for (final v in obj[k]!) {
        next.add({...c, k: v});
      }
    }
    combos = next;
  }
  return combos;
}

/// ---- 按指标排序选优（metric: 'sharpe'|'totalReturn'|'winRate'|'profitFactor'）----
Map<String, dynamic>? pickBest(List<Map<String, dynamic>> results, String metric) {
  final valid = results.where((r) => ((r['metrics'] as BacktestMetrics).trades) >= 3).toList();
  final pool = valid.isNotEmpty ? valid : results;
  if (pool.isEmpty) return null;
  final sorted = List<Map<String, dynamic>>.from(pool)
    ..sort((a, b) => _metricOf(b, metric).compareTo(_metricOf(a, metric)));
  return sorted.first;
}

double _metricOf(Map<String, dynamic> r, String metric) {
  final m = r['metrics'] as BacktestMetrics;
  switch (metric) {
    case 'totalReturn':
      return m.totalReturn;
    case 'winRate':
      return m.winRate;
    case 'profitFactor':
      return m.profitFactor;
    case 'sharpe':
    default:
      return m.sharpe;
  }
}

// ============ A) 日内做T参数优化 ============
const Map<String, List<dynamic>> INTRADAY_GRID = {
  'buyBand': [0.004, 0.006, 0.008, 0.010],
  'sellBand': [0.006, 0.008, 0.010, 0.012],
  'targetPct': [0.008, 0.012, 0.016],
  'stopPct': [0.010, 0.015, 0.020],
  'maxTPerDay': [2, 3, 4],
};

Map<String, dynamic> gridSearchIntraday(List<Bar> minuteBars, Map<String, List<dynamic>> grid, String metric) {
  final combos = cartesian(grid);
  final results = <Map<String, dynamic>>[];
  for (final params in combos) {
    final r = backtestIntradayT(minuteBars, _intradayParamsFrom(params));
    results.add({'params': params, 'metrics': r.metrics});
  }
  final best = pickBest(results, metric);
  return {'best': best, 'total': combos.length, 'metric': metric};
}

IntradayParams _intradayParamsFrom(Map<String, dynamic> m) => IntradayParams(
      buyBand: (m['buyBand'] as num).toDouble(),
      sellBand: (m['sellBand'] as num).toDouble(),
      targetPct: (m['targetPct'] as num).toDouble(),
      stopPct: (m['stopPct'] as num).toDouble(),
      maxTPerDay: (m['maxTPerDay'] as num).toInt(),
    );

/// Walk-Forward：按交易日切分训练/验证
Map<String, dynamic> walkForwardIntraday(
  List<Bar> minuteBars,
  Map<String, List<dynamic>> grid,
  String metric, [
  double trainRatio = 0.7,
]) {
  final days = minuteBars.map((b) => b.time.length >= 10 ? b.time.substring(0, 10) : b.time).toSet().toList()..sort();
  if (days.length < 6) return {'ok': false, 'reason': '交易日不足(${days.length}天，需≥6)'};
  final splitIdx = (days.length * trainRatio).floor();
  final trainDays = days.sublist(0, splitIdx).toSet();
  final testDays = days.sublist(splitIdx).toSet();
  final trainBars = minuteBars.where((b) => trainDays.contains(b.time.substring(0, 10))).toList();
  final testBars = minuteBars.where((b) => testDays.contains(b.time.substring(0, 10))).toList();
  final trainSearch = gridSearchIntraday(trainBars, grid, metric);
  if (trainSearch['best'] == null) return {'ok': false, 'reason': '训练期无有效交易'};
  final bestParams = trainSearch['best']!['params'] as Map<String, dynamic>;
  final trainPerf = backtestIntradayT(trainBars, _intradayParamsFrom(bestParams)).metrics;
  final testPerf = backtestIntradayT(testBars, _intradayParamsFrom(bestParams)).metrics;
  return {
    'ok': true,
    'bestParams': bestParams,
    'metric': metric,
    'train': {'days': trainDays.length, 'perf': trainPerf},
    'test': {'days': testDays.length, 'perf': testPerf},
    'overfitGap': optRound(_metricVal(trainPerf, metric) - _metricVal(testPerf, metric), 3),
    'verdict': judgeOverfit(trainPerf, testPerf, metric),
  };
}

// ============ B) 日线波段T参数优化 ============
const Map<String, List<dynamic>> DAILY_GRID = {
  'stopLoss': [0.03, 0.05, 0.08],
  'takeProfit': [0.08, 0.12, 0.20],
  'signalThreshold': [2, 3, 4],
  'useWeak': [true, false],
};

Map<String, dynamic> gridSearchDaily(List<Bar> daily, ScoreConfig cfg, Map<String, List<dynamic>> grid, String metric) {
  final combos = cartesian(grid);
  final results = <Map<String, dynamic>>[];
  for (final params in combos) {
    final r = backtestDailySwing(daily, cfg, _dailyParamsFrom(params, cfg));
    results.add({'params': params, 'metrics': r.metrics});
  }
  final best = pickBest(results, metric);
  return {'best': best, 'total': combos.length, 'metric': metric};
}

DailyParams _dailyParamsFrom(Map<String, dynamic> m, ScoreConfig cfg) => DailyParams(
      stopLoss: (m['stopLoss'] as num).toDouble(),
      takeProfit: (m['takeProfit'] as num).toDouble(),
      signalThreshold: (m['signalThreshold'] as num).toInt(),
      useWeak: m['useWeak'] as bool,
      costRate: cfg.costRate,
    );

Map<String, dynamic> walkForwardDaily(
  List<Bar> daily,
  ScoreConfig cfg,
  Map<String, List<dynamic>> grid,
  String metric, [
  double trainRatio = 0.7,
]) {
  if (daily.length < 80) return {'ok': false, 'reason': '日线样本不足(${daily.length}，需≥80)'};
  final splitIdx = (daily.length * trainRatio).floor();
  final trainData = daily.sublist(0, splitIdx);
  final testData = daily.sublist(splitIdx);
  final trainSearch = gridSearchDaily(trainData, cfg, grid, metric);
  if (trainSearch['best'] == null) return {'ok': false, 'reason': '训练期无有效交易'};
  final bestParams = trainSearch['best']!['params'] as Map<String, dynamic>;
  final trainPerf = backtestDailySwing(trainData, cfg, _dailyParamsFrom(bestParams, cfg)).metrics;
  final testPerf = backtestDailySwing(testData, cfg, _dailyParamsFrom(bestParams, cfg)).metrics;
  return {
    'ok': true,
    'bestParams': bestParams,
    'metric': metric,
    'train': {'bars': trainData.length, 'perf': trainPerf},
    'test': {'bars': testData.length, 'perf': testPerf},
    'overfitGap': optRound(_metricVal(trainPerf, metric) - _metricVal(testPerf, metric), 3),
    'verdict': judgeOverfit(trainPerf, testPerf, metric),
  };
}

double _metricVal(BacktestMetrics m, String metric) {
  switch (metric) {
    case 'totalReturn':
      return m.totalReturn;
    case 'winRate':
      return m.winRate;
    case 'profitFactor':
      return m.profitFactor;
    case 'sharpe':
    default:
      return m.sharpe;
  }
}

/// ---- 过拟合判定 ----
Map<String, String> judgeOverfit(BacktestMetrics trainPerf, BacktestMetrics testPerf, String metric) {
  final tr = _metricVal(trainPerf, metric);
  final te = _metricVal(testPerf, metric);
  if (te <= 0 && tr > 0) {
    return {'level': '严重过拟合', 'advice': '训练期盈利但样本外亏损，参数不可用，应简化策略或扩大样本'};
  }
  final gap = tr - te;
  final rel = tr != 0 ? (gap.abs() / tr.abs()) : 1;
  if (te > 0 && rel < 0.5) return {'level': '稳健', 'advice': '样本外保持盈利且与训练期差距小，参数可用'};
  if (te > 0) return {'level': '轻度衰减', 'advice': '样本外仍盈利但明显衰减，可谨慎使用并持续跟踪'};
  return {'level': '样本外失效', 'advice': '样本外未盈利，建议降低参数敏感度或结合多因子打分筛选标的'};
}

// ============ 综合自优化报告（单只股票，数据由外部注入）============
Map<String, dynamic> autoOptimizeReport(
  List<Bar> daily,
  List<Bar> minuteBars,
  ScoreConfig cfg, [
  String metric = 'sharpe',
]) {
  final report = <String, dynamic>{
    'dailyBars': daily.length,
    'minBars': minuteBars.length,
    'metric': metric,
  };
  report['daily'] = walkForwardDaily(daily, cfg, DAILY_GRID, metric);
  report['intraday'] = walkForwardIntraday(minuteBars, INTRADAY_GRID, metric);
  final dailyWf = report['daily'] as Map<String, dynamic>;
  final intradayWf = report['intraday'] as Map<String, dynamic>;
  // 推荐参数（取验证期仍稳健的；若过拟合则回退到保守默认）
  final dailyVerdict = (dailyWf['ok'] == true) ? (dailyWf['verdict'] as Map<String, String>)['level'] : null;
  final intradayVerdict = (intradayWf['ok'] == true) ? (intradayWf['verdict'] as Map<String, String>)['level'] : null;
  report['recommend'] = {
    'daily': (dailyWf['ok'] == true && dailyVerdict != '严重过拟合' && dailyVerdict != '样本外失效')
        ? dailyWf['bestParams']
        : {'stopLoss': 0.05, 'takeProfit': 0.12, 'signalThreshold': 3, 'useWeak': false},
    'intraday': (intradayWf['ok'] == true && intradayVerdict != '严重过拟合' && intradayVerdict != '样本外失效')
        ? intradayWf['bestParams']
        : {'buyBand': 0.006, 'sellBand': 0.008, 'targetPct': 0.012, 'stopPct': 0.015, 'maxTPerDay': 3},
  };
  return report;
}
