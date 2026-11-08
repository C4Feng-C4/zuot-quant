# 做T量化选股系统 APP（Flutter 移植版 v2.0）

Web 版「做T量化选股系统」的 Android APP 忠实移植：全A股扫描 · 七因子打分 · 双策略回测 · 参数自优化 · ML对照。
**参数与算法与 Web 版完全一致**（详见《做T量化选股系统_参数交叉对比报告.html》）。

## 版本历史
- **v1.0**（已冻结：`做T量化选股系统_v1.0_FINAL.zip`）：扫描/详情/参数/方法论，核心算法移植
- **v2.0**（当前）：新增「第二日做T挂单详情」+「收盘复盘对比」闭环——
  对全部筛选股按算法推断次日挂单（VWAP±0.6%买/±0.8%卖、目标1.2%、止损1.5%、单日≤3笔），
  挂单数据持久化保留；次日收盘后一键复盘（自动对比实际K线 → 诊断推断错误原因 → 参数完善建议），
  并可直接生成下一交易日挂盘建议。

---

## 一、GitHub 云编译生成 APK（不用装任何环境）

> 只需一个 GitHub 账号，浏览器操作，约 8-15 分钟出 APK。

### 步骤 1：创建仓库
1. 打开 https://github.com/new
2. Repository name 填 `zuot-quant`（随意）
3. 选 **Public**（Private 需要 Actions 额度，免费版 Private 每月 2000 分钟也够）
4. **不要**勾选 "Add a README file"（保持空仓库）
5. 点 **Create repository**

### 步骤 2：上传本项目文件
**方法 A（网页上传，最简单）：**
1. 在新仓库页点 `uploading an existing file` 链接
2. 把解压后的 **文件夹内所有内容**（`lib/`、`pubspec.yaml`、`.github/`、`analysis_options.yaml`、`README.md`）拖进网页
   - ⚠️ 是拖「文件夹里的内容」，不是拖文件夹本身
   - ⚠️ `.github` 是隐藏文件夹，Windows 资源管理器需先「显示隐藏项目」
3. 点 **Commit changes**

**方法 B（git 命令行）：**
```bash
cd 做T量化选股APP
git init
git add .
git commit -m "做T量化选股系统 Flutter 版"
git branch -M main
git remote add origin https://github.com/你的用户名/zuot-quant.git
git push -u origin main
```

### 步骤 3：触发云编译
1. 打开仓库的 **Actions** 标签页
2. 若提示 "Workflows aren't being run on this repository"，点 **I understand my workflows, go ahead and enable them**
3. 左侧选 **Build Android APK** → 右侧 **Run workflow** → **Run workflow**
   （push 代码后也会自动触发）

### 步骤 4：下载 APK
1. 等待约 8-15 分钟，工作流变绿 ✅
2. 点进该次运行 → 底部 **Artifacts** → 下载 `zuot-quant-apk`
3. 解压得到 `做T量化选股-v2.0.apk`，传到手机安装即可
   - 手机需允许「安装未知来源应用」
   - ⚠️ Artifacts 保留 90 天，请及时下载

---

## 二、APP 功能

| 页面 | 功能 |
|---|---|
| **扫描** | 一键全A股两级漏斗扫描：快照预筛（5500→数百）→ 日线精评七因子打分 → 做T适配度排行榜，点任意股票进详情 |
| **个股详情** | 日K线（蜡烛+MA5/10/20，可切换量/RSI/MACD副图，双指缩放）+ 5分钟K线 + 七因子打分明细 + 做T方向/买卖信号 + 双策略回测 + 参数自优化 + ML对照 |
| **挂单** ⭐v2.0 | 第二日做T挂单详情：对全部筛选股生成算法挂单（买入挂/卖出挂/止损/试单股数金额/操作要点），支持保存、历史查看、一键复制导出 |
| **复盘** ⭐v2.0 | 收盘复盘对比：选挂单日 → 自动拉实际K线对比 → 逐笔诊断（止盈/止损/持仓/未成交+原因）→ 参数完善建议 → 一键生成下一交易日挂单 |
| **参数** | 预筛阈值、七因子权重、评分区间、双策略回测参数、交易成本，全部可调 |
| **方法论** | 系统完整方法论说明 |

## 三、数据源

- 主：新浪财经（全A股列表 + K线，免费无需 token）
- 备：东方财富 push2（自动回退）
- 限频：全局串行 + 150ms 间隔，避免被封 IP
- 行情有延迟，以交易所为准；本系统仅供学习研究，不构成投资建议

## 四、本地开发（可选）

```bash
flutter pub get
flutter run          # 连手机调试
flutter build apk    # 本地打 APK
```

## 五、项目结构

```
lib/
├── main.dart              # 入口 + 底部导航
├── models.dart            # Bar/StockSnap/ScoreResult/Trade 等数据模型
├── state.dart             # 全局状态（扫描/评分/回测参数）
├── core/                  # 核心算法（自 Web 版 lib/ 忠实移植）
│   ├── indicators.dart    # MA/RSI/MACD/KDJ/BOLL/ATR/ADX/量比/VWAP
│   ├── scoring.dart       # 硬过滤 + 七因子打分 + 方向 + 信号
│   ├── backtest.dart      # 策略一 日线波段T / 策略二 日内做T
│   ├── optimize.dart      # 网格搜索 + 滚动前推 + 过拟合判定
│   ├── ml.dart            # MLP 神经网络对照
│   └── scan.dart          # 两级漏斗扫描引擎
├── services/
│   └── datasource.dart    # 新浪/东财行情 + 限频 + 缓存
├── pages/                 # 扫描页 / 个股详情 / 参数页 / 方法论页
└── widgets/
    ├── core/order_planner.dart # 次日挂单推断+复盘诊断+参数建议
├── services/storage.dart  # 挂单/复盘数据持久化
├── pages/                 # 扫描/挂单/复盘/参数/方法论
└── widgets/kline_painter.dart # K线手绘（蜡烛+均线+量+RSI+MACD）
```

## 六、与 Web 版的参数一致性

评分权重（振幅20/流动性20/波动率15/趋势15/震荡15/量能10/股性5）、振幅理想区间[3,5,8,12]、换手[2,3,15,20]、
日内做T偏离0.6%/0.8%、目标1.2%/止损1.5%/单日≤3次、日线止损5%止盈12%、成本0.16%/次——
**全部与 Web 版一致，逐条复刻未做"优化"**。

---
*基于 Web 版做T量化选股系统（Node.js 零依赖）移植 · 2026-10*
