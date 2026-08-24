import 'package:flutter/material.dart';

import 'package:photo_application/features/folders/screens/folders_screen.dart';
import 'package:photo_application/features/gallery/screens/gallery_screen.dart';
import 'package:photo_application/features/settings/screens/settings_screen.dart';
import 'package:photo_application/features/tags/screens/tags_screen.dart';

/// 하단 탭 4개를 담는 껍데기.
///
/// [IndexedStack] 을 써서 탭을 오갈 때 각 화면의 스크롤 위치와 이미 읽어둔
/// 사진 페이지가 유지되도록 합니다.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  static const _tabs = <Widget>[
    GalleryScreen(),
    FoldersScreen(),
    TagsScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.photo_outlined),
            selectedIcon: Icon(Icons.photo),
            label: '사진',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder),
            label: '폴더',
          ),
          NavigationDestination(
            icon: Icon(Icons.sell_outlined),
            selectedIcon: Icon(Icons.sell),
            label: '태그',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '설정',
          ),
        ],
      ),
    );
  }
}
