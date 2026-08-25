import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:photo_application/core/providers/core_providers.dart';
import 'package:photo_application/features/gallery/providers/photo_meta_providers.dart';
import 'package:photo_application/features/gallery/screens/photo_browser_screen.dart';
import 'package:photo_application/features/gallery/services/photo_query_service.dart';
import 'package:photo_application/features/tags/models/tag.dart';
import 'package:photo_application/features/tags/models/tag_group.dart';

/// "태그" 탭 — 분류별로 묶인 태그들과 각 태그가 달린 사진 수.
///
/// 태그를 누르면 그 태그가 달린 사진이 모두 모입니다. 조합 모드로 바꾸면
/// 여러 태그를 골라 **그 태그를 전부 가진** 사진만 좁혀 볼 수 있습니다.
///
/// 태그가 늘어나면 한 줄 목록으로는 찾기 어려워지므로 그 위에 분류를 둡니다.
/// 어느 분류에도 넣지 않은 태그는 맨 아래 "미분류"에 모입니다 — 폴더의
/// "미지정"과 같은 규칙입니다.
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

  // --- 태그 ---------------------------------------------------------------

  Future<void> _createTag({String groupId = TagGroup.none}) async {
    final name = await _promptName(context, title: '새 태그');
    if (name == null || name.isEmpty) return;
    await ref.read(tagServiceProvider).ensure(name, groupId: groupId);
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

  Future<void> _move(Tag tag, List<TagGroup> groups) async {
    final groupId = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('"${tag.name}" 을(를) 옮길 분류'),
        children: [
          for (final group in [...groups, null])
            _GroupChoice(
              label: group?.name ?? '미분류',
              value: group?.id ?? TagGroup.none,
              current: tag.groupId,
            ),
        ],
      ),
    );
    if (groupId == null || groupId == tag.groupId) return;
    await ref.read(tagServiceProvider).moveToGroup(tag.id, groupId);
    if (!mounted) return;
    ref.bumpDataRevision();
  }

  Future<void> _delete(Tag tag) async {
    final ok = await _confirm(
      title: '"${tag.name}" 태그를 지울까요?',
      message: '사진은 그대로 남고, 이 태그만 사진들에서 떨어집니다.',
    );
    if (!ok) return;
    await ref.read(tagServiceProvider).delete(tag.id);
    if (!mounted) return;
    setState(() => _picked.remove(tag.id));
    ref.bumpDataRevision();
  }

  // --- 분류 ---------------------------------------------------------------

  Future<void> _createGroup() async {
    final name = await _promptName(context, title: '새 분류');
    if (name == null || name.isEmpty) return;
    await ref.read(tagServiceProvider).ensureGroup(name);
    if (!mounted) return;
    ref.bumpDataRevision();
  }

  Future<void> _renameGroup(TagGroup group) async {
    final name =
        await _promptName(context, title: '분류 이름 바꾸기', initial: group.name);
    if (name == null || name.isEmpty) return;
    await ref.read(tagServiceProvider).renameGroup(group.id, name);
    if (!mounted) return;
    ref.bumpDataRevision();
  }

  Future<void> _deleteGroup(TagGroup group) async {
    final ok = await _confirm(
      title: '"${group.name}" 분류를 지울까요?',
      message: '안에 있던 태그는 지워지지 않고 미분류로 돌아갑니다.',
    );
    if (!ok) return;
    await ref.read(tagServiceProvider).deleteGroup(group.id);
    if (!mounted) return;
    ref.bumpDataRevision();
  }

  Future<bool> _confirm({
    required String title,
    required String message,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
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
    return ok ?? false;
  }

  // --- 화면 ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final tagsAsync = ref.watch(allTagsProvider);
    final groupsAsync = ref.watch(allTagGroupsProvider);

    final allTags = tagsAsync.valueOrNull ?? const <Tag>[];
    final groups = groupsAsync.valueOrNull ?? const <TagGroup>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('태그'),
        actions: [
          if (!_combineMode)
            IconButton(
              icon: const Icon(Icons.create_new_folder_outlined),
              tooltip: '분류 만들기',
              onPressed: _createGroup,
            ),
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
              onPressed:
                  _picked.isEmpty ? null : () => _openCombination(allTags),
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
          if (tags.isEmpty && groups.isEmpty) return const _EmptyTags();
          return _buildSections(tags, groups);
        },
      ),
    );
  }

  /// 분류별 묶음 → 미분류 순으로 한 줄짜리 목록을 만듭니다.
  ///
  /// 섹션마다 ListView 를 따로 두면 스크롤이 중첩되므로, 헤더와 태그를 같은
  /// 목록의 항목으로 평평하게 펼칩니다.
  Widget _buildSections(List<Tag> tags, List<TagGroup> groups) {
    final rows = <Widget>[];

    for (final group in groups) {
      final mine = tags.where((t) => t.groupId == group.id).toList();
      rows.add(_GroupHeader(
        name: group.name,
        count: mine.length,
        onSelected: _combineMode
            ? null
            : (value) {
                if (value == 'add') _createTag(groupId: group.id);
                if (value == 'rename') _renameGroup(group);
                if (value == 'delete') _deleteGroup(group);
              },
      ));
      if (mine.isEmpty) {
        rows.add(const _GroupEmpty());
      } else {
        rows.addAll(mine.map((tag) => _tagTile(tag, groups)));
      }
    }

    final loose = tags.where((t) => t.groupId.isEmpty).toList();
    if (loose.isNotEmpty) {
      // 분류를 하나도 안 만들었으면 굳이 "미분류" 머리글을 보일 필요가 없습니다.
      if (groups.isNotEmpty) {
        rows.add(_GroupHeader(name: '미분류', count: loose.length));
      }
      rows.addAll(loose.map((tag) => _tagTile(tag, groups)));
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: rows.length,
      itemBuilder: (context, index) => rows[index],
    );
  }

  Widget _tagTile(Tag tag, List<TagGroup> groups) {
    final picked = _picked.contains(tag.id);
    return ListTile(
      leading: _combineMode
          ? Icon(
              picked ? Icons.check_circle : Icons.radio_button_unchecked,
              color: picked ? Theme.of(context).colorScheme.primary : null,
            )
          : const Icon(Icons.sell_outlined),
      title: Text(tag.name),
      subtitle: Text('사진 ${tag.photoCount}장'),
      trailing: _combineMode
          ? null
          : PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'rename') _rename(tag);
                if (value == 'move') _move(tag, groups);
                if (value == 'delete') _delete(tag);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'rename', child: Text('이름 바꾸기')),
                PopupMenuItem(value: 'move', child: Text('분류 옮기기')),
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
  }
}

/// 분류 고르기 다이얼로그의 한 줄. 고르면 그 분류 id 로 닫힙니다.
class _GroupChoice extends StatelessWidget {
  const _GroupChoice({
    required this.label,
    required this.value,
    required this.current,
  });

  final String label;
  final String value;
  final String current;

  @override
  Widget build(BuildContext context) {
    final selected = value == current;
    return ListTile(
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        color: selected ? Theme.of(context).colorScheme.primary : null,
      ),
      title: Text(label),
      onTap: () => Navigator.of(context).pop(value),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.name, required this.count, this.onSelected});

  final String name;
  final int count;
  final ValueChanged<String>? onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      padding: EdgeInsets.fromLTRB(16, 10, onSelected == null ? 16 : 4, 10),
      child: Row(
        children: [
          Icon(Icons.folder_special_outlined,
              size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              name,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Text('태그 $count개', style: theme.textTheme.bodySmall),
          if (onSelected != null)
            PopupMenuButton<String>(
              onSelected: onSelected,
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'add', child: Text('이 분류에 태그 추가')),
                PopupMenuItem(value: 'rename', child: Text('이름 바꾸기')),
                PopupMenuItem(value: 'delete', child: Text('분류 지우기')),
              ],
            ),
        ],
      ),
    );
  }
}

class _GroupEmpty extends StatelessWidget {
  const _GroupEmpty();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(48, 12, 16, 12),
      child: Text(
        '아직 이 분류에 넣은 태그가 없습니다.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

class _EmptyTags extends StatelessWidget {
  const _EmptyTags();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Text(
          '아직 태그가 없습니다.\n\n'
          '사진을 열어 "태그"를 누르거나, 목록에서 사진을 길게 눌러 '
          '여러 장에 한 번에 달 수 있습니다.\n\n'
          '태그가 많아지면 위쪽 폴더 아이콘으로 분류를 만들어 묶어 두세요.',
          textAlign: TextAlign.center,
        ),
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
          onPressed: () => Navigator.of(context).pop(controller.text.trim()),
          child: const Text('확인'),
        ),
      ],
    ),
  );
}
