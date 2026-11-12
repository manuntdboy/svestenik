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

  group('Сан пред името', () {
    test('о. се заменя със сана', () {
      expect(withRank(ClergyRank.archpriest, 'о. Тодор Чобанов'), 'Протойерей Тодор Чобанов');
      expect(withRank(ClergyRank.archpriest, 'о.Тодор Чобанов'), 'Протойерей Тодор Чобанов');
      expect(withRank(ClergyRank.stavrophor, 'Отец Георги'), 'Свещеноиконом Георги');
      expect(withRank(ClergyRank.priest, 'Иерей Иван'), 'Иерей Иван');
      expect(withRank(ClergyRank.archimandrite, 'Йеромонах Серафим'), 'Архимандрит Серафим');
      expect(withRank(ClergyRank.bishop, 'о. Николай'), 'Епископ Николай');
    });
    test('без сан името остава', () {
      expect(withRank(null, 'о. Тодор Чобанов'), 'о. Тодор Чобанов');
      final u = AppUser(id: '1', username: 't', fullName: 'Тодор Чобанов', rank: ClergyRank.deacon);
      expect(u.fullName, 'Дякон Тодор Чобанов');
      expect(u.name, 'Тодор Чобанов');
      expect(priestInitials(u.fullName), 'ТЧ');
      expect(ClergyRank.fromCode('protodeacon'), ClergyRank.protodeacon);
      expect(ClergyRank.fromCode('x'), isNull);
    });
  });

  group('Номер за Viber', () {
    test('български номера стават международни', () {
      expect(viberNumber('0888 123 456'), '+359888123456');
      expect(viberNumber('+359 888 123 456'), '+359888123456');
      expect(viberNumber('00359888123456'), '+359888123456');
      expect(viberNumber('359888123456'), '+359888123456');
      expect(viberNumber('0888-12-34-56'), '+359888123456');
      expect(viberNumber('123'), isNull);
    });
  });

  group('Адрес извън храма', () {
    test('пълен адрес и търсене в картата', () {
      final e = ev(outside: true)
        ..address = 'ул. Иван Вазов 12'
        ..addressExtra = 'бл. 5, ап. 9'
        ..addressTown = 'гр. Пловдив';
      expect(e.fullAddress, 'ул. Иван Вазов 12, бл. 5, ап. 9, гр. Пловдив');
      expect(e.placeLabel, e.fullAddress);
      expect(e.mapsQuery('гр. София'), 'ул. Иван Вазов 12, гр. Пловдив, България');
      e.addressTown = '';
      expect(e.mapsQuery('гр. София'), 'ул. Иван Вазов 12, гр. София, България');
      final back = ChurchEvent.fromRow({...e.toRow(), 'address_town': 'с. Белащица'});
      expect(back.addressTown, 'с. Белащица');
      expect(back.addressExtra, 'бл. 5, ап. 9');
    });
  });

  group('Архиерейска Литургия', () {
    test('6 часа и заема целия храм', () {
      expect(EventKind.arhiereyska.defaultMinutes, 360);
      expect(EventKind.arhiereyska.defaultStartHour, 8);
      expect(EventKind.arhiereyska.occupiesChurch, isTrue);
      expect(EventKind.krashtene.occupiesChurch, isFalse);
      expect(EventKind.fromName('arhiereyska'), EventKind.arhiereyska);
    });
  });

  group('Каса', () {
    CashEntry ce(CashBook b, double a, {String st = 'approved', String acc = 'cash', String? dir}) => CashEntry(
        id: 'x',
        churchId: 'c',
        book: b,
        amount: a,
        account: acc,
        direction: dir,
        category: 'Друго',
        date: DateTime(2026, 11, 13),
        createdBy: 'u',
        createdAt: DateTime(2026, 11, 13),
        status: st);
    test('балансът: приходи, разходи, сторно, банка', () {
      final list = [
        ce(CashBook.income, 50),
        ce(CashBook.income, -50), // сторно
        ce(CashBook.income, 20),
        ce(CashBook.expense, 80),
        ce(CashBook.expense, 200, st: 'pending'), // не се брои
        ce(CashBook.income, 1000, acc: 'bank'),
        ce(CashBook.transfer, 300, dir: 'to_bank'),
      ];
      final (cash, bank) = cashBalance(list);
      expect(cash, 20 - 80 - 300);
      expect(bank, 1000 + 300);
    });
    test('номер в книгата и вид', () {
      final e = CashEntry.fromRow({
        'id': '1', 'church_id': 'c', 'book': 'expense', 'number': 3, 'amount': 12.5,
        'category': 'Друго', 'category_other': 'Хор', 'entry_date': '2026-11-13',
        'created_by': 'u', 'created_at': '2026-11-13T10:00:00Z', 'status': 'approved',
      });
      expect(e.ref, 'Р-3');
      expect(e.categoryLabel, 'Хор');
      expect(incomeCategoryFor(EventKind.krashtene), 'Треби');
    });
  });
}
