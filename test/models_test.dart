import 'package:flutter_test/flutter_test.dart';
import 'package:kairos/data/models.dart';

void main() {
  test('събитие се записва и чете обратно', () {
    final e = ChurchEvent(
      id: '1',
      ownerId: 'u',
      churchId: 'c',
      kind: EventKind.vodosvet,
      startsAt: DateTime(2026, 11, 12, 17, 30),
      outsideChurch: true,
      address: 'ул. Витоша 1',
    );
    final back = ChurchEvent.fromJson(e.toJson());
    expect(back.kind, EventKind.vodosvet);
    expect(back.startsAt, e.startsAt);
    expect(back.placeLabel, 'ул. Витоша 1');
  });
}
