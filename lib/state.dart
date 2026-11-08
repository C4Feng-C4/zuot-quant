/// state.dart — 全局应用状态（扫描配置/结果/评分配置）
library;

import 'package:flutter/foundation.dart';

import 'core/scoring.dart';
import 'core/backtest.dart';
import 'models.dart';

class AppState extends ChangeNotifier {
  /// 扫描参数
  int scanLimit = 60; // 精评候选上限
  int dailyLen = 120;

  /// 快照预筛参数
  double preMinPrice = 3;
  double preMaxPrice = 300;
  double preMinAmount = 1.5e8;
  double preMinTurnover = 2;
  double preMaxTurnover = 25;
  double preMinAmplitude = 2.5;
  bool preExcludeST = true;
  bool preExcludeBJ = true;

  /// 评分配置
  ScoreConfig scoreCfg = ScoreConfig();

  /// 日线波段T参数
  DailyParams dailyParams = DailyParams();

  /// 日内做T参数
  IntradayParams intradayParams = IntradayParams();

  /// 扫描结果
  bool scanning = false;
  String progressText = '';
  Map<String, dynamic>? scanReport;
  List<ScoreResult> results = <ScoreResult>[];

  Map<String, dynamic> preFilterCfg() => {
        'minPrice': preMinPrice,
        'maxPrice': preMaxPrice,
        'minAmount': preMinAmount,
        'minTurnover': preMinTurnover,
        'maxTurnover': preMaxTurnover,
        'minAmplitude': preMinAmplitude,
        'excludeST': preExcludeST,
        'excludeBJ': preExcludeBJ,
      };

  void update(void Function(AppState) fn) {
    fn(this);
    notifyListeners();
  }
}

/// 单例访问
final AppState appState = AppState();
