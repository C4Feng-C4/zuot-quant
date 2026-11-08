/// kline_painter.dart — K线图手绘（蜡烛 + 均线 + 成交量 + RSI + MACD）
/// 与 Web 版 Canvas 绘制逻辑对齐：上=K线主图，中=成交量，下=RSI/MACD
library;

import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/indicators.dart';
import '../models.dart';

enum SubChart { volume, rsi, macd }

class KlineChart extends StatefulWidget {
  final List<Bar> bars;
  final SubChart sub;
  final String title;

  const KlineChart({
    super.key,
    required this.bars,
    this.sub = SubChart.volume,
    this.title = '',
  });

  @override
  State<KlineChart> createState() => _KlineChartState();
}

class _KlineChartState extends State<KlineChart> {
  int _visible = 80; // 可见K线根数
  late IndicatorResult _ind;

  @override
  void initState() {
    super.initState();
    _ind = computeAll(widget.bars);
  }

  @override
  void didUpdateWidget(KlineChart old) {
    super.didUpdateWidget(old);
    if (!listEquals(old.bars, widget.bars)) {
      _ind = computeAll(widget.bars);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bars = widget.bars;
    if (bars.length < 2) {
      return const SizedBox(
          height: 300, child: Center(child: Text('K线数据不足')));
    }
    final visible = math.min(_visible, bars.length);
    final start = bars.length - visible;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.title.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 4),
            child: Text(widget.title,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        SizedBox(
          height: 320,
          child: GestureDetector(
            onScaleUpdate: (d) {
              setState(() {
                _visible =
                    (_visible / d.horizontalScale).clamp(20, bars.length).round();
              });
            },
            child: CustomPaint(
              size: const Size(double.infinity, 320),
              painter: _KlinePainter(
                bars: bars,
                ind: _ind,
                start: start,
                visible: visible,
                sub: widget.sub,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _KlinePainter extends CustomPainter {
  final List<Bar> bars;
  final IndicatorResult ind;
  final int start;
  final int visible;
  final SubChart sub;

  _KlinePainter({
    required this.bars,
    required this.ind,
    required this.start,
    required this.visible,
    required this.sub,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const mainRatio = 0.55; // 主图高度占比
    const subRatio = 0.20;
    final mainH = size.height * mainRatio;
    final subH = size.height * subRatio;
    final subTop = mainH + 8;
    final volTop = subTop;
    final indTop = subTop + subH + 4;

    final end = start + visible;
    final win = bars.sublist(start, end);

    // ---- 主图价格范围（含均线）----
    var lo = double.infinity, hi = -double.infinity;
    for (var i = start; i < end; i++) {
      lo = math.min(lo, bars[i].low);
      hi = math.max(hi, bars[i].high);
      for (final ma in [ind.ma5, ind.ma10, ind.ma20]) {
        final v = ma[i];
        if (v.isFinite) {
          lo = math.min(lo, v);
          hi = math.max(hi, v);
        }
      }
    }
    if (!lo.isFinite || !hi.isFinite || hi <= lo) {
      lo = 0;
      hi = 1;
    }
    final pad = (hi - lo) * 0.08;
    lo -= pad;
    hi += pad;

    double yPrice(double p) => mainH - (p - lo) / (hi - lo) * (mainH - 16) - 4;

    final cw = size.width / visible;
    final bodyW = math.max(1.0, cw * 0.62);

    // ---- 蜡烛 ----
    final upPaint = Paint()..color = const Color(0xFFE53935); // 涨红
    final downPaint = Paint()..color = const Color(0xFF43A047); // 跌绿
    final flatPaint = Paint()..color = Colors.grey;
    for (var i = 0; i < win.length; i++) {
      final b = win[i];
      final cx = i * cw + cw / 2;
      final isUp = b.close >= b.open;
      final p = isUp ? upPaint : (b.close == b.open ? flatPaint : downPaint);
      // 影线
      canvas.drawLine(Offset(cx, yPrice(b.high)), Offset(cx, yPrice(b.low)), p..strokeWidth = 1);
      // 实体
      final top = yPrice(math.max(b.open, b.close));
      final bot = yPrice(math.min(b.open, b.close));
      final rect =
          Rect.fromLTWH(cx - bodyW / 2, top, bodyW, math.max(1.0, bot - top));
      if (isUp) {
        // 空心（涨）
        canvas.drawRect(rect, Paint()..color = Colors.white..style = PaintingStyle.fill);
        canvas.drawRect(rect, Paint()..color = const Color(0xFFE53935)..style = PaintingStyle.stroke..strokeWidth = 1);
      } else {
        canvas.drawRect(rect, p);
      }
    }

    // ---- 均线 ----
    void drawMa(List<double> ma, Color color) {
      final path = Path();
      var started = false;
      for (var i = 0; i < win.length; i++) {
        final v = ma[start + i];
        if (!v.isFinite) continue;
        final x = i * cw + cw / 2;
        final y = yPrice(v);
        if (!started) {
          path.moveTo(x, y);
          started = true;
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(
          path,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2);
    }

    drawMa(ind.ma5, const Color(0xFFFF9800));
    drawMa(ind.ma10, const Color(0xFF2196F3));
    drawMa(ind.ma20, const Color(0xFF9C27B0));

    // ---- 副图1：成交量 ----
    var maxVol = 0.0;
    for (final b in win) {
      maxVol = math.max(maxVol, b.volume);
    }
    if (maxVol <= 0) maxVol = 1;
    for (var i = 0; i < win.length; i++) {
      final b = win[i];
      final cx = i * cw + cw / 2;
      final h = b.volume / maxVol * (subH - 10);
      final isUp = b.close >= b.open;
      canvas.drawRect(
          Rect.fromLTWH(cx - bodyW / 2, volTop + (subH - 10) - h, bodyW, h),
          Paint()
            ..color = (isUp ? const Color(0xFFE53935) : const Color(0xFF43A047))
                .withValues(alpha: 0.55));
    }

    // ---- 副图2：RSI 或 MACD ----
    if (sub == SubChart.rsi) {
      double yRsi(double v) =>
          indTop + (subH - 10) - (v / 100) * (subH - 10);
      // 30/70 参考线
      for (final level in [30.0, 70.0]) {
        canvas.drawLine(
            Offset(0, yRsi(level)),
            Offset(size.width, yRsi(level)),
            Paint()
              ..color = Colors.grey.withValues(alpha: 0.4)
              ..strokeWidth = 0.6
              ..strokeCap = StrokeCap.round);
      }
      final path = Path();
      var started = false;
      for (var i = 0; i < win.length; i++) {
        final v = ind.rsi14[start + i];
        if (!v.isFinite) continue;
        final x = i * cw + cw / 2;
        final y = yRsi(v.clamp(0, 100));
        if (!started) {
          path.moveTo(x, y);
          started = true;
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(
          path,
          Paint()
            ..color = const Color(0xFF2196F3)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.3);
    } else {
      // MACD
      var mMax = 0.0;
      for (var i = start; i < end; i++) {
        mMax = math.max(mMax,
            math.max(ind.macd.dif[i].abs(), math.max(ind.macd.dea[i].abs(), ind.macd.hist[i].abs())));
      }
      if (mMax <= 0) mMax = 1;
      double yMacd(double v) =>
          indTop + (subH - 10) / 2 - v / mMax * ((subH - 10) / 2 - 4);
      // 零轴
      canvas.drawLine(
          Offset(0, yMacd(0)),
          Offset(size.width, yMacd(0)),
          Paint()
            ..color = Colors.grey.withValues(alpha: 0.5)
            ..strokeWidth = 0.6);
      for (var i = 0; i < win.length; i++) {
        final idx = start + i;
        final cx = i * cw + cw / 2;
        final h = ind.macd.hist[idx];
        final paint = Paint()
          ..color = (h >= 0 ? const Color(0xFFE53935) : const Color(0xFF43A047))
              .withValues(alpha: 0.65);
        final y0 = yMacd(0);
        final y1 = yMacd(h);
        canvas.drawRect(
            Rect.fromLTWH(cx - bodyW / 2, math.min(y0, y1), bodyW, (y1 - y0).abs()),
            paint);
      }
      void drawMacdLine(List<double> arr, Color color) {
        final path = Path();
        var started = false;
        for (var i = 0; i < win.length; i++) {
          final v = arr[start + i];
          if (!v.isFinite) continue;
          final x = i * cw + cw / 2;
          final y = yMacd(v);
          if (!started) {
            path.moveTo(x, y);
            started = true;
          } else {
            path.lineTo(x, y);
          }
        }
        canvas.drawPath(
            path,
            Paint()
              ..color = color
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.2);
      }

      drawMacdLine(ind.macd.dif, const Color(0xFFFF9800));
      drawMacdLine(ind.macd.dea, const Color(0xFF2196F3));
    }

    // ---- 价格轴标签 ----
    final tp = TextPainter(
        textDirection: TextDirection.ltr, maxLines: 1, ellipsis: '…');
    for (final frac in [0.0, 0.5, 1.0]) {
      final price = hi - (hi - lo) * frac;
      tp.text = TextSpan(
          text: price.toStringAsFixed(2),
          style: const TextStyle(fontSize: 9, color: Colors.grey));
      tp.layout();
      tp.paint(canvas, Offset(size.width - tp.width - 2, mainH * frac + 2));
    }
    // 最新价标签
    final last = win[win.length - 1];
    final lastY = yPrice(last.close);
    final lastColor = last.close >= last.open ? const Color(0xFFE53935) : const Color(0xFF43A047);
    canvas.drawRect(Rect.fromLTWH(0, lastY - 7, 46, 14), Paint()..color = lastColor.withValues(alpha: 0.85));
    tp.text = TextSpan(
        text: last.close.toStringAsFixed(2),
        style: const TextStyle(fontSize: 9, color: Colors.white));
    tp.layout();
    tp.paint(canvas, Offset(2, lastY - 6));
  }

  @override
  bool shouldRepaint(_KlinePainter old) =>
      old.bars != bars || old.start != start || old.visible != visible || old.sub != sub;
}
