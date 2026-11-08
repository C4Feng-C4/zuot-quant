/// datasource.dart — A股免费行情数据层（忠实移植自 lib/datasource.js）
///
/// 主数据源：新浪财经（稳定、无需 token）
///   - 全A股列表：vip.stock.finance.sina.com.cn Market_Center.getHQNodeData（分页）
///   - K线：quotes.sina.cn CN_MarketDataService.getKLineData（scale=240日 / 5,15,30,60分钟）
/// 备选数据源：东方财富 push2（字段更全，含振幅/量比；被限流时自动回退）
///
/// 设计要点：
///   - 全局串行队列 + 最小间隔限频（MIN_INTERVAL_MS=150），避免被封 IP
///   - 指数退避重试（retries=3）
///   - 内存缓存（列表按当日、K线按当日+参数），移动端会话级缓存
///   - 新浪响应为 GBK 编码，使用 gbk_codec 解码中文名
library;

import 'dart:async';
import 'dart:convert';

import 'package:gbk_codec/gbk_codec.dart';
import 'package:http/http.dart' as http;

import '../models.dart';

const int minIntervalMs = 150;
int _lastReqTime = 0;

/// 限频等待：保证两次请求间隔 >= minIntervalMs
Future<void> _throttleWait() async {
  final now = DateTime.now().millisecondsSinceEpoch;
  final w = _lastReqTime + minIntervalMs - now;
  _lastReqTime = now + (w > 0 ? w : 0);
  if (w > 0) {
    await Future<void>.delayed(Duration(milliseconds: w));
  }
}

/// 全局串行队列（对应 JS 的 queue Promise 链）
Future<void> _queue = Future<void>.value();

Future<http.Response> _serialGet(Uri url, Map<String, String> headers,
    {int retries = 3, int timeoutMs = 12000}) {
  final completer = Completer<http.Response>();
  _queue = _queue.then((_) async {
    try {
      final r = await _doGet(url, headers, retries: retries, timeoutMs: timeoutMs);
      completer.complete(r);
    } catch (e, st) {
      completer.completeError(e, st);
    }
  });
  return completer.future;
}

Future<http.Response> _doGet(Uri url, Map<String, String> headers,
    {required int retries, required int timeoutMs}) async {
  var attempt = 0;
  Object? lastErr;
  while (attempt <= retries) {
    attempt++;
    await _throttleWait();
    try {
      final resp = await http
          .get(url, headers: headers)
          .timeout(Duration(milliseconds: timeoutMs));
      if (resp.statusCode == 200) return resp;
      lastErr = Exception('HTTP ${resp.statusCode}');
    } catch (e) {
      lastErr = e;
    }
    if (attempt <= retries) {
      await Future<void>.delayed(Duration(milliseconds: 400 * attempt));
    }
  }
  throw Exception('请求失败: $url ($lastErr)');
}

const Map<String, String> sinaHdr = {
  'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
  'Referer': 'https://finance.sina.com.cn',
};
const Map<String, String> emHdr = {
  'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
  'Referer': 'https://quote.eastmoney.com/',
};

/// GBK 字节流 -> 字符串（新浪响应）；失败回退 UTF-8
/// 注意：http 响应是原始字节流，须用 gbk_bytes（不是 gbk 的 16 位码表接口）
String _decodeSina(List<int> bytes) {
  try {
    return gbk_bytes.decode(bytes);
  } catch (_) {
    return utf8.decode(bytes, allowMalformed: true);
  }
}

// ---- 缓存（内存，按 key + 日期） ----
String todayStr() {
  final d = DateTime.now();
  final mm = d.month.toString().padLeft(2, '0');
  final dd = d.day.toString().padLeft(2, '0');
  return '${d.year}$mm$dd';
}

final Map<String, (DateTime, Object)> _cache = <String, (DateTime, Object)>{};

Object? _readCache(String name, int maxAgeMs) {
  final c = _cache[name];
  if (c == null) return null;
  if (maxAgeMs > 0 &&
      DateTime.now().difference(c.$1).inMilliseconds > maxAgeMs) {
    _cache.remove(name);
    return null;
  }
  return c.$2;
}

void _writeCache(String name, Object obj) {
  _cache[name] = (DateTime.now(), obj);
}

/// 清空内存缓存
void clearCache() => _cache.clear();

// ---- 代码 -> 新浪 symbol / 东财 secid ----
String marketPrefix(String code) {
  final c = code.trim();
  if (RegExp(r'^92').hasMatch(c)) return 'bj'; // 北交所 920xxx
  if (RegExp(r'^(4|8)').hasMatch(c)) return 'bj'; // 北交所 43/83/87xxx
  if (RegExp(r'^(6|5|9)').hasMatch(c)) return 'sh'; // 沪主板/科创/基金/B股
  if (RegExp(r'^(0|2|3|1)').hasMatch(c)) return 'sz'; // 深主板/创业板/B股/基金
  return 'sh';
}

String toSinaSymbol(String code) => marketPrefix(code) + code;

String toSecId(String code) {
  final p = marketPrefix(code);
  return (p == 'sh' ? '1.' : '0.') + code;
}

// =====================================================================
// 1) 全A股列表
// =====================================================================
// 新浪字段：symbol code name trade pricechange changepercent open high low
//          volume amount turnoverratio per pb mktcap nmc(流通市值万元)
Future<List<StockSnap>> fetchStockListSina(
    {bool useCache = true, int num = 100, int maxPages = 80}) async {
  final cacheName = 'list_sina_${todayStr()}';
  if (useCache) {
    final c = _readCache(cacheName, 6 * 3600 * 1000);
    if (c is List<StockSnap> && c.isNotEmpty) return c;
  }
  final all = <StockSnap>[];
  for (var page = 1; page <= maxPages; page++) {
    final url = Uri.parse(
        'https://vip.stock.finance.sina.com.cn/quotes_service/api/json_v2.php/Market_Center.getHQNodeData?page=$page&num=$num&sort=symbol&asc=1&node=hs_a');
    String txt;
    try {
      final resp = await _serialGet(url, sinaHdr);
      txt = _decodeSina(resp.bodyBytes);
    } catch (_) {
      break;
    }
    List<dynamic>? arr;
    try {
      final decoded = json.decode(txt);
      if (decoded is List<dynamic>) arr = decoded;
    } catch (_) {
      break;
    }
    if (arr == null || arr.isEmpty) break;
    for (final it in arr) {
      final m = Map<String, dynamic>.from(it as Map);
      final price = double.tryParse('${m['trade']}') ?? 0;
      final floatMvWan = double.tryParse('${m['nmc']}') ?? 0; // 万元
      // 流通股本(股) = 流通市值(元) / 价格
      final floatShares = price > 0 ? (floatMvWan * 1e4) / price : 0.0;
      all.add(StockSnap(
        code: '${m['code']}',
        symbol: '${m['symbol']}',
        name: '${m['name']}',
        price: price,
        chgPct: double.tryParse('${m['changepercent']}') ?? 0,
        open: double.tryParse('${m['open']}') ?? 0,
        high: double.tryParse('${m['high']}') ?? 0,
        low: double.tryParse('${m['low']}') ?? 0,
        volume: double.tryParse('${m['volume']}') ?? 0,
        amount: double.tryParse('${m['amount']}') ?? 0,
        turnover: double.tryParse('${m['turnoverratio']}') ?? 0,
        pe: double.tryParse('${m['per']}') ?? 0,
        pb: double.tryParse('${m['pb']}') ?? 0,
        totalMv: (double.tryParse('${m['mktcap']}') ?? 0) * 1e4,
        floatMv: floatMvWan * 1e4,
        floatShares: floatShares,
      ));
    }
    if (arr.length < num) break;
  }
  if (all.isNotEmpty) _writeCache(cacheName, all);
  return all;
}

// 东财列表（备选，字段含振幅f7/量比f10；f15最高 f16最低 f17开盘 —— 实测接口确认）
const String _emListFields = 'f12,f14,f2,f3,f5,f6,f7,f8,f10,f9,f23,f20,f21,f15,f16,f17';
const String _emListFs =
    'm:0+t:6,m:0+t:80,m:1+t:2,m:1+t:23,m:0+t:81+s:2048';

Future<List<StockSnap>> fetchStockListEM(
    {bool useCache = true, int pageSize = 200}) async {
  final cacheName = 'list_em_${todayStr()}';
  if (useCache) {
    final c = _readCache(cacheName, 6 * 3600 * 1000);
    if (c is List<StockSnap> && c.isNotEmpty) return c;
  }
  final all = <StockSnap>[];
  for (var pn = 1; pn <= 60; pn++) {
    final url = Uri.parse(
        'https://push2.eastmoney.com/api/qt/clist/get?pn=$pn&pz=$pageSize&po=1&np=1&fltt=2&invt=2&fid=f6&fs=$_emListFs&fields=$_emListFields');
    Map<String, dynamic> jsonMap;
    try {
      final resp = await _serialGet(url, emHdr);
      jsonMap = json.decode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      break;
    }
    final data = jsonMap['data'];
    final diff = data is Map ? data['diff'] : null;
    if (diff is! List || diff.isEmpty) break;
    for (final it in diff) {
      final m = Map<String, dynamic>.from(it as Map);
      all.add(StockSnap(
        code: '${m['f12']}',
        name: '${m['f14']}',
        price: _numOf(m['f2']) ?? 0,
        chgPct: _numOf(m['f3']) ?? 0,
        // StockSnap 的 open/high/low 是必填项；scan.dart 用 high-low 算当日振幅做预筛，
        // 填 0 会导致东财回退路径下全市场振幅为 0、预筛全部淘汰，故必须取真值 f17/f15/f16
        open: _numOf(m['f17']) ?? 0,
        high: _numOf(m['f15']) ?? 0,
        low: _numOf(m['f16']) ?? 0,
        volume: _numOf(m['f5']) ?? 0,
        amount: _numOf(m['f6']) ?? 0,
        amplitude: _numOf(m['f7']) ?? 0,
        turnover: _numOf(m['f8']) ?? 0,
        volRatio: _numOf(m['f10']) ?? 0,
        pe: _numOf(m['f9']) ?? 0,
        pb: _numOf(m['f23']) ?? 0,
        totalMv: _numOf(m['f20']) ?? 0,
        floatMv: _numOf(m['f21']) ?? 0,
        floatShares: 0,
      ));
    }
    final total = data is Map ? (_numOf(data['total']) ?? 0) : 0;
    if (all.length >= total) break;
  }
  if (all.isNotEmpty) _writeCache(cacheName, all);
  return all;
}

double? _numOf(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse('$v');
}

/// 统一入口：全A股列表（优先新浪；为空回退东财）
Future<List<StockSnap>> fetchStockList({bool useCache = true}) async {
  List<StockSnap> list;
  try {
    list = await fetchStockListSina(useCache: useCache);
  } catch (_) {
    list = <StockSnap>[];
  }
  if (list.isEmpty) {
    try {
      list = await fetchStockListEM(useCache: useCache);
    } catch (_) {
      list = <StockSnap>[];
    }
  }
  return list;
}

// =====================================================================
// 2) K线
// =====================================================================
// 新浪 K线：scale=240日 / 5,15,30,60分钟；datalen=根数
List<Bar> _parseSinaKline(List<dynamic> arr, bool isDaily) {
  final out = <Bar>[];
  double? prevClose;
  for (final it in arr) {
    final m = Map<String, dynamic>.from(it as Map);
    final open = _numOf(m['open']) ?? 0;
    final high = _numOf(m['high']) ?? 0;
    final low = _numOf(m['low']) ?? 0;
    final close = _numOf(m['close']) ?? 0;
    final volume = _numOf(m['volume']) ?? 0; // 股
    // 日线无 amount，用 VWAP 近似；分钟线有 amount
    double amount = _numOf(m['amount']) ?? double.nan;
    if (!amount.isFinite) {
      amount = volume * (open + high + low + close) / 4;
    }
    final chgPct =
        prevClose != null && prevClose != 0 ? (close - prevClose) / prevClose * 100 : 0.0;
    final amplitude = prevClose != null && prevClose != 0
        ? (high - low) / prevClose * 100
        : (open != 0 ? (high - low) / open * 100 : 0.0);
    out.add(Bar(
      time: '${m['day']}', // 日线"YYYY-MM-DD"，分钟"YYYY-MM-DD HH:MM:SS"
      open: open,
      high: high,
      low: low,
      close: close,
      volume: volume,
      amount: amount,
      chgPct: chgPct,
      amplitude: amplitude,
    ));
    prevClose = close;
  }
  return out;
}

Future<List<Bar>> fetchKlineSina(String code,
    {int scale = 240,
    int datalen = 250,
    bool useCache = true,
    int cacheHours = 12}) async {
  final isDaily = scale == 240;
  final cacheName = 'k_sina_${code}_${scale}_${datalen}_${todayStr()}';
  if (useCache) {
    final c = _readCache(cacheName, cacheHours * 3600 * 1000);
    if (c is List<Bar> && c.isNotEmpty) return c;
  }
  final sym = toSinaSymbol(code);
  final url = Uri.parse(
      'https://quotes.sina.cn/cn/api/json_v2.php/CN_MarketDataService.getKLineData?symbol=$sym&scale=$scale&ma=no&datalen=$datalen');
  List<dynamic>? arr;
  try {
    final resp = await _serialGet(url, sinaHdr);
    final decoded = json.decode(_decodeSina(resp.bodyBytes));
    if (decoded is List<dynamic>) arr = decoded;
  } catch (_) {
    return <Bar>[];
  }
  if (arr == null || arr.isEmpty) return <Bar>[];
  final parsed = _parseSinaKline(arr, isDaily);
  _writeCache(cacheName, parsed);
  return parsed;
}

// 东财 K线（备选，含真实成交额/换手率/振幅）
const String _emKFields2 = 'f51,f52,f53,f54,f55,f56,f57,f58,f59,f60,f61';

List<Bar> _parseEMKline(List<dynamic> raw) {
  final out = <Bar>[];
  for (final line in raw) {
    final p = '$line'.split(',');
    out.add(Bar(
      time: p[0],
      open: double.tryParse(p[1]) ?? 0,
      close: double.tryParse(p[2]) ?? 0,
      high: double.tryParse(p[3]) ?? 0,
      low: double.tryParse(p[4]) ?? 0,
      volume: (double.tryParse(p[5]) ?? 0) * 100, // 东财成交量单位=手，转成股
      amount: double.tryParse(p[6]) ?? 0,
      amplitude: p.length > 7 ? (double.tryParse(p[7]) ?? 0) : 0,
      chgPct: p.length > 8 ? (double.tryParse(p[8]) ?? 0) : 0,
      turnover: p.length > 10 ? double.tryParse(p[10]) : null,
    ));
  }
  return out;
}

Future<List<Bar>> fetchKlineEM(String code,
    {int klt = 101,
    int fqt = 1,
    int lmt = 250,
    bool useCache = true,
    int cacheHours = 12}) async {
  final cacheName = 'k_em_${code}_${klt}_${fqt}_${lmt}_${todayStr()}';
  if (useCache) {
    final c = _readCache(cacheName, cacheHours * 3600 * 1000);
    if (c is List<Bar> && c.isNotEmpty) return c;
  }
  final url = Uri.parse(
      'https://push2his.eastmoney.com/api/qt/stock/kline/get?secid=${toSecId(code)}&fields1=f1,f2,f3,f4,f5,f6&fields2=$_emKFields2&klt=$klt&fqt=$fqt&end=20500101&lmt=$lmt');
  try {
    final resp = await _serialGet(url, emHdr);
    final jsonMap =
        json.decode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    final data = jsonMap['data'];
    final klines = data is Map ? data['klines'] : null;
    if (klines is! List || klines.isEmpty) return <Bar>[];
    final parsed = _parseEMKline(klines);
    _writeCache(cacheName, parsed);
    return parsed;
  } catch (_) {
    return <Bar>[];
  }
}

/// 统一入口：日线（新浪主，东财备）
Future<List<Bar>> fetchDaily(String code,
    {int lmt = 250, bool useCache = true, int cacheHours = 12}) async {
  var k = await fetchKlineSina(code,
      scale: 240, datalen: lmt, useCache: useCache, cacheHours: cacheHours);
  if (k.length < 2) {
    try {
      final k2 = await fetchKlineEM(code, klt: 101, lmt: lmt, useCache: useCache);
      if (k2.length > k.length) k = k2;
    } catch (_) {/* 忽略 */}
  }
  return k;
}

/// 统一入口：分钟线（scale=5/15/30/60）
Future<List<Bar>> fetchMin(String code, int scale,
    {int lmt = 480, bool useCache = true, int cacheHours = 12}) async {
  var k = await fetchKlineSina(code,
      scale: scale, datalen: lmt, useCache: useCache, cacheHours: cacheHours);
  if (k.length < 2) {
    try {
      final k2 = await fetchKlineEM(code, klt: scale, lmt: lmt, useCache: useCache);
      if (k2.length > k.length) k = k2;
    } catch (_) {/* 忽略 */}
  }
  return k;
}
