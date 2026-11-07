import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pages/home_page.dart';
import 'pages/history_page.dart';
import 'pages/profile_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // 设置沉浸式透明状态栏
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));

  runApp(const ChaojiHuiwanApp());
}

class ChaojiHuiwanApp extends StatelessWidget {
  const ChaojiHuiwanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '钞机汇玩',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF127C44),
          primary: const Color(0xFF127C44),
        ),
        scaffoldBackgroundColor: const Color(0xFFF7FAF8),
        useMaterial3: true,
        fontFamily: 'sans-serif',
      ),
      home: const MainNavigationScreen(),
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomePage(onTabChange: (idx) => setState(() => _currentIndex = idx)),
      const HistoryPage(),
      const ProfilePage(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: pages,
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFF0F4F1), width: 1)),
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          backgroundColor: Colors.white,
          indicatorColor: const Color(0xFFE8F3EC),
          elevation: 0,
          onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded, color: Color(0xFF127C44)),
              label: '提取',
            ),
            NavigationDestination(
              icon: Icon(Icons.history_outlined),
              selectedIcon: Icon(Icons.history_rounded, color: Color(0xFF127C44)),
              label: '记录',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(Icons.person_rounded, color: Color(0xFF127C44)),
              label: '我的',
            ),
          ],
        ),
      ),
    );
  }
}
