/// 사진 한 장에 붙는 메모.
///
/// 사진 위에 글자를 그려 넣는 게 아니라, 사진 파일과 별도로 보관되는
/// 텍스트입니다. 원본 사진 파일은 절대 수정되지 않습니다.
class PhotoNote {
  const PhotoNote({
    required this.photoKey,
    required this.body,
    required this.updatedMs,
  });

  final String photoKey;
  final String body;
  final int updatedMs;

  bool get isEmpty => body.trim().isEmpty;

  DateTime get updatedAt => DateTime.fromMillisecondsSinceEpoch(updatedMs);

  factory PhotoNote.fromRow(Map<String, Object?> row) => PhotoNote(
        photoKey: row['photo_key'] as String,
        body: (row['body'] as String?) ?? '',
        updatedMs: (row['updated_ms'] as int?) ?? 0,
      );
}
