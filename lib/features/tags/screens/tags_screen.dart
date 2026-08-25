import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:photo_application/core/providers/core_providers.dart';
import 'package:photo_application/features/gallery/providers/photo_meta_providers.dart';
import 'package:photo_application/features/gallery/screens/photo_browser_screen.dart';
import 'package:photo_application/features/gallery/services/photo_query_service.dart';
import 'package:photo_application/features/tags/models/tag.dart';

/// "태그" 탭 — 만든 태그들과 각 태그가 달린 사진 수.
///
/// 태그를 누르면 그 태그가 달린 사진이 모두 모입니다. 조합 모드로 바꾸면
/// 여러 태그를 골라 **그 태그를 전부 가진** 사진만 좁혀 볼 수 있습니다.
class TagsScreen extends ConsumerStatefulWidget {
  const TagsScreen({super.key});

  @override
  ConsumerState<TagsScreen> createState() => _TagsScreenState();
}

class _TagsScreenState extends ConsumerState<TagsScreen> {
  bool _combineMode = false;
  final Set<String> _picked = {};

  void _openTag(Tag tag) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PhotoBrowserScreen(
          title: '# ${tag.name}',
          query: PhotoQuery(scope: PhotoScope.tag, tagIds: [tag.id]),
          emptyMessage: '이 태그가 달린 사진이 없습니다.',
        ),
      ),
    );
  }

  void _openCombination(List<Tag> all) {
    final picked = all.where((t) => _picked.contains(t.id)).toList();
    if (picked.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PhotoBrowserScreen(
          title: picked.map((t) => '# ${t.name}').join('  '),
          subtitle: '태그 ${picked.length}개를 모두 가진 사진',
          query: PhotoQuery(
            scope: PhotoScope.tag,
            tagIds: picked.map((t) => t.id).toList(),
          ),
          emptyMessage: '고른 태그를 모두 가진 사진이 없습니다.',
        ),
      ),
    );
  }

  Future<void> _createTag() async {
    final name = await _promptName(context, title: '새 태그');
    if (name == null || name.isEmpty) return;
    await ref.read(tagServiceProvider).ensure(name);
    if (!mounted) return;
    ref.bumpDataRevision();
  }

  Future<void> _rename(Tag tag) async {
    final name =
        await _promptName(context, title: '태그 이름 바꾸기', initial: tag.name);
    if (name == null || name.isEmpty) return;
    await ref.read(tagServiceProvider).rename(tag.id, name);
    if (!mounted) return;
    ref.bumpDataRevision();
  }

  Future<void> _delete(Tag tag) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('"${tag.name}" 태그를 지울까요?'),
        content: const Text('사진은 그대로 남고, 이 태그만 사진들에서 떨어집니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('지우기'),
          ),
        ],
      ),
    );
    if (!(ok ?? false)) return;
    await ref.read(tagServiceProvider).delete(tag.id);
    if (!mounted) return;
    setState(() => _picked.remove(tag.id));
    ref.bumpDataRevision();
  }

  @override
  Widget build(BuildContext context) {
    final tagsAsync = ref.watch(allTagsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('태그'),
        actions: [
          IconButton(
            icon: Icon(_combineMode ? Icons.filter_alt_off : Icons.filter_alt),
            tooltip: _combineMode ? '조합 모드 끄기' : '여러 태그 조합하기',
            onPressed: () => setState(() {
              _combineMode = !_combineMode;
              _picked.clear();
            }),
          ),
        ],
      ),
      floatingActionButton: _combineMode
          ? FloatingActionButton.extended(
              onPressed: _picked.isEmpty
                  ? null
                  : () => _openCombination(tagsAsync.valueOrNull ?? const []),
              icon: const Icon(Icons.photo_library_outlined),
              label: Text('${_picked.length}개 태그로 보기'),
            )
          : FloatingActionButton(
              onPressed: _createTag,
              tooltip: '태그 만들기',
              child: const Icon(Icons.add),
            ),
      body: tagsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('$error')),
        data: (tags) {
          if (tags.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  '아직 태그가 없습니다.\n\n'
                  '사진을 열어 "태그"를 누르거나, 목록에서 사진을 길게 눌러 '
                  '여러 장에 한 번에 달 수 있습니다.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 88),
            itemCount: tags.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final tag = tags[index];
              final picked = _picked.contains(tag.id);
              return ListTile(
                leading: _combineMode
                    ? Icon(
                        picked
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        color: picked
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      )
                    : const Icon(Icons.sell_outlined),
                title: Text(tag.name),
                subtitle: Text('사진 ${tag.photoCount}장'),
                trailing: _combineMode
                    ? null
                    : PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'rename') _rename(tag);
                          if (value == 'delete') _delete(tag);
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'rename',
                            child: Text('이름 바꾸기'),
                          ),
                          PopupMenuItem(value: 'delete', child: Text('지우기')),
                        ],
                      ),
                onTap: () {
                  if (_combineMode) {
                    setState(() {
                      if (!_picked.remove(tag.id)) _picked.add(tag.id);
                    });
                  } else {
                    _openTag(tag);
                  }
                },
              );
            },
          );
        },
      ),
    );
  }
}

/// 이름 한 줄을 입력받는 공용 다이얼로그.
Future<String?> _promptName(
  BuildContext context, {
  required String title,
  String initial = '',
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(hintText: '이름'),
        onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(controller.text.trim()),
          child: const Text('확인'),
        ),
      ],
    ),
  );
}
