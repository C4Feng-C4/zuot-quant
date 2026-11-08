/// review_page.dart — 次日收盘复盘对比页（v2.0）
/// 选已保存的挂单日 → 拉实际K线对比 → 诊断偏差原因 → 参数完善建议 → 生成下一交易日挂单
library;

import 'package:flutter/material.dart';

import '../core/order_planner.dart';
import '../models.dart';
import '../services/datasource.dart';
import '../services/storage.dart';
import '../state.dart';

class ReviewPage extends StatefulWidget {
  const ReviewPage({super.key});

  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  List<String> _dates = <String>[];
  String? _selected;
  bool _running = false;
  Map<String, dynamic>? _report;
  List<OrderPlan> _plans = <OrderPlan>[];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final d = await listOrderDates();
    if (mounted) {
      setState(() {
        _dates = d;
        if (_selected == null && d.isNotEmpty) _selected = d.first;
      });
    }
  }

  Future<void> _runReview() async {
    final date = _selected;
    if (date == null) return;
    setState(() {
      _running = true;
      _report = null;
    });
    final plans = await loadOrders(date);
    if (plans == null || plans.isEmpty) {
      setState(() => _running = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('未找到 $date 的挂单记录')));
      return;
    }
    // 逐股拉日线，找 planDate 当天的K线
    final bars = <Bar>[];
    for (final p in plans) {
      try {
        final daily = await fetchDaily(p.code, lmt: 15, useCache: true);
        for (final b in daily) {
          final d = b.time.length >= 10 ? b.time.substring(0, 10) : b.time;
          if (d == date) {
            bars.add(b);
            break;
          }
        }
      } catch (_) {/* 跳过缺数据 */}
    }
    final report = reviewAll(plans, bars);
    // 序列化保存
    await saveReview(date, {
      'summary': report['summary'],
      'paramAdvice': report['paramAdvice'],
      'items': (report['items'] as List<ReviewItem>)
          .map((e) => e.toJson())
          .toList(),
    });
    await appendParamLog(date, List<String>.from(report['paramAdvice'] as List));

    setState(() {
      _plans = plans;
      _report = report;
      _running = false;
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('复盘完成并已保存：${(report['summary'] as Map)['total']}笔')));
  }

  String _nextTradingDayAfter(String date) {
    var d = DateTime.parse(date).add(const Duration(days: 1));
    while (d.weekday == 6 || d.weekday == 7) {
      d = d.add(const Duration(days: 1));
    }
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Future<void> _genNextDay() async {
    final results = appState.results;
    if (results.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('无扫描结果：请先「扫描」页重新扫描获取最新价，再到「挂单」页生成')));
      return;
    }
    final base = _selected ?? DateTime.now().toString().substring(0, 10);
    final next = _nextTradingDayAfter(base);
    final plans =
        generateOrderPlans(results, planDate: next, unitAmount: 10000);
    await saveOrders(next, plans);
    await _refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('已生成下一交易日 $next 挂单 ${plans.length} 笔（建议先重新扫描刷新现价）')));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: Colors.blueGrey.shade50,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              const Text('挂单日: ', style: TextStyle(fontSize: 13)),
              DropdownButton<String>(
                value: _selected,
                hint: const Text('选择', style: TextStyle(fontSize: 12)),
                underline: const SizedBox(),
                items: _dates
                    .map((d) => DropdownMenuItem(
                        value: d,
                        child: Text(d, style: const TextStyle(fontSize: 12))))
                    .toList(),
                onChanged: (v) => setState(() => _selected = v),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _running ? null : _runReview,
                icon: _running
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.fact_check, size: 18),
                label: Text(_running ? '复盘中…' : '执行复盘(对比实际)'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _genNextDay,
                icon: const Icon(Icons.skip_next, size: 16),
                label: const Text('生成下一交易日挂单'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _report == null
              ? const Center(
                  child: Text('选择挂单日 → 执行复盘：自动对比实际K线，检查推断错误原因',
                      style: TextStyle(color: Colors.black45)))
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    _summaryCard(),
                    const SizedBox(height: 10),
                    _adviceCard(),
                    const SizedBox(height: 10),
                    const Text('逐笔明细',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    ...(_report!['items'] as List<ReviewItem>)
                        .map((e) => _itemCard(e)),
                    const SizedBox(height: 24),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _summaryCard() {
    final s = _report!['summary'] as Map<String, dynamic>;
    Widget cell(String label, String value, Color? color) => Expanded(
            child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: 17, fontWeight: FontWeight.bold, color: color)),
            Text(label,
                style: const TextStyle(fontSize: 10, color: Colors.black54)),
          ],
        ));
    final pnl = (s['totalPnlPct'] as num).toDouble();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                cell('计划笔数', '${s['total']}', null),
                cell('成交', '${s['filled']}', null),
                cell('止盈', '${s['wins']}', Colors.red.shade700),
                cell('止损', '${s['losses']}', Colors.green.shade700),
                cell('未成交', '${s['noFill']}', Colors.black54),
                cell('胜率', '${s['winRate']}%', null),
                cell('合计收益', '$pnl%',
                    pnl >= 0 ? Colors.red.shade700 : Colors.green.shade700),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _adviceCard() {
    final advice = List<String>.from(_report!['paramAdvice'] as List);
    return Card(
      color: Colors.amber.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('推断偏差诊断 → 参数完善建议',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            ...advice.map((a) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text('· $a', style: const TextStyle(fontSize: 12)),
                )),
          ],
        ),
      ),
    );
  }

  Widget _itemCard(ReviewItem e) {
    final p = e.plan;
    final statusColor = e.status == '止盈'
        ? Colors.red.shade700
        : (e.status == '止损'
            ? Colors.green.shade700
            : (e.status == '未成交' ? Colors.black45 : Colors.orange.shade800));
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('${p.name} ${p.code}',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                Text(p.direction,
                    style: const TextStyle(fontSize: 11, color: Colors.black54)),
                const Spacer(),
                Text(e.status,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: statusColor)),
                const SizedBox(width: 8),
                Text('${e.pnlPct}%',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: statusColor)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
                '挂单: 买${p.buyPrice.toStringAsFixed(2)} / 卖${p.sellPrice.toStringAsFixed(2)} / 止损${p.stopPrice.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 11, color: Colors.black54)),
            Text('诊断: ${e.diagnosis}', style: const TextStyle(fontSize: 11)),
            Text('建议: ${e.advice}',
                style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade700)),
          ],
        ),
      ),
    );
  }
}
