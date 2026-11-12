import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kairos/data/models.dart';
import 'package:kairos/widgets/common.dart';

ChurchEvent ev({
  String id = 'e1',
  String owner = 'a',
  String? assignee,
  DateTime? at,
  int minutes = 30,
  bool outside = false,
  EventStatus status = EventStatus.planned,
}) =>
    ChurchEvent(
      id: id,
      ownerId: owner,
      churchId: 'c',
      assigneeId: assignee,
      kind: EventKind.krashtene,
      startsAt: at ?? DateTime(2026, 11, 12, 11, 0),
      durationMinutes: minutes,
      outsideChurch: outside,
      status: status,
    );

void main() {
  setUpAll(() async => initializeDateFormatting('bg'));

  group('Застъпване', () {
    test('застъпващи се събития', () {
      final a = ev(at: DateTime(2026, 11, 12, 11, 0), minutes: 60);
      final b = ev(id: 'e2', at: DateTime(2026, 11, 12, 11, 30));
      expect(a.overlaps(b), isTrue);
      expect(b.overlaps(a), isTrue);
    });
    test('допиране не е застъпване', () {
      final a = ev(at: DateTime(2026, 11, 12, 11, 0), minutes: 30);
      final b = ev(id: 'e2', at: DateTime(2026, 11, 12, 11, 30));
      expect(a.overlaps(b), isFalse);
    });
    test('краят се смята от продължителността', () {
      final a = ev(at: DateTime(2026, 11, 12, 23, 30), minutes: 90);
      expect(a.endsAt, DateTime(2026, 11, 13, 1, 0));
    });
  });

  group('Запис в базата и обратно', () {
    test('toRow → fromRow пази всичко', () {
      final e = ev(assignee: 'b', outside: true, status: EventStatus.done)
        ..forWhom = 'Иван Петров'
        ..phone = '0888 123 456'
        ..address = 'ул. Витоша 1'
        ..remindMinutes = 120
        ..alarm = true
        ..shared = true
        ..note = 'бележка';
      final back = ChurchEvent.fromRow(e.toRow());
      expect(back.assigneeId, 'b');
      expect(back.ownerId, 'a');
      expect(back.startsAt, e.startsAt);
      expect(back.durationMinutes, 30);
      expect(back.forWhom, 'Иван Петров');
      expect(back.phone, '0888 123 456');
      expect(back.outsideChurch, isTrue);
      expect(back.address, 'ул. Витоша 1');
      expect(back.remindMinutes, 120);
      expect(back.alarm, isTrue);
      expect(back.shared, isTrue);
      expect(back.status, EventStatus.done);
      expect(back.note, 'бележка');
    });
    test('часът се праща в UTC и се чете в местно време', () {
      final row = ev().toRow();
      expect((row['starts_at'] as String).endsWith('Z'), isTrue);
    });
    test('стари записи без нови полета', () {
      final back = ChurchEvent.fromRow({
        'id': 'x',
        'owner_id': 'a',
        'church_id': 'c',
        'kind': 'nepoznat',
        'starts_at': '2026-11-12T09:00:00Z',
        'visibility': 'private',
      });
      expect(back.assigneeId, 'a');
      expect(back.kind, EventKind.drugo);
      expect(back.durationMinutes, defaultDurationMinutes);
      expect(back.status, EventStatus.planned);
    });
    test('копие: ново събитие, записано от мен, предстоящо', () {
      final e = ev(assignee: 'b', status: EventStatus.cancelled)..forWhom = 'X';
      final c = e.copyAs(id: 'new', ownerId: 'me');
      expect(c.id, 'new');
      expect(c.ownerId, 'me');
      expect(c.assigneeId, 'b');
      expect(c.forWhom, 'X');
      expect(c.status, EventStatus.planned);
    });
  });

  group('Видове събития', () {
    test('всички видове имат име и продължителност', () {
      for (final k in EventKind.values) {
        expect(k.label, isNotEmpty);
        expect(k.defaultMinutes, inInclusiveRange(minDurationMinutes, maxDurationMinutes));
      }
    });
    test('водосветът е извън храма по подразбиране', () {
      expect(EventKind.vodosvet.defaultOutside, isTrue);
      expect(EventKind.krashtene.defaultOutside, isFalse);
    });
  });

  group('Имен ден', () {
    test('след колко дни', () {
      final d = ProfileDetails(nameDayMonth: 12, nameDayDay: 6);
      expect(d.daysToNameDay(DateTime(2026, 11, 12)), 24);
      expect(d.daysToNameDay(DateTime(2026, 12, 6)), 0);
      expect(d.daysToNameDay(DateTime(2026, 12, 7)), 364);
    });
    test('29 февруари в невисокосна година е на 28-и', () {
      final d = ProfileDetails(nameDayMonth: 2, nameDayDay: 29);
      expect(d.daysToNameDay(DateTime(2027, 2, 1)), 27);
    });
    test('без имен ден', () {
      expect(ProfileDetails().daysToNameDay(), isNull);
    });
    test('датите се записват без час', () {
      final d = ProfileDetails(birthDate: DateTime(1975, 4, 3), nameDayMonth: 5, nameDayDay: 6);
      final row = d.toRow();
      expect(row['birth_date'], '1975-04-03');
      expect(ProfileDetails.fromRow(row).birthDate, DateTime(1975, 4, 3));
    });
  });

  group('Членство', () {
    test('чакащият не е председател; права', () {
      final m = Membership.fromRow({
        'church_id': 'c',
        'user_id': 'u',
        'role': 'manager',
        'status': 'pending',
        'permissions': ['cash'],
      });
      expect(m.isPending, isTrue);
      expect(m.isManager, isFalse);
      expect(m.isCashier, isTrue);
    });
  });

  group('Текстове', () {
    test('продължителност', () {
      expect(fmtDuration(30), '30 мин');
      expect(fmtDuration(60), '1 ч');
      expect(fmtDuration(75), '1 ч 15 мин');
    });
    test('инициали без „Отец“', () {
      expect(priestInitials('Отец Иван Петров'), 'ИП');
      expect(priestInitials('о. Георги'), 'Г');
      expect(priestInitials(''), '?');
    });
    test('час и интервал', () {
      expect(fmtRange(ev(minutes: 45)), '11:00 – 11:45');
    });
    test('след колко време', () {
      final now = DateTime.now();
      expect(timeUntil(now.subtract(const Duration(minutes: 1))), isNull);
      expect(timeUntil(now.add(const Duration(minutes: 10))), startsWith('след'));
    });
  });

  group('Потвърждение и почивки', () {
    test('състоянието на потвърждение се чете от базата', () {
      final e = ChurchEvent.fromRow({
        'id': 'x',
        'owner_id': 'a',
        'church_id': 'c',
        'assignee_id': 'b',
        'kind': 'krashtene',
        'starts_at': '2026-11-20T09:00:00Z',
        'visibility': 'church',
        'assignment_status': 'declined',
        'decline_reason': 'служба другаде',
        'proposed_substitute': 'c2',
        'declined_by': 'b',
      });
      expect(e.isDeclined, isTrue);
      expect(e.declineReason, 'служба другаде');
      expect(e.proposedSubstituteId, 'c2');
      expect(e.declinedById, 'b');
      // полетата за потвърждение не се пращат от приложението
      expect(e.toRow().containsKey('assignment_status'), isFalse);
    });
    test('почивката важи в дните си, включително последния', () {
      final l = LeaveRequest.fromRow({
        'id': 'l',
        'church_id': 'c',
        'user_id': 'b',
        'start_date': '2026-11-20',
        'end_date': '2026-11-22',
        'status': 'approved',
      });
      expect(l.days, 3);
      expect(l.covers(DateTime(2026, 11, 19, 23, 59)), isFalse);
      expect(l.covers(DateTime(2026, 11, 20, 8)), isTrue);
      expect(l.covers(DateTime(2026, 11, 22, 23, 59)), isTrue);
      expect(l.covers(DateTime(2026, 11, 23)), isFalse);
      expect(l.status, LeaveStatus.approved);
    });
  });
}
