import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:photo_application/core/providers/core_providers.dart';
import 'package:photo_application/features/gallery/services/gallery_service.dart';

/// 고른 사진을 기기에서 치웁니다 — 되도록 **휴지통으로** 보냅니다.
///
/// 목록(여러 장)과 뷰어(한 장)가 같은 길을 쓰도록 여기 한 곳에 둡니다.
/// 지우는 경로가 둘로 갈라지면 한쪽만 고치는 일이 생기는데, 사진을 지우는
/// 코드에서 그런 어긋남은 되돌릴 수 없는 결과를 냅니다.
///
/// 이 앱의 다른 모든 동작은 사진 파일을 읽기만 하는데 이것만 예외라서,
/// 확인 창에서 무엇이 일어나는지 분명히 말합니다. 그 뒤에 안드로이드가
/// 시스템 확인 창을 한 번 더 띄웁니다.
///
/// 사용자가 확인 창에서 취소하면 null 을 돌려줍니다. 시스템 확인 창에서
/// 거절해도 빈 결과가 오므로, **요청한 수가 아니라 실제로 치워진 것만**
/// 인덱스에서 뺍니다. 요청한 id 를 그대로 지우면 아직 기기에 있는 사진이
/// 목록에서 사라집니다.
Future<PhotoRemoval?> confirmAndTrash(
  BuildContext context,
  WidgetRef ref,
  List<String> assetIds,
) async {
  if (assetIds.isEmpty) return null;

  final single = assetIds.length == 1;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(
        single ? '이 사진을 휴지통으로 보낼까요?' : '사진 ${assetIds.length}장을 휴지통으로 보낼까요?',
      ),
      content: const Text(
        '기기의 휴지통으로 들어가며, 30일 안에는 갤러리에서 되살릴 수 '
        '있습니다. 휴지통이 없는 기기(안드로이드 10 이하)에서는 바로 '
        '지워집니다.\n\n'
        '메모와 태그는 지우지 않습니다. 같은 사진이 다른 기기에 남아 있을 수 '
        '있어서, 거기서는 그대로 보입니다.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('휴지통으로'),
        ),
      ],
    ),
  );
  if (!(ok ?? false) || !context.mounted) return null;

  final removed = await ref.read(galleryServiceProvider).removeAssets(assetIds);
  await ref.read(photoIndexServiceProvider).forget(removed.ids);
  ref.bumpDataRevision();
  return removed;
}

/// [confirmAndTrash] 의 결과를 사람 말로.
///
/// 휴지통으로 갔는지 바로 지워졌는지는 사용자가 알아야 하는 차이입니다.
String trashMessage(PhotoRemoval removed) {
  if (removed.isEmpty) return '아무것도 치우지 않았습니다.';
  if (removed.trashed) return '${removed.ids.length}장을 휴지통으로 보냈습니다.';
  return '${removed.ids.length}장을 기기에서 지웠습니다.';
}
