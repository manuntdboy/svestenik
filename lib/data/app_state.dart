import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// Цялото състояние на тестовата версия. Всичко се пази само на телефона.
/// По-късно този клас се заменя с връзка към сървъра (Supabase),
/// а екраните остават същите.
class AppState extends ChangeNotifier {
  static const _kData = 'data_v1';
  static const _kSession = 'session_user';
  static const _kChurch = 'current_church';
  static const _kTheme = 'theme_mode';
  static const _kTextScale = 'text_scale';

  late SharedPreferences _prefs;

  final List<AppUser> _users = [];
  final List<Church> _churches = [];
  final List<Membership> _members = [];
  final List<ChurchEvent> _events = [];

  AppUser? currentUser;
  String? currentChurchId;
  ThemeMode themeMode = ThemeMode.system;
  double textScale = 1.0;

  final _rnd = Random.secure();

  // ------------------------------------------------------------------
  // Зареждане и запис
  // ------------------------------------------------------------------
  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs.getString(_kData);
    if (raw != null) {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      _users.addAll((j['users'] as List).map((e) => AppUser.fromJson(e)));
      _churches.addAll((j['churches'] as List).map((e) => Church.fromJson(e)));
      _members.addAll((j['members'] as List).map((e) => Membership.fromJson(e)));
      _events.addAll((j['events'] as List).map((e) => ChurchEvent.fromJson(e)));
    }
    final uid = _prefs.getString(_kSession);
    if (uid != null) {
      currentUser = _users.where((u) => u.id == uid).firstOrNull;
    }
    currentChurchId = _prefs.getString(_kChurch);
    if (currentChurchId != null && !myChurches.any((c) => c.id == currentChurchId)) {
      currentChurchId = null;
    }
    currentChurchId ??= myChurches.firstOrNull?.id;
    themeMode = ThemeMode.values[_prefs.getInt(_kTheme) ?? 0];
    textScale = _prefs.getDouble(_kTextScale) ?? 1.0;
  }

  Future<void> _save() async {
    await _prefs.setString(
      _kData,
      jsonEncode({
        'users': _users.map((e) => e.toJson()).toList(),
        'churches': _churches.map((e) => e.toJson()).toList(),
        'members': _members.map((e) => e.toJson()).toList(),
        'events': _events.map((e) => e.toJson()).toList(),
      }),
    );
  }

  String _newId() =>
      List.generate(16, (_) => _rnd.nextInt(256).toRadixString(16).padLeft(2, '0')).join();

  String _hash(String password, String salt) =>
      sha256.convert(utf8.encode('$salt:$password')).toString();

  // ------------------------------------------------------------------
  // Вход и регистрация
  // ------------------------------------------------------------------
  bool get isLoggedIn => currentUser != null;

  bool usernameTaken(String username) =>
      _users.any((u) => u.username == username.trim().toLowerCase());

  /// Връща текст на грешка или null при успех.
  Future<String?> register({
    required String fullName,
    required String username,
    required String email,
    required String password,
  }) async {
    final uname = username.trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9._-]{3,30}$').hasMatch(uname)) {
      return 'Потребителското име трябва да е от 3 до 30 латински букви, цифри, точка или тире.';
    }
    if (usernameTaken(uname)) return 'Това потребителско име вече е заето.';
    if (fullName.trim().length < 2) return 'Въведете име.';
    if (email.trim().isNotEmpty && !email.contains('@')) return 'Имейлът не изглежда правилен.';
    if (password.length < 6) return 'Паролата трябва да е поне 6 знака.';
    final salt = _newId();
    final u = AppUser(
      id: _newId(),
      username: uname,
      fullName: fullName.trim(),
      email: email.trim(),
      passwordHash: _hash(password, salt),
      salt: salt,
    );
    _users.add(u);
    currentUser = u;
    currentChurchId = null;
    await _prefs.setString(_kSession, u.id);
    await _prefs.remove(_kChurch);
    await _save();
    notifyListeners();
    return null;
  }

  Future<String?> login(String username, String password) async {
    final uname = username.trim().toLowerCase();
    final u = _users.where((u) => u.username == uname).firstOrNull;
    if (u == null || u.passwordHash != _hash(password, u.salt)) {
      return 'Грешно потребителско име или парола.';
    }
    currentUser = u;
    await _prefs.setString(_kSession, u.id);
    currentChurchId = myChurches.firstOrNull?.id;
    if (currentChurchId != null) await _prefs.setString(_kChurch, currentChurchId!);
    notifyListeners();
    return null;
  }

  Future<void> logout() async {
    currentUser = null;
    currentChurchId = null;
    await _prefs.remove(_kSession);
    await _prefs.remove(_kChurch);
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // Храмове
  // ------------------------------------------------------------------
  List<Church> get myChurches {
    final u = currentUser;
    if (u == null) return [];
    final ids = _members.where((m) => m.userId == u.id).map((m) => m.churchId).toSet();
    return _churches.where((c) => ids.contains(c.id)).toList();
  }

  Church? get currentChurch =>
      _churches.where((c) => c.id == currentChurchId).firstOrNull;

  bool isManagerOf(String churchId) => _members.any(
      (m) => m.churchId == churchId && m.userId == currentUser?.id && m.isManager);

  List<(AppUser, Membership)> membersOf(String churchId) => _members
      .where((m) => m.churchId == churchId)
      .map((m) => (_users.firstWhere((u) => u.id == m.userId), m))
      .toList();

  String _newJoinCode() {
    const alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
    while (true) {
      final code = List.generate(6, (_) => alphabet[_rnd.nextInt(alphabet.length)]).join();
      if (!_churches.any((c) => c.joinCode == code)) return code;
    }
  }

  Future<Church> createChurch(String name, String settlement, String municipality) async {
    final c = Church(
      id: _newId(),
      name: name.trim(),
      settlement: settlement.trim(),
      municipality: municipality.trim(),
      joinCode: _newJoinCode(),
    );
    _churches.add(c);
    _members.add(Membership(churchId: c.id, userId: currentUser!.id, role: 'manager'));
    await selectChurch(c.id);
    await _save();
    return c;
  }

  /// Връща текст на грешка или null при успех.
  Future<String?> joinChurch(String code) async {
    final clean = code.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final c = _churches.where((c) => c.joinCode == clean).firstOrNull;
    if (c == null) return 'Няма храм с този код.';
    if (!_members.any((m) => m.churchId == c.id && m.userId == currentUser!.id)) {
      _members.add(Membership(churchId: c.id, userId: currentUser!.id, role: 'priest'));
    }
    await selectChurch(c.id);
    await _save();
    return null;
  }

  Future<void> selectChurch(String id) async {
    currentChurchId = id;
    await _prefs.setString(_kChurch, id);
    notifyListeners();
  }

  Future<String> regenerateCode(String churchId) async {
    final c = _churches.firstWhere((c) => c.id == churchId);
    c.joinCode = _newJoinCode();
    await _save();
    notifyListeners();
    return c.joinCode;
  }

  Future<void> removeMember(String churchId, String userId) async {
    _members.removeWhere((m) => m.churchId == churchId && m.userId == userId);
    await _save();
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // Събития
  // ------------------------------------------------------------------
  /// Събитията, които текущият потребител вижда в текущия храм:
  /// своите (лични и споделени) и споделените от другите.
  List<ChurchEvent> get visibleEvents {
    final u = currentUser;
    if (u == null || currentChurchId == null) return [];
    return _events
        .where((e) => e.churchId == currentChurchId && (e.ownerId == u.id || e.shared))
        .toList()
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
  }

  List<ChurchEvent> eventsOn(DateTime day) => visibleEvents
      .where((e) =>
          e.startsAt.year == day.year &&
          e.startsAt.month == day.month &&
          e.startsAt.day == day.day)
      .toList();

  ChurchEvent? get nextEvent {
    final now = DateTime.now();
    return visibleEvents.where((e) => e.startsAt.isAfter(now)).firstOrNull;
  }

  ChurchEvent? eventById(String id) => _events.where((e) => e.id == id).firstOrNull;

  String ownerName(ChurchEvent e) =>
      _users.where((u) => u.id == e.ownerId).firstOrNull?.fullName ?? '';

  bool canEdit(ChurchEvent e) => e.ownerId == currentUser?.id;

  bool canDelete(ChurchEvent e) =>
      canEdit(e) || (e.shared && isManagerOf(e.churchId));

  ChurchEvent newEventDraft(DateTime day) {
    final now = DateTime.now();
    final start = DateTime(day.year, day.month, day.day,
        day.year == now.year && day.month == now.month && day.day == now.day
            ? (now.hour + 1).clamp(0, 23)
            : 10);
    return ChurchEvent(
      id: _newId(),
      ownerId: currentUser!.id,
      churchId: currentChurchId!,
      kind: EventKind.krashtene,
      startsAt: start,
    );
  }

  Future<void> saveEvent(ChurchEvent e) async {
    _events.removeWhere((x) => x.id == e.id);
    _events.add(e);
    await _save();
    notifyListeners();
  }

  Future<void> deleteEvent(String id) async {
    _events.removeWhere((e) => e.id == id);
    await _save();
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // Настройки
  // ------------------------------------------------------------------
  Future<void> setThemeMode(ThemeMode m) async {
    themeMode = m;
    await _prefs.setInt(_kTheme, m.index);
    notifyListeners();
  }

  Future<void> setTextScale(double s) async {
    textScale = s;
    await _prefs.setDouble(_kTextScale, s);
    notifyListeners();
  }

  /// Изтрива всички данни от телефона (за тестове).
  Future<void> wipeAll() async {
    _users.clear();
    _churches.clear();
    _members.clear();
    _events.clear();
    currentUser = null;
    currentChurchId = null;
    await _prefs.clear();
    notifyListeners();
  }
}

/// Дава достъп до AppState от всеки екран: AppScope.of(context).
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
      : super(notifier: state);

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  /// Без абониране за промени (за бутони и действия).
  static AppState read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
