/// methodology_page.dart — 方法论说明页（与 Web 版方法论章节对齐）
library;

import 'package:flutter/material.dart';

class MethodologyPage extends StatelessWidget {
  const MethodologyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        _H('做T量化选股系统 · 方法论'),
        _P('本APP是Web版「做T量化选股系统」的忠实移植，参数与算法完全一致，可在手机上完成全A股扫描、个股评分、双策略回测、参数自优化与ML对照。'),
        _H('一、系统定位'),
        _P('做T（T+0回转交易）：在持有底仓的前提下，日内低买高卖或高卖低买，赚取振幅差价。本系统回答两个问题：\n1) 哪些股票适合做T？（多因子打分排名）\n2) 什么时候买卖？（信号 + 双策略回测验证）'),
        _H('二、两级漏斗筛选'),
        _P('第一级·快照预筛（不拉K线，秒级）：价格3-300元、今日成交额≥1.5亿、换手2-25%、振幅≥2.5%、剔除ST/退市/北交所。5500只 → 数百只。\n第二级·日线精评：对候选拉120根日K线，跑七因子打分，硬过滤（上市≥60日、日均成交额≥5000万、剔除僵尸股）后排名。'),
        _H('三、七因子评分模型（0-100，加权汇总）'),
        _P('振幅(20%)：近10日均振幅，3-5%起分，5-8%满分，>12%回落——振幅是做T的利润来源。\n流动性(20%)：日均成交额与换手，≥5亿满分，保证进得去出得来。\n波动率(15%)：ATR/价格，1.5-2.5%起分，2.5-6%满分。\n趋势(15%)：ADX强弱+均线排列——趋势太强不宜做T（单边），太弱无波幅。\n震荡(15%)：RSI/KDJ/布林位置，震荡市是做T最佳环境。\n量能(10%)：量比1.0-1.2起分，1.2-6满分。\n股性(5%)：价格弹性、高价股加分、过度投机降分。'),
        _H('四、做T方向判断'),
        _P('正T为主（先买后卖）：均线多头排列且站上5日线——回踩买入、冲高卖出。\n反T为主（先卖后买）：均线空头排列或跌破5日线——冲高先卖、回补接回。\n双向做T（震荡）：方向不明，双向操作。\n⚠️ 正T需先持有底仓；反T先卖须当日/次日补回，否则踏空。'),
        _H('五、双策略回测'),
        _P('策略一·日线波段T：按日线信号（RSI超卖+KDJ金叉+MACD金叉等净分≥3）买入，止损5%止盈12%，成本0.16%/次。适合没时间盯盘的投资者。\n策略二·日内做T：5分钟K线，价格低于VWAP均价线0.6%买入、高于0.8%卖出，目标1.2%、止损1.5%，单日≤3次。适合有时间盯盘的投资者。\n绩效指标：总收益/年化/胜率/最大回撤/夏普/盈亏比。'),
        _H('六、参数自优化（防过拟合）'),
        _P('网格搜索全参数组合 → 按夏普择优 → 滚动前推（70%训练/30%验证）→ 过拟合判定（稳健/轻度衰减/严重过拟合/样本外失效）。\n关键纪律：验证期显著劣于训练期时，放弃优化参数、回退保守默认。参数稳健比参数最优更重要。'),
        _H('七、ML神经网络对照'),
        _P('MLP（16隐单元）预测「次日上涨概率」，滚动前推测样本外准确率。⚠️ ML仅作规则打分的印证参考，不作为独立交易信号：两者分歧大时谨慎参与。'),
        _H('八、风险提示'),
        _P('1. 历史回测收益不代表未来表现。\n2. 做T有交易成本摩擦（佣金+印花税+滑点，单次约0.16%），振幅小于成本即亏损。\n3. T+0回转需底仓，满仓被套者慎用反T。\n4. 数据源为新浪/东财免费行情，可能延迟或缺失，以交易所行情为准。\n5. 本系统仅供学习研究，不构成投资建议。'),
        SizedBox(height: 40),
        Center(
            child: Text('做T量化选股系统 v1.0 · Flutter 移植版',
                style: TextStyle(fontSize: 11, color: Colors.black38))),
        SizedBox(height: 40),
      ],
    );
  }
}

class _H extends StatelessWidget {
  final String text;
  const _H(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 6),
        child: Text(text,
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Colors.blueGrey)),
      );
}

class _P extends StatelessWidget {
  final String text;
  const _P(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(fontSize: 13, height: 1.7, color: Colors.black87));
}
