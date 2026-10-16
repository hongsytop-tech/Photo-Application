import 'package:flutter_test/flutter_test.dart';

import 'package:photo_application/features/folders/models/photo_folder.dart';

/// 평평한 폴더 목록을 트리로 펼치는 규칙.
///
/// 여기서 중요한 것은 "정상일 때 잘 나온다"가 아니라 **망가진 데이터에서도
/// 폴더가 사라지지 않는다**는 쪽입니다. 고리(X 아래 Y, Y 아래 X)는 두 기기가
/// 서로 모르는 채 각각 옮긴 뒤 동기화되면 실제로 만들어집니다. 그때 그
/// 폴더들이 화면에서 사라지면 사용자는 폴더를 잃은 것처럼 느끼고, 앱 안에서
/// 되돌릴 방법도 없습니다.
void main() {
  PhotoFolder folder(String id, {String parent = '', int children = 0}) =>
      PhotoFolder(
        id: id,
        name: id,
        parentId: parent,
        subfolderCount: children,
      );

  List<String> idsOf(List<FolderNode> nodes) =>
      nodes.map((n) => n.folder.id).toList();

  group('폴더 트리 펼치기', () {
    test('부모 바로 다음에 그 자식들이 온다', () {
      final nodes = buildFolderTree([
        folder('여행', children: 1),
        folder('2023', parent: '여행', children: 1),
        folder('제주', parent: '2023'),
        folder('음식'),
      ]);

      expect(idsOf(nodes), ['여행', '2023', '제주', '음식']);
      expect(nodes.map((n) => n.depth).toList(), [0, 1, 2, 0]);
    });

    test('펼친 폴더의 자식만 따라 내려간다', () {
      final all = [
        folder('여행', children: 1),
        folder('2023', parent: '여행', children: 1),
        folder('제주', parent: '2023'),
        folder('음식'),
      ];

      expect(idsOf(buildFolderTree(all, expanded: {})), ['여행', '음식']);
      expect(
        idsOf(buildFolderTree(all, expanded: {'여행'})),
        ['여행', '2023', '음식'],
      );
      expect(
        idsOf(buildFolderTree(all, expanded: {'여행', '2023'})),
        ['여행', '2023', '제주', '음식'],
      );
      // null 은 전부 펼침 (폴더 고르기 시트처럼 한눈에 다 보여줄 때).
      expect(idsOf(buildFolderTree(all)).length, 4);
    });

    test('부모가 사라진 폴더는 뿌리로 올라와 반드시 보인다', () {
      final nodes = buildFolderTree([
        folder('음식'),
        folder('길잃은', parent: '없는폴더'),
      ]);

      expect(idsOf(nodes).toSet(), {'음식', '길잃은'});
      expect(nodes.firstWhere((n) => n.folder.id == '길잃은').depth, 0);
    });

    test('두 폴더가 서로를 품은 고리에서도 멈추고, 둘 다 보인다', () {
      // 동기화가 만들어 낼 수 있는 상태. 끝나지 않으면 앱이 멈춘다.
      final nodes = buildFolderTree([
        folder('X', parent: 'Y'),
        folder('Y', parent: 'X'),
      ]);

      expect(idsOf(nodes).toSet(), {'X', 'Y'});
      expect(nodes.every((n) => n.depth == 0), isTrue);
    });

    test('자기 자신을 품은 폴더도 뿌리로', () {
      final nodes = buildFolderTree([folder('혼자', parent: '혼자')]);
      expect(idsOf(nodes), ['혼자']);
      expect(nodes.single.depth, 0);
    });

    test('세 폴더가 돌아가는 고리에서도 전부 보인다', () {
      final nodes = buildFolderTree([
        folder('A', parent: 'C'),
        folder('B', parent: 'A'),
        folder('C', parent: 'B'),
      ]);
      expect(idsOf(nodes).toSet(), {'A', 'B', 'C'});
    });

    test('고리에 매달린 정상 폴더도 사라지지 않는다', () {
      final nodes = buildFolderTree([
        folder('X', parent: 'Y'),
        folder('Y', parent: 'X'),
        folder('아래', parent: 'X'),
      ]);
      expect(idsOf(nodes).toSet(), {'X', 'Y', '아래'});
    });

    test('빈 목록은 빈 트리', () {
      expect(buildFolderTree(const []), isEmpty);
    });

    test('받은 순서를 형제들 사이에서 지킨다', () {
      // SQL 이 sort_order 로 정렬해 주므로, 트리는 그 순서를 흐트리지
      // 않기만 하면 된다.
      final nodes = buildFolderTree([
        folder('나중', children: 0),
        folder('먼저'),
      ]);
      expect(idsOf(nodes), ['나중', '먼저']);
    });

    test('하위가 있는지 알려 준다', () {
      final nodes = buildFolderTree([
        folder('부모', children: 2),
        folder('자식', parent: '부모'),
      ]);
      expect(nodes.first.hasChildren, isTrue);
      expect(nodes.last.hasChildren, isFalse);
    });
  });
}
