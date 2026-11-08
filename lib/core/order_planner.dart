/// order_planner.dart — 次日做T挂单推断引擎（v2.0）
///
/// 算法来源：日内做T回测参数（VWAP锚定）
///   正T：买入挂 = 锚定价×(1-0.6%)，卖出挂 = 买入×(1+1.2%)，止损 = 买入×(1-1.5%)
///   反T：卖出挂 = 锚定价×(1+0.8%)，买回挂 = 锚定价×(1-0.6%)，回补止损 = 卖出×(1+1.5%)
///   双向：两侧都给
/// 金额规则：默认试单金额、RSI≥70减半、反T按底仓1/3、向下取整到100股
/// 复盘规则：用次日日线OHLC模拟挂单成交/止盈/止损/未成交，诊断推断偏差原因
library;

import 'dart:math' as math;

import '../models.dart';

/// 单笔挂单计划
class OrderPlan {
  final String planDate; // 计划交易日（YYYY-MM-DD）
  final String code;
  final String name;
  final double score;
  final double refPrice; // 锚定价（生成时现价≈VWAP代理）
  final String direction; // '正T' | '反T' | '双向'
  final String signalText;
  final double buyPrice; // 正T买入挂 / 反T买回挂
  final double sellPrice; // 正T卖出挂 / 反T先卖价
  final double stopPrice; // 止损价（正T止损 / 反T回补止损）
  final double amount; // 建议金额（元）
  final int shares; // 建议股数（100股整数倍）
  final double rsi;
  final List<String> notes; // 操作要点/风控提示

  OrderPlan({
    required this.planDate,
    required this.code,
    required this.name,
    required this.score,
    required this.refPrice,
    required this.direction,
    required this.signalText,
    required this.buyPrice,
    required this.sellPrice,
    required this.stopPrice,
    required this.amount,
    required this.shares,
    required this.rsi,
    required this.notes,
  });

  Map<String, dynamic> toJson() => {
        'planDate': planDate,
        'code': code,
        'name': name,
        'score': score,
        'refPrice': refPrice,
        'direction': direction,
        'signalText': signalText,
        'buyPrice': buyPrice,
        'sellPrice': sellPrice,
        'stopPrice': stopPrice,
        'amount': amount,
        'shares': shares,
        'rsi': rsi,
        'notes': notes,
      };

  static OrderPlan fromJson(Map<String, dynamic> j) => OrderPlan(
        planDate: j['planDate'] as String,
        code: j['code'] as String,
        name: j['name'] as String,
        score: (j['score'] as num).toDouble(),
        refPrice: (j['refPrice'] as num).toDouble(),
        direction: j['direction'] as String,
        signalText: j['signalText'] as String? ?? '',
        buyPrice: (j['buyPrice'] as num).toDouble(),
        sellPrice: (j['sellPrice'] as num).toDouble(),
        stopPrice: (j['stopPrice'] as num).toDouble(),
        amount: (j['amount'] as num).toDouble(),
        shares: (j['shares'] as num).toInt(),
        rsi: (j['rsi'] as num?)?.toDouble() ?? 50,
        notes: List<String>.from(j['notes'] as List? ?? const []),
      );
}

double _r2(double x) => (x * 100).roundToDouble() / 100;

/// 由扫描结果生成次日挂单计划（全部筛选股都生成）
/// [unitAmount] 单笔试单金额（元），默认1万
/// [basePosition] 反T可卖底仓股数（0=不做反T）
List<OrderPlan> generateOrderPlans(
  List<ScoreResult> results, {
  required String planDate,
  double unitAmount = 10000,
  int basePosition = 0,
}) {
  final plans = <OrderPlan>[];
  for (final r in results) {
    if (!r.pass) continue;
    final price = r.price;
    if (!(price > 0)) continue;
    final rsi = r.metrics['rsi'] ?? 50;
    final dirLabel = r.directionLabelText ?? '';
    final isZhengT = dirLabel.contains('正T');
    final isFanT = dirLabel.contains('反T');
    final sigText = r.signal == null ? '' : signalLabel(r.signal!.action).$1;

    final notes = <String>[];
    double buy, sell, stop, amount;
    String direction;

    if (isFanT && !isZhengT) {
      // 反T：先卖后买（需底仓）
      direction = '反T';
      sell = _r2(price * 1.008);
      buy = _r2(price * 0.994);
      stop = _r2(sell * 1.015);
      amount = unitAmount;
      if (basePosition <= 0) {
        notes.add('无底仓不做裸卖：只挂买单${buy.toStringAsFixed(2)}等回落');
      } else {
        final sellShares = math.min(basePosition ~/ 3, (unitAmount / price).floor());
        notes.add('按底仓1/3卖出，最多${sellShares * 100}股；当日或次日必须补回，防踏空');
      }
    } else if (isZhengT && isFanT) {
      // 双向
      direction = '双向';
      buy = _r2(price * 0.994);
      sell = _r2(price * 1.008);
      stop = _r2(buy * 0.985);
      amount = unitAmount;
      notes.add('双向挂单：下方${buy.toStringAsFixed(2)}接、上方${sell.toStringAsFixed(2)}抛');
    } else {
      // 正T：先买后卖
      direction = '正T';
      buy = _r2(price * 0.994);
      sell = _r2(buy * 1.012);
      stop = _r2(buy * 0.985);
      amount = unitAmount;
      notes.add('先买后卖：持有底仓的前提下低吸做T');
    }

    // RSI 超买减半
    if (rsi >= 70) {
      amount = amount / 2;
      notes.add('RSI ${rsi.toStringAsFixed(1)}超买区，金额减半试探');
    }
    // 信号卖出 + 正T
    if (sigText == '卖出' && direction != '反T') {
      notes.add('信号=卖出：日线偏超买，只逢低吸不追高');
    }
    notes.add('单次目标+1.2% / 止损-1.5% / 成本0.16%；单日≤3笔');

    // 股数：向下取整到100股
    final px = direction == '反T' ? sell : buy;
    final shares = ((amount / px) ~/ 100) * 100;

    plans.add(OrderPlan(
      planDate: planDate,
      code: r.code,
      name: r.name,
      score: r.score,
      refPrice: price,
      direction: direction,
      signalText: sigText,
      buyPrice: buy,
      sellPrice: sell,
      stopPrice: stop,
      amount: amount,
      shares: shares,
      rsi: rsi,
      notes: notes,
    ));
  }
  return plans;
}

/// ============ 次日复盘：用实际日线对比挂单推断 ============

class ReviewItem {
  final OrderPlan plan;
  final String status; // '止盈' | '止损' | '持仓' | '未成交'
  final double pnlPct; // 实际收益%（未成交=0）
  final bool filled;
  final String diagnosis; // 推断偏差原因
  final String advice; // 参数完善建议

  ReviewItem({
    required this.plan,
    required this.status,
    required this.pnlPct,
    required this.filled,
    required this.diagnosis,
    required this.advice,
  });

  Map<String, dynamic> toJson() => {
        'plan': plan.toJson(),
        'status': status,
        'pnlPct': pnlPct,
        'filled': filled,
        'diagnosis': diagnosis,
        'advice': advice,
      };
}

/// 用当日实际K线（bar.time == planDate）复盘单笔挂单
ReviewItem reviewOrder(OrderPlan plan, Bar? dayBar) {
  if (dayBar == null) {
    return ReviewItem(
      plan: plan,
      status: '未成交',
      pnlPct: 0,
      filled: false,
      diagnosis: '当日K线缺失（停牌/数据缺失）',
      advice: '检查数据源；停牌日跳过不计入统计',
    );
  }
  final hi = dayBar.high, lo = dayBar.low, cl = dayBar.close;
  final isFan = plan.direction == '反T';

  if (isFan) {
    // 反T：先卖后买
    if (hi < plan.sellPrice) {
      return ReviewItem(
        plan: plan,
        status: '未成交',
        pnlPct: 0,
        filled: false,
        diagnosis:
            '全天最高${_r2(hi)}未触及卖价${plan.sellPrice}（振幅${_r2(dayBar.amplitude)}%不足）',
        advice: '未成交：可将卖出偏离开到1.0%（VWAP+1.0%）或改用开盘价锚定',
      );
    }
    // 卖出成交，看买回/回补止损
    if (hi >= plan.stopPrice) {
      final pnl = (plan.sellPrice - plan.stopPrice) / plan.stopPrice * 100 - 0.16;
      return ReviewItem(
        plan: plan,
        status: '止损',
        pnlPct: _r2(pnl),
        filled: true,
        diagnosis: '冲高${_r2(hi)}触发回补止损${plan.stopPrice}',
        advice: '止损被扫：回补止损可放宽到+2.0%，或避开ADX>30强趋势股',
      );
    }
    if (lo <= plan.buyPrice) {
      final pnl = (plan.sellPrice - plan.buyPrice) / plan.buyPrice * 100 - 0.16;
      return ReviewItem(
        plan: plan,
        status: '止盈',
        pnlPct: _r2(pnl),
        filled: true,
        diagnosis: '反T完成：${plan.sellPrice}卖→${plan.buyPrice}买回',
        advice: '按计划达成，参数保持',
      );
    }
    final pnl = (plan.sellPrice - cl) / cl * 100 - 0.16;
    return ReviewItem(
      plan: plan,
      status: '持仓',
      pnlPct: _r2(pnl),
      filled: true,
      diagnosis: '卖出成交后未到买回价，收盘价${_r2(cl)}浮动结算',
      advice: '收盘未回补须次日补回；可将买回偏离开到0.8%提高成交率',
    );
  }

  // 正T/双向：先买后卖
  if (lo > plan.buyPrice) {
    return ReviewItem(
      plan: plan,
      status: '未成交',
      pnlPct: 0,
      filled: false,
      diagnosis:
          '全天最低${_r2(lo)}未触及买价${plan.buyPrice}（振幅${_r2(dayBar.amplitude)}%不足/高开）',
      advice: '未成交：可将买入偏离开到0.8%（VWAP-0.8%）或挂单上移到开盘价附近',
    );
  }
  if (lo <= plan.stopPrice) {
    final pnl = (plan.stopPrice - plan.buyPrice) / plan.buyPrice * 100 - 0.16;
    return ReviewItem(
      plan: plan,
      status: '止损',
      pnlPct: _r2(pnl),
      filled: true,
      diagnosis: '买入后下探${_r2(lo)}触发止损${plan.stopPrice}',
      advice: '止损频触：stopPct可放宽到2.0%，或提高信号阈值只做强信号股',
    );
  }
  if (hi >= plan.sellPrice) {
    final pnl = (plan.sellPrice - plan.buyPrice) / plan.buyPrice * 100 - 0.16;
    return ReviewItem(
      plan: plan,
      status: '止盈',
      pnlPct: _r2(pnl),
      filled: true,
      diagnosis: '正T完成：${plan.buyPrice}买→${plan.sellPrice}卖',
      advice: '按计划达成，参数保持',
    );
  }
  final pnl = (cl - plan.buyPrice) / plan.buyPrice * 100 - 0.16;
  return ReviewItem(
    plan: plan,
    status: '持仓',
    pnlPct: _r2(pnl),
    filled: true,
    diagnosis: '买入成交未到目标价，收盘价${_r2(cl)}浮动结算',
    advice: '未到目标：可将目标收益降到1.0%提高日内了结率',
  );
}

/// 批量复盘 + 汇总统计 + 参数完善建议
Map<String, dynamic> reviewAll(List<OrderPlan> plans, List<Bar> barsOfDate) {
  final barMap = {for (final b in barsOfDate) b.time: b};
  final items = <ReviewItem>[];
  for (final p in plans) {
    // K线日期可能带时间，取前10位匹配
    Bar? bar;
    for (final b in barsOfDate) {
      final d = b.time.length >= 10 ? b.time.substring(0, 10) : b.time;
      if (d == p.planDate) {
        bar = b;
        break;
      }
    }
    bar ??= barMap[p.planDate];
    items.add(reviewOrder(p, bar));
  }
  final filled = items.where((e) => e.filled).toList();
  final wins = filled.where((e) => e.status == '止盈').length;
  final losses = filled.where((e) => e.status == '止损').length;
  final totalPnl = items.fold<double>(0, (a, e) => a + e.pnlPct);
  final noFill = items.where((e) => e.status == '未成交').length;

  final advice = <String>[];
  if (items.isNotEmpty && noFill / items.length > 0.5) {
    advice.add('未成交率${_r2(noFill / items.length * 100)}%过高：建议买入偏离0.6%→0.8%，或改用开盘价作锚');
  }
  if (filled.isNotEmpty && losses / filled.length > 0.5) {
    advice.add('止损率过高：建议stopPct 1.5%→2.0%，或signalThreshold提高到4只做强信号');
  }
  if (filled.isNotEmpty && wins / filled.length >= 0.61) {
    advice.add('胜率${_r2(wins / filled.length * 100)}%已过61%盈亏平衡线：参数可用，逐步加验证笔数');
  }
  if (advice.isEmpty) {
    advice.add('样本不足以下结论：继续记录满10-15笔再调参，避免过度拟合单日结果');
  }

  return {
    'items': items,
    'summary': {
      'total': items.length,
      'filled': filled.length,
      'wins': wins,
      'losses': losses,
      'noFill': noFill,
      'winRate': filled.isNotEmpty ? _r2(wins / filled.length * 100) : 0,
      'totalPnlPct': _r2(totalPnl),
    },
    'paramAdvice': advice,
  };
}
