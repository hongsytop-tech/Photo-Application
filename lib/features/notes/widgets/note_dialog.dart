import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:photo_application/core/providers/core_providers.dart';

/// 사진의 메모를 팝업으로 열고 그 자리에서 고칩니다.
///
/// 그리드에서 메모 배지를 눌렀을 때 쓰입니다. 사진을 열고 → 메모 화면으로
/// 들어가는 두 단계를 거치지 않고 바로 읽고 고칠 수 있게 하려는 것입니다.
Future<void> showNoteDialog(
  BuildContext context,
  WidgetRef ref,
  String photoKey,
) async {
  final note = await ref.read(noteServiceProvider).read(photoKey);
  if (!context.mounted) return;

  final changed = await showDialog<bool>(
    context: context,
    builder: (_) => _NoteDialog(photoKey: photoKey, initial: note?.body ?? ''),
  );
  // 메모가 지워지면 배지도 사라져야 하고, "메모" 필터의 개수도 달라집니다.
  if (changed ?? false) ref.bumpDataRevision();
}

class _NoteDialog extends ConsumerStatefulWidget {
  const _NoteDialog({required this.photoKey, required this.initial});

  final String photoKey;
  final String initial;

  @override
  ConsumerState<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends ConsumerState<_NoteDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _controller.text;
    // 내용이 그대로면 저장하지 않습니다. updated_ms 만 새로 찍히면 다른 기기의
    // 더 나중 수정본을 이 기기의 옛 내용이 덮어쓸 수 있습니다.
    if (text.trim() == widget.initial.trim()) {
      if (mounted) Navigator.of(context).pop(false);
      return;
    }
    await ref.read(noteServiceProvider).write(widget.photoKey, text);
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _clear() async {
    await ref.read(noteServiceProvider).delete(widget.photoKey);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('메모'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLines: 6,
        minLines: 3,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          hintText: '이 사진에 남길 메모',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        if (widget.initial.trim().isNotEmpty)
          TextButton(
            onPressed: _clear,
            child: const Text('지우기'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('취소'),
        ),
        FilledButton(onPressed: _save, child: const Text('저장')),
      ],
    );
  }
}
