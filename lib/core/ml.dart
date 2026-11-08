/// ml.dart — 轻量神经网络方向预测（忠实移植自 lib/ml.js）
/// 纯 Dart 实现单隐层 MLP + 反向传播，walk-forward 样本外验证
/// 严格遵循：分类优于回归 / 标签阈值过滤 / 滚动归一化(禁全局标准化) / 固定种子 / 梯度裁剪
library;

import 'dart:math' as math;

import '../models.dart';
import 'indicators.dart';

double get nan => double.nan;
bool _finite(double x) => x.isFinite;

// ---- 可复现随机数（固定种子，与 JS mulberry32 位级一致）----
class Mulberry32 {
  int _seed;
  Mulberry32(this._seed);

  double next() {
    _seed = (_seed + 0x6D2B79F5) & 0xFFFFFFFF;
    int t = _seed;
    t = ((t ^ (t >>> 15)) * (t | 1)) & 0xFFFFFFFF;
    t = (t + ((t ^ (t >>> 7)) * (t | 61))) & 0xFFFFFFFF;
    t = (t ^ (t >>> 14)) & 0xFFFFFFFF;
    return t / 4294967296;
  }
}

// ---- 特征工程（无未来函数）----
const List<String> FEATURE_NAMES = ['ret1', 'ret5', 'ret20', 'maRatio', 'vol20', 'volRatio', 'rsi', 'macdHist', 'atrPct', 'kdjK'];

class Dataset {
  final List<List<double>> x;
  final List<int> y;
  final List<String> times;
  final List<double> rets;
  Dataset(this.x, this.y, this.times, this.rets);
}

Dataset buildDataset(List<Bar> daily, {double labelThreshold = 0.001}) {
  final indicators = computeAll(daily);
  final close = indicators.close;
  final volume = indicators.volume;
  final X = <List<double>>[];
  final y = <int>[];
  final times = <String>[];
  final rets = <double>[];
  const warm = 60; // 指标预热
  for (int i = warm; i < daily.length - 1; i++) {
    final c = close[i];
    if (!_finite(c) || c <= 0) continue;
    final ret1 = close[i - 1] != 0 ? c / close[i - 1] - 1 : 0;
    final ret5 = close[i - 5] != 0 ? c / close[i - 5] - 1 : 0;
    final ret20 = close[i - 20] != 0 ? c / close[i - 20] - 1 : 0;
    final maRatio = _finite(indicators.ma20[i]) ? c / indicators.ma20[i] - 1 : 0;
    final vol20 = _finite(indicators.vol20[i]) ? indicators.vol20[i] : 0;
    final volRatio = _finite(indicators.volRatio[i]) ? indicators.volRatio[i] - 1 : 0;
    final rsi = _finite(indicators.rsi14[i]) ? (indicators.rsi14[i] - 50) / 50 : 0;
    final macdHist = _finite(indicators.macd.hist[i]) ? indicators.macd.hist[i] / c : 0;
    final atrPct = _finite(indicators.atr14[i]) ? indicators.atr14[i] / c : 0;
    final kdjK = _finite(indicators.kdj.k[i]) ? (indicators.kdj.k[i] - 50) / 50 : 0;
    final feat = [ret1, ret5, ret20, maRatio, vol20, volRatio, rsi, macdHist, atrPct, kdjK]
        .map((v) => v.isFinite ? v : 0.0)
        .toList();
    // 标签：次日方向（阈值过滤）
    final nextRet = close[i + 1] / c - 1;
    int label;
    if (nextRet > labelThreshold) {
      label = 1;
    } else if (nextRet < -labelThreshold) {
      label = 0;
    } else {
      continue; // 模糊样本丢弃
    }
    X.add(feat);
    y.add(label);
    times.add(daily[i].time);
    rets.add(nextRet);
  }
  return Dataset(X, y, times, rets);
}

/// ---- 用训练集统计做 min-max 归一化，应用到任意集（无泄漏）----
class Scaler {
  final List<double> min;
  final List<double> max;
  Scaler(this.min, this.max);

  factory Scaler.fit(List<List<double>> X) {
    final n = X[0].length;
    final mn = List<double>.filled(n, double.infinity);
    final mx = List<double>.filled(n, -double.infinity);
    for (final row in X) {
      for (int j = 0; j < n; j++) {
        if (row[j] < mn[j]) mn[j] = row[j];
        if (row[j] > mx[j]) mx[j] = row[j];
      }
    }
    return Scaler(mn, mx);
  }

  List<double> apply(List<double> row) {
    return List<double>.generate(row.length, (j) {
      final r = max[j] - min[j];
      return r > 1e-9 ? (row[j] - min[j]) / r : 0.5;
    });
  }
}

// ---- 单隐层 MLP ----
class MLP {
  late List<List<double>> w1; // [inputSize][hiddenSize]
  late List<double> b1;
  late List<double> w2; // [hiddenSize]
  late double b2;
  final int hiddenSize;
  final int inputSize;

  MLP(this.inputSize, [this.hiddenSize = 16, int seed = 42]) {
    final rnd = Mulberry32(seed);
    w1 = List<List<double>>.generate(inputSize, (_) => <double>[]);
    b1 = List<double>.filled(hiddenSize, 0);
    for (int i = 0; i < inputSize; i++) {
      final row = <double>[];
      for (int h = 0; h < hiddenSize; h++) {
        row.add((rnd.next() * 2 - 1) * math.sqrt(2 / inputSize));
      }
      w1[i] = row;
    }
    w2 = List<double>.filled(hiddenSize, 0).map((_) => (rnd.next() * 2 - 1) * math.sqrt(2 / hiddenSize)).toList();
    b2 = 0;
  }

  static double sigmoid(double x) => 1 / (1 + math.exp(-math.max(-30, math.min(30, x))));

  (List<double>, double) forward(List<double> x) {
    final h = List<double>.filled(hiddenSize, 0);
    for (int j = 0; j < hiddenSize; j++) {
      double s = b1[j];
      for (int i = 0; i < inputSize; i++) {
        s += x[i] * w1[i][j];
      }
      h[j] = math.tanh(s);
    }
    double o = b2;
    for (int j = 0; j < hiddenSize; j++) {
      o += h[j] * w2[j];
    }
    return (h, sigmoid(o));
  }

  double predict(List<double> x) => forward(x).$2;

  void train(List<List<double>> X, List<int> y,
      {int epochs = 60, double lr = 0.05, double clip = 1.0, int seed = 42, bool classWeight = true}) {
    final rnd = Mulberry32(seed);
    final n = X.length;
    // 类别平衡权重（防止模型靠"永远预测一类"刷准确率）
    double w1c = 1, w0c = 1;
    if (classWeight) {
      final n1 = y.fold<int>(0, (a, b) => a + b);
      final n0 = n - n1;
      if (n1 > 0 && n0 > 0) {
        w1c = n / (2 * n1);
        w0c = n / (2 * n0);
      }
    }
    for (int ep = 0; ep < epochs; ep++) {
      // 随机梯度（mini-batch=1，shuffle）
      final idx = List<int>.generate(n, (i) => i);
      for (int i = n - 1; i > 0; i--) {
        final j = (rnd.next() * (i + 1)).floor();
        final tmp = idx[i];
        idx[i] = idx[j];
        idx[j] = tmp;
      }
      for (final k in idx) {
        final x = X[k];
        final t = y[k];
        final (h, p) = forward(x);
        // 输出层误差（加权 BCE 对 sigmoid 求导）：dL/do = w*(p - t)
        double dO = (t == 1 ? w1c : w0c) * (p - t);
        dO = math.max(-clip, math.min(clip, dO));
        // 梯度
        for (int j = 0; j < hiddenSize; j++) {
          final dW2 = dO * h[j];
          final dH = dO * w2[j] * (1 - h[j] * h[j]); // tanh'
          w2[j] -= lr * dW2;
          for (int i = 0; i < inputSize; i++) {
            w1[i][j] -= lr * dH * x[i];
          }
          b1[j] -= lr * dH;
        }
        b2 -= lr * dO;
      }
    }
  }
}

// ---- 评估 ----
class EvalResult {
  final double acc;
  final double precision;
  final double recall;
  final double f1;
  final int tp, tn, fp, fn;
  final List<double> probs;
  EvalResult(this.acc, this.precision, this.recall, this.f1, this.tp, this.tn, this.fp, this.fn, this.probs);
}

EvalResult evaluate(MLP model, List<List<double>> X, List<int> y) {
  int tp = 0, tn = 0, fp = 0, fn = 0;
  final probs = <double>[];
  for (int i = 0; i < X.length; i++) {
    final p = model.predict(X[i]);
    probs.add(p);
    final pred = p >= 0.5 ? 1 : 0;
    if (pred == 1 && y[i] == 1) {
      tp++;
    } else if (pred == 0 && y[i] == 0) {
      tn++;
    } else if (pred == 1 && y[i] == 0) {
      fp++;
    } else {
      fn++;
    }
  }
  final acc = (tp + tn) / X.length;
  final precision = tp + fp > 0 ? tp / (tp + fp) : 0;
  final recall = tp + fn > 0 ? tp / (tp + fn) : 0;
  return EvalResult(acc, precision, recall,
      precision + recall > 0 ? 2 * precision * recall / (precision + recall) : 0, tp, tn, fp, fn, probs);
}

double mlRound(double x, [int d = 4]) {
  final m = [1, 10, 100, 1000, 10000][d.clamp(0, 4)];
  return (x * m).roundToDouble() / m;
}

// ---- Walk-Forward 验证（滚动训练→样本外测试）----
Map<String, dynamic> walkForward(List<Bar> daily, {Map<String, dynamic>? cfg}) {
  final opt = <String, dynamic>{
    'trainLen': 200,
    'testLen': 40,
    'hiddenSize': 16,
    'epochs': 50,
    'lr': 0.05,
    'labelThreshold': 0.001,
    'seed': 42,
    'probThreshold': 0.55, // 预测概率>该值才视为买入信号
    ...?cfg,
  };
  final ds = buildDataset(daily, labelThreshold: (opt['labelThreshold'] as num).toDouble());
  final X = ds.x, y = ds.y, times = ds.times, rets = ds.rets;
  final trainLen = opt['trainLen'] as int;
  final testLen = opt['testLen'] as int;
  if (X.length < trainLen + testLen) {
    return {'ok': false, 'reason': '样本不足(需≥${trainLen + testLen}，实际${X.length})', 'n': X.length};
  }
  final allTestY = <int>[];
  final allTestProb = <double>[];
  final allTestRet = <double>[];
  final allTestTime = <String>[];
  final folds = <Map<String, dynamic>>[];
  int cursor = 0;
  while (cursor + trainLen + testLen <= X.length) {
    final trStart = cursor, trEnd = cursor + trainLen;
    final teStart = trEnd;
    final teEnd = math.min(trEnd + testLen, X.length);
    final Xtr = X.sublist(trStart, trEnd);
    final ytr = y.sublist(trStart, trEnd);
    final Xte = X.sublist(teStart, teEnd);
    final yte = y.sublist(teStart, teEnd);
    final scaler = Scaler.fit(Xtr);
    final XtrN = Xtr.map(scaler.apply).toList();
    final XteN = Xte.map(scaler.apply).toList();
    final model = MLP(XtrN[0].length, opt['hiddenSize'] as int, opt['seed'] as int);
    model.train(XtrN, ytr,
        epochs: opt['epochs'] as int, lr: (opt['lr'] as num).toDouble(), seed: opt['seed'] as int);
    final ev = evaluate(model, XteN, yte);
    folds.add({
      'trainEnd': times[trEnd - 1],
      'testStart': times[teStart],
      'testEnd': times[teEnd - 1],
      'acc': mlRound(ev.acc),
      'n': Xte.length,
    });
    allTestY.addAll(yte);
    allTestProb.addAll(ev.probs);
    allTestRet.addAll(rets.sublist(teStart, teEnd));
    allTestTime.addAll(times.sublist(teStart, teEnd));
    cursor += testLen; // 滚动
  }
  // 汇总样本外表现
  int tp = 0, tn = 0, fp = 0, fn = 0;
  for (int i = 0; i < allTestY.length; i++) {
    final pred = allTestProb[i] >= 0.5 ? 1 : 0;
    if (pred == 1 && allTestY[i] == 1) {
      tp++;
    } else if (pred == 0 && allTestY[i] == 0) {
      tn++;
    } else if (pred == 1 && allTestY[i] == 0) {
      fp++;
    } else {
      fn++;
    }
  }
  final acc = allTestY.isEmpty ? 0.0 : (tp + tn) / allTestY.length;
  final precision = tp + fp > 0 ? tp / (tp + fp) : 0;
  // 模拟"按预测信号交易"的样本外真实收益（概率>probThreshold 次日买入，持有1日）
  double stratRet = 0;
  int stratTrades = 0, stratWins = 0;
  for (int i = 0; i < allTestProb.length; i++) {
    if (allTestProb[i] >= (opt['probThreshold'] as num).toDouble()) {
      stratTrades++;
      final r = allTestRet[i] - 0.0016; // 真实次日收益 - 成本
      stratRet += r;
      if (r > 0) stratWins++;
    }
  }
  return {
    'ok': true,
    'n': X.length,
    'folds': folds,
    'outOfSample': {
      'acc': mlRound(acc),
      'precision': mlRound(precision),
      'recall': mlRound(tp + fn > 0 ? tp / (tp + fn) : 0),
      'tp': tp,
      'tn': tn,
      'fp': fp,
      'fn': fn,
      'testSamples': allTestY.length,
    },
    'signalStrategy': {
      'trades': stratTrades,
      'winRate': stratTrades != 0 ? mlRound(stratWins / stratTrades * 100, 1) : 0,
      'totalReturn': mlRound(stratRet * 100, 2),
      'avgReturn': stratTrades != 0 ? mlRound(stratRet / stratTrades * 100, 3) : 0,
    },
    'latestProb': allTestProb.isNotEmpty ? mlRound(allTestProb[allTestProb.length - 1]) : null,
    'opt': opt,
  };
}

// ---- 对单只股票给出"次日上涨概率"（用全部历史训练，预测最后一天）----
Map<String, dynamic> predictLatest(List<Bar> daily, {Map<String, dynamic>? cfg}) {
  final opt = <String, dynamic>{
    'hiddenSize': 16,
    'epochs': 60,
    'lr': 0.05,
    'labelThreshold': 0.001,
    'seed': 42,
    ...?cfg,
  };
  final ds = buildDataset(daily, labelThreshold: (opt['labelThreshold'] as num).toDouble());
  final X = ds.x, y = ds.y, times = ds.times;
  if (X.length < 80) return {'ok': false, 'reason': '样本不足'};
  final scaler = Scaler.fit(X);
  final Xn = X.map(scaler.apply).toList();
  final model = MLP(Xn[0].length, opt['hiddenSize'] as int, opt['seed'] as int);
  model.train(Xn, y, epochs: opt['epochs'] as int, lr: (opt['lr'] as num).toDouble(), seed: opt['seed'] as int);
  // 预测最后一天（用最后特征）
  final lastFeat = X[X.length - 1];
  final prob = model.predict(scaler.apply(lastFeat));
  final ev = evaluate(model, Xn, y);
  return {
    'ok': true,
    'prob': mlRound(prob),
    'inSampleAcc': mlRound(ev.acc),
    'time': times[times.length - 1],
    'n': X.length,
  };
}
