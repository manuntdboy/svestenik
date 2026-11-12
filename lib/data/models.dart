// Модели на данните. Пазят се в Supabase (PostgreSQL).

class AppUser {
  final String id;
  final String username;
  final String fullName;
  final String email;

  AppUser({required this.id, required this.username, required this.fullName, this.email = ''});

  factory AppUser.fromRow(Map<String, dynamic> r, {String email = ''}) => AppUser(
        id: r['id'] as String,
        username: r['username'] as String,
        fullName: r['full_name'] as String,
        email: email,
      );
}

class Church {
  final String id;
  final String name;
  final String settlement;
  final String municipality;
  String joinCode;

  Church({
    required this.id,
    required this.name,
    required this.settlement,
    required this.municipality,
    required this.joinCode,
  });

  String get place => '$settlement, общ. $municipality';

  factory Church.fromRow(Map<String, dynamic> r) => Church(
        id: r['id'] as String,
        name: r['name'] as String,
        settlement: r['settlement'] as String,
        municipality: r['municipality'] as String,
        joinCode: r['join_code'] as String,
      );
}

class Membership {
  final String churchId;
  final String userId;
  final String role; // 'manager' (председател) или 'priest'
  final DateTime joinedAt;

  Membership({required this.churchId, required this.userId, required this.role, DateTime? joinedAt})
      : joinedAt = joinedAt ?? DateTime(2000);

  bool get isManager => role == 'manager';

  factory Membership.fromRow(Map<String, dynamic> r) => Membership(
        churchId: r['church_id'] as String,
        userId: r['user_id'] as String,
        role: r['role'] as String,
        joinedAt: DateTime.tryParse((r['joined_at'] as String?) ?? ''),
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

  static EventKind fromName(String n) =>
      EventKind.values.firstWhere((k) => k.name == n, orElse: () => EventKind.drugo);
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
  }) : assigneeId = assigneeId ?? ownerId;

  DateTime get endsAt => startsAt.add(Duration(minutes: durationMinutes));

  /// Застъпват ли се двете събития по време (допиране не се брои).
  bool overlaps(ChurchEvent other) =>
      startsAt.isBefore(other.endsAt) && other.startsAt.isBefore(endsAt);

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
