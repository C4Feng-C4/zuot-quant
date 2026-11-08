/// stock_detail_page.dart — 个股详情页
/// K线图 + 因子打分 + 信号 + 双策略回测 + 参数优化 + ML对照
library;

import 'package:flutter/material.dart';

import '../core/backtest.dart';
import '../core/ml.dart';
import '../core/optimize.dart';
import '../core/scoring.dart';
import '../models.dart';
import '../services/datasource.dart';
import '../state.dart';
import '../widgets/kline_painter.dart';

class StockDetailPage extends StatefulWidget {
  final String code;
  final String name;
  const StockDetailPage({super.key, required this.code, required this.name});

  @override
  State<StockDetailPage> createState() => _StockDetailPageState();
}

class _StockDetailPageState extends State<StockDetailPage> {
  bool _loading = true;
  String _error = '';
  List<Bar> _daily = <Bar>[];
  List<Bar> _min5 = <Bar>[];
  StockSnap? _snap;
  ScoreResult? _score;
  BacktestResult? _swing;
  BacktestResult? _intraday;
  Map<String, dynamic>? _optimize;
  Map<String, dynamic>? _mlPredict;
  Map<String, dynamic>? _mlWf;
  SubChart _sub = SubChart.volume;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final daily = await fetchDaily(widget.code, lmt: 250);
      final min5 = await fetchMin(widget.code, 5, lmt: 480);
      if (daily.length < 30) {
        setState(() {
          _loading = false;
          _error = '日线数据不足（${daily.length}根）';
        });
        return;
      }
      // 构造快照（用最新一根日线）
      final last = daily[daily.length - 1];
      final snap = StockSnap(
        code: widget.code,
        name: widget.name,
        price: last.close,
        chgPct: last.chgPct,
        open: last.open,
        high: last.high,
        low: last.low,
        volume: last.volume,
        amount: last.amount,
        turnover: last.turnover ?? 0,
        pe: 0,
        pb: 0,
        totalMv: 0,
        floatMv: 0,
        floatShares: 0,
      );
      final score = scoreStock(snap, daily, appState.scoreCfg);

      // 回测
      final swing = backtestDailySwing(daily, appState.scoreCfg, appState.dailyParams);
      BacktestResult? intraday;
      Map<String, dynamic>? optimize;
      if (min5.length >= 60) {
        intraday = backtestIntradayT(min5, appState.intradayParams);
        optimize = autoOptimizeReport(daily, min5, appState.scoreCfg);
      }
      final mlPredict = predictLatest(daily);
      final mlWf = walkForward(daily);

      setState(() {
        _daily = daily;
        _min5 = min5;
        _snap = snap;
        _score = score;
        _swing = swing;
        _intraday = intraday;
        _optimize = optimize;
        _mlPredict = mlPredict;
        _mlWf = mlWf;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = '加载失败: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.name} ${widget.code}'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
              ? Center(child: Text(_error))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      _buildChartCard(),
                      const SizedBox(height: 12),
                      if (_score != null) _buildScoreCard(),
                      const SizedBox(height: 12),
                      if (_swing != null) _buildBacktestCard(),
                      const SizedBox(height: 12),
                      if (_optimize != null) _buildOptimizeCard(),
                      const SizedBox(height: 12),
                      if (_mlPredict != null) _buildMlCard(),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
    );
  }

  Widget _buildChartCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('日K线',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                const Spacer(),
                SegmentedButton<SubChart>(
                  segments: const [
                    ButtonSegment(value: SubChart.volume, label: Text('量', style: TextStyle(fontSize: 11))),
                    ButtonSegment(value: SubChart.rsi, label: Text('RSI', style: TextStyle(fontSize: 11))),
                    ButtonSegment(value: SubChart.macd, label: Text('MACD', style: TextStyle(fontSize: 11))),
                  ],
                  selected: {_sub},
                  onSelectionChanged: (s) => setState(() => _sub = s.first),
                  style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                ),
              ],
            ),
            const SizedBox(height: 4),
            KlineChart(bars: _daily, sub: _sub),
            const SizedBox(height: 4),
            const Text('双指捏合缩放 · 红涨绿跌 · MA5橙 MA10蓝 MA20紫',
                style: TextStyle(fontSize: 10, color: Colors.black45)),
            if (_min5.length >= 60) ...[
              const Divider(),
              KlineChart(bars: _min5, sub: SubChart.macd, title: '5分钟K线（日内做T用）'),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildScoreCard() {
    final r = _score!;
    final m = r.metrics;
    final factorNames = {
      'amplitude': '振幅',
      'liquidity': '流动性',
      'volatility': '波动率',
      'trend': '趋势',
      'oscillation': '震荡',
      'volume': '量能',
      'character': '股性',
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('做T适配度评分',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                const SizedBox(width: 12),
                Text('${r.score} 分',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: r.score >= 80
                            ? Colors.red.shade700
                            : Colors.orange.shade800)),
                const SizedBox(width: 12),
                if (!r.pass)
                  Text('未通过: ${r.reason}',
                      style: TextStyle(color: Colors.red.shade600)),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: r.factors.entries
                  .map((e) => Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text(
                            '${factorNames[e.key] ?? e.key}: ${e.value}',
                            style: const TextStyle(fontSize: 12)),
                        backgroundColor: e.value >= 80
                            ? Colors.red.shade50
                            : (e.value >= 60
                                ? Colors.orange.shade50
                                : Colors.grey.shade100),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                _kv('近10日均振幅', '${m['ampAvg']}%'),
                _kv('均换手', '${m['toAvg']}%'),
                _kv('均成交额', '${m['amtAvg']}亿'),
                _kv('ATR%', '${m['atrPct']}'),
                _kv('RSI14', '${m['rsi']}'),
                _kv('ADX14', '${m['adx']}'),
                _kv('量比', '${m['volRatio']}'),
                _kv('布林位置', '${m['bollPos']}'),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: Colors.blueGrey.shade50,
                  borderRadius: BorderRadius.circular(6)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('做T方向: ${r.directionLabelText ?? '-'}',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  if (r.signal != null) ...[
                    const SizedBox(height: 4),
                    Text(
                        '信号: ${signalLabel(r.signal!.action).$1} (买${r.signal!.buy} 卖${r.signal!.sell} 净${r.signal!.strength})',
                        style: const TextStyle(fontSize: 13)),
                    ...r.signal!.reasons
                        .map((t) => Text('· $t',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.black87))),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Text('$k $v',
      style: const TextStyle(fontSize: 12, color: Colors.black87));

  Widget _buildBacktestCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('双策略回测',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('策略一：日线波段T（信号阈值${appState.dailyParams.signalThreshold}，止损${(appState.dailyParams.stopLoss * 100).toStringAsFixed(0)}%，止盈${(appState.dailyParams.takeProfit * 100).toStringAsFixed(0)}%）',
                style: const TextStyle(fontSize: 12, color: Colors.black54)),
            _metricsRow(_swing!.metrics),
            if (_intraday != null) ...[
              const Divider(height: 20),
              Text('策略二：日内做T（买偏离${(appState.intradayParams.buyBand * 100).toStringAsFixed(1)}%，卖偏离${(appState.intradayParams.sellBand * 100).toStringAsFixed(1)}%，单日≤${appState.intradayParams.maxTPerDay}次）',
                  style:
                      const TextStyle(fontSize: 12, color: Colors.black54)),
              _metricsRow(_intraday!.metrics),
            ] else
              const Text('（5分钟数据不足，跳过日内策略）',
                  style: TextStyle(fontSize: 11, color: Colors.black38)),
          ],
        ),
      ),
    );
  }

  Widget _metricsRow(BacktestMetrics m) {
    Widget cell(String label, String value, Color? color) => Expanded(
            child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.bold, color: color)),
            Text(label,
                style: const TextStyle(fontSize: 10, color: Colors.black54)),
          ],
        ));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          cell('总收益', '${m.totalReturn}%',
              m.totalReturn >= 0 ? Colors.red.shade700 : Colors.green.shade700),
          cell('年化', '${m.annual}%', null),
          cell('胜率', '${m.winRate}%', null),
          cell('交易数', '${m.trades}', null),
          cell('最大回撤', '${m.maxDrawdown}%', Colors.green.shade700),
          cell('夏普', '${m.sharpe}', null),
          cell('盈亏比', '${m.profitFactor}', null),
        ],
      ),
    );
  }

  Widget _buildOptimizeCard() {
    final o = _optimize!;
    final recommend =
        (o['recommend'] as Map<String, dynamic>?) ?? <String, dynamic>{};

    Widget wfBlock(String title, Map<String, dynamic> wf, String recommendKey) {
      if (wf['ok'] != true) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text('$title: 跳过（${wf['reason'] ?? '数据不足'}）',
              style: const TextStyle(fontSize: 11, color: Colors.black38)),
        );
      }
      final best = (wf['bestParams'] as Map<String, dynamic>?) ?? {};
      final verdict = (wf['verdict'] as Map<String, String>?) ?? {};
      final trainPerf = ((wf['train'] as Map?)?['perf'] as BacktestMetrics?);
      final testPerf = ((wf['test'] as Map?)?['perf'] as BacktestMetrics?);
      final rec = (recommend[recommendKey] as Map<String, dynamic>?) ?? {};
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600)),
            Text('网格搜索最优参数: $best', style: const TextStyle(fontSize: 11)),
            if (trainPerf != null && testPerf != null)
              Text(
                  '训练期: 收益${trainPerf.totalReturn}% 夏普${trainPerf.sharpe} | 验证期: 收益${testPerf.totalReturn}% 夏普${testPerf.sharpe}',
                  style: const TextStyle(fontSize: 11, color: Colors.black54)),
            Text('过拟合判定: ${verdict['level'] ?? '-'}（${verdict['advice'] ?? ''}）',
                style: TextStyle(
                    fontSize: 11,
                    color: (verdict['level'] == '严重过拟合' ||
                            verdict['level'] == '样本外失效')
                        ? Colors.red.shade600
                        : Colors.green.shade700)),
            Text('APP推荐参数: $rec', style: const TextStyle(fontSize: 11)),
          ],
        ),
      );
    }

    final dailyWf = (o['daily'] as Map<String, dynamic>?) ?? {};
    final intradayWf = (o['intraday'] as Map<String, dynamic>?) ?? {};
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('参数自优化（网格搜索 + 滚动前推，目标: 夏普）',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            wfBlock('日内做T参数', intradayWf, 'intraday'),
            const Divider(height: 12),
            wfBlock('日线波段T参数', dailyWf, 'daily'),
            const SizedBox(height: 4),
            const Text('提示：验证期显著劣于训练期时应放弃该参数，回退保守默认（0.6%/0.8%偏离、止损5%止盈12%）',
                style: TextStyle(fontSize: 10, color: Colors.black45)),
          ],
        ),
      ),
    );
  }

  Widget _buildMlCard() {
    final pred = _mlPredict!;
    final wf = _mlWf;
    final prob = (pred['prob'] as num?)?.toDouble() ?? 0;
    final predUp = prob >= 0.5;
    final oos = wf != null && wf['ok'] == true
        ? (wf['outOfSample'] as Map<String, dynamic>?)
        : null;
    final sig = wf != null && wf['ok'] == true
        ? (wf['signalStrategy'] as Map<String, dynamic>?)
        : null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('ML神经网络对照（MLP 16隐单元，仅作对照非交易信号）',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              '最新预测: 次日上涨概率 ${(prob * 100).toStringAsFixed(1)}% → ${predUp ? '偏多' : '偏空'}',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: predUp ? Colors.red.shade700 : Colors.green.shade700),
            ),
            const SizedBox(height: 4),
            Text('全样本内准确率: ${pred['inSampleAcc'] ?? '-'}% | 训练样本数: ${pred['n'] ?? '-'} | 时点: ${pred['time'] ?? '-'}',
                style: const TextStyle(fontSize: 11, color: Colors.black54)),
            if (oos != null)
              Text(
                  '滚动前推样本外: 准确率${oos['acc']}% 精确率${oos['precision']}% (样本${oos['testSamples']})',
                  style: const TextStyle(fontSize: 11)),
            if (sig != null)
              Text(
                  '按预测信号模拟: ${sig['trades']}笔 胜率${sig['winRate']}% 累计${sig['totalReturn']}%',
                  style: const TextStyle(fontSize: 11)),
            const SizedBox(height: 4),
            const Text('ML与规则打分互相印证：两者分歧大时谨慎参与',
                style: TextStyle(fontSize: 10, color: Colors.black45)),
          ],
        ),
      ),
    );
  }
}
