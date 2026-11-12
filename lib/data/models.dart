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

  AppUser({
    required this.id,
    required this.username,
    required String fullName,
    this.rank,
    this.phone = '',
    this.email = '',
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
        EventKind.izpoved => 30,
        EventKind.maslosvet => 60,
        EventKind.kurban => 30,
        EventKind.drugo => 30,
      };

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
  String address;
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
        remindMinutes: remindMinutes,
        alarm: alarm,
        shared: shared,
        note: note,
      );

  String get placeLabel => outsideChurch
      ? (address.isEmpty ? 'Извън храма' : address)
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
  rejected('Неодобрена');

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

  LeaveRequest({
    required this.id,
    required this.churchId,
    required this.userId,
    required this.start,
    required this.end,
    this.note = '',
    this.status = LeaveStatus.pending,
  });

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
      );
}
