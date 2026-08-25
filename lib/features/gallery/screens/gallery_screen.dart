import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:photo_application/features/gallery/providers/gallery_providers.dart';
import 'package:photo_application/features/gallery/screens/photo_browser_screen.dart';
import 'package:photo_application/features/gallery/services/photo_query_service.dart';
import 'package:photo_application/features/gallery/widgets/permission_gate.dart';
import 'package:photo_application/features/update/widgets/update_banner.dart';

/// "사진" 탭 — 기기의 모든 사진과 기본 필터들.
class GalleryScreen extends ConsumerStatefulWidget {
  const GalleryScreen({super.key});

  @override
  ConsumerState<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends ConsumerState<GalleryScreen> {
  PhotoScope _scope = PhotoScope.all;
  final _searchController = TextEditingController();
  String _keyword = '';
  bool _searching = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  static const _scopes = <PhotoScope, String>{
    PhotoScope.all: '전체',
    PhotoScope.unassigned: '미지정',
    PhotoScope.withNote: '메모',
    PhotoScope.tagged: '태그',
  };

  static const _emptyMessages = <PhotoScope, String>{
    PhotoScope.all: '아직 사진을 못 찾았습니다.\n아래로 당겨 다시 훑어보세요.',
    PhotoScope.unassigned: '모든 사진이 폴더에 들어가 있습니다.',
    PhotoScope.withNote: '메모를 붙인 사진이 아직 없습니다.\n사진을 열고 "메모 쓰기"를 눌러 보세요.',
    PhotoScope.tagged: '태그를 붙인 사진이 아직 없습니다.',
  };

  @override
  Widget build(BuildContext context) {
    final indexing = ref.watch(indexingProvider);
    final query = PhotoQuery(
      scope: _scope,
      keyword: _keyword.isEmpty ? null : _keyword,
    );

    return PermissionGate(
      child: PhotoBrowserScreen(
        key: ValueKey('$_scope|$_keyword'),
        title: '사진',
        showBack: false,
        query: query,
        emptyMessage: _keyword.isNotEmpty
            ? '"$_keyword" 와 맞는 사진이 없습니다.'
            : (_emptyMessages[_scope] ?? '사진이 없습니다.'),
        actions: [
          IconButton(
            icon: Icon(_searching ? Icons.search_off : Icons.search),
            tooltip: '파일명·메모 검색',
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching) {
                _searchController.clear();
                _keyword = '';
              }
            }),
          ),
          IconButton(
            icon: indexing.running
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            tooltip: '갤러리 다시 훑기',
            onPressed: indexing.running
                ? null
                : () => ref.read(indexingProvider.notifier).run(),
          ),
        ],
        header: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const UpdateBanner(),
            const LimitedAccessBanner(),
            if (indexing.running)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '사진을 훑는 중… ${indexing.done}/${indexing.total}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(value: indexing.progress),
                  ],
                ),
              ),
            if (_searching)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                    hintText: '파일명 또는 메모 내용',
                    prefixIcon: Icon(Icons.search),
                    isDense: true,
                  ),
                  onSubmitted: (value) =>
                      setState(() => _keyword = value.trim()),
                ),
              ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Row(
                children: [
                  for (final entry in _scopes.entries) ...[
                    ChoiceChip(
                      label: Text(entry.value),
                      selected: _scope == entry.key,
                      onSelected: (_) => setState(() => _scope = entry.key),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
