/// main.dart — 做T量化选股系统 APP 入口（v2.0）
/// 底部导航：扫描 / 挂单 / 复盘 / 参数 / 方法论
library;

import 'package:flutter/material.dart';

import 'pages/scan_page.dart';
import 'pages/orders_page.dart';
import 'pages/review_page.dart';
import 'pages/params_page.dart';
import 'pages/methodology_page.dart';

void main() {
  runApp(const ZuotApp());
}

class ZuotApp extends StatelessWidget {
  const ZuotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '做T量化选股',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF7F8FA),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1565C0),
          foregroundColor: Colors.white,
          titleTextStyle: TextStyle(
              fontSize: 17, fontWeight: FontWeight.w600, color: Colors.white),
        ),
      ),
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _idx = 0;

  static const _titles = [
    '全A股做T扫描',
    '第二日做T挂单详情',
    '收盘复盘对比',
    '参数设置',
    '方法论',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_idx]),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 12),
            child: Center(
                child: Text('v2.0', style: TextStyle(fontSize: 12))),
          ),
        ],
      ),
      body: IndexedStack(
        index: _idx,
        children: const [
          ScanPage(),
          OrdersPage(),
          ReviewPage(),
          ParamsPage(),
          MethodologyPage(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _idx,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFF1565C0),
        unselectedItemColor: Colors.black45,
        onTap: (i) => setState(() => _idx = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.radar), label: '扫描'),
          BottomNavigationBarItem(icon: Icon(Icons.upcoming), label: '挂单'),
          BottomNavigationBarItem(icon: Icon(Icons.fact_check), label: '复盘'),
          BottomNavigationBarItem(icon: Icon(Icons.tune), label: '参数'),
          BottomNavigationBarItem(icon: Icon(Icons.menu_book), label: '方法论'),
        ],
      ),
    );
  }
}
