import 'package:flutter/material.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import 'package:photo_application/features/gallery/models/photo_item.dart';

/// 사진 한 장을 손가락으로 확대·축소해서 보는 영역.
///
/// `InteractiveViewer` 를 그냥 `PageView` 안에 넣으면 제대로 동작하지
/// 않습니다. 둘 다 끌기 동작을 노리기 때문입니다.
/// * 1배에서 사진을 끌면 `InteractiveViewer` 가 그 손짓을 먹어 페이지가
///   넘어가지 않습니다.
/// * 확대한 뒤 사진을 끌어 옮기려 하면 거꾸로 `PageView` 가 가로채 옆
///   사진으로 넘어갑니다. 확대는 되는데 확대한 자리를 볼 수 없으니
///   사실상 쓸 수 없습니다.
///
/// 그래서 배율에 따라 둘 중 하나만 켭니다.
/// * 1배: 끌기를 끄고([panEnabled] false) 페이지 넘김에 양보합니다.
/// * 확대 중: 끌기를 켜고, [onZoomChanged] 로 바깥에 알려 페이지 넘김을
///   끄게 합니다.
///
/// 다만 이것만으로는 **벌리는 동작의 시작**을 지키지 못합니다. 배율이
/// 올라간 뒤에야 넘김이 꺼지므로, 핀치의 첫 순간은 늘 페이저와 경주가 되고
/// 페이저가 이기면 확대가 아니라 옆 사진으로 넘어갑니다. 그래서 바깥(뷰어
/// 화면)에서 **손가락이 두 개가 되는 순간** 넘김을 끕니다.
///
/// 확대한 동안에는 옆으로 넘길 수 없으므로, 페이지를 떠날 때는 늘 1배입니다.
/// 되돌리는 처리를 따로 두지 않아도 되는 이유입니다.
///
/// 두 번 눌러 확대도 함께 넣습니다. 한 손으로 들고 볼 때 두 손가락을 쓰기
/// 어렵고, 눌린 자리를 그대로 키워 주므로 보고 싶은 곳을 바로 볼 수 있습니다.
class ZoomablePhoto extends StatefulWidget {
  const ZoomablePhoto({
    super.key,
    required this.item,
    this.onZoomChanged,
  });

  final PhotoItem item;

  /// 1배를 벗어났는지가 바뀔 때 호출됩니다.
  final void Function(bool zoomed)? onZoomChanged;

  @override
  State<ZoomablePhoto> createState() => _ZoomablePhotoState();
}

class _ZoomablePhotoState extends State<ZoomablePhoto> {
  final _controller = TransformationController();

  static const _doubleTapScale = 2.5;
  static const _maxScale = 6.0;

  /// 1배보다 작게는 줄이지 않습니다.
  ///
  /// InteractiveViewer 의 기본값은 0.8 인데, 그대로 두면 두 손가락을 오므렸을
  /// 때 사진이 화면에 맞는 크기보다 **작아진 채 멈춥니다**. 그 상태는 1배가
  /// 아니지만 '확대 중'으로도 치지 않아(1.01 미만) 끌기도 꺼져 있어서,
  /// 되돌릴 손짓이 남지 않습니다. 1 로 막으면 오므리는 동작이 정확히 '원래
  /// 크기'에서 멈추고, 그때 페이지 넘김도 다시 켜집니다.
  static const _minScale = 1.0;

  bool _zoomed = false;
  Offset _lastTapAt = Offset.zero;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTransform);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTransform);
    _controller.dispose();
    super.dispose();
  }

  void _onTransform() {
    // 1에 아주 가까우면 1로 봅니다. 부동소수 오차로 1.0000001 이 남아
    // 페이지 넘김이 영영 안 켜지는 일을 막습니다.
    final zoomed = _controller.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed == _zoomed) return;

    // panEnabled 를 build 에서 읽으므로 setState 가 필요합니다. 손짓
    // 도중에 바뀌어도 괜찮습니다 — InteractiveViewer 는 panEnabled 를
    // 손짓을 받을 때마다 다시 보기 때문에 진행 중인 동작이 끊기지 않습니다.
    setState(() => _zoomed = zoomed);
    widget.onZoomChanged?.call(zoomed);
  }

  void _onDoubleTap() {
    if (_zoomed) {
      _controller.value = Matrix4.identity();
      return;
    }

    // 누른 지점이 확대 후에도 같은 자리에 있도록 옮깁니다. 배율만 올리면
    // 화면 가운데가 커져서 보려던 곳은 테두리 밖으로 밀려납니다.
    //
    // 대각선에 배율, 마지막 열에 이동을 넣은 행렬은 p -> s*p + t 입니다.
    // t = -누른지점*(s-1) 로 두면 s*누른지점 + t = 누른지점 이 되어 그
    // 지점이 제자리에 남습니다.
    const s = _doubleTapScale;
    _controller.value = Matrix4.identity()
      ..setEntry(0, 0, s)
      ..setEntry(1, 1, s)
      ..setEntry(2, 2, s)
      ..setEntry(0, 3, -_lastTapAt.dx * (s - 1))
      ..setEntry(1, 3, -_lastTapAt.dy * (s - 1));
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // onDoubleTap 은 누른 좌표를 주지 않아서, 좌표는 onDoubleTapDown 에서
      // 받아 두고 확대는 onDoubleTap 에서 합니다.
      onDoubleTapDown: (details) => _lastTapAt = details.localPosition,
      onDoubleTap: _onDoubleTap,
      child: InteractiveViewer(
        transformationController: _controller,
        minScale: _minScale,
        maxScale: _maxScale,
        // 확대한 사진을 끝까지 끌어 볼 수 있게 여유를 무한으로 둡니다.
        // 0 이면 모서리가 화면 가장자리에 붙어 그 너머를 볼 수 없습니다.
        boundaryMargin: const EdgeInsets.all(double.infinity),
        panEnabled: _zoomed,
        child: Center(
          child: Image(
            image: AssetEntityImageProvider(
              widget.item.toEntity(),
              isOriginal: true,
            ),
            fit: BoxFit.contain,
            errorBuilder: (context, error, stack) => const Center(
              child: Icon(
                Icons.broken_image_outlined,
                color: Colors.white38,
                size: 48,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
