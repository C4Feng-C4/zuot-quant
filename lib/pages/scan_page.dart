/// scan_page.dart — 全A股扫描页（预筛进度 + 做T适配度排行榜）
library;

import 'package:flutter/material.dart';

import '../core/scan.dart';
import '../models.dart';
import '../services/datasource.dart';
import '../state.dart';
import 'stock_detail_page.dart';

class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  @override
  Widget build(BuildContext context) {
    final st = appState;
    return Column(
      children: [
        // ---- 扫描控制条 ----
        Container(
          color: Colors.blueGrey.shade50,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              const Text('精评前N只: ', style: TextStyle(fontSize: 13)),
              SizedBox(
                width: 60,
                child: TextFormField(
                  initialValue: '${st.scanLimit}',
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontSize: 13),
                  decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                      border: OutlineInputBorder()),
                  onFieldSubmitted: (v) {
                    final n = int.tryParse(v);
                    if (n != null && n > 0) {
                      st.update((s) => s.scanLimit = n);
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: st.scanning ? null : _runScan,
                icon: st.scanning
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.radar, size: 18),
                label: Text(st.scanning ? '扫描中…' : '开始扫描'),
              ),
              const SizedBox(width: 8),
              if (st.scanReport != null && !st.scanning)
                Text(
                  '全市场${st.scanReport!['universe']} → 候选${st.scanReport!['candidates']} → 通过${st.scanReport!['scored']}，耗时${st.scanReport!['elapsed']}s',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              const Spacer(),
              if (st.scanning)
                Text(st.progressText,
                    style: const TextStyle(fontSize: 12, color: Colors.blue)),
            ],
          ),
        ),
        // ---- 结果表 ----
        Expanded(
          child: st.results.isEmpty
              ? Center(
                  child: Text(
                    st.scanning ? '正在扫描…' : '点击「开始扫描」全A股做T适配度排名',
                    style: const TextStyle(color: Colors.black45),
                  ),
                )
              : ListView.builder(
                  itemCount: st.results.length + 1,
                  itemBuilder: (context, i) {
                    if (i == 0) return const _TableHeader();
                    final r = st.results[i - 1];
                    return _ResultRow(rank: i, r: r);
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _runScan() async {
    final st = appState;
    st.update((s) {
      s.scanning = true;
      s.progressText = '正在获取全A股列表…';
      s.results = <ScoreResult>[];
      s.scanReport = null;
    });
    final report = await fullScan(
      limit: st.scanLimit,
      dailyLen: st.dailyLen,
      cfg: st.scoreCfg,
      preFilterCfg: st.preFilterCfg(),
      fetchList: fetchStockList,
      fetchDaily: fetchDaily,
      onProgress: (p) {
        if (p['stage'] == 'prefilter') {
          st.update((s) => s.progressText =
              '预筛: ${p['total']}只 → 候选${p['candidates']}只 → 精评${p['picked']}只');
        } else {
          st.update((s) => s.progressText =
              '精评 ${p['done']}/${p['total']}  ${p['code']} ${p['name']}');
        }
      },
    );
    st.update((s) {
      s.scanning = false;
      s.progressText = '';
      if (report['ok'] == true) {
        s.scanReport = report;
        s.results = List<ScoreResult>.from(report['results'] as List);
      }
    });
    if (!mounted) return;
    if (report['ok'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('扫描失败: ${report['reason']}')));
    }
  }
}

class _TableHeader extends StatelessWidget {
  const _TableHeader();

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
        fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87);
    return Container(
      color: Colors.grey.shade200,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      child: const Row(
        children: [
          SizedBox(width: 28, child: Text('#', style: style)),
          SizedBox(width: 56, child: Text('代码', style: style)),
          SizedBox(width: 64, child: Text('名称', style: style)),
          SizedBox(width: 40, child: Text('总分', style: style)),
          SizedBox(width: 44, child: Text('振幅%', style: style)),
          SizedBox(width: 44, child: Text('换手%', style: style)),
          SizedBox(width: 48, child: Text('额(亿)', style: style)),
          SizedBox(width: 36, child: Text('RSI', style: style)),
          SizedBox(width: 36, child: Text('ADX', style: style)),
          Expanded(child: Text('方向 / 信号', style: style)),
        ],
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  final int rank;
  final ScoreResult r;
  const _ResultRow({required this.rank, required this.r});

  @override
  Widget build(BuildContext context) {
    final m = r.metrics;
    final scoreColor = r.score >= 80
        ? Colors.red.shade700
        : (r.score >= 60 ? Colors.orange.shade800 : Colors.black87);
    return InkWell(
      onTap: () {
        Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => StockDetailPage(code: r.code, name: r.name)));
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 8),
        decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.grey.shade200))),
        child: Row(
          children: [
            SizedBox(
                width: 28,
                child: Text('$rank',
                    style: const TextStyle(fontSize: 11, color: Colors.black54))),
            SizedBox(width: 56, child: Text(r.code, style: const TextStyle(fontSize: 11))),
            SizedBox(
                width: 64,
                child: Text(r.name,
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis)),
            SizedBox(
                width: 40,
                child: Text('${r.score}',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: scoreColor))),
            SizedBox(
                width: 44,
                child: Text('${m['ampAvg'] ?? '-'}',
                    style: const TextStyle(fontSize: 11))),
            SizedBox(
                width: 44,
                child: Text('${m['toAvg'] ?? '-'}',
                    style: const TextStyle(fontSize: 11))),
            SizedBox(
                width: 48,
                child: Text('${m['amtAvg'] ?? '-'}',
                    style: const TextStyle(fontSize: 11))),
            SizedBox(
                width: 36,
                child: Text('${m['rsi'] ?? '-'}',
                    style: const TextStyle(fontSize: 11))),
            SizedBox(
                width: 36,
                child: Text('${m['adx'] ?? '-'}',
                    style: const TextStyle(fontSize: 11))),
            Expanded(
              child: Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                        color: r.direction == TDirection.positive
                            ? Colors.red.shade50
                            : (r.direction == TDirection.negative
                                ? Colors.green.shade50
                                : Colors.blueGrey.shade50),
                        borderRadius: BorderRadius.circular(3)),
                    child: Text(
                      r.directionLabelText == null
                          ? '-'
                          : r.directionLabelText!
                              .replaceAll('为主', '')
                              .replaceAll('(先买后卖)', '→先买')
                              .replaceAll('(先卖后买)', '→先卖')
                              .replaceAll('(震荡)', ''),
                      style: const TextStyle(fontSize: 10),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Builder(builder: (context) {
                      final sig = r.signal;
                      if (sig == null) return const SizedBox();
                      final label = signalLabel(sig.action).$1;
                      final color = sig.action == SignalAction.buy ||
                              sig.action == SignalAction.weakBuy
                          ? Colors.red.shade700
                          : (sig.action == SignalAction.sell ||
                                  sig.action == SignalAction.weakSell
                              ? Colors.green.shade700
                              : Colors.black45);
                      return Text('$label(${sig.strength})',
                          style: TextStyle(fontSize: 11, color: color),
                          overflow: TextOverflow.ellipsis);
                    }),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
