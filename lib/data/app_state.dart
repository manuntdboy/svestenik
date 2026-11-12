import 'dart:async';
import 'dart:typed_data';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';
import 'notifier.dart';
import 'push.dart';

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

  /// Последното състояние от сървъра по номер на събитие – за да знаем
  /// какво се е променило при запис (формулярът променя обекта на място).
  final Map<String, Map<String, dynamic>> _rows = {};

  StreamSubscription<String>? _tokenSub;
  String? _pushToken;

  AppUser? currentUser;
  String? currentChurchId;
  ThemeMode themeMode = ThemeMode.system;
  double textScale = 1.0;

  /// „Запомни ме“: ако е изключено, при следващо отваряне се иска вход.
  bool rememberMe = true;

  /// Последното потребителско име (попълва се на екрана за вход).
  String lastUsername = '';

  /// Моят личен профил и снимката ми (зареждат се отделно).
  ProfileDetails myDetails = ProfileDetails();
  Uint8List? myPhoto;

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
    _tokenSub?.cancel();
    _authSub?.cancel();
    super.dispose();
  }

  void _clear() {
    currentUser = null;
    myDetails = ProfileDetails();
    myPhoto = null;
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
      _rows
        ..clear()
        ..addEntries(results[3].map((r) => MapEntry(r['id'] as String, r)));

      currentUser = _profiles.where((p) => p.id == authUser.id).firstOrNull;
      if (currentChurchId == null || !myChurches.any((c) => c.id == currentChurchId)) {
        currentChurchId = myChurches.firstOrNull?.id;
      }
      syncError = null;
      unawaited(_loadDetails());
      unawaited(rescheduleReminders());
      unawaited(_registerPush());
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

  /// Записва това устройство на сървъра, за да идват push известия.
  Future<void> _registerPush() async {
    if (!Push.ready || currentUser == null) return;
    Push.onEvent ??= () => unawaited(refresh());
    final token = await Push.token();
    if (token == null) return;
    if (token != _pushToken) {
      try {
        await _db.rpc('register_device', params: {'p_token': token});
        _pushToken = token;
      } catch (e) {
        debugPrint('Устройството не се записа: $e');
      }
    }
    _tokenSub ??= Push.tokenRefresh.listen((t) async {
      if (currentUser == null) return;
      try {
        await _db.rpc('register_device', params: {'p_token': t});
        _pushToken = t;
      } catch (_) {}
    });
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

  /// Събитията, които аз ще извърша (във всички мои храмове) – за тях идват
  /// напомняния, дори ако ги е записал колега.
  Iterable<ChurchEvent> get _myEvents {
    final u = currentUser;
    if (u == null) return const [];
    final ids = myChurches.map((c) => c.id).toSet();
    return _events.where((e) =>
        e.assigneeId == u.id && ids.contains(e.churchId) && e.status == EventStatus.planned);
  }

  Future<void> rescheduleReminders() => Notifier.rescheduleAll(_myEvents);

  Future<void> logout() async {
    await Notifier.cancelAll();
    // Спираме push известията за този профил на това устройство.
    final token = _pushToken;
    if (token != null) {
      try {
        await _db.rpc('unregister_device', params: {'p_token': token});
      } catch (_) {}
      _pushToken = null;
    }
    await Push.deleteToken();
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
  /// Храмовете, в които съм одобрен.
  List<Church> get myChurches {
    final u = currentUser;
    if (u == null) return [];
    final ids = _members
        .where((m) => m.userId == u.id && m.isActive)
        .map((m) => m.churchId)
        .toSet();
    return _churches.where((c) => ids.contains(c.id)).toList();
  }

  /// Храмовете, в които чакам одобрение от председателя.
  List<Church> get pendingChurches {
    final u = currentUser;
    if (u == null) return [];
    final ids = _members
        .where((m) => m.userId == u.id && m.isPending)
        .map((m) => m.churchId)
        .toSet();
    return _churches.where((c) => ids.contains(c.id)).toList();
  }

  /// Свещениците, които чакат одобрение в храма (вижда ги председателят).
  List<(AppUser, Membership)> pendingRequests(String churchId) => [
        for (final m in _members.where((m) => m.churchId == churchId && m.isPending))
          (
            _profiles.where((p) => p.id == m.userId).firstOrNull ??
                AppUser(id: m.userId, username: '', fullName: 'Нов свещеник'),
            m
          ),
      ];

  /// Одобрява чакащ свещеник и му праща известие.
  Future<void> approveMember(String churchId, String userId) async {
    try {
      await _db.rpc('approve_member', params: {'p_church': churchId, 'p_user': userId});
      await refresh();
    } catch (e) {
      throw AppError(_friendly(e));
    }
    unawaited(_invokeNotify({'type': 'member_approved', 'church_id': churchId, 'user_id': userId}));
  }

  /// Отказва чакащ свещеник (премахва заявката).
  Future<void> declineMember(String churchId, String userId) => removeMember(churchId, userId);

  Future<void> _invokeNotify(Map<String, dynamic> body) async {
    try {
      await _db.functions.invoke('notify', body: body);
    } catch (e) {
      debugPrint('Известието не тръгна: $e');
    }
  }

  Future<void> _loadDetails() async {
    try {
      final row = await _db.from('profile_details').select().maybeSingle();
      myDetails = row == null ? ProfileDetails() : ProfileDetails.fromRow(row);
      final path = myDetails.photoPath;
      myPhoto = path == null ? null : await _db.storage.from('avatars').download(path);
      notifyListeners();
    } catch (e) {
      debugPrint('Личният профил не се зареди: $e');
    }
  }

  /// Записва личния профил (три имена, дати, имен ден).
  Future<void> saveDetails(ProfileDetails d) async {
    try {
      final row = await _db
          .from('profile_details')
          .upsert({...d.toRow(), 'user_id': currentUser!.id})
          .select()
          .single();
      myDetails = ProfileDetails.fromRow(row);
      notifyListeners();
    } catch (e) {
      throw AppError(_friendly(e));
    }
  }

  /// Качва нова снимка (JPEG) в частното хранилище и я записва в профила.
  Future<void> uploadPhoto(Uint8List bytes) async {
    final path = '${currentUser!.id}/avatar.jpg';
    try {
      await _db.storage.from('avatars').uploadBinary(path, bytes,
          fileOptions: const FileOptions(upsert: true, contentType: 'image/jpeg'));
      final d = myDetails.copy()..photoPath = path;
      await saveDetails(d);
      myPhoto = bytes;
      notifyListeners();
    } on AppError {
      rethrow;
    } catch (e) {
      throw AppError(_friendly(e));
    }
  }

  /// Премахва снимката.
  Future<void> removePhoto() async {
    final path = myDetails.photoPath;
    try {
      if (path != null) await _db.storage.from('avatars').remove([path]);
      final d = myDetails.copy()..photoPath = null;
      await saveDetails(d);
      myPhoto = null;
      notifyListeners();
    } on AppError {
      rethrow;
    } catch (e) {
      throw AppError(_friendly(e));
    }
  }

  /// Сменя името, което виждат колегите.
  Future<void> updateFullName(String name) async {
    final n = name.trim();
    if (n.length < 2) throw AppError('Въведете име.');
    try {
      await _db.from('profiles').update({'full_name': n}).eq('id', currentUser!.id);
      await refresh();
    } catch (e) {
      throw AppError(_friendly(e));
    }
  }

  Church? get currentChurch =>
      myChurches.where((c) => c.id == currentChurchId).firstOrNull;

  bool isManagerOf(String churchId) => _members.any(
      (m) => m.churchId == churchId && m.userId == currentUser?.id && m.isManager);

  List<(AppUser, Membership)> membersOf(String churchId) => [
        for (final m in _members.where((m) => m.churchId == churchId && m.isActive))
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
      if (myChurches.any((x) => x.id == c.id)) {
        // Вече съм член на този храм.
        await selectChurch(c.id);
      } else {
        // Заявката чака одобрение – известяваме председателя.
        unawaited(_invokeNotify({'type': 'join_request', 'church_id': c.id}));
      }
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
        .where((e) =>
            e.churchId == currentChurchId &&
            (e.ownerId == u.id || e.assigneeId == u.id || e.shared))
        .toList()
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
  }

  List<ChurchEvent> eventsOn(DateTime day) => visibleEvents
      .where((e) =>
          e.startsAt.year == day.year &&
          e.startsAt.month == day.month &&
          e.startsAt.day == day.day)
      .toList();

  /// Моето следващо събитие (което аз ще извърша) в текущия храм.
  ChurchEvent? get nextEvent {
    final now = DateTime.now();
    return visibleEvents
        .where((e) =>
            e.assigneeId == currentUser?.id &&
            e.status == EventStatus.planned &&
            e.startsAt.isAfter(now))
        .firstOrNull;
  }

  /// Събитията на същия свещеник (във всички мои храмове), които се
  /// застъпват по време с [e]. Самото [e] не се брои.
  List<ChurchEvent> overlapsFor(ChurchEvent e) {
    final u = currentUser;
    if (u == null) return [];
    if (e.isCancelled) return [];
    final myChurchIds = myChurches.map((c) => c.id).toSet();
    return _events
        .where((x) =>
            x.id != e.id &&
            !x.isCancelled &&
            x.assigneeId == e.assigneeId &&
            myChurchIds.contains(x.churchId) &&
            x.overlaps(e))
        .toList()
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
  }

  /// Други събития В ХРАМА по същото време (при друг свещеник) – храмът
  /// е зает. Събития извън храма не се броят.
  List<ChurchEvent> placeOverlapsFor(ChurchEvent e) {
    final u = currentUser;
    if (u == null || e.outsideChurch || e.isCancelled) return [];
    return _events
        .where((x) =>
            x.id != e.id &&
            x.churchId == e.churchId &&
            !x.outsideChurch &&
            !x.isCancelled &&
            x.assigneeId != e.assigneeId &&
            (x.ownerId == u.id || x.assigneeId == u.id || x.shared) &&
            x.overlaps(e))
        .toList()
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
  }

  /// Търсене в събитията на текущия храм: име, телефон, адрес, бележка,
  /// вид, свещеник. Предстоящите първи (най-близкото най-горе), после минали.
  List<ChurchEvent> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.length < 2) return [];
    final now = DateTime.now();
    final qDigits = q.replaceAll(' ', '');
    bool hit(ChurchEvent e) =>
        [e.forWhom, e.address, e.note, e.kind.label, priestName(e.assigneeId)]
            .any((f) => f.toLowerCase().contains(q)) ||
        (qDigits.isNotEmpty && e.phone.replaceAll(' ', '').contains(qDigits));
    final found = visibleEvents.where(hit).toList();
    final upcoming = found.where((e) => !e.startsAt.isBefore(now)).toList()
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    final past = found.where((e) => e.startsAt.isBefore(now)).toList()
      ..sort((a, b) => b.startsAt.compareTo(a.startsAt));
    return [...upcoming, ...past];
  }

  /// Последно въведените „за кого“ с техния телефон – за бързо попълване.
  List<(String, String)> recentContacts(String typed) {
    final t = typed.trim().toLowerCase();
    final seen = <String>{};
    final out = <(String, String)>[];
    final all = [..._events]..sort((a, b) => b.startsAt.compareTo(a.startsAt));
    for (final e in all) {
      final name = e.forWhom.trim();
      if (name.isEmpty) continue;
      final key = name.toLowerCase();
      if (seen.contains(key)) continue;
      if (t.isNotEmpty && !key.contains(t)) continue;
      if (key == t) continue;
      seen.add(key);
      out.add((name, e.phone));
      if (out.length >= 6) break;
    }
    return out;
  }

  /// Копие на събитие за нова дата (записвам го аз).
  ChurchEvent copyDraft(ChurchEvent e) {
    final copy = e.copyAs(id: _uuid(), ownerId: currentUser!.id);
    if (!membersOf(e.churchId).any((m) => m.$1.id == copy.assigneeId)) {
      copy.assigneeId = currentUser!.id;
    }
    return copy;
  }

  /// Отбелязва събитието като проведено, отменено или пак предстоящо.
  Future<void> setStatus(ChurchEvent e, EventStatus status) async {
    final old = e.status;
    e.status = status;
    try {
      await saveEvent(e);
    } on AppError {
      e.status = old;
      rethrow;
    }
  }

  String churchName(String churchId) =>
      _churches.where((c) => c.id == churchId).firstOrNull?.name ?? '';

  ChurchEvent? eventById(String id) => _events.where((e) => e.id == id).firstOrNull;

  String ownerName(ChurchEvent e) =>
      _profiles.where((u) => u.id == e.ownerId).firstOrNull?.fullName ?? '';

  /// Името на свещеника (за падащото меню и календара).
  String priestName(String userId) =>
      _profiles.where((u) => u.id == userId).firstOrNull?.fullName ?? '';

  bool isMine(ChurchEvent e) => e.assigneeId == currentUser?.id;

  /// Свещениците на храма по реда на присъединяване (председателят обикновено е пръв).
  List<(AppUser, Membership)> priestsOf(String churchId) =>
      membersOf(churchId)..sort((a, b) => a.$2.joinedAt.compareTo(b.$2.joinedAt));

  /// Пореден номер на свещеника в храма – по него се избира цветът му.
  int priestIndex(String churchId, String userId) {
    final i = priestsOf(churchId).indexWhere((p) => p.$1.id == userId);
    return i < 0 ? 7 : i;
  }

  /// Различните свещеници със събития в деня (за цветните точки).
  List<String> priestsOn(DateTime day) {
    final ids = <String>[];
    for (final e in eventsOn(day)) {
      if (!ids.contains(e.assigneeId)) ids.add(e.assigneeId);
    }
    return ids;
  }

  /// Редактират записалият и свещеникът, за когото е събитието.
  bool canEdit(ChurchEvent e) =>
      e.ownerId == currentUser?.id || e.assigneeId == currentUser?.id;

  /// Трият записалият и председателят (споделени събития).
  bool canDelete(ChurchEvent e) =>
      e.ownerId == currentUser?.id || (e.shared && isManagerOf(e.churchId));

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
      durationMinutes: EventKind.krashtene.defaultMinutes,
    );
  }

  /// Записва събитието на сървъра. При грешка хвърля [AppError].
  Future<void> saveEvent(ChurchEvent e) async {
    // Събитие за колега винаги е споделено с храма.
    if (e.assigneeId != e.ownerId) e.shared = true;
    final before = _rows[e.id];
    try {
      final row = await _db.from('events').upsert(e.toRow()).select().single();
      final saved = ChurchEvent.fromRow(row);
      _events.removeWhere((x) => x.id == saved.id);
      _events.add(saved);
      _rows[saved.id] = row;
      notifyListeners();
      if (isMine(saved) && saved.status == EventStatus.planned) {
        await Notifier.schedule(saved);
      } else {
        await Notifier.cancel(saved.id);
      }
      unawaited(_notifyAssignee(saved, before));
    } catch (err) {
      // Връщаме копието от сървъра, ако формулярът вече е променил обекта.
      unawaited(refresh());
      throw AppError(_friendly(err));
    }
  }

  /// Праща push на колегата, ако записвам събитие за него или сменям
  /// нещо важно (свещеник, дата, час, вид).
  Future<void> _notifyAssignee(ChurchEvent saved, Map<String, dynamic>? before) async {
    if (saved.ownerId != currentUser?.id || saved.assigneeId == currentUser?.id) return;
    final String change;
    if (before == null || before['assignee_id'] != saved.assigneeId) {
      change = 'created';
    } else if (before['starts_at'] != _rows[saved.id]?['starts_at'] ||
        before['kind'] != saved.kind.name ||
        before['duration_minutes'] != saved.durationMinutes) {
      change = 'updated';
    } else {
      return;
    }
    await _invokeNotify({'type': 'event', 'event_id': saved.id, 'change': change});
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
