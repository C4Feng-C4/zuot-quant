/// orders_page.dart — 第二日做T挂单详情页（v2.0）
/// 对全部筛选股按算法生成次日挂单 → 卡片列表 → 保存/导出
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/order_planner.dart';
import '../services/storage.dart';
import '../state.dart';

class OrdersPage extends StatefulWidget {
  const OrdersPage({super.key});

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  List<OrderPlan> _plans = <OrderPlan>[];
  String _planDate = '';
  bool _showAll = false;
  List<String> _savedDates = <String>[];
  final double _unitAmount = 10000;

  @override
  void initState() {
    super.initState();
    _refreshDates();
    if (appState.results.isNotEmpty && _plans.isEmpty) {
      _generate();
    }
  }

  Future<void> _refreshDates() async {
    final d = await listOrderDates();
    if (mounted) setState(() => _savedDates = d);
  }

  String _nextTradingDay() {
    // 简化：跳过周末（节假日需人工调整）
    var d = DateTime.now().add(const Duration(days: 1));
    while (d.weekday == 6 || d.weekday == 7) {
      d = d.add(const Duration(days: 1));
    }
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Future<void> _generate() async {
    final results = appState.results;
    if (results.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('请先在「扫描」页完成全A股扫描，再生成挂单')));
      return;
    }
    final date = _nextTradingDay();
    final plans = generateOrderPlans(results,
        planDate: date, unitAmount: _unitAmount);
    setState(() {
      _plans = plans;
      _planDate = date;
    });
    await saveOrders(date, plans);
    await _refreshDates();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('已生成 ${plans.length} 笔挂单计划（$date）并保存')));
  }

  Future<void> _loadDate(String date) async {
    final plans = await loadOrders(date);
    setState(() {
      _plans = plans ?? <OrderPlan>[];
      _planDate = date;
    });
  }

  Future<void> _export() async {
    if (_plans.isEmpty) return;
    final text = exportOrdersText(_planDate, _plans);
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('挂单详情文本已复制到剪贴板，可直接粘贴保存')));
  }

  @override
  Widget build(BuildContext context) {
    final visible = _showAll ? _plans : _plans.take(20).toList();
    return Column(
      children: [
        Container(
          color: Colors.blueGrey.shade50,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              ElevatedButton.icon(
                onPressed: _generate,
                icon: const Icon(Icons.upcoming, size: 18),
                label: const Text('生成明日挂单'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _plans.isEmpty ? null : _export,
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('复制详情'),
              ),
              const SizedBox(width: 8),
              if (_plans.isNotEmpty)
                Text(
                  '$_planDate · ${_plans.length}笔 · 试单1万/笔',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              const Spacer(),
              if (_savedDates.isNotEmpty)
                DropdownButton<String>(
                  value: _savedDates.contains(_planDate) ? _planDate : null,
                  hint: const Text('历史记录', style: TextStyle(fontSize: 12)),
                  underline: const SizedBox(),
                  items: _savedDates
                      .map((d) => DropdownMenuItem(
                          value: d,
                          child: Text(d, style: const TextStyle(fontSize: 12))))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) _loadDate(v);
                  },
                ),
            ],
          ),
        ),
        Expanded(
          child: _plans.isEmpty
              ? const Center(
                  child: Text('点击「生成明日挂单」，对全部筛选股生成算法挂单',
                      style: TextStyle(color: Colors.black45)))
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: visible.length + 1,
                  itemBuilder: (context, i) {
                    if (i == visible.length) {
                      return TextButton(
                        onPressed: () => setState(() => _showAll = !_showAll),
                        child: Text(_showAll
                            ? '收起'
                            : '显示全部（共${_plans.length}笔）'),
                      );
                    }
                    return _OrderCard(rank: i + 1, plan: visible[i]);
                  },
                ),
        ),
      ],
    );
  }
}

class _OrderCard extends StatelessWidget {
  final int rank;
  final OrderPlan plan;
  const _OrderCard({required this.rank, required this.plan});

  @override
  Widget build(BuildContext context) {
    final isFan = plan.direction == '反T';
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('#$rank',
                    style: const TextStyle(fontSize: 11, color: Colors.black45)),
                const SizedBox(width: 6),
                Text('${plan.name} ${plan.code}',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isFan
                        ? Colors.green.shade50
                        : (plan.direction == '正T'
                            ? Colors.red.shade50
                            : Colors.blueGrey.shade50),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(plan.direction,
                      style: TextStyle(
                          fontSize: 11,
                          color: isFan
                              ? Colors.green.shade800
                              : Colors.red.shade800)),
                ),
                const SizedBox(width: 6),
                Text('评分${plan.score}',
                    style: const TextStyle(fontSize: 11, color: Colors.black54)),
                const Spacer(),
                Text('信号:${plan.signalText}',
                    style: const TextStyle(fontSize: 11, color: Colors.black54)),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                _px('锚定价', plan.refPrice, Colors.black54),
                isFan
                    ? _px('卖出挂', plan.sellPrice, Colors.green.shade700)
                    : _px('买入挂', plan.buyPrice, Colors.red.shade700),
                isFan
                    ? _px('买回挂', plan.buyPrice, Colors.red.shade700)
                    : _px('卖出挂', plan.sellPrice, Colors.green.shade700),
                _px(isFan ? '回补止损' : '止损', plan.stopPrice, Colors.orange.shade800),
                const SizedBox(width: 8),
                Text('试单 ${plan.shares}股 ≈ ${(plan.amount / 10000).toStringAsFixed(2)}万',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w500)),
              ],
            ),
            const SizedBox(height: 4),
            ...plan.notes.map((n) => Text('· $n',
                style: const TextStyle(fontSize: 11, color: Colors.black54))),
          ],
        ),
      ),
    );
  }

  Widget _px(String label, double v, Color color) => Padding(
        padding: const EdgeInsets.only(right: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(fontSize: 10, color: Colors.black45)),
            Text(v.toStringAsFixed(2),
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      );
}
