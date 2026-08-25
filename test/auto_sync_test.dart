import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:photo_application/core/providers/core_providers.dart';

/// 확장이 `Ref` 위에 정의되어 있어, 테스트에서도 `Ref` 를 하나 꺼내 와야
/// 앱과 똑같은 코드를 부를 수 있습니다.
final _refProvider = Provider<Ref>((ref) => ref);

/// 자동 동기화는 "이 기기에서 직접 고친 것"에만 반응해야 합니다.
///
/// 서버에서 받아온 변경까지 신호로 세면, 받아온 것 때문에 또 동기화가 돌고
/// 그게 또 신호가 되면서 앱이 열려 있는 내내 네트워크를 칩니다.
void main() {
  late ProviderContainer container;
  late Ref ref;

  setUp(() {
    container = ProviderContainer();
    ref = container.read(_refProvider);
  });
  tearDown(() => container.dispose());

  test('내가 고치면 두 카운터가 모두 올라간다', () {
    ref.bumpDataRevision();

    expect(container.read(dataRevisionProvider), 1);
    expect(container.read(localEditRevisionProvider), 1);
  });

  test('서버에서 받아온 변경은 화면만 갱신하고 자동 동기화를 깨우지 않는다', () {
    ref.bumpDataRevisionFromSync();

    expect(container.read(dataRevisionProvider), 1, reason: '화면은 다시 그려야 한다');
    expect(
      container.read(localEditRevisionProvider),
      0,
      reason: '자동 동기화가 자기 꼬리를 물면 안 된다',
    );
  });
}
