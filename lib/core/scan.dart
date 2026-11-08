/// scan.dart — 全A股做T适配度扫描引擎（忠实移植自 lib/scan.js）
/// 两级漏斗：快照预筛（列表字段）→ 日线精评（多因子打分）
library;

import '../models.dart';
import 'scoring.dart';

/// ---- 快照预筛（不拉K线，仅用列表字段）----
List<StockSnap> preFilter(List<StockSnap> list, [Map<String, dynamic>? cfgOverride]) {
  final cfg = <String, dynamic>{
    'minPrice': 3.0,
    'maxPrice': 300.0,
    'minAmount': 1.5e8, // 今日成交额≥1.5亿
    'minTurnover': 2.0,
    'maxTurnover': 25.0,
    'minAmplitude': 2.5, // 今日振幅≥2.5%
    'excludeST': true,
    'excludeBJ': true,
    ...?cfgOverride,
  };
  final minPrice = (cfg['minPrice'] as num).toDouble();
  final maxPrice = (cfg['maxPrice'] as num).toDouble();
  final minAmount = (cfg['minAmount'] as num).toDouble();
  final minTurnover = (cfg['minTurnover'] as num).toDouble();
  final maxTurnover = (cfg['maxTurnover'] as num).toDouble();
  final minAmplitude = (cfg['minAmplitude'] as num).toDouble();
  final excludeST = cfg['excludeST'] as bool;
  final excludeBJ = cfg['excludeBJ'] as bool;

  final out = <StockSnap>[];
  for (final s in list) {
    final name = s.name;
    if (excludeST && RegExp(r'ST|退').hasMatch(name)) continue;
    final code = s.code;
    if (excludeBJ && RegExp(r'^(4|8|92)').hasMatch(code)) continue;
    if (!(s.price >= minPrice && s.price <= maxPrice)) continue;
    if (!(s.amount >= minAmount)) continue;
    if (!(s.turnover >= minTurnover && s.turnover <= maxTurnover)) continue;
    // 振幅 = (高-低)/昨收；昨收 = 价/(1+涨幅%)
    final prevClose = s.chgPct != -100 ? s.price / (1 + s.chgPct / 100) : s.price;
    final amplitude = prevClose > 0 ? (s.high - s.low) / prevClose * 100 : 0;
    if (!(amplitude >= minAmplitude)) continue;
    out.add(s.copyWith(amplitudeToday: (amplitude * 100).roundToDouble() / 100));
  }
  return out;
}

double roundX(double x, [int d = 2]) {
  var m = 1;
  for (var i = 0; i < d; i++) {
    m *= 10;
  }
  return (x * m).roundToDouble() / m;
}

/// ---- 全量扫描 ----
/// [fetchList] 返回全A股快照列表；[fetchDaily] 返回指定代码日线
/// onProgress: {'stage':'prefilter', total, candidates, picked} 或 {'stage':'scoring', done, total, code, name}
Future<Map<String, dynamic>> fullScan({
  int limit = 200, // 精评候选上限（按今日成交额排序取前N）
  int dailyLen = 120, // 精评用日线长度
  ScoreConfig? cfg,
  Map<String, dynamic> preFilterCfg = const {},
  required Future<List<StockSnap>> Function({bool useCache}) fetchList,
  required Future<List<Bar>> Function(String code, {required int lmt, bool useCache}) fetchDaily,
  bool useCache = true,
  void Function(Map<String, dynamic> progress)? onProgress,
}) async {
  final t0 = DateTime.now().millisecondsSinceEpoch;
  final config = cfg ?? ScoreConfig();
  final list = await fetchList(useCache: useCache);
  if (list.isEmpty) {
    return {'ok': false, 'reason': '获取全A股列表失败', 'results': <ScoreResult>[]};
  }
  final candidates = preFilter(list, preFilterCfg);
  // 按成交额降序，取前 limit 只精评（流动性优先）
  candidates.sort((a, b) => b.amount.compareTo(a.amount));
  final picked = candidates.length > limit ? candidates.sublist(0, limit) : candidates;
  onProgress?.call({
    'stage': 'prefilter',
    'total': list.length,
    'candidates': candidates.length,
    'picked': picked.length,
  });

  final results = <ScoreResult>[];
  var done = 0;
  for (final s in picked) {
    List<Bar> daily;
    try {
      daily = await fetchDaily(s.code, lmt: dailyLen, useCache: useCache);
    } catch (_) {
      daily = <Bar>[];
    }
    done++;
    if (onProgress != null && (done % 10 == 0 || done == picked.length)) {
      onProgress({
        'stage': 'scoring',
        'done': done,
        'total': picked.length,
        'code': s.code,
        'name': s.name,
      });
    }
    if (daily.length < 30) continue;
    final r = scoreStock(s, daily, config);
    if (r.pass) results.add(r);
  }
  results.sort((a, b) => b.score.compareTo(a.score));
  return {
    'ok': true,
    'elapsed': roundX((DateTime.now().millisecondsSinceEpoch - t0) / 1000, 1),
    'universe': list.length,
    'candidates': candidates.length,
    'scored': results.length,
    'results': results,
  };
}
