/// models.dart — 数据模型（与 Web 版 datasource.js 字段一一对应）
library;

/// K线bar（日线/分钟线通用）
/// 对应 JS: {time, open, high, low, close, volume, amount, chgPct, amplitude, turnover?}
class Bar {
  String time;
  double open;
  double high;
  double low;
  double close;
  double volume;
  double amount;
  double chgPct;
  double amplitude;
  double? turnover; // 新浪日线无换手，由 scoreStock 用 floatShares 推算

  Bar({
    required this.time,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
    required this.amount,
    required this.chgPct,
    required this.amplitude,
    this.turnover,
  });

  Map<String, dynamic> toJson() => {
        'time': time,
        'open': open,
        'high': high,
        'low': low,
        'close': close,
        'volume': volume,
        'amount': amount,
        'chgPct': chgPct,
        'amplitude': amplitude,
        if (turnover != null) 'turnover': turnover,
      };

  static Bar fromJson(Map<String, dynamic> j) => Bar(
        time: j['time'] as String,
        open: (j['open'] as num).toDouble(),
        high: (j['high'] as num).toDouble(),
        low: (j['low'] as num).toDouble(),
        close: (j['close'] as num).toDouble(),
        volume: (j['volume'] as num).toDouble(),
        amount: (j['amount'] as num).toDouble(),
        chgPct: (j['chgPct'] as num).toDouble(),
        amplitude: (j['amplitude'] as num).toDouble(),
        turnover: (j['turnover'] as num?)?.toDouble(),
      );
}

/// 股票快照（列表）
/// 对应 JS: {code, symbol, name, price, chgPct, open, high, low, volume, amount, turnover, pe, pb, totalMv, floatMv, floatShares, volRatio?, amplitude?}
class StockSnap {
  String code;
  String? symbol;
  String name;
  double price;
  double chgPct;
  double open;
  double high;
  double low;
  double volume;
  double amount;
  double turnover;
  double pe;
  double pb;
  double totalMv;
  double floatMv;
  double floatShares;
  double? volRatio; // 仅东财
  double? amplitude; // 仅东财
  double? amplitudeToday; // 预筛计算附加

  StockSnap({
    required this.code,
    this.symbol,
    required this.name,
    required this.price,
    required this.chgPct,
    required this.open,
    required this.high,
    required this.low,
    required this.volume,
    required this.amount,
    required this.turnover,
    required this.pe,
    required this.pb,
    required this.totalMv,
    required this.floatMv,
    required this.floatShares,
    this.volRatio,
    this.amplitude,
    this.amplitudeToday,
  });

  StockSnap copyWith({double? amplitudeToday}) => StockSnap(
        code: code,
        symbol: symbol,
        name: name,
        price: price,
        chgPct: chgPct,
        open: open,
        high: high,
        low: low,
        volume: volume,
        amount: amount,
        turnover: turnover,
        pe: pe,
        pb: pb,
        totalMv: totalMv,
        floatMv: floatMv,
        floatShares: floatShares,
        volRatio: volRatio,
        amplitude: amplitude,
        amplitudeToday: amplitudeToday ?? this.amplitudeToday,
      );
}

/// 做T方向
enum TDirection { positive, negative, both }

String directionLabel(TDirection d) {
  switch (d) {
    case TDirection.positive:
      return '正T为主(先买后卖)';
    case TDirection.negative:
      return '反T为主(先卖后买)';
    case TDirection.both:
      return '双向做T(震荡)';
  }
}

/// 信号动作
enum SignalAction { buy, weakBuy, sell, weakSell, hold }

(String, String) signalLabel(SignalAction a) {
  switch (a) {
    case SignalAction.buy:
      return ('买入', 'sig-buy');
    case SignalAction.weakBuy:
      return ('弱买', 'sig-buy');
    case SignalAction.sell:
      return ('卖出', 'sig-sell');
    case SignalAction.weakSell:
      return ('弱卖', 'sig-sell');
    case SignalAction.hold:
      return ('观望', 'sig-hold');
  }
}

/// 买卖信号结果
class Signal {
  final SignalAction action;
  final int strength; // 净分 buy - sell
  final int buy;
  final int sell;
  final List<String> reasons;

  Signal(this.action, this.strength, this.buy, this.sell, this.reasons);
}

/// 硬过滤/打分结果
class ScoreResult {
  final String code;
  final String name;
  final bool pass;
  final String? reason;
  final double price;
  final double score;
  final Map<String, int> factors;
  final Map<String, double> metrics;
  final TDirection? direction;
  final String? directionLabelText;
  final Signal? signal;

  ScoreResult({
    required this.code,
    required this.name,
    required this.pass,
    this.reason,
    this.price = 0,
    this.score = 0,
    this.factors = const {},
    this.metrics = const {},
    this.direction,
    this.directionLabelText,
    this.signal,
  });
}

/// 回测交易记录
class Trade {
  final String type; // 'swing' | 'intraday'
  final String? dir; // '正T' | '反T'（日内）
  final String buyTime;
  final String sellTime;
  final double buyPrice;
  final double sellPrice;
  final double pnl; // 小数（0.01=1%）
  final String reason;

  Trade({
    required this.type,
    this.dir,
    required this.buyTime,
    required this.sellTime,
    required this.buyPrice,
    required this.sellPrice,
    required this.pnl,
    required this.reason,
  });
}

/// 绩效指标
class BacktestMetrics {
  final double totalReturn; // %
  final double annual; // %
  final double winRate; // %
  final int trades;
  final double maxDrawdown; // %
  final double sharpe;
  final double profitFactor;
  final double avgWin; // %
  final double avgLoss; // %

  BacktestMetrics({
    required this.totalReturn,
    required this.annual,
    required this.winRate,
    required this.trades,
    required this.maxDrawdown,
    required this.sharpe,
    required this.profitFactor,
    required this.avgWin,
    required this.avgLoss,
  });

  static BacktestMetrics get empty => BacktestMetrics(
        totalReturn: 0,
        annual: 0,
        winRate: 0,
        trades: 0,
        maxDrawdown: 0,
        sharpe: 0,
        profitFactor: 0,
        avgWin: 0,
        avgLoss: 0,
      );
}

/// 回测结果
class BacktestResult {
  final String strategy;
  final Map<String, dynamic> params;
  final BacktestMetrics metrics;
  final List<Trade> trades;
  final List<double> equity;
  final List<Map<String, dynamic>>? dailyPnl; // 日内策略的每日盈亏

  BacktestResult({
    required this.strategy,
    required this.params,
    required this.metrics,
    required this.trades,
    required this.equity,
    this.dailyPnl,
  });
}

/// 列表工具：模拟 JS 的 slice(-n)
List<T> tail(List<T> a, int n) {
  if (n <= 0) return <T>[];
  if (n >= a.length) return List<T>.from(a);
  return a.sublist(a.length - n);
}
