import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:photo_application/core/providers/core_providers.dart';
import 'package:photo_application/features/gallery/providers/photo_meta_providers.dart';
import 'package:photo_application/features/tags/models/tag.dart';
import 'package:photo_application/features/tags/models/tag_group.dart';

/// 사진들에 붙일 태그를 고르는 바텀시트.
///
/// 사진 한 장([photoKeys] 가 1개)이면 현재 달린 태그가 미리 체크되어 있고,
/// 여러 장이면 "고른 태그를 전부에 추가"하는 방식으로 동작합니다. 여러 장을
/// 다룰 때 체크 해제로 일괄 제거까지 하면 실수로 남의 태그를 날리기 쉬워서
/// 추가만 하도록 좁혔습니다.
///
/// 분류를 만들어 두었다면 위쪽 칩으로 분류를 골라 목록을 좁힐 수 있습니다.
/// 태그가 수십 개가 되면 전체 목록을 훑는 것보다 이쪽이 빠릅니다.
class TagPickerSheet extends ConsumerStatefulWidget {
  const TagPickerSheet({super.key, required this.photoKeys});

  final List<String> photoKeys;

  static Future<bool?> show(BuildContext context, List<String> photoKeys) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => TagPickerSheet(photoKeys: photoKeys),
    );
  }

  @override
  ConsumerState<TagPickerSheet> createState() => _TagPickerSheetState();
}

/// 분류 칩에서 "전체"를 나타내는 값. 실제 분류 id 와 겹치지 않도록 null 을
/// 씁니다 (빈 문자열은 이미 "미분류"라는 뜻이라 자리가 찼습니다).
const String? _allGroups = null;

class _TagPickerSheetState extends ConsumerState<TagPickerSheet> {
  final _newTag = TextEditingController();
  Set<String> _checked = {};
  Set<String> _initial = {};
  bool _ready = false;

  /// 지금 보고 있는 분류. null 이면 전체입니다.
  String? _filter = _allGroups;

  bool get _isSingle => widget.photoKeys.length == 1;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  @override
  void dispose() {
    _newTag.dispose();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    if (_isSingle) {
      final tags =
          await ref.read(tagServiceProvider).tagsOf(widget.photoKeys.first);
      if (!mounted) return;
      setState(() {
        _initial = tags.map((t) => t.id).toSet();
        _checked = {..._initial};
        _ready = true;
      });
    } else {
      setState(() => _ready = true);
    }
  }

  Future<void> _createTag() async {
    final name = _newTag.text.trim();
    if (name.isEmpty) return;
    // 특정 분류를 보고 있었다면 새 태그도 거기에 넣습니다. 방금 고른 서랍에
    // 넣으려던 참일 테니, 만들고 나서 다시 옮기게 하지 않습니다.
    final tag = await ref
        .read(tagServiceProvider)
        .ensure(name, groupId: _filter ?? TagGroup.none);
    if (!mounted) return;
    _newTag.clear();
    setState(() => _checked = {..._checked, tag.id});
    ref.bumpDataRevision();
  }

  Future<void> _save() async {
    final service = ref.read(tagServiceProvider);

    if (_isSingle) {
      final photoKey = widget.photoKeys.first;
      for (final id in _checked.difference(_initial)) {
        await service.attach(photoKey, id);
      }
      for (final id in _initial.difference(_checked)) {
        await service.detach(photoKey, id);
      }
    } else {
      for (final id in _checked) {
        await service.attachMany(widget.photoKeys, id);
      }
    }

    if (!mounted) return;
    ref.bumpDataRevision();
    Navigator.of(context).pop(true);
  }

  void _toggle(String tagId, bool checked) {
    setState(() {
      if (checked) {
        _checked = {..._checked, tagId};
      } else {
        _checked = {..._checked}..remove(tagId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final tagsAsync = ref.watch(allTagsProvider);
    final groups =
        ref.watch(allTagGroupsProvider).valueOrNull ?? const <TagGroup>[];
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Column(
          children: [
            const SizedBox(height: 12),
            Text(
              _isSingle
                  ? '태그 지정'
                  : '태그 추가 — 사진 ${widget.photoKeys.length}장',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (!_isSingle)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '고른 태그가 선택한 사진 전부에 추가됩니다.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _newTag,
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        hintText: _filter == null
                            ? '새 태그 이름'
                            : '새 태그 이름 (${_groupName(groups, _filter!)}에 추가)',
                        isDense: true,
                      ),
                      onSubmitted: (_) => _createTag(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    onPressed: _createTag,
                    icon: const Icon(Icons.add),
                    tooltip: '태그 만들기',
                  ),
                ],
              ),
            ),
            if (groups.isNotEmpty)
              _GroupFilterBar(
                groups: groups,
                selected: _filter,
                onSelected: (value) => setState(() => _filter = value),
              ),
            const Divider(height: 1),
            Expanded(
              child: !_ready
                  ? const Center(child: CircularProgressIndicator())
                  : tagsAsync.when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (error, _) => Center(child: Text('$error')),
                      data: (tags) =>
                          _buildList(scrollController, tags, groups),
                    ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('취소'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _ready ? _save : null,
                        child: const Text('저장'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 전체를 보고 있으면 분류별 머리글과 함께, 한 분류만 보고 있으면 그 안의
  /// 태그만 평평하게 보여 줍니다.
  Widget _buildList(
    ScrollController controller,
    List<Tag> tags,
    List<TagGroup> groups,
  ) {
    if (tags.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            '아직 태그가 없습니다.\n위에서 첫 태그를 만들어 보세요.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final rows = <Widget>[];

    if (_filter != _allGroups) {
      final mine = tags.where((t) => t.groupId == _filter).toList();
      if (mine.isEmpty) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              '"${_groupName(groups, _filter!)}"에 든 태그가 없습니다.\n'
              '위에서 이름을 적어 만들면 이 분류로 들어갑니다.',
              textAlign: TextAlign.center,
            ),
          ),
        );
      }
      rows.addAll(mine.map(_tagTile));
    } else {
      for (final group in groups) {
        final mine = tags.where((t) => t.groupId == group.id).toList();
        if (mine.isEmpty) continue;
        rows.add(_SectionLabel(group.name));
        rows.addAll(mine.map(_tagTile));
      }
      final loose = tags.where((t) => t.groupId.isEmpty).toList();
      if (loose.isNotEmpty) {
        if (groups.isNotEmpty) rows.add(const _SectionLabel('미분류'));
        rows.addAll(loose.map(_tagTile));
      }
    }

    return ListView.builder(
      controller: controller,
      itemCount: rows.length,
      itemBuilder: (context, index) => rows[index],
    );
  }

  Widget _tagTile(Tag tag) => CheckboxListTile(
        value: _checked.contains(tag.id),
        title: Text(tag.name),
        subtitle: Text('사진 ${tag.photoCount}장'),
        onChanged: (checked) => _toggle(tag.id, checked ?? false),
      );

  static String _groupName(List<TagGroup> groups, String id) {
    if (id == TagGroup.none) return '미분류';
    for (final group in groups) {
      if (group.id == id) return group.name;
    }
    return '분류';
  }
}

class _GroupFilterBar extends StatelessWidget {
  const _GroupFilterBar({
    required this.groups,
    required this.selected,
    required this.onSelected,
  });

  final List<TagGroup> groups;
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          _chip(context, '전체', _allGroups),
          for (final group in groups) _chip(context, group.name, group.id),
          _chip(context, '미분류', TagGroup.none),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: selected == value,
        onSelected: (_) => onSelected(value),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.name);

  final String name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Text(
        name,
        style: theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
