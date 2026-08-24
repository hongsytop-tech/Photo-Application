import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:photo_application/core/providers/core_providers.dart';
import 'package:photo_application/features/gallery/models/photo_item.dart';
import 'package:photo_application/features/gallery/services/gallery_service.dart';
import 'package:photo_application/features/gallery/services/photo_index_service.dart';
import 'package:photo_application/features/gallery/services/photo_query_service.dart';

// ---------------------------------------------------------------------------
// 권한
// ---------------------------------------------------------------------------

/// 현재 사진 접근 권한. 권한 화면을 띄우지 않고 상태만 봅니다.
final galleryAccessProvider = FutureProvider<GalleryAccess>(
  (ref) => ref.watch(galleryServiceProvider).currentAccess(),
);

// ---------------------------------------------------------------------------
// 갤러리 스캔
// ---------------------------------------------------------------------------

/// 스캔 진행 상황.
@immutable
class IndexingState {
  const IndexingState({
    this.running = false,
    this.done = 0,
    this.total = 0,
    this.lastResult,
    this.error,
  });

  final bool running;
  final int done;
  final int total;
  final PhotoIndexResult? lastResult;
  final Object? error;

  double? get progress => total == 0 ? null : (done / total).clamp(0.0, 1.0);

  IndexingState copyWith({
    bool? running,
    int? done,
    int? total,
    PhotoIndexResult? lastResult,
    Object? error,
  }) =>
      IndexingState(
        running: running ?? this.running,
        done: done ?? this.done,
        total: total ?? this.total,
        lastResult: lastResult ?? this.lastResult,
        error: error,
      );
}

class IndexingController extends StateNotifier<IndexingState> {
  IndexingController(this._ref) : super(const IndexingState());

  final Ref _ref;

  /// 갤러리를 다시 훑어 인덱스를 갱신합니다.
  ///
  /// 이미 돌고 있으면 그냥 무시합니다. 앱 시작과 당겨서 새로고침이 겹쳐
  /// 두 번 도는 걸 막기 위해서입니다.
  Future<void> run() async {
    if (state.running) return;
    state = const IndexingState(running: true);
    try {
      final result = await _ref.read(photoIndexServiceProvider).reindex(
        onProgress: (done, total) {
          if (mounted) {
            state = state.copyWith(done: done, total: total);
          }
        },
      );
      if (!mounted) return;
      state = IndexingState(lastResult: result, done: result.indexed, total: result.total);
      _ref.bumpDataRevision();
    } catch (error, stack) {
      debugPrint('사진 스캔 실패: $error\n$stack');
      if (mounted) state = IndexingState(error: error);
    }
  }
}

final indexingProvider =
    StateNotifierProvider<IndexingController, IndexingState>(
  IndexingController.new,
);

// ---------------------------------------------------------------------------
// 사진 목록 (페이지 단위 로딩)
// ---------------------------------------------------------------------------

@immutable
class PhotoListState {
  const PhotoListState({
    this.items = const [],
    this.total = 0,
    this.loading = false,
    this.hasMore = true,
  });

  final List<PhotoItem> items;

  /// 조건에 맞는 전체 사진 수 (지금 로드된 수가 아님).
  final int total;
  final bool loading;
  final bool hasMore;

  bool get isEmpty => !loading && items.isEmpty;

  PhotoListState copyWith({
    List<PhotoItem>? items,
    int? total,
    bool? loading,
    bool? hasMore,
  }) =>
      PhotoListState(
        items: items ?? this.items,
        total: total ?? this.total,
        loading: loading ?? this.loading,
        hasMore: hasMore ?? this.hasMore,
      );
}

/// 조건에 맞는 사진을 스크롤에 따라 조금씩 읽어옵니다.
///
/// 사진이 수만 장이어도 목록은 한 번에 한 페이지씩만 메모리에 올립니다.
class PhotoListController extends StateNotifier<PhotoListState> {
  PhotoListController(this._service, this._query)
      : super(const PhotoListState(loading: true)) {
    refresh();
  }

  final PhotoQueryService _service;
  final PhotoQuery _query;

  static const pageSize = 120;

  /// 처음부터 다시 읽습니다.
  Future<void> refresh() => _load(reset: true);

  /// 다음 페이지를 이어 붙입니다.
  Future<void> loadMore() async {
    if (state.loading || !state.hasMore) return;
    await _load(reset: false);
  }

  /// 이미 읽어둔 만큼을 그대로 다시 읽습니다.
  ///
  /// 메모를 고치고 목록으로 돌아왔을 때 쓰입니다. 처음부터 다시 읽으면
  /// 스크롤이 맨 위로 튀어서, 보고 있던 위치를 지키려고 분리했습니다.
  Future<void> reloadInPlace() async {
    final loaded = state.items.length;
    if (loaded == 0) return refresh();
    state = state.copyWith(loading: true);
    try {
      final total = await _service.count(_query);
      final items =
          await _service.page(_query, limit: loaded, offset: 0);
      if (!mounted) return;
      state = PhotoListState(
        items: items,
        total: total,
        loading: false,
        hasMore: items.length < total,
      );
    } catch (error, stack) {
      debugPrint('사진 목록 갱신 실패: $error\n$stack');
      if (mounted) state = state.copyWith(loading: false);
    }
  }

  Future<void> _load({required bool reset}) async {
    state = state.copyWith(loading: true);
    final offset = reset ? 0 : state.items.length;
    try {
      final total = reset ? await _service.count(_query) : state.total;
      final page = await _service.page(
        _query,
        limit: pageSize,
        offset: offset,
      );
      if (!mounted) return;
      final items = reset ? page : [...state.items, ...page];
      state = PhotoListState(
        items: items,
        total: total,
        loading: false,
        hasMore: page.length == pageSize && items.length < total,
      );
    } catch (error, stack) {
      debugPrint('사진 목록 로딩 실패: $error\n$stack');
      if (mounted) state = state.copyWith(loading: false, hasMore: false);
    }
  }
}

/// 조건별 사진 목록. autoDispose 를 쓰지 않아 탭을 오가도 스크롤 위치와
/// 읽어둔 페이지가 유지됩니다.
final photoListProvider = StateNotifierProvider.family<PhotoListController,
    PhotoListState, PhotoQuery>((ref, query) {
  final controller = PhotoListController(
    ref.watch(photoQueryServiceProvider),
    query,
  );
  // 메타데이터가 바뀌면 (태그/폴더 지정 등) 목록 조건이 달라질 수 있으므로
  // 보고 있던 만큼만 다시 읽습니다.
  ref.listen<int>(dataRevisionProvider, (_, __) => controller.reloadInPlace());
  return controller;
});

/// 특정 조건의 사진 개수만 필요할 때 (배지 등).
final photoCountProvider =
    FutureProvider.family<int, PhotoQuery>((ref, query) async {
  ref.watch(dataRevisionProvider);
  return ref.watch(photoQueryServiceProvider).count(query);
});
