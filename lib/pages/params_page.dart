/// params_page.dart — 参数设置页（预筛阈值 / 因子权重 / 回测参数）
library;

import 'package:flutter/material.dart';

import '../core/backtest.dart';
import '../core/scoring.dart';
import '../state.dart';

class ParamsPage extends StatefulWidget {
  const ParamsPage({super.key});

  @override
  State<ParamsPage> createState() => _ParamsPageState();
}

class _ParamsPageState extends State<ParamsPage> {
  @override
  Widget build(BuildContext context) {
    final st = appState;
    final cfg = st.scoreCfg;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _section('一、快照预筛阈值（扫描第一级漏斗）'),
        _numField('最低价格(元)', st.preMinPrice, (v) => st.update((s) => s.preMinPrice = v)),
        _numField('最高价格(元)', st.preMaxPrice, (v) => st.update((s) => s.preMaxPrice = v)),
        _numField('最低今日成交额(亿)', st.preMinAmount / 1e8,
            (v) => st.update((s) => s.preMinAmount = v * 1e8)),
        _numField('最低换手(%)', st.preMinTurnover, (v) => st.update((s) => s.preMinTurnover = v)),
        _numField('最高换手(%)', st.preMaxTurnover, (v) => st.update((s) => s.preMaxTurnover = v)),
        _numField('最低振幅(%)', st.preMinAmplitude,
            (v) => st.update((s) => s.preMinAmplitude = v)),
        SwitchListTile(
          dense: true,
          title: const Text('排除ST/退市', style: TextStyle(fontSize: 13)),
          value: st.preExcludeST,
          onChanged: (v) => st.update((s) => s.preExcludeST = v),
        ),
        SwitchListTile(
          dense: true,
          title: const Text('排除北交所(4/8/92开头)', style: TextStyle(fontSize: 13)),
          value: st.preExcludeBJ,
          onChanged: (v) => st.update((s) => s.preExcludeBJ = v),
        ),
        _section('二、七因子权重（合计100）'),
        ...cfg.weights.keys.map((k) => _intSlider(
            '${_factorName(k)}($k)',
            cfg.weights[k]!,
            0,
            40,
            (v) => st.update((s) => s.scoreCfg.weights[k] = v))),
        _section('三、评分区间参数'),
        _numField('振幅理想区间(%) [下,满起,满止,上]', cfg.ampIdeal[0], (v) {
          cfg.ampIdeal[0] = v;
        }, hint: '${cfg.ampIdeal.join(' / ')}'),
        _numField('换手理想区间(%)', cfg.turnoverIdeal[0], (v) {
          cfg.turnoverIdeal[0] = v;
        }, hint: '${cfg.turnoverIdeal.join(' / ')}'),
        _numField('满分成交额(亿)', cfg.amountFull / 1e8,
            (v) => cfg.amountFull = v * 1e8),
        _numField('ADX趋势阈值', cfg.adxTrend.toDouble(),
            (v) => cfg.adxTrend = v.round()),
        _numField('RSI超卖线', cfg.rsiOversold.toDouble(),
            (v) => cfg.rsiOversold = v.round()),
        _numField('RSI超买线', cfg.rsiOverbought.toDouble(),
            (v) => cfg.rsiOverbought = v.round()),
        _section('四、日线波段T回测参数'),
        _numField('信号阈值(|net|≥)', st.dailyParams.signalThreshold.toDouble(),
            (v) => st.update((s) => s.dailyParams.signalThreshold = v.round())),
        _numField('止损(%)', st.dailyParams.stopLoss * 100,
            (v) => st.update((s) => s.dailyParams.stopLoss = v / 100)),
        _numField('止盈(%)', st.dailyParams.takeProfit * 100,
            (v) => st.update((s) => s.dailyParams.takeProfit = v / 100)),
        SwitchListTile(
          dense: true,
          title: const Text('使用弱信号', style: TextStyle(fontSize: 13)),
          value: st.dailyParams.useWeak,
          onChanged: (v) => st.update((s) => s.dailyParams.useWeak = v),
        ),
        _section('五、日内做T回测参数'),
        _numField('买入偏离均价线(%)', st.intradayParams.buyBand * 100,
            (v) => st.update((s) => s.intradayParams.buyBand = v / 100)),
        _numField('卖出偏离均价线(%)', st.intradayParams.sellBand * 100,
            (v) => st.update((s) => s.intradayParams.sellBand = v / 100)),
        _numField('单次目标利润(%)', st.intradayParams.targetPct * 100,
            (v) => st.update((s) => s.intradayParams.targetPct = v / 100)),
        _numField('单次止损(%)', st.intradayParams.stopPct * 100,
            (v) => st.update((s) => s.intradayParams.stopPct = v / 100)),
        _numField('单日最多做T次数', st.intradayParams.maxTPerDay.toDouble(),
            (v) => st.update((s) => s.intradayParams.maxTPerDay = v.round())),
        _section('六、交易成本'),
        _numField('单次完整做T成本(%)', cfg.costRate * 100,
            (v) => st.update((s) => s.scoreCfg.costRate = v / 100)),
        const SizedBox(height: 8),
        Center(
          child: OutlinedButton.icon(
            icon: const Icon(Icons.restore),
            label: const Text('恢复默认参数'),
            onPressed: () {
              st.update((s) {
                s.scoreCfg = ScoreConfig();
                s.dailyParams = DailyParams();
                s.intradayParams = IntradayParams();
                s.preMinPrice = 3;
                s.preMaxPrice = 300;
                s.preMinAmount = 1.5e8;
                s.preMinTurnover = 2;
                s.preMaxTurnover = 25;
                s.preMinAmplitude = 2.5;
                s.preExcludeST = true;
                s.preExcludeBJ = true;
              });
              setState(() {});
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('已恢复默认参数')));
            },
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  String _factorName(String k) {
    const names = {
      'amplitude': '振幅',
      'liquidity': '流动性',
      'volatility': '波动率',
      'trend': '趋势',
      'oscillation': '震荡',
      'volume': '量能',
      'character': '股性',
    };
    return names[k] ?? k;
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 6),
        child: Text(title,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.blueGrey)),
      );

  Widget _numField(String label, double value, void Function(double) onChanged,
      {String? hint}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
              width: 210,
              child: Text(label, style: const TextStyle(fontSize: 12))),
          SizedBox(
            width: 110,
            child: TextFormField(
              initialValue: value == value.roundToDouble()
                  ? value.round().toString()
                  : value.toStringAsFixed(3),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 12),
              decoration: InputDecoration(
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                border: const OutlineInputBorder(),
                hintText: hint,
                hintStyle: const TextStyle(fontSize: 9),
              ),
              onFieldSubmitted: (v) {
                final n = double.tryParse(v);
                if (n != null) onChanged(n);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _intSlider(
      String label, int value, int min, int max, void Function(int) onChanged) {
    return Row(
      children: [
        SizedBox(width: 150, child: Text(label, style: const TextStyle(fontSize: 12))),
        Expanded(
          child: Slider(
            value: value.toDouble(),
            min: min.toDouble(),
            max: max.toDouble(),
            divisions: max - min,
            label: '$value',
            onChanged: (v) {
              setState(() => onChanged(v.round()));
            },
          ),
        ),
        SizedBox(width: 28, child: Text('$value', style: const TextStyle(fontSize: 12))),
      ],
    );
  }
}
