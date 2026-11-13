// Модели на данните. Пазят се в Supabase (PostgreSQL).

/// Сан на свещенослужителя. Стои пред името: „Протойерей Тодор Чобанов“.
enum ClergyRank {
  deacon('deacon', 'Дякон'),
  hierodeacon('hierodeacon', 'Йеродякон'),
  protodeacon('protodeacon', 'Протодякон'),
  archdeacon('archdeacon', 'Архидякон'),
  priest('priest', 'Иерей'),
  hieromonk('hieromonk', 'Йеромонах'),
  archpriest('archpriest', 'Протойерей'),
  stavrophor('stavrophor', 'Свещеноиконом'),
  archimandrite('archimandrite', 'Архимандрит'),
  bishop('bishop', 'Епископ');

  final String code;
  final String label;
  const ClergyRank(this.code, this.label);

  static ClergyRank? fromCode(Object? c) =>
      ClergyRank.values.where((r) => r.code == c).firstOrNull;
}

/// Думи за обръщение/сан, които се махат от началото на името, когато
/// пред него стои избраният сан („о. Тодор“ → „Протойерей Тодор“).
const clergyTitleWords = {
  'о.', 'о', 'отец', 'свещеник', 'иерей', 'йерей', 'протойерей', 'протоиерей',
  'дякон', 'протодякон', 'свещеноиконом', 'ставрофор', 'йеродякон', 'иеродякон',
  'архидякон', 'йеромонах', 'иеромонах', 'архимандрит', 'епископ', 'владика',
};

String withRank(ClergyRank? rank, String name) {
  if (rank == null) return name;
  var words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  while (words.isNotEmpty) {
    final w = words.first.toLowerCase();
    if (clergyTitleWords.contains(w)) {
      words = words.sublist(1);
    } else if (w.startsWith('о.') && w.length > 2) {
      words = [words.first.substring(2), ...words.sublist(1)];
    } else {
      break;
    }
  }
  return words.isEmpty ? rank.label : '${rank.label} ${words.join(' ')}';
}

/// Номер за Viber: международен вид с „+“ (0888… → +359888…).
String? viberNumber(String phone) {
  var n = phone.replaceAll(RegExp(r'[^0-9+]'), '');
  if (n.startsWith('00')) n = '+${n.substring(2)}';
  if (n.startsWith('0')) n = '+359${n.substring(1)}';
  if (!n.startsWith('+')) n = n.startsWith('359') ? '+$n' : '+359$n';
  return RegExp(r'^\+[0-9]{8,15}$').hasMatch(n) ? n : null;
}

class AppUser {
  final String id;
  final String username;
  /// Името, както е въведено (без сана).
  final String name;
  final ClergyRank? rank;
  /// Телефон за колегите (по желание).
  final String phone;
  final String email;
  /// Коя версия на текста за личните данни е приел (0 = още не).
  final int privacyVersion;

  AppUser({
    required this.id,
    required this.username,
    required String fullName,
    this.rank,
    this.phone = '',
    this.email = '',
    this.privacyVersion = 0,
  }) : name = fullName;

  /// Името за показване – със сана отпред, ако е избран.
  String get fullName => withRank(rank, name);

  factory AppUser.fromRow(Map<String, dynamic> r, {String email = ''}) => AppUser(
        id: r['id'] as String,
        username: r['username'] as String,
        fullName: r['full_name'] as String,
        rank: ClergyRank.fromCode(r['rank']),
        phone: (r['phone'] as String?) ?? '',
        email: email,
        privacyVersion: (r['privacy_version'] as num?)?.toInt() ?? 0,
      );
}

class Church {
  final String id;
  final String name;
  final String settlement;
  final String municipality;
  String joinCode;
  final String? pendingChairId; // предложен за председател, чака отговор
  final String? chairProposedById;

  Church({
    required this.id,
    required this.name,
    required this.settlement,
    required this.municipality,
    required this.joinCode,
    this.pendingChairId,
    this.chairProposedById,
  });

  String get place => '$settlement, общ. $municipality';

  factory Church.fromRow(Map<String, dynamic> r) => Church(
        id: r['id'] as String,
        name: r['name'] as String,
        settlement: r['settlement'] as String,
        municipality: r['municipality'] as String,
        joinCode: r['join_code'] as String,
        pendingChairId: r['pending_chair'] as String?,
        chairProposedById: r['chair_proposed_by'] as String?,
      );
}

class Membership {
  final String churchId;
  final String userId;
  final String role; // 'manager' (председател) или 'priest'
  final DateTime joinedAt;
  final String status; // 'active' или 'pending' (чака одобрение)
  final List<String> permissions; // напр. 'cash' = касиер

  Membership(
      {required this.churchId,
      required this.userId,
      required this.role,
      DateTime? joinedAt,
      this.status = 'active',
      this.permissions = const []})
      : joinedAt = joinedAt ?? DateTime(2000);

  bool get isManager => role == 'manager' && isActive;
  bool get isActive => status == 'active';
  bool get isPending => status == 'pending';
  bool get isCashier => permissions.contains('cash');

  factory Membership.fromRow(Map<String, dynamic> r) => Membership(
        churchId: r['church_id'] as String,
        userId: r['user_id'] as String,
        role: r['role'] as String,
        joinedAt: DateTime.tryParse((r['joined_at'] as String?) ?? ''),
        status: (r['status'] as String?) ?? 'active',
        permissions: ((r['permissions'] as List?) ?? const []).cast<String>(),
      );
}

enum EventKind {
  krashtene('Кръщене'),
  venchavka('Венчавка'),
  pogrebenie('Погребение'),
  panihida('Панихида'),
  vodosvet('Водосвет'),
  sluzhba('Служба'),
  arhiereyska('Архиерейска Литургия'),
  izpoved('Изповед'),
  maslosvet('Маслосвет'),
  kurban('Курбан'),
  drugo('Друго');

  final String label;
  const EventKind(this.label);

  /// Водосветът по подразбиране е извън храма.
  bool get defaultOutside => this == EventKind.vodosvet;

  /// Продължителност по подразбиране за вида (минути). Начални стойности –
  /// лесно се сменят тук.
  int get defaultMinutes => switch (this) {
        EventKind.krashtene => 60,
        EventKind.venchavka => 60,
        EventKind.pogrebenie => 60,
        EventKind.panihida => 30,
        EventKind.vodosvet => 30,
        EventKind.sluzhba => 120,
        EventKind.arhiereyska => 360, // 08:00–14:00
        EventKind.izpoved => 30,
        EventKind.maslosvet => 60,
        EventKind.kurban => 30,
        EventKind.drugo => 30,
      };

  /// Заема целия храм: всяко друго събитие в храма по това време получава
  /// предупреждение (но може да се запише).
  bool get occupiesChurch => this == EventKind.arhiereyska;

  /// Час на започване по подразбиране (само за някои видове).
  int? get defaultStartHour => this == EventKind.arhiereyska ? 8 : null;

  static EventKind fromName(String n) =>
      EventKind.values.firstWhere((k) => k.name == n, orElse: () => EventKind.drugo);
}

/// Потвърждение от свещеника, за когото е записано събитието.
enum AssignmentStatus {
  pending, // чака свещеника
  accepted, // прието (или записано за себе си)
  declined; // отказано – решава председателят

  static AssignmentStatus fromName(String? n) =>
      AssignmentStatus.values.firstWhere((s) => s.name == n, orElse: () => AssignmentStatus.accepted);
}

/// Състояние на събитието.
enum EventStatus {
  planned('Предстои'),
  done('Проведено'),
  cancelled('Отменено');

  final String label;
  const EventStatus(this.label);

  static EventStatus fromName(String? n) =>
      EventStatus.values.firstWhere((s) => s.name == n, orElse: () => EventStatus.planned);
}

/// Продължителност на събитие по подразбиране и стъпка за промяна (минути).
const defaultDurationMinutes = 30;
const durationStepMinutes = 15;
const minDurationMinutes = 15;
const maxDurationMinutes = 12 * 60;

/// „30 мин“, „1 ч“, „1 ч 15 мин“
String fmtDuration(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '$m мин';
  if (m == 0) return '$h ч';
  return '$h ч $m мин';
}

/// Варианти за напомняне (в минути). null = без напомняне.
const reminderOptions = <int?, String>{
  null: 'Без напомняне',
  15: '15 минути преди',
  30: '30 минути преди',
  60: '1 час преди',
  120: '2 часа преди',
  1440: '1 ден преди',
};

class ChurchEvent {
  final String id;
  final String ownerId; // кой е записал събитието
  final String churchId;
  String assigneeId; // кой свещеник ще го извърши
  EventKind kind;
  DateTime startsAt;
  int durationMinutes;
  String forWhom;
  String phone;
  bool outsideChurch;
  String address; // улица / квартал и номер
  String addressTown; // населено място
  String addressExtra; // блок, вход, етаж, ап.
  int? remindMinutes;
  bool alarm; // true = напомнянето звъни като будилник
  bool shared; // false = лично, true = споделено с храма
  String note;
  EventStatus status;
  // Попълват се от сървъра (само през функциите за потвърждение).
  AssignmentStatus assignment;
  String declineReason;
  String? proposedSubstituteId;
  String? declinedById;
  DateTime? seenAt; // кога свещеникът е видял молбата

  ChurchEvent({
    required this.id,
    required this.ownerId,
    required this.churchId,
    String? assigneeId,
    required this.kind,
    required this.startsAt,
    this.durationMinutes = defaultDurationMinutes,
    this.forWhom = '',
    this.phone = '',
    this.outsideChurch = false,
    this.address = '',
    this.addressTown = '',
    this.addressExtra = '',
    this.remindMinutes = 60,
    this.alarm = false,
    this.shared = false,
    this.note = '',
    this.status = EventStatus.planned,
    this.assignment = AssignmentStatus.accepted,
    this.declineReason = '',
    this.proposedSubstituteId,
    this.declinedById,
    this.seenAt,
  }) : assigneeId = assigneeId ?? ownerId;

  DateTime get endsAt => startsAt.add(Duration(minutes: durationMinutes));

  /// Застъпват ли се двете събития по време (допиране не се брои).
  bool overlaps(ChurchEvent other) =>
      startsAt.isBefore(other.endsAt) && other.startsAt.isBefore(endsAt);

  bool get isCancelled => status == EventStatus.cancelled;
  bool get awaitsConfirmation => assignment == AssignmentStatus.pending;
  bool get isDeclined => assignment == AssignmentStatus.declined;
  bool get isAccepted => assignment == AssignmentStatus.accepted;
  bool get isDone => status == EventStatus.done;

  /// Копие за нова дата: същите данни, ново събитие, записано от [ownerId].
  ChurchEvent copyAs({required String id, required String ownerId}) => ChurchEvent(
        id: id,
        ownerId: ownerId,
        churchId: churchId,
        assigneeId: assigneeId,
        kind: kind,
        startsAt: startsAt,
        durationMinutes: durationMinutes,
        forWhom: forWhom,
        phone: phone,
        outsideChurch: outsideChurch,
        address: address,
        addressTown: addressTown,
        addressExtra: addressExtra,
        remindMinutes: remindMinutes,
        alarm: alarm,
        shared: shared,
        note: note,
      );

  /// Пълният адрес за показване: улица, блок/ап., населено място.
  String get fullAddress =>
      [address, addressExtra, addressTown].map((x) => x.trim()).where((x) => x.isNotEmpty).join(', ');

  /// Текст за търсене в картата (без блок/апартамент, които я объркват).
  String mapsQuery(String fallbackTown) => [
        address.trim(),
        addressTown.trim().isNotEmpty ? addressTown.trim() : fallbackTown.trim(),
        'България',
      ].where((x) => x.isNotEmpty).join(', ');

  String get placeLabel => outsideChurch
      ? (fullAddress.isEmpty ? 'Извън храма' : fullAddress)
      : 'В храма';

  Map<String, dynamic> toJson() => {
        'id': id,
        'ownerId': ownerId,
        'churchId': churchId,
        'kind': kind.name,
        'startsAt': startsAt.toIso8601String(),
        'durationMinutes': durationMinutes,
        'forWhom': forWhom,
        'phone': phone,
        'outsideChurch': outsideChurch,
        'address': address,
        'address_town': addressTown.isEmpty ? null : addressTown,
        'address_extra': addressExtra.isEmpty ? null : addressExtra,
        'remindMinutes': remindMinutes,
        'alarm': alarm,
        'shared': shared,
        'note': note,
      };

  /// Ред за таблица `events` в Supabase.
  Map<String, dynamic> toRow() => {
        'id': id,
        'owner_id': ownerId,
        'church_id': churchId,
        'assignee_id': assigneeId,
        'kind': kind.name,
        'starts_at': startsAt.toUtc().toIso8601String(),
        'duration_minutes': durationMinutes,
        'for_whom': forWhom,
        'contact_phone': phone,
        'outside_church': outsideChurch,
        'address': address,
        'address_town': addressTown,
        'address_extra': addressExtra,
        'remind_minutes': remindMinutes,
        'alarm': alarm,
        'visibility': shared ? 'church' : 'private',
        'note': note,
        'status': status.name,
      };

  factory ChurchEvent.fromRow(Map<String, dynamic> r) => ChurchEvent(
        id: r['id'] as String,
        ownerId: r['owner_id'] as String,
        churchId: r['church_id'] as String,
        assigneeId: r['assignee_id'] as String?,
        kind: EventKind.fromName(r['kind'] as String),
        startsAt: DateTime.parse(r['starts_at'] as String).toLocal(),
        durationMinutes: (r['duration_minutes'] as int?) ?? defaultDurationMinutes,
        forWhom: (r['for_whom'] as String?) ?? '',
        phone: (r['contact_phone'] as String?) ?? '',
        outsideChurch: (r['outside_church'] as bool?) ?? false,
        address: (r['address'] as String?) ?? '',
        addressTown: (r['address_town'] as String?) ?? '',
        addressExtra: (r['address_extra'] as String?) ?? '',
        remindMinutes: r['remind_minutes'] as int?,
        alarm: (r['alarm'] as bool?) ?? false,
        shared: r['visibility'] == 'church',
        note: (r['note'] as String?) ?? '',
        status: EventStatus.fromName(r['status'] as String?),
        assignment: AssignmentStatus.fromName(r['assignment_status'] as String?),
        declineReason: (r['decline_reason'] as String?) ?? '',
        proposedSubstituteId: r['proposed_substitute'] as String?,
        declinedById: r['declined_by'] as String?,
        seenAt: DateTime.tryParse((r['seen_at'] as String?) ?? '')?.toLocal(),
      );

  factory ChurchEvent.fromJson(Map<String, dynamic> j) => ChurchEvent(
        id: j['id'] as String,
        ownerId: j['ownerId'] as String,
        churchId: j['churchId'] as String,
        kind: EventKind.fromName(j['kind'] as String),
        startsAt: DateTime.parse(j['startsAt'] as String),
        // По-старите записи нямат продължителност – приемаме 30 минути.
        durationMinutes: (j['durationMinutes'] as int?) ?? defaultDurationMinutes,
        forWhom: (j['forWhom'] as String?) ?? '',
        phone: (j['phone'] as String?) ?? '',
        outsideChurch: (j['outsideChurch'] as bool?) ?? false,
        address: (j['address'] as String?) ?? '',
        addressTown: (j['address_town'] as String?) ?? '',
        addressExtra: (j['address_extra'] as String?) ?? '',
        remindMinutes: j['remindMinutes'] as int?,
        alarm: (j['alarm'] as bool?) ?? false,
        shared: (j['shared'] as bool?) ?? false,
        note: (j['note'] as String?) ?? '',
      );
}

/// Личен профил на свещеника (вижда го само той).
class ProfileDetails {
  String threeNames;
  DateTime? birthDate;
  DateTime? ordinationDate;
  int? nameDayMonth;
  int? nameDayDay;
  String? photoPath;

  ProfileDetails({
    this.threeNames = '',
    this.birthDate,
    this.ordinationDate,
    this.nameDayMonth,
    this.nameDayDay,
    this.photoPath,
  });

  bool get hasNameDay => nameDayMonth != null && nameDayDay != null;

  static DateTime? _date(Object? v) => v == null ? null : DateTime.tryParse(v as String);
  static String? _iso(DateTime? d) => d == null
      ? null
      : '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  factory ProfileDetails.fromRow(Map<String, dynamic> r) => ProfileDetails(
        threeNames: (r['three_names'] as String?) ?? '',
        birthDate: _date(r['birth_date']),
        ordinationDate: _date(r['ordination_date']),
        nameDayMonth: r['name_day_month'] as int?,
        nameDayDay: r['name_day_day'] as int?,
        photoPath: r['photo_path'] as String?,
      );

  Map<String, dynamic> toRow() => {
        'three_names': threeNames.trim().isEmpty ? null : threeNames.trim(),
        'birth_date': _iso(birthDate),
        'ordination_date': _iso(ordinationDate),
        'name_day_month': nameDayMonth,
        'name_day_day': nameDayDay,
        'photo_path': photoPath,
      };

  ProfileDetails copy() => ProfileDetails(
        threeNames: threeNames,
        birthDate: birthDate,
        ordinationDate: ordinationDate,
        nameDayMonth: nameDayMonth,
        nameDayDay: nameDayDay,
        photoPath: photoPath,
      );

  /// След колко дни е следващият имен ден (0 = днес).
  int? daysToNameDay([DateTime? from]) {
    if (!hasNameDay) return null;
    final now = from ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    DateTime at(int year) {
      var d = nameDayDay!;
      // 29 февруари в невисокосна година се празнува на 28-и.
      final last = DateTime(year, nameDayMonth! + 1, 0).day;
      if (d > last) d = last;
      return DateTime(year, nameDayMonth!, d);
    }

    var next = at(today.year);
    if (next.isBefore(today)) next = at(today.year + 1);
    return next.difference(today).inDays;
  }
}

/// Заявка за почивка.
enum LeaveStatus {
  pending('Чака одобрение'),
  approved('Одобрена'),
  rejected('Неодобрена'),
  ended('Отменена');

  final String label;
  const LeaveStatus(this.label);

  static LeaveStatus fromName(String? n) =>
      LeaveStatus.values.firstWhere((s) => s.name == n, orElse: () => LeaveStatus.pending);
}

class LeaveRequest {
  final String id;
  final String churchId;
  final String userId;
  final DateTime start; // само дата
  final DateTime end; // само дата, включително
  final String note;
  final LeaveStatus status;
  final String decisionNote; // коментар на председателя при решението
  final String endNote; // коментар при прекратяване/отмяна
  final DateTime? plannedEnd; // първоначален край, ако е прекратена по-рано
  final DateTime? endedAt;
  final String? decidedBy;
  final String? endedBy;
  final bool decisionSeen; // свещеникът е натиснал „ОК“ на решението

  LeaveRequest({
    required this.id,
    required this.churchId,
    required this.userId,
    required this.start,
    required this.end,
    this.note = '',
    this.status = LeaveStatus.pending,
    this.decisionNote = '',
    this.endNote = '',
    this.plannedEnd,
    this.endedAt,
    this.decidedBy,
    this.endedBy,
    this.decisionSeen = true,
  });

  /// Одобрена, но председателят я е прекратил преди края.
  bool get cutShort => status == LeaveStatus.approved && plannedEnd != null;

  /// Текст за значката: „Прекратена“ за съкратена одобрена почивка.
  String get statusLabel => cutShort ? 'Прекратена' : status.label;

  bool covers(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    return !d.isBefore(start) && !d.isAfter(end);
  }

  int get days => end.difference(start).inDays + 1;

  static DateTime _d(String s) {
    final p = DateTime.parse(s);
    return DateTime(p.year, p.month, p.day);
  }

  factory LeaveRequest.fromRow(Map<String, dynamic> r) => LeaveRequest(
        id: r['id'] as String,
        churchId: r['church_id'] as String,
        userId: r['user_id'] as String,
        start: _d(r['start_date'] as String),
        end: _d(r['end_date'] as String),
        note: (r['note'] as String?) ?? '',
        status: LeaveStatus.fromName(r['status'] as String?),
        decisionNote: (r['decision_note'] as String?) ?? '',
        endNote: (r['end_note'] as String?) ?? '',
        plannedEnd: r['planned_end'] == null ? null : _d(r['planned_end'] as String),
        endedAt: r['ended_at'] == null ? null : DateTime.tryParse(r['ended_at'] as String)?.toLocal(),
        decidedBy: r['decided_by'] as String?,
        endedBy: r['ended_by'] as String?,
        decisionSeen: r['decision_seen_at'] != null,
      );
}

// ---------------------------------------------------------------------
// Каса
// ---------------------------------------------------------------------
enum CashBook {
  income('Приход', 'Приходна книга', 'П'),
  expense('Разход', 'Разходна книга', 'Р'),
  transfer('Банка', 'Движения с банката', 'Б'),
  opening('Начално салдо', 'Начално салдо', 'Н');

  final String label;
  final String bookName;
  final String prefix;
  const CashBook(this.label, this.bookName, this.prefix);

  static CashBook fromName(String? n) =>
      CashBook.values.firstWhere((b) => b.name == n, orElse: () => CashBook.income);
}

const incomeCategories = [
  'Свещи',
  'Треби',
  'Дарение',
  'Записки и помени',
  'Наем',
  'Друго',
];

const expenseCategories = [
  'Заплати и възнаграждения',
  'Ток',
  'Вода',
  'Отопление',
  'Ремонти и поддръжка',
  'Свещи (доставка)',
  'Вноска към митрополията',
  'Канцеларски',
  'Друго',
];

/// Вид приход по подразбиране за проведено събитие.
String incomeCategoryFor(EventKind k) => switch (k) {
      EventKind.sluzhba || EventKind.arhiereyska => 'Свещи',
      EventKind.panihida => 'Записки и помени',
      EventKind.drugo => 'Друго',
      _ => 'Треби',
    };

class CashEntry {
  final String id;
  final String churchId;
  final CashBook book;
  final int? number;
  final double amount; // сторното е с отрицателна сума
  final String account; // 'cash' или 'bank'
  final String? direction; // 'to_bank' / 'from_bank' за движенията с банката
  final String category;
  final String categoryOther;
  final String note;
  final DateTime date;
  final String? eventId;
  final String createdBy;
  final DateTime createdAt;
  final String status; // pending / approved / returned
  final String? autoReason; // holder / under_limit / single
  final String? decidedBy;
  final String returnReason;
  final String? reverses;
  final String? reversedBy;
  final bool backdated; // със задна дата в приключен месец
  final String donor; // дарител (по желание) при „Дарение“

  CashEntry({
    required this.id,
    required this.churchId,
    required this.book,
    this.number,
    required this.amount,
    this.account = 'cash',
    this.direction,
    required this.category,
    this.categoryOther = '',
    this.note = '',
    required this.date,
    this.eventId,
    required this.createdBy,
    required this.createdAt,
    this.status = 'pending',
    this.autoReason,
    this.decidedBy,
    this.returnReason = '',
    this.reverses,
    this.reversedBy,
    this.backdated = false,
    this.decidedAt,
    this.donor = '',
    this.returnSeen = true,
  });

  final DateTime? decidedAt;
  final bool returnSeen; // създателят е натиснал „ОК“ на върнатия запис

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isReturned => status == 'returned';
  bool get isReversal => reverses != null;

  /// „П-12“, „Р-3“ – номерът в книгата (след влизане в нея).
  String get ref => number == null ? '' : '${book.prefix}-$number';

  String get categoryLabel => book == CashBook.opening
      ? (account == 'bank' ? 'Начално салдо · банка' : 'Начално салдо · брой')
      : category == 'Друго' && categoryOther.isNotEmpty ? categoryOther : category;

  String get kindLabel => isReversal
      ? 'Сторно'
      : book == CashBook.transfer
          ? (direction == 'from_bank' ? 'Теглене от банката' : 'Внасяне в банката')
          : book.label;

  /// Как се отразява на брой и банка (само одобрените).
  (double cash, double bank) get effect {
    if (!isApproved) return (0, 0);
    switch (book) {
      case CashBook.income:
      case CashBook.opening:
        return account == 'bank' ? (0, amount) : (amount, 0);
      case CashBook.expense:
        return account == 'bank' ? (0, -amount) : (-amount, 0);
      case CashBook.transfer:
        return direction == 'from_bank' ? (amount, -amount) : (-amount, amount);
    }
  }

  factory CashEntry.fromRow(Map<String, dynamic> r) => CashEntry(
        id: r['id'] as String,
        churchId: r['church_id'] as String,
        book: CashBook.fromName(r['book'] as String?),
        number: r['number'] as int?,
        amount: (r['amount'] as num).toDouble(),
        account: (r['account'] as String?) ?? 'cash',
        direction: r['direction'] as String?,
        category: (r['category'] as String?) ?? 'Друго',
        categoryOther: (r['category_other'] as String?) ?? '',
        note: (r['note'] as String?) ?? '',
        date: DateTime.parse(r['entry_date'] as String),
        eventId: r['event_id'] as String?,
        createdBy: (r['created_by'] as String?) ?? '',
        createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
        status: (r['status'] as String?) ?? 'pending',
        autoReason: r['auto_reason'] as String?,
        decidedBy: r['decided_by'] as String?,
        returnReason: (r['return_reason'] as String?) ?? '',
        reverses: r['reverses'] as String?,
        reversedBy: r['reversed_by'] as String?,
        backdated: (r['backdated'] as bool?) ?? false,
        donor: (r['donor'] as String?) ?? '',
        decidedAt: r['decided_at'] == null ? null : DateTime.parse(r['decided_at'] as String).toLocal(),
        returnSeen: r['return_seen_at'] != null,
      );
}

/// Месец в касата: чака одобрение или приключен.
class CashPeriod {
  final String churchId;
  final DateTime month; // първо число
  final String status; // pending / closed
  final String? requestedBy;
  final DateTime requestedAt;
  final String? approvedBy;
  final DateTime? approvedAt;
  final bool single;

  CashPeriod({
    required this.churchId,
    required this.month,
    required this.status,
    this.requestedBy,
    required this.requestedAt,
    this.approvedBy,
    this.approvedAt,
    this.single = false,
  });

  bool get isClosed => status == 'closed';

  factory CashPeriod.fromRow(Map<String, dynamic> r) => CashPeriod(
        churchId: r['church_id'] as String,
        month: DateTime.parse(r['month'] as String),
        status: (r['status'] as String?) ?? 'pending',
        requestedBy: r['requested_by'] as String?,
        requestedAt: DateTime.parse(r['requested_at'] as String).toLocal(),
        approvedBy: r['approved_by'] as String?,
        approvedAt: r['approved_at'] == null ? null : DateTime.parse(r['approved_at'] as String).toLocal(),
        single: (r['single'] as bool?) ?? false,
      );
}

/// Сума по вид за одобрените записи от книга в период [from, to).
Map<String, double> cashByCategory(Iterable<CashEntry> entries, CashBook book, DateTime from, DateTime to) {
  final m = <String, double>{};
  for (final e in entries) {
    if (!e.isApproved || e.book != book || e.date.isBefore(from) || !e.date.isBefore(to)) continue;
    m[e.categoryLabel] = (m[e.categoryLabel] ?? 0) + e.amount;
  }
  m.removeWhere((_, v) => v.abs() < 0.005);
  return m;
}

double cashTotal(Iterable<CashEntry> entries, CashBook book, DateTime from, DateTime to) =>
    cashByCategory(entries, book, from, to).values.fold(0.0, (a, b) => a + b);

class CashSettings {
  final double limitEur;
  final bool hasBank;
  /// Временно изключено второ одобрение (за проба) – всичко влиза веднага.
  final bool approvalsOff;
  const CashSettings({this.limitEur = 100, this.hasBank = false, this.approvalsOff = false});

  factory CashSettings.fromRow(Map<String, dynamic> r) => CashSettings(
        limitEur: (r['limit_eur'] as num?)?.toDouble() ?? 100,
        hasBank: (r['has_bank'] as bool?) ?? false,
        approvalsOff: (r['approvals_off'] as bool?) ?? false,
      );
}

/// Баланс на касата: брой, банка и общо.
(double cash, double bank) cashBalance(Iterable<CashEntry> entries) {
  var c = 0.0, b = 0.0;
  for (final e in entries) {
    final (dc, db) = e.effect;
    c += dc;
    b += db;
  }
  return (c, b);
}

// ---------------------------------------------------------------------
// Склад
// ---------------------------------------------------------------------
enum StockSection { candles, papers }

enum StockItem {
  candle020('candle_020', 'Свещи 0,20 €', StockSection.candles, 5),
  candle050('candle_050', 'Свещи 0,50 €', StockSection.candles, 5),
  candle1('candle_1', 'Свещи 1 €', StockSection.candles, 3),
  candle2('candle_2', 'Свещи 2 €', StockSection.candles, 2),
  candle4('candle_4', 'Свещи 4 €', StockSection.candles, 1),
  certBaptism('cert_baptism', 'Кръщелни свидетелства', StockSection.papers, 10),
  certWedding('cert_wedding', 'Венчални свидетелства', StockSection.papers, 10),
  diploma('diploma', 'Грамоти', StockSection.papers, 10);

  final String code;
  final String label;
  final StockSection section;
  final int defaultMin;
  const StockItem(this.code, this.label, this.section, this.defaultMin);

  String get unit => section == StockSection.candles ? 'кг' : 'бр.';
  String qty(int n) => '$n $unit';

  static StockItem? fromCode(String? c) => StockItem.values.where((i) => i.code == c).firstOrNull;
}

/// Какво изписва от склада проведеното събитие.
Map<StockItem, int> stockForEvent(EventKind k) => switch (k) {
      EventKind.krashtene => {StockItem.certBaptism: 1},
      EventKind.venchavka => {StockItem.certWedding: 2, StockItem.diploma: 1},
      _ => const {},
    };

class StockMove {
  final String id;
  final String churchId;
  final StockItem item;
  final int qty; // + влиза, − излиза
  final String kind; // load / writeoff / event / event_return
  final String? eventId;
  final String note;
  final String createdBy;
  final DateTime createdAt;
  final String status;
  final String? autoReason;
  final String? decidedBy;
  final DateTime? decidedAt;
  final String returnReason;

  StockMove({
    required this.id,
    required this.churchId,
    required this.item,
    required this.qty,
    required this.kind,
    this.eventId,
    this.note = '',
    required this.createdBy,
    required this.createdAt,
    this.status = 'approved',
    this.autoReason,
    this.decidedBy,
    this.decidedAt,
    this.returnReason = '',
  });

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isReturned => status == 'returned';

  String get kindLabel => switch (kind) {
        'load' => 'Зареждане',
        'writeoff' => 'Изписване',
        'event' => 'Проведено събитие',
        _ => 'Върнато от събитие',
      };

  factory StockMove.fromRow(Map<String, dynamic> r) => StockMove(
        id: r['id'] as String,
        churchId: r['church_id'] as String,
        item: StockItem.fromCode(r['item'] as String?) ?? StockItem.diploma,
        qty: (r['qty'] as num).toInt(),
        kind: (r['kind'] as String?) ?? 'load',
        eventId: r['event_id'] as String?,
        note: (r['note'] as String?) ?? '',
        createdBy: (r['created_by'] as String?) ?? '',
        createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
        status: (r['status'] as String?) ?? 'approved',
        autoReason: r['auto_reason'] as String?,
        decidedBy: r['decided_by'] as String?,
        decidedAt: r['decided_at'] == null ? null : DateTime.parse(r['decided_at'] as String).toLocal(),
        returnReason: (r['return_reason'] as String?) ?? '',
      );
}

/// Наличност по вид (само одобрените движения).
Map<StockItem, int> stockBalances(Iterable<StockMove> moves) {
  final m = {for (final i in StockItem.values) i: 0};
  for (final mv in moves) {
    if (mv.isApproved) m[mv.item] = m[mv.item]! + mv.qty;
  }
  return m;
}

/// Ревизия: преброено срещу книгата. Само проверка – не мени наличността.
class StockAudit {
  final String id;
  final String churchId;
  final String batch;
  final StockItem item;
  final int counted;
  final int bookQty;
  final String note;
  final String createdBy;
  final DateTime createdAt;

  StockAudit({
    required this.id,
    required this.churchId,
    required this.batch,
    required this.item,
    required this.counted,
    required this.bookQty,
    this.note = '',
    required this.createdBy,
    required this.createdAt,
  });

  int get diff => counted - bookQty;

  factory StockAudit.fromRow(Map<String, dynamic> r) => StockAudit(
        id: r['id'] as String,
        churchId: r['church_id'] as String,
        batch: r['batch'] as String,
        item: StockItem.fromCode(r['item'] as String?) ?? StockItem.diploma,
        counted: (r['counted'] as num).toInt(),
        bookQty: (r['book_qty'] as num).toInt(),
        note: (r['note'] as String?) ?? '',
        createdBy: (r['created_by'] as String?) ?? '',
        createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
      );
}

// ---------------------------------------------------------------------
// График на дежурствата
// ---------------------------------------------------------------------

DateTime _dateOf(String s) {
  final p = DateTime.parse(s);
  return DateTime(p.year, p.month, p.day);
}

/// Дежурство: свещеник от начало до край (включително).
class Duty {
  final String id;
  final String churchId;
  final String userId;
  final DateTime start;
  final DateTime end;
  final String note;

  Duty({
    required this.id,
    required this.churchId,
    required this.userId,
    required this.start,
    required this.end,
    this.note = '',
  });

  bool covers(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    return !d.isBefore(start) && !d.isAfter(end);
  }

  int get days => end.difference(start).inDays + 1;

  bool overlaps(DateTime a, DateTime b) => !start.isAfter(b) && !end.isBefore(a);

  factory Duty.fromRow(Map<String, dynamic> r) => Duty(
        id: r['id'] as String,
        churchId: r['church_id'] as String,
        userId: r['user_id'] as String,
        start: _dateOf(r['start_date'] as String),
        end: _dateOf(r['end_date'] as String),
        note: (r['note'] as String?) ?? '',
      );
}

/// Размяна на дежурства: колегата приема → председателят одобрява.
class DutySwap {
  final String id;
  final String churchId;
  final String fromDuty;
  final String toDuty;
  final String fromUser;
  final String toUser;
  final String note;
  final String status; // peer / chair / approved / rejected / cancelled
  final String reason;
  final DateTime createdAt;

  DutySwap({
    required this.id,
    required this.churchId,
    required this.fromDuty,
    required this.toDuty,
    required this.fromUser,
    required this.toUser,
    this.note = '',
    required this.status,
    this.reason = '',
    required this.createdAt,
  });

  bool get isOpen => status == 'peer' || status == 'chair';

  String get statusLabel => switch (status) {
        'peer' => 'чака колегата',
        'chair' => 'чака председателя',
        'approved' => 'одобрена',
        'rejected' => 'не е приета',
        _ => 'оттеглена',
      };

  factory DutySwap.fromRow(Map<String, dynamic> r) => DutySwap(
        id: r['id'] as String,
        churchId: r['church_id'] as String,
        fromDuty: r['from_duty'] as String,
        toDuty: r['to_duty'] as String,
        fromUser: r['from_user'] as String,
        toUser: r['to_user'] as String,
        note: (r['note'] as String?) ?? '',
        status: (r['status'] as String?) ?? 'peer',
        reason: (r['reason'] as String?) ?? '',
        createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
      );
}
