import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:photo_application/core/providers/core_providers.dart';

/// 사진 한 장에 붙는 메모를 쓰고 고치는 화면.
///
/// 사진 파일은 건드리지 않습니다. 메모는 앱 안에만 저장되고, 사진을 다른 앱
/// 으로 열거나 공유해도 메모가 따라가지 않습니다.
class NoteEditScreen extends ConsumerStatefulWidget {
  const NoteEditScreen({
    super.key,
    required this.photoKey,
    required this.photoName,
  });

  final String photoKey;
  final String photoName;

  @override
  ConsumerState<NoteEditScreen> createState() => _NoteEditScreenState();
}

class _NoteEditScreenState extends ConsumerState<NoteEditScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  String _original = '';
  bool _loaded = false;
  int? _updatedMs;

  bool get _dirty => _controller.text.trim() != _original.trim();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final note = await ref.read(noteServiceProvider).read(widget.photoKey);
    if (!mounted) return;
    setState(() {
      _original = note?.body ?? '';
      _controller.text = _original;
      _updatedMs = note?.updatedMs;
      _loaded = true;
    });
    if (_original.isEmpty) _focus.requestFocus();
  }

  Future<void> _save() async {
    if (!_dirty) return;
    await ref
        .read(noteServiceProvider)
        .write(widget.photoKey, _controller.text);
    if (!mounted) return;
    _original = _controller.text;
    ref.bumpDataRevision();
  }

  Future<void> _saveAndClose() async {
    await _save();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('메모를 지울까요?'),
        content: const Text('사진은 그대로 남고 메모만 지워집니다.'),
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

    await ref.read(noteServiceProvider).delete(widget.photoKey);
    if (!mounted) return;
    ref.bumpDataRevision();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    // 화면을 벗어날 때 자동 저장합니다. 메모를 쓰다가 뒤로 가기를 눌렀다고
    // 내용이 날아가면 안 됩니다.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _save();
        if (mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('메모'),
              Text(
                widget.photoName,
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          actions: [
            if (_original.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: _confirmDelete,
                tooltip: '메모 지우기',
              ),
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: _saveAndClose,
              tooltip: '저장',
            ),
          ],
        ),
        body: !_loaded
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_updatedMs != null && _original.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Text(
                        '마지막 수정 ${DateFormat('yyyy.M.d HH:mm').format(
                          DateTime.fromMillisecondsSinceEpoch(_updatedMs!),
                        )}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: TextField(
                        controller: _controller,
                        focusNode: _focus,
                        maxLines: null,
                        expands: true,
                        textAlignVertical: TextAlignVertical.top,
                        keyboardType: TextInputType.multiline,
                        decoration: const InputDecoration(
                          hintText: '이 사진에 대해 남기고 싶은 내용을 적으세요.',
                          border: InputBorder.none,
                          filled: false,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
