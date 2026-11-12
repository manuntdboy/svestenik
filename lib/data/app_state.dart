import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';
import 'notifier.dart';

/// Адрес и публичен ключ на Supabase. Подават се при изграждането
/// (--dart-define) от GitHub Secrets.
const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabasePublishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
bool get supabaseConfigured => supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;

/// Грешка с текст за потребителя.
class AppError implements Exception {
  final String message;
  AppError(this.message);
  @override
  String toString() => message;
}

/// Цялото състояние на приложението. Данните са в Supabase; тук се пази
/// копие в паметта, за да са екраните бързи. Правилата кой какво вижда
/// се спазват от самата база (RLS), не от приложението.
class AppState extends ChangeNotifier {
  static const _kChurch = 'current_church';
  static const _kTheme = 'theme_mode';
  static const _kTextScale = 'text_scale';
  static const _kRemember = 'remember_me';
  static const _kLastUser = 'last_username';

  late SharedPreferences _prefs;
  SupabaseClient get _db => Supabase.instance.client;
  StreamSubscription<AuthState>? _authSub;

  final List<AppUser> _profiles = [];
  final List<Church> _churches = [];
  final List<Membership> _members = [];
  final List<ChurchEvent> _events = [];

  AppUser? currentUser;
  String? currentChurchId;
  ThemeMode themeMode = ThemeMode.system;
  double textScale = 1.0;

  /// „Запомни ме“: ако е изключено, при следващо отваряне се иска вход.
  bool rememberMe = true;

  /// Последното потребителско име (попълва се на екрана за вход).
  String lastUsername = '';

  /// true докато се зареждат данните след вход или стартиране.
  bool loading = false;

  /// Текст, ако последното обновяване от сървъра не е успяло.
  String? syncError;

  final _rnd = Random.secure();

  // ------------------------------------------------------------------
  // Стартиране
  // ------------------------------------------------------------------
  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    themeMode = ThemeMode.values[_prefs.getInt(_kTheme) ?? 0];
    textScale = _prefs.getDouble(_kTextScale) ?? 1.0;
    currentChurchId = _prefs.getString(_kChurch);
    rememberMe = _prefs.getBool(_kRemember) ?? true;
    lastUsername = rememberMe ? (_prefs.getString(_kLastUser) ?? '') : '';

    _authSub = _db.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.signedOut && currentUser != null) {
        _clear();
        notifyListeners();
      }
    });

    // Без „Запомни ме“ сесията от предишното отваряне не се ползва.
    if (_db.auth.currentSession != null && !rememberMe) {
      try {
        await _db.auth.signOut(scope: SignOutScope.local);
      } catch (_) {}
    }

    if (_db.auth.currentSession != null) {
      loading = true;
      // Не чакаме: екранът показва „зареждане“, докато дойдат данните.
      unawaited(refresh());
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  void _clear() {
    currentUser = null;
    _profiles.clear();
    _churches.clear();
    _members.clear();
    _events.clear();
    syncError = null;
  }

  /// Изтегля наново профила, храмовете, членовете и събитията.
  Future<void> refresh() async {
    final authUser = _db.auth.currentUser;
    if (authUser == null) {
      loading = false;
      notifyListeners();
      return;
    }
    try {
      final results = await Future.wait([
        _db.from('profiles').select(),
        _db.from('churches').select(),
        _db.from('church_members').select(),
        _db.from('events').select().order('starts_at'),
      ]);
      _profiles
        ..clear()
        ..addAll(results[0].map((r) => AppUser.fromRow(r,
            email: r['id'] == authUser.id ? (authUser.email ?? '') : '')));
      _churches
        ..clear()
        ..addAll(results[1].map(Church.fromRow));
      _members
        ..clear()
        ..addAll(results[2].map(Membership.fromRow));
      _events
        ..clear()
        ..addAll(results[3].map(ChurchEvent.fromRow));

      currentUser = _profiles.where((p) => p.id == authUser.id).firstOrNull;
      if (currentChurchId == null || !myChurches.any((c) => c.id == currentChurchId)) {
        currentChurchId = myChurches.firstOrNull?.id;
      }
      syncError = null;
      unawaited(rescheduleReminders());
    } catch (e) {
      debugPrint('Обновяването не успя: $e');
      syncError = 'Няма връзка със сървъра. Показват се последните заредени данни.';
      // Ако профилът още не е зареден, поне да не стоим на „зареждане“.
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  String _uuid() {
    final b = List<int>.generate(16, (_) => _rnd.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
        '${h.substring(16, 20)}-${h.substring(20)}';
  }

  /// Превежда грешките от сървъра на разбираем език.
  String _friendly(Object e) {
    final text = switch (e) {
      PostgrestException(:final message) => message,
      AuthException(:final message) => message,
      FunctionException(:final details) => details.toString(),
      _ => e.toString(),
    };
    final t = text.toLowerCase();
    if (t.contains('invalid_code')) return 'Няма храм с този код.';
    if (t.contains('not_manager')) return 'Само председателят може да направи това.';
    if (t.contains('cannot_remove_self')) return 'Не можете да премахнете себе си.';
    if (t.contains('last_manager')) return 'Храмът трябва да има поне един председател.';
    if (t.contains('row-level security') || t.contains('permission')) {
      return 'Нямате права за това.';
    }
    if (t.contains('socket') || t.contains('network') || t.contains('failed host lookup') ||
        t.contains('timed out') || t.contains('connection')) {
      return 'Няма връзка с интернет. Опитайте отново.';
    }
    return 'Нещо се обърка: $text';
  }

  // ------------------------------------------------------------------
  // Вход и регистрация
  // ------------------------------------------------------------------
  bool get isLoggedIn => currentUser != null;

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
    if (fullName.trim().length < 2) return 'Въведете име.';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email.trim())) {
      return 'Въведете правилен имейл. Той е нужен при забравена парола.';
    }
    if (password.length < 6) return 'Паролата трябва да е поне 6 знака.';
    try {
      final free = await _db.rpc('username_available', params: {'p_username': uname});
      if (free != true) return 'Това потребителско име вече е заето.';
      final res = await _db.auth.signUp(
        email: email.trim(),
        password: password,
        data: {'username': uname, 'full_name': fullName.trim()},
      );
      if (res.session == null) {
        return 'Профилът е създаден. Отворете писмото, което изпратихме на ${email.trim()}, '
            'потвърдете имейла и после влезте.';
      }
      currentChurchId = null;
      await _prefs.remove(_kChurch);
      loading = true;
      notifyListeners();
      await refresh();
      return null;
    } on AuthException catch (e) {
      final t = e.message.toLowerCase();
      if (t.contains('already registered') || t.contains('already been registered')) {
        return 'С този имейл вече има профил. Влезте с него.';
      }
      if (t.contains('database error')) return 'Това потребителско име вече е заето.';
      if (t.contains('password')) return 'Паролата е твърде слаба. Изберете по-дълга.';
      if (t.contains('rate limit')) return 'Твърде много опити. Изчакайте няколко минути.';
      return _friendly(e);
    } catch (e) {
      return _friendly(e);
    }
  }

  /// Вход с потребителско име (или имейл) и парола.
  Future<String?> login(String usernameOrEmail, String password,
      {bool remember = true}) async {
    final id = usernameOrEmail.trim();
    rememberMe = remember;
    await _prefs.setBool(_kRemember, remember);
    if (remember) {
      lastUsername = id;
      await _prefs.setString(_kLastUser, id);
    } else {
      lastUsername = '';
      await _prefs.remove(_kLastUser);
    }
    if (id.isEmpty || password.isEmpty) return 'Въведете потребителско име и парола.';
    try {
      if (id.contains('@')) {
        await _db.auth.signInWithPassword(email: id, password: password);
      } else {
        final res = await _db.functions.invoke('login',
            body: {'username': id.toLowerCase(), 'password': password});
        final data = res.data;
        final refreshToken = data is Map ? data['refresh_token'] as String? : null;
        if (refreshToken == null) return 'Грешно потребителско име или парола.';
        await _db.auth.setSession(refreshToken);
      }
      loading = true;
      notifyListeners();
      await refresh();
      if (currentUser == null) return syncError ?? 'Профилът не можа да се зареди.';
      return null;
    } on FunctionException catch (e) {
      final d = e.details.toString();
      if (d.contains('email_not_confirmed')) {
        return 'Имейлът още не е потвърден. Отворете писмото от Кайрос.';
      }
      if (e.status == 401 || e.status == 400) return 'Грешно потребителско име или парола.';
      return _friendly(e);
    } on AuthException catch (e) {
      if (e.message.toLowerCase().contains('invalid')) {
        return 'Грешен имейл или парола.';
      }
      return _friendly(e);
    } catch (e) {
      return _friendly(e);
    }
  }

  /// Изпраща писмо за нова парола.
  Future<String?> sendPasswordReset(String email) async {
    try {
      await _db.auth.resetPasswordForEmail(email.trim());
      return null;
    } catch (e) {
      return _friendly(e);
    }
  }

  /// Моите събития във всички мои храмове – за тях идват напомняния.
  Iterable<ChurchEvent> get _myEvents {
    final u = currentUser;
    if (u == null) return const [];
    final ids = myChurches.map((c) => c.id).toSet();
    return _events.where((e) => e.ownerId == u.id && ids.contains(e.churchId));
  }

  Future<void> rescheduleReminders() => Notifier.rescheduleAll(_myEvents);

  Future<void> logout() async {
    await Notifier.cancelAll();
    _clear();
    currentChurchId = null;
    await _prefs.remove(_kChurch);
    notifyListeners();
    try {
      await _db.auth.signOut();
    } catch (_) {
      // Без интернет сесията се изтрива само на телефона – достатъчно е.
    }
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
      myChurches.where((c) => c.id == currentChurchId).firstOrNull;

  bool isManagerOf(String churchId) => _members.any(
      (m) => m.churchId == churchId && m.userId == currentUser?.id && m.isManager);

  List<(AppUser, Membership)> membersOf(String churchId) => [
        for (final m in _members.where((m) => m.churchId == churchId))
          (
            _profiles.where((p) => p.id == m.userId).firstOrNull ??
                AppUser(id: m.userId, username: '', fullName: '—'),
            m
          ),
      ];

  Future<Church> createChurch(String name, String settlement, String municipality) async {
    try {
      final row = await _db.rpc('create_church', params: {
        'p_name': name.trim(),
        'p_settlement': settlement.trim(),
        'p_municipality': municipality.trim(),
      });
      final c = Church.fromRow(Map<String, dynamic>.from(row as Map));
      await refresh();
      await selectChurch(c.id);
      return c;
    } catch (e) {
      throw AppError(_friendly(e));
    }
  }

  /// Връща текст на грешка или null при успех.
  Future<String?> joinChurch(String code) async {
    final clean = code.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (clean.length != 6) return 'Кодът е от 6 знака.';
    try {
      final row = await _db.rpc('join_church', params: {'p_code': clean});
      final c = Church.fromRow(Map<String, dynamic>.from(row as Map));
      await refresh();
      await selectChurch(c.id);
      return null;
    } catch (e) {
      return _friendly(e);
    }
  }

  Future<void> selectChurch(String id) async {
    currentChurchId = id;
    await _prefs.setString(_kChurch, id);
    notifyListeners();
  }

  Future<String> regenerateCode(String churchId) async {
    try {
      final code = await _db.rpc('regenerate_join_code', params: {'p_church': churchId});
      _churches.firstWhere((c) => c.id == churchId).joinCode = code as String;
      notifyListeners();
      return code;
    } catch (e) {
      throw AppError(_friendly(e));
    }
  }

  Future<void> removeMember(String churchId, String userId) async {
    try {
      await _db.rpc('remove_member', params: {'p_church': churchId, 'p_user': userId});
      await refresh();
    } catch (e) {
      throw AppError(_friendly(e));
    }
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

  /// Моите събития (във всички мои храмове), които се застъпват по време с [e].
  /// Самото [e] не се брои.
  List<ChurchEvent> overlapsFor(ChurchEvent e) {
    final u = currentUser;
    if (u == null) return [];
    final myChurchIds = myChurches.map((c) => c.id).toSet();
    return _events
        .where((x) =>
            x.id != e.id &&
            x.ownerId == u.id &&
            myChurchIds.contains(x.churchId) &&
            x.overlaps(e))
        .toList()
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
  }

  String churchName(String churchId) =>
      _churches.where((c) => c.id == churchId).firstOrNull?.name ?? '';

  ChurchEvent? eventById(String id) => _events.where((e) => e.id == id).firstOrNull;

  String ownerName(ChurchEvent e) =>
      _profiles.where((u) => u.id == e.ownerId).firstOrNull?.fullName ?? '';

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
      id: _uuid(),
      ownerId: currentUser!.id,
      churchId: currentChurchId!,
      kind: EventKind.krashtene,
      startsAt: start,
    );
  }

  /// Записва събитието на сървъра. При грешка хвърля [AppError].
  Future<void> saveEvent(ChurchEvent e) async {
    try {
      final row = await _db.from('events').upsert(e.toRow()).select().single();
      final saved = ChurchEvent.fromRow(row);
      _events.removeWhere((x) => x.id == saved.id);
      _events.add(saved);
      notifyListeners();
      if (saved.ownerId == currentUser?.id) await Notifier.schedule(saved);
    } catch (err) {
      // Връщаме копието от сървъра, ако формулярът вече е променил обекта.
      unawaited(refresh());
      throw AppError(_friendly(err));
    }
  }

  /// Изтрива събитието на сървъра. При грешка хвърля [AppError].
  Future<void> deleteEvent(String id) async {
    try {
      final deleted = await _db.from('events').delete().eq('id', id).select();
      if (deleted.isEmpty) throw AppError('Нямате права да изтриете това събитие.');
      _events.removeWhere((e) => e.id == id);
      notifyListeners();
      await Notifier.cancel(id);
    } on AppError {
      rethrow;
    } catch (err) {
      throw AppError(_friendly(err));
    }
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
