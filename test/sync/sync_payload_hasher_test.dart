import 'package:aish_warehouse/core/sync/sync_payload_hasher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('canonical hash ignores map insertion order', () {
    const hasher = Sha256SyncPayloadHasher();
    expect(
      hasher.hash({
        'b': 2,
        'a': 1,
        'nested': {'z': true, 'a': null},
      }),
      hasher.hash({
        'nested': {'a': null, 'z': true},
        'a': 1,
        'b': 2,
      }),
    );
    expect(hasher.hash({'a': 1}), matches(RegExp(r'^[0-9a-f]{64}$')));
  });
}
