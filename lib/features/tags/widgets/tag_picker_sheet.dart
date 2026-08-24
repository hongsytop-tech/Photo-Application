import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:photo_application/core/providers/core_providers.dart';
import 'package:photo_application/features/gallery/providers/photo_meta_providers.dart';
import 'package:photo_application/features/tags/models/tag.dart';

/// 사진들에 붙일 태그를 고르는 바텀시트.
///
/// 사진 한 장([photoKeys] 가 1개)이면 현재 달린 태그가 미리 체크되어 있고,
/// 여러 장이면 "고른 태그를 전부에 추가"하는 방식으로 동작합니다. 여러 장을
/// 다룰 때 체크 해제로 일괄 제거까지 하면 실수로 남의 태그를 날리기 쉬워서
/// 추가만 하도록 좁혔습니다.
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

class _TagPickerSheetState extends ConsumerState<TagPickerSheet> {
  final _newTag = TextEditingController();
  Set<String> _checked = {};
  Set<String> _initial = {};
  bool _ready = false;

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
    final tag = await ref.read(tagServiceProvider).ensure(name);
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

  @override
  Widget build(BuildContext context) {
    final tagsAsync = ref.watch(allTagsProvider);
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
                      decoration: const InputDecoration(
                        hintText: '새 태그 이름',
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
            const Divider(height: 1),
            Expanded(
              child: !_ready
                  ? const Center(child: CircularProgressIndicator())
                  : tagsAsync.when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (error, _) => Center(child: Text('$error')),
                      data: (tags) => tags.isEmpty
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(32),
                                child: Text(
                                  '아직 태그가 없습니다.\n위에서 첫 태그를 만들어 보세요.',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            )
                          : ListView.builder(
                              controller: scrollController,
                              itemCount: tags.length,
                              itemBuilder: (context, index) {
                                final Tag tag = tags[index];
                                return CheckboxListTile(
                                  value: _checked.contains(tag.id),
                                  title: Text(tag.name),
                                  subtitle: Text('사진 ${tag.photoCount}장'),
                                  onChanged: (checked) => setState(() {
                                    if (checked ?? false) {
                                      _checked = {..._checked, tag.id};
                                    } else {
                                      _checked = {..._checked}..remove(tag.id);
                                    }
                                  }),
                                );
                              },
                            ),
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
}
