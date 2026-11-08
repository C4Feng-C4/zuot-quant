/// storage.dart — 挂单推断/复盘数据持久化（JSON 文件，应用文档目录）
///
/// 目录结构（应用文档目录/zuoT_records/）：
///   orders_YYYY-MM-DD.json   —— 当日生成的次日挂单计划（数据保留）
///   reviews_YYYY-MM-DD.json  —— 对该计划的复盘结果
///   param_log.json           —— 参数完善日志（复盘建议累积）
library;

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../core/order_planner.dart';

Future<Directory> _recordsDir() async {
  final base = await getApplicationDocumentsDirectory();
  final dir = Directory('${base.path}/zuoT_records');
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir;
}

/// 保存某日挂单计划（覆盖写）
Future<void> saveOrders(String planDate, List<OrderPlan> plans) async {
  final dir = await _recordsDir();
  final f = File('${dir.path}/orders_$planDate.json');
  await f.writeAsString(json.encode({
    'planDate': planDate,
    'savedAt': DateTime.now().toIso8601String(),
    'plans': plans.map((p) => p.toJson()).toList(),
  }));
}

/// 读取某日挂单计划
Future<List<OrderPlan>?> loadOrders(String planDate) async {
  try {
    final dir = await _recordsDir();
    final f = File('${dir.path}/orders_$planDate.json');
    if (!await f.exists()) return null;
    final j = json.decode(await f.readAsString()) as Map<String, dynamic>;
    return (j['plans'] as List)
        .map((e) => OrderPlan.fromJson(e as Map<String, dynamic>))
        .toList();
  } catch (_) {
    return null;
  }
}

/// 保存复盘结果
Future<void> saveReview(String planDate, Map<String, dynamic> review) async {
  final dir = await _recordsDir();
  final f = File('${dir.path}/reviews_$planDate.json');
  // ReviewItem 不可直接json化，由调用方传入已序列化的map
  await f.writeAsString(json.encode({
    'planDate': planDate,
    'reviewedAt': DateTime.now().toIso8601String(),
    ...review,
  }));
}

Future<Map<String, dynamic>?> loadReview(String planDate) async {
  try {
    final dir = await _recordsDir();
    final f = File('${dir.path}/reviews_$planDate.json');
    if (!await f.exists()) return null;
    return json.decode(await f.readAsString()) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
}

/// 追加参数完善日志
Future<void> appendParamLog(String planDate, List<String> advice) async {
  final dir = await _recordsDir();
  final f = File('${dir.path}/param_log.json');
  List<dynamic> log = [];
  if (await f.exists()) {
    try {
      log = json.decode(await f.readAsString()) as List<dynamic>;
    } catch (_) {
      log = [];
    }
  }
  log.add({
    'planDate': planDate,
    'at': DateTime.now().toIso8601String(),
    'advice': advice,
  });
  await f.writeAsString(json.encode(log));
}

Future<List<dynamic>> loadParamLog() async {
  try {
    final dir = await _recordsDir();
    final f = File('${dir.path}/param_log.json');
    if (!await f.exists()) return [];
    return json.decode(await f.readAsString()) as List<dynamic>;
  } catch (_) {
    return [];
  }
}

/// 列出所有已保存的挂单日期（倒序）
Future<List<String>> listOrderDates() async {
  try {
    final dir = await _recordsDir();
    final dates = <String>[];
    await for (final e in dir.list()) {
      final name = e.path.split(Platform.pathSeparator).last;
      if (name.startsWith('orders_') && name.endsWith('.json')) {
        dates.add(name.substring(7, name.length - 5));
      }
    }
    dates.sort((a, b) => b.compareTo(a)); // 倒序：最新在前
    return dates;
  } catch (_) {
    return [];
  }
}

/// 导出挂单详情为可读文本（便于辉哥发到聊天/打印核对）
String exportOrdersText(String planDate, List<OrderPlan> plans) {
  final sb = StringBuffer();
  sb.writeln('====== 第二日做T挂单详情 · $planDate ======');
  sb.writeln('生成时间: ${DateTime.now().toString().substring(0, 19)}');
  sb.writeln('算法: VWAP锚定 ±0.6%买/±0.8%卖 · 目标1.2% · 止损1.5% · 单日≤3笔');
  sb.writeln('');
  for (var i = 0; i < plans.length; i++) {
    final p = plans[i];
    sb.writeln('【${i + 1}】${p.name} ${p.code}  ${p.direction}  评分${p.score}  信号:${p.signalText}');
    sb.writeln('  现价(锚定) ${p.refPrice.toStringAsFixed(2)}');
    if (p.direction == '反T') {
      sb.writeln('  卖出挂 ${p.sellPrice.toStringAsFixed(2)} / 买回挂 ${p.buyPrice.toStringAsFixed(2)} / 回补止损 ${p.stopPrice.toStringAsFixed(2)}');
    } else {
      sb.writeln('  买入挂 ${p.buyPrice.toStringAsFixed(2)} / 卖出挂 ${p.sellPrice.toStringAsFixed(2)} / 止损 ${p.stopPrice.toStringAsFixed(2)}');
    }
    sb.writeln('  试单 ${p.shares}股 ≈ ${(p.amount / 10000).toStringAsFixed(2)}万');
    for (final n in p.notes) {
      sb.writeln('  · $n');
    }
    sb.writeln('');
  }
  sb.writeln('⚠️ 验证实验不构成投资建议；严格止损，单只首日只做1笔。');
  return sb.toString();
}
