import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:photo_application/core/providers/core_providers.dart';
import 'package:photo_application/features/folders/models/photo_folder.dart';
import 'package:photo_application/features/notes/models/photo_note.dart';
import 'package:photo_application/features/tags/models/tag.dart';
import 'package:photo_application/features/tags/models/tag_group.dart';

/// 사진 한 장에 붙은 메모.
final noteForPhotoProvider =
    FutureProvider.family<PhotoNote?, String>((ref, photoKey) async {
  ref.watch(dataRevisionProvider);
  return ref.watch(noteServiceProvider).read(photoKey);
});

/// 사진 한 장에 달린 태그들.
final tagsForPhotoProvider =
    FutureProvider.family<List<Tag>, String>((ref, photoKey) async {
  ref.watch(dataRevisionProvider);
  return ref.watch(tagServiceProvider).tagsOf(photoKey);
});

/// 사진 한 장이 속한 가상 폴더 id 들.
final folderIdsForPhotoProvider =
    FutureProvider.family<Set<String>, String>((ref, photoKey) async {
  ref.watch(dataRevisionProvider);
  return ref.watch(folderServiceProvider).folderIdsOf(photoKey);
});

/// 전체 태그 목록 (사진 수 포함).
final allTagsProvider = FutureProvider<List<Tag>>((ref) async {
  ref.watch(dataRevisionProvider);
  return ref.watch(tagServiceProvider).listAll();
});

/// 전체 태그 분류 목록 (태그 수 포함).
final allTagGroupsProvider = FutureProvider<List<TagGroup>>((ref) async {
  ref.watch(dataRevisionProvider);
  return ref.watch(tagServiceProvider).listGroups();
});

/// 전체 가상 폴더 목록 (사진 수 포함).
final allFoldersProvider = FutureProvider<List<PhotoFolder>>((ref) async {
  ref.watch(dataRevisionProvider);
  return ref.watch(folderServiceProvider).listAll();
});

/// 어떤 폴더에도 속하지 않은 사진 수.
final unassignedCountProvider = FutureProvider<int>((ref) async {
  ref.watch(dataRevisionProvider);
  return ref.watch(folderServiceProvider).countUnassigned();
});
