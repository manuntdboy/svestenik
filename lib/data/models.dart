// Модели на данните. В тестовата версия се пазят като JSON на телефона.

class AppUser {
  final String id;
  final String username;
  final String fullName;
  final String email;
  final String passwordHash;
  final String salt;

  AppUser({
    required this.id,
    required this.username,
    required this.fullName,
    required this.email,
    required this.passwordHash,
    required this.salt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'fullName': fullName,
        'email': email,
        'passwordHash': passwordHash,
        'salt': salt,
      };

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: j['id'] as String,
        username: j['username'] as String,
        fullName: j['fullName'] as String,
        email: (j['email'] as String?) ?? '',
        passwordHash: j['passwordHash'] as String,
        salt: j['salt'] as String,
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

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'settlement': settlement,
        'municipality': municipality,
        'joinCode': joinCode,
      };

  factory Church.fromJson(Map<String, dynamic> j) => Church(
        id: j['id'] as String,
        name: j['name'] as String,
        settlement: j['settlement'] as String,
        municipality: j['municipality'] as String,
        joinCode: j['joinCode'] as String,
      );
}

class Membership {
  final String churchId;
  final String userId;
  final String role; // 'manager' или 'priest'

  Membership({required this.churchId, required this.userId, required this.role});

  bool get isManager => role == 'manager';

  Map<String, dynamic> toJson() =>
      {'churchId': churchId, 'userId': userId, 'role': role};

  factory Membership.fromJson(Map<String, dynamic> j) => Membership(
        churchId: j['churchId'] as String,
        userId: j['userId'] as String,
        role: j['role'] as String,
      );
}

enum EventKind {
  krashtene('Кръщене'),
  venchavka('Венчавка'),
  pogrebenie('Погребение'),
  panihida('Панихида'),
  vodosvet('Водосвет'),
  sluzhba('Служба'),
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
  final String ownerId;
  final String churchId;
  EventKind kind;
  DateTime startsAt;
  int durationMinutes;
  String forWhom;
  String phone;
  bool outsideChurch;
  String address;
  int? remindMinutes;
  bool shared; // false = лично, true = споделено с храма
  String note;

  ChurchEvent({
    required this.id,
    required this.ownerId,
    required this.churchId,
    required this.kind,
    required this.startsAt,
    this.durationMinutes = defaultDurationMinutes,
    this.forWhom = '',
    this.phone = '',
    this.outsideChurch = false,
    this.address = '',
    this.remindMinutes = 60,
    this.shared = false,
    this.note = '',
  });

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
        'shared': shared,
        'note': note,
      };

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
        shared: (j['shared'] as bool?) ?? false,
        note: (j['note'] as String?) ?? '',
      );
}
