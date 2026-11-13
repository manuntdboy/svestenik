import 'dart:async';
import 'dart:typed_data';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';
import 'notifier.dart';
import 'push.dart';
import '../widgets/whats_new.dart' show buildNumber;

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
  final List<LeaveRequest> _leaves = [];
  final List<CashEntry> _cash = [];
  final Map<String, CashSettings> _cashSettings = {};
  final List<CashPeriod> _periods = [];
  final List<StockMove> _stock = [];
  final List<StockAudit> _audits = [];
  final List<Duty> _duties = [];
  final List<DutySwap> _swaps = [];
  final Map<String, int> _stockMin = {};
  // Потвърждения за Архиерейска Литургия: събитие → (свещеник → кога).
  final Map<String, Map<String, DateTime>> _confirmations = {};

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

  /// Профилът на създателя (решава сървърът) – отключва „Кайрос в числа“.
  bool isCreator = false;

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
    isCreator = false;
    _versionAt = null;
    currentUser = null;
    myDetails = ProfileDetails();
    myPhoto = null;
    _myPhotoStamp = null;
    _cash.clear();
    _cashSettings.clear();
    _periods.clear();
    _stock.clear();
    _audits.clear();
    _duties.clear();
    _swaps.clear();
    _stockMin.clear();
    _details.clear();
    _photos.clear();
    _photoStamp.clear();
    _profiles.clear();
    _churches.clear();
    _members.clear();
    _events.clear();
    _leaves.clear();
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
        _db.from('leave_requests').select().order('start_date'),
        _db.from('event_confirmations').select(),
        _db.from('cash_entries').select(),
        _db.from('cash_settings').select(),
        _db.from('cash_periods').select(),
        _db.from('stock_moves').select(),
        _db.from('stock_thresholds').select(),
        _db.from('stock_audits').select(),
        _db.from('duties').select().order('start_date'),
        _db.from('duty_swaps').select().order('created_at'),
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
      _leaves
        ..clear()
        ..addAll(results[4].map(LeaveRequest.fromRow));
      _cash
        ..clear()
        ..addAll(results[6].map(CashEntry.fromRow));
      _cashSettings
        ..clear()
        ..addEntries(results[7].map((r) => MapEntry(r['church_id'] as String, CashSettings.fromRow(r))));
      _periods
        ..clear()
        ..addAll(results[8].map(CashPeriod.fromRow));
      _stock
        ..clear()
        ..addAll(results[9].map(StockMove.fromRow));
      _audits
        ..clear()
        ..addAll(results[11].map(StockAudit.fromRow));
      _duties
        ..clear()
        ..addAll(results[12].map(Duty.fromRow));
      _swaps
        ..clear()
        ..addAll(results[13].map(DutySwap.fromRow));
      _stockMin.clear();
      for (final r in results[10]) {
        final it = StockItem.fromCode(r['item'] as String?);
        if (it != null) _stockMin['${r['church_id']}|${it.code}'] = (r['min_qty'] as num).toInt();
      }
      _confirmations.clear();
      for (final r in results[5]) {
        (_confirmations[r['event_id'] as String] ??= {})[r['user_id'] as String] =
            DateTime.parse(r['confirmed_at'] as String).toLocal();
      }
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
      unawaited(_reportVersion());
      unawaited(_checkCreator());
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
    if (t.contains('assignee_on_leave')) return 'Свещеникът е в почивка в този ден.';
    if (t.contains('not_pending')) return 'Това вече е решено от някой друг. Обновете.';
    if (t.contains('not_declined')) return 'Отказът вече е решен.';
    if (t.contains('bad_substitute')) return 'Изберете свещеник от храма.';
    if (t.contains('no_offer')) return 'Предложението вече не е активно.';
    if (t.contains('already_chair')) return 'Вие вече сте председател.';
    if (t.contains('not_assignee')) return 'Само свещеникът, за когото е събитието, може да отговори.';
    if (t.contains('month_not_over')) return 'Приключва се само изминал месец.';
    if (t.contains('pending_in_month')) return 'В този месец има чакащи записи – първо ги решете.';
    if (t.contains('already_closed')) return 'Месецът вече е приключен или чака одобрение.';
    if (t.contains('future_date')) return 'Датата не може да е в бъдещето.';
    if (t.contains('opening_exists')) return 'Началното салдо вече е въведено. Ако е грешно, сторнирайте го.';
    if (t.contains('not_cash_holder')) return 'Само касиерът и председателят могат да направят това.';
    if (t.contains('own_entry')) return 'Свой запис не може да одобрите – одобрява го другият.';
    if (t.contains('not_cashier')) return 'Приходите от свещениците ги приема касиерът.';
    if (t.contains('no_bank')) return 'Банковата сметка не е включена в настройките на касата.';
    if (t.contains('bad_amount')) return 'Въведете сума, по-голяма от нула.';
    if (t.contains('already_reversed')) return 'Записът вече е сторниран.';
    if (t.contains('not_reversible')) return 'Този запис не може да се сторнира.';
    if (t.contains('reason_required')) return 'Напишете причина за сторното.';
    if (t.contains('not_church_event')) return 'Това събитие не изисква потвърждение.';
    if (t.contains('not_enough_stock')) {
      final what = t.contains('cert_baptism')
          ? 'кръщелни свидетелства'
          : t.contains('cert_wedding')
              ? 'венчални свидетелства'
              : t.contains('diploma')
                  ? 'грамоти'
                  : 'наличност';
      return 'В склада няма достатъчно $what. Заредете склада и опитайте пак.';
    }
    if (t.contains('event_has_income')) {
      return 'Приходът от събитието е записан в касата. Първо го сторнирайте, после върнете събитието.';
    }
    if (t.contains('one_cashier')) {
      return 'В храма вече има касиер. Първо махнете правото на сегашния касиер.';
    }
    if (t.contains('not_manager')) return 'Само председателят може да направи това.';
    if (t.contains('cannot_remove_self')) return 'Не можете да премахнете себе си.';
    if (t.contains('amount_check')) return 'Сумата е твърде голяма – най-много 12 цифри.';
    if (t.contains('duty_overlap')) return 'В тези дни вече има дежурен. Изберете други дати.';
    if (t.contains('duty_too_long')) return 'Едно дежурство е най-много 2 месеца.';
    if (t.contains('swap_exists')) return 'За това дежурство вече има молба за размяна.';
    if (t.contains('duty_past')) return 'Минало дежурство не се разменя.';
    if (t.contains('leave_over')) return 'Тази почивка вече е приключила.';
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

  /// Казва на сървъра коя версия ползва този профил (вижда се само в
  /// прегледа на създателя). Най-много веднъж на 30 минути.
  DateTime? _versionAt;
  Future<void> _reportVersion() async {
    if (currentUser == null) return;
    final now = DateTime.now();
    if (_versionAt != null && now.difference(_versionAt!).inMinutes < 30) return;
    _versionAt = now;
    try {
      await _db.rpc('report_version', params: {'p_build': buildNumber});
    } catch (e) {
      debugPrint('Версията не се записа: $e');
    }
  }

  Future<void> _checkCreator() async {
    try {
      isCreator = await _db.rpc('is_creator') == true;
    } catch (_) {
      isCreator = false;
    }
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
        e.assigneeId == u.id &&
        ids.contains(e.churchId) &&
        e.status == EventStatus.planned &&
        e.isAccepted);
  }

  Future<void> rescheduleReminders() => Notifier.rescheduleAll(_myEvents, duties: _myDuties);

  Iterable<Duty> get _myDuties {
    final u = currentUser;
    if (u == null) return const [];
    final ids = myChurches.map((c) => c.id).toSet();
    return _duties.where((d) => d.userId == u.id && ids.contains(d.churchId));
  }

  // ------------------------------------------------------------------
  // График на дежурствата
  // ------------------------------------------------------------------
  List<Duty> dutiesOf(String churchId) => _duties.where((d) => d.churchId == churchId).toList()
    ..sort((a, b) => a.start.compareTo(b.start));

  Duty? dutyOn(String churchId, DateTime day) =>
      _duties.where((d) => d.churchId == churchId && d.covers(day)).firstOrNull;

  Duty? dutyById(String id) => _duties.where((d) => d.id == id).firstOrNull;

  /// Дежурният днес (или следващият, ако днес няма).
  Duty? currentDuty(String churchId) => dutyOn(churchId, DateTime.now());

  Duty? nextDuty(String churchId) {
    final n = DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    return dutiesOf(churchId).where((d) => d.start.isAfter(today)).firstOrNull;
  }

  /// Одобрена почивка на свещеника, която се застъпва с периода.
  LeaveRequest? leaveConflict(String churchId, String userId, DateTime a, DateTime b) => _leaves
      .where((l) =>
          l.churchId == churchId &&
          l.userId == userId &&
          l.status == LeaveStatus.approved &&
          !l.start.isAfter(b) &&
          !l.end.isBefore(a))
      .firstOrNull;

  List<DutySwap> swapsOf(String churchId) =>
      _swaps.where((w) => w.churchId == churchId).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  /// Молби за размяна към мен (чакат моя отговор).
  List<DutySwap> swapsForMe(String churchId) =>
      swapsOf(churchId).where((w) => w.status == 'peer' && w.toUser == currentUser?.id).toList();

  /// Размени, които чакат председателя.
  List<DutySwap> swapsForChair(String churchId) =>
      isManagerOf(churchId) ? swapsOf(churchId).where((w) => w.status == 'chair').toList() : [];

  DutySwap? openSwapFor(String dutyId) =>
      _swaps.where((w) => w.isOpen && (w.fromDuty == dutyId || w.toDuty == dutyId)).firstOrNull;

  Future<void> _dutyNotify(dynamic res) async {
    final by = <String, List<int>>{};
    for (final r in (res as List? ?? const [])) {
      final m = Map<String, dynamic>.from(r as Map);
      (by[m['user_id'] as String] ??= []).add((m['log_id'] as num).toInt());
    }
    for (final e in by.entries) {
      if (e.key == currentUser?.id) continue;
      unawaited(_invokeNotify({'type': 'duty', 'user_id': e.key, 'log_ids': e.value}));
    }
  }

  Future<void> addDuty(String churchId, String userId, DateTime start, DateTime end, String note) async {
    try {
      final res = await _db.rpc('duty_add', params: {
        'p_church': churchId,
        'p_user': userId,
        'p_start': _iso(start),
        'p_end': _iso(end),
        'p_note': note.trim().isEmpty ? null : note.trim(),
      });
      await refresh();
      unawaited(_dutyNotify(res));
    } catch (e) {
      throw AppError(_friendly(e));
    }
  }

  Future<void> updateDuty(Duty d, String userId, DateTime start, DateTime end, String note) async {
    try {
      final res = await _db.rpc('duty_update', params: {
        'p_duty': d.id,
        'p_user': userId,
        'p_start': _iso(start),
        'p_end': _iso(end),
        'p_note': note.trim().isEmpty ? null : note.trim(),
      });
      await refresh();
      unawaited(_dutyNotify(res));
    } catch (e) {
      throw AppError(_friendly(e));
    }
  }

  Future<void> deleteDuty(Duty d) async {
    try {
      final res = await _db.rpc('duty_delete', params: {'p_duty': d.id});
      await refresh();
      unawaited(_dutyNotify(res));
    } catch (e) {
      throw AppError(_friendly(e));
    }
  }

  Future<void> addDutySeries(String churchId, DateTime start, int days, List<String> users, int count) async {
    try {
      final res = await _db.rpc('duty_series', params: {
        'p_church': churchId,
        'p_start': _iso(start),
        'p_days': days,
        'p_users': users,
        'p_count': count,
      });
      await refresh();
      unawaited(_dutyNotify(res));
    } catch (e) {
      throw AppError(_friendly(e));
    }
  }

  Future<void> requestSwap(Duty mine, Duty other, String note) async {
    try {
      final r = await _db.rpc('duty_swap_request',
          params: {'p_from': mine.id, 'p_to': other.id, 'p_note': note.trim().isEmpty ? null : note.trim()});
      await refresh();
      unawaited(_invokeNotify({'type': 'duty_swap', 'swap_id': (r as Map)['id']}));
    } catch (e) {
      throw AppError(_friendly(e));
    }
  }

  Future<void> answerSwap(DutySwap w, bool accept) async {
    try {
      await _db.rpc('duty_swap_peer', params: {'p_swap': w.id, 'p_accept': accept});
      await refresh();
    } catch (e) {
      throw AppError(_friendly(e));
    }
    unawaited(_invokeNotify({'type': 'duty_swap', 'swap_id': w.id}));
  }

  Future<void> decideSwap(DutySwap w, bool approve, String reason) async {
    try {
      await _db.rpc('duty_swap_decide',
          params: {'p_swap': w.id, 'p_approve': approve, 'p_reason': reason.trim().isEmpty ? null : reason.trim()});
      await refresh();
    } catch (e) {
      throw AppError(_friendly(e));
    }
    unawaited(_invokeNotify({'type': 'duty_swap', 'swap_id': w.id}));
  }

  Future<void> cancelSwap(DutySwap w) async {
    try {
      await _db.rpc('duty_swap_cancel', params: {'p_swap': w.id});
      await refresh();
    } catch (e) {
      throw AppError(_friendly(e));
    }
    unawaited(_invokeNotify({'type': 'duty_swap', 'swap_id': w.id}));
  }

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

  // Личните профили на колегите (виждат се в общ храм) и снимките им.
  final Map<String, ProfileDetails> _details = {};
  final Map<String, String> _detailsStamp = {};
  final Map<String, Uint8List> _photos = {};
  final Map<String, String> _photoStamp = {};
  final Set<String> _photoLoading = {};
  String? _myPhotoStamp;

  ProfileDetails? detailsOf(String userId) =>
      userId == currentUser?.id ? myDetails : _details[userId];

  /// Снимката на свещеник (или null). Сваля се при първо поискване и при смяна.
  Uint8List? photoOf(String? userId) {
    if (userId == null) return null;
    if (userId == currentUser?.id) return myPhoto;
    final path = _details[userId]?.photoPath;
    if (path == null) return null;
    final stamp = '$path@${_detailsStamp[userId]}';
    if (_photoStamp[userId] != stamp && !_photoLoading.contains(userId)) {
      _photoLoading.add(userId);
      unawaited(_downloadPhoto(userId, path, stamp));
    }
    return _photos[userId];
  }

  Future<void> _downloadPhoto(String userId, String path, String stamp) async {
    try {
      _photos[userId] = await _db.storage.from('avatars').download(path);
    } catch (e) {
      _photos.remove(userId);
      debugPrint('Снимката не се свали: $e');
    }
    _photoStamp[userId] = stamp;
    _photoLoading.remove(userId);
    notifyListeners();
  }

  Future<void> _loadDetails() async {
    try {
      final rows = await _db.from('profile_details').select();
      _details.clear();
      _detailsStamp.clear();
      for (final r in rows) {
        final id = r['user_id'] as String;
        _details[id] = ProfileDetails.fromRow(r);
        _detailsStamp[id] = r['updated_at']?.toString() ?? '';
      }
      final me = currentUser?.id;
      myDetails = (me == null ? null : _details[me]) ?? ProfileDetails();
      final path = myDetails.photoPath;
      final stamp = path == null ? null : '$path@${_detailsStamp[me]}';
      if (stamp != _myPhotoStamp) {
        myPhoto = path == null ? null : await _db.storage.from('avatars').download(path);
        _myPhotoStamp = stamp;
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Личните профили не се заредиха: $e');
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
      _myPhotoStamp = null;
      unawaited(_loadDetails());
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

  /// Има ли свещеникът право [perm] в храма. Председателят има всички.
  bool hasPermission(String churchId, String perm, {String? userId}) {
    final uid = userId ?? currentUser?.id;
    final m = _members
        .where((m) => m.churchId == churchId && m.userId == uid && m.isActive)
        .firstOrNull;
    if (m == null) return false;
    return m.isManager || m.permissions.contains(perm);
  }

  /// Касиер: достъп до касата (председателят винаги има).
  bool canSeeCash(String churchId) => hasPermission(churchId, 'cash');

  // ------------------------------------------------------------------
  // Каса
  // ------------------------------------------------------------------
  CashSettings cashSettings(String churchId) => _cashSettings[churchId] ?? const CashSettings();

  /// Назначеният касиер (не председателят) или null.
  String? cashierOf(String churchId) => _members
      .where((m) =>
          m.churchId == churchId && m.isActive && !m.isManager && m.permissions.contains('cash'))
      .firstOrNull
      ?.userId;

  bool _isHolder(String churchId, String userId) => hasPermission(churchId, 'cash', userId: userId);

  /// Записите, които виждам (целия храм за касиер/председател, иначе своите).
  List<CashEntry> cashEntries(String churchId) => _cash.where((e) => e.churchId == churchId).toList()
    ..sort((a, b) {
      final d = b.date.compareTo(a.date);
      return d != 0 ? d : b.createdAt.compareTo(a.createdAt);
    });

  List<CashEntry> myCashEntries(String churchId) =>
      cashEntries(churchId).where((e) => e.createdBy == currentUser?.id).toList();

  // ------------------------------------------------------------------
  // Склад (води се като касата: председател и касиер)
  // ------------------------------------------------------------------
  List<StockMove> stockMoves(String churchId, {StockItem? item}) => _stock
      .where((m) => m.churchId == churchId && (item == null || m.item == item))
      .toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  Map<StockItem, int> stockOf(String churchId) => stockBalances(_stock.where((m) => m.churchId == churchId));

  int stockMin(String churchId, StockItem i) => _stockMin['$churchId|${i.code}'] ?? i.defaultMin;

  /// Видовете под границата (за предупреждението на началния екран).
  List<StockItem> lowStock(String churchId) {
    if (!canSeeCash(churchId)) return [];
    final b = stockOf(churchId);
    return StockItem.values.where((i) => b[i]! <= stockMin(churchId, i)).toList();
  }

  List<StockMove> stockToDecide(String churchId) {
    final me = currentUser?.id;
    if (!canSeeCash(churchId)) return [];
    return _stock.where((m) => m.churchId == churchId && m.isPending && m.createdBy != me).toList();
  }

  Future<void> loadStock(String churchId, StockItem item, int qty, String note) async {
    try {
      final row = await _db.rpc('stock_load',
          params: {'p_church': churchId, 'p_item': item.code, 'p_qty': qty, 'p_note': note});
      final mv = StockMove.fromRow(Map<String, dynamic>.from(row as Map));
      _stock.add(mv);
      notifyListeners();
      unawaited(_invokeNotify({'type': 'stock_loaded', 'move_id': mv.id}));
    } catch (err) {
      throw AppError(_friendly(err));
    }
  }

  Future<StockMove> writeOffStock(String churchId, StockItem item, int qty, String reason) async {
    try {
      final row = await _db.rpc('stock_writeoff',
          params: {'p_church': churchId, 'p_item': item.code, 'p_qty': qty, 'p_note': reason});
      final mv = StockMove.fromRow(Map<String, dynamic>.from(row as Map));
      _stock.add(mv);
      notifyListeners();
      if (mv.isPending) unawaited(_invokeNotify({'type': 'stock_pending', 'move_id': mv.id}));
      return mv;
    } catch (err) {
      throw AppError(_friendly(err));
    }
  }

  Future<void> decideStock(StockMove mv, bool approve, {String reason = ''}) async {
    try {
      await _db.rpc('stock_decide', params: {'p_move': mv.id, 'p_approve': approve, 'p_reason': reason});
      await refresh();
    } catch (err) {
      throw AppError(_friendly(err));
    }
    unawaited(_invokeNotify({'type': 'stock_decided', 'move_id': mv.id}));
  }

  /// Ревизиите, групирани по проверка (най-новите отгоре).
  List<List<StockAudit>> stockAudits(String churchId) {
    final by = <String, List<StockAudit>>{};
    for (final a in _audits.where((a) => a.churchId == churchId)) {
      (by[a.batch] ??= []).add(a);
    }
    final list = by.values.toList()
      ..sort((a, b) => b.first.createdAt.compareTo(a.first.createdAt));
    for (final l in list) {
      l.sort((a, b) => a.item.index.compareTo(b.item.index));
    }
    return list;
  }

  static String _newUuid() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  /// Председателят изтрива ревизия (само архив – складът не се променя).
  Future<void> deleteAudit(String churchId, String batch) async {
    try {
      await _db.rpc('stock_audit_delete', params: {'p_church': churchId, 'p_batch': batch});
      _audits.removeWhere((a) => a.churchId == churchId && a.batch == batch);
      notifyListeners();
    } catch (err) {
      throw AppError(_friendly(err));
    }
  }

  /// Записва ревизия (само проверка – наличността не се променя).
  Future<void> saveAudit(String churchId, Map<StockItem, int> counted, String note) async {
    final batch = _newUuid();
    try {
      for (final e in counted.entries) {
        await _db.rpc('stock_audit', params: {
          'p_church': churchId,
          'p_batch': batch,
          'p_item': e.key.code,
          'p_counted': e.value,
          'p_note': note,
        });
      }
      await refresh();
    } catch (err) {
      throw AppError(_friendly(err));
    }
  }

  Future<void> setStockMin(String churchId, StockItem item, int min) async {
    try {
      await _db.rpc('stock_set_threshold', params: {'p_church': churchId, 'p_item': item.code, 'p_min': min});
      _stockMin['$churchId|${item.code}'] = min;
      notifyListeners();
    } catch (err) {
      throw AppError(_friendly(err));
    }
  }

  // ---- приключване на месеци
  CashPeriod? periodOf(String churchId, DateTime d) => _periods
      .where((p) => p.churchId == churchId && p.month.year == d.year && p.month.month == d.month)
      .firstOrNull;

  bool isMonthClosed(String churchId, DateTime d) => periodOf(churchId, d)?.isClosed ?? false;

  /// Месец, чакащ моето одобрение (председателят).
  List<CashPeriod> closesToApprove(String churchId) => isManagerOf(churchId)
      ? _periods
          .where((p) => p.churchId == churchId && !p.isClosed && p.requestedBy != currentUser?.id)
          .toList()
      : [];

  /// Мога ли да поискам приключване (касиерът; без касиер – председателят).
  bool canRequestClose(String churchId) {
    if (cashSettings(churchId).approvalsOff && canSeeCash(churchId)) return true;
    final cashier = cashierOf(churchId);
    return cashier == null ? isManagerOf(churchId) : cashier == currentUser?.id;
  }

  String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> requestClose(String churchId, DateTime month) async {
    final m = DateTime(month.year, month.month, 1);
    try {
      final row = await _db.rpc('cash_close_request', params: {'p_church': churchId, 'p_month': _iso(m)});
      await refresh();
      final st = (row as Map)['status'];
      if (st == 'pending') {
        unawaited(_invokeNotify({'type': 'cash_close_pending', 'church_id': churchId, 'month': _iso(m)}));
      }
    } catch (err) {
      throw AppError(_friendly(err));
    }
  }

  Future<void> decideClose(String churchId, DateTime month, bool approve) async {
    final m = DateTime(month.year, month.month, 1);
    try {
      await _db.rpc('cash_close_decide', params: {'p_church': churchId, 'p_month': _iso(m), 'p_approve': approve});
      await refresh();
    } catch (err) {
      throw AppError(_friendly(err));
    }
    unawaited(_invokeNotify(
        {'type': 'cash_close_decided', 'church_id': churchId, 'month': _iso(m), 'approved': approve}));
  }

  /// Въведеното начално салдо за сметката (чакащо или влязло) или null.
  CashEntry? openingFor(String churchId, String account) => _cash
      .where((e) =>
          e.churchId == churchId && e.book == CashBook.opening && e.account == account && !e.isReturned)
      .firstOrNull;

  /// За кои сметки още може да се въведе начално салдо (еднократно).
  List<String> openingAccountsLeft(String churchId) => [
        if (openingFor(churchId, 'cash') == null) 'cash',
        if (cashSettings(churchId).hasBank && openingFor(churchId, 'bank') == null) 'bank',
      ];

  /// Мога ли да реша чакащия запис (същото правило като на сървъра).
  bool canDecideCash(CashEntry e) {
    final me = currentUser?.id;
    if (me == null || !e.isPending || e.createdBy == me || !canSeeCash(e.churchId)) return false;
    if (e.book == CashBook.income && !e.isReversal && !_isHolder(e.churchId, e.createdBy)) {
      final cashier = cashierOf(e.churchId);
      return cashier == null || cashier == me;
    }
    return true;
  }

  List<CashEntry> cashToDecide(String churchId) =>
      cashEntries(churchId).where(canDecideCash).toList().reversed.toList();

  Future<CashEntry> addCash({
    required CashBook book,
    required double amount,
    required String category,
    String categoryOther = '',
    String note = '',
    String account = 'cash',
    String? direction,
    String? eventId,
    DateTime? date,
    String donor = '',
  }) async {
    String iso(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    try {
      final row = await _db.rpc('cash_add', params: {
        'p_church': currentChurchId,
        'p_book': book.name,
        'p_amount': amount,
        'p_category': category,
        'p_category_other': categoryOther,
        'p_note': note,
        'p_account': account,
        'p_direction': direction,
        'p_event': eventId,
        'p_date': date == null ? null : iso(date),
      });
      var e = CashEntry.fromRow(Map<String, dynamic>.from(row as Map));
      if (donor.trim().isNotEmpty && book == CashBook.income && category == 'Дарение') {
        await _db.rpc('cash_set_donor', params: {'p_entry': e.id, 'p_donor': donor.trim()});
        e = CashEntry.fromRow({...Map<String, dynamic>.from(row), 'donor': donor.trim()});
      }
      _cash.add(e);
      notifyListeners();
      if (e.isPending) unawaited(_invokeNotify({'type': 'cash_pending', 'entry_id': e.id}));
      return e;
    } catch (err) {
      throw AppError(_friendly(err));
    }
  }

  Future<void> decideCash(CashEntry e, bool approve, {String reason = ''}) async {
    try {
      await _db.rpc('cash_decide', params: {'p_entry': e.id, 'p_approve': approve, 'p_reason': reason});
      await refresh();
    } catch (err) {
      throw AppError(_friendly(err));
    }
    unawaited(_invokeNotify({'type': 'cash_decided', 'entry_id': e.id}));
  }

  Future<CashEntry> reverseCash(CashEntry e, String reason) async {
    try {
      final row = await _db.rpc('cash_reverse', params: {'p_entry': e.id, 'p_reason': reason});
      final r = CashEntry.fromRow(Map<String, dynamic>.from(row as Map));
      await refresh();
      if (r.isPending) unawaited(_invokeNotify({'type': 'cash_pending', 'entry_id': r.id}));
      return r;
    } catch (err) {
      throw AppError(_friendly(err));
    }
  }

  Future<void> saveCashSettings(String churchId, double limit, bool hasBank, {bool approvalsOff = false}) async {
    try {
      await _db.rpc('cash_save_settings',
          params: {'p_church': churchId, 'p_limit': limit, 'p_has_bank': hasBank, 'p_approvals_off': approvalsOff});
      await refresh();
    } catch (err) {
      throw AppError(_friendly(err));
    }
  }

  /// Председателят дава или отнема право на свещеник.
  Future<void> setPermission(String churchId, String userId, String perm, bool on) async {
    try {
      await _db.rpc('set_member_permission',
          params: {'p_church': churchId, 'p_user': userId, 'p_perm': perm, 'p_on': on});
      await refresh();
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

  /// Сменя сана (или го маха с null) и телефона за колегите.
  Future<void> setRankAndPhone(ClergyRank? rank, String phone) async {
    final ph = phone.trim();
    try {
      await _db
          .from('profiles')
          .update({'rank': rank?.code, 'phone': ph.isEmpty ? null : ph}).eq('id', currentUser!.id);
      await refresh();
    } on PostgrestException catch (e) {
      if (e.message.contains('phone')) throw AppError('Телефонът не изглежда правилен.');
      throw AppError(_friendly(e));
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
            (e.ownerId == u.id || e.assigneeId == u.id || e.shared) &&
            // моите непотвърдени са в картите „Моля, потвърдете“, не в календара
            !(e.assigneeId == u.id && e.ownerId != u.id && !e.isAccepted))
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
    if (u == null || e.isCancelled) return [];
    return _events
        .where((x) =>
            x.id != e.id &&
            x.churchId == e.churchId &&
            !x.isCancelled &&
            (x.ownerId == u.id || x.assigneeId == u.id || x.shared) &&
            x.overlaps(e) &&
            // Архиерейската Литургия заема целия храм – засича се с всичко.
            (x.kind.occupiesChurch ||
                e.kind.occupiesChurch ||
                (!e.outsideChurch && !x.outsideChurch && x.assigneeId != e.assigneeId)))
        .toList()
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
  }

  /// Заглавие на предупреждението за заетия храм.
  String placeOverlapTitle(ChurchEvent e, List<ChurchEvent> list) {
    if (e.kind.occupiesChurch) return 'По време на Архиерейската Литургия има записани събития';
    if (list.any((x) => x.kind.occupiesChurch)) return 'По това време е Архиерейска Литургия – храмът е зает';
    return 'Храмът е зает по това време';
  }

  /// Търсене в събитията на текущия храм: име, телефон, адрес, бележка,
  /// вид, свещеник. Предстоящите първи (най-близкото най-горе), после минали.
  List<ChurchEvent> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.length < 2) return [];
    final now = DateTime.now();
    final qDigits = q.replaceAll(' ', '');
    bool hit(ChurchEvent e) =>
        [e.forWhom, e.fullAddress, e.note, e.kind.label, priestName(e.assigneeId)]
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

  // ------------------------------------------------------------------
  // Потвърждение на събитие, записано от колега
  // ------------------------------------------------------------------
  /// Събития, които чакат моето потвърждение (във всички мои храмове).
  List<ChurchEvent> get awaitingMyConfirmation {
    final u = currentUser;
    if (u == null) return [];
    final ids = myChurches.map((c) => c.id).toSet();
    return _events
        .where((e) => e.assigneeId == u.id && e.awaitsConfirmation && ids.contains(e.churchId))
        .toList()
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
  }

  /// Моите откази, които чакат решение на председателя.
  List<ChurchEvent> get myDeclinesInReview {
    final u = currentUser;
    if (u == null) return [];
    return _events.where((e) => e.declinedById == u.id && e.isDeclined).toList();
  }

  /// Отказани събития за решение (вижда ги председателят).
  List<ChurchEvent> declinedForReview(String churchId) => isManagerOf(churchId)
      ? (_events.where((e) => e.churchId == churchId && e.isDeclined).toList()
        ..sort((a, b) => a.startsAt.compareTo(b.startsAt)))
      : [];

  ChurchEvent _merge(Map<String, dynamic> row) {
    final e = ChurchEvent.fromRow(row);
    _events.removeWhere((x) => x.id == e.id);
    _events.add(e);
    _rows[e.id] = row;
    return e;
  }

  final Set<String> _seenSent = {};

  /// Отбелязва „видяно“ на молба за потвърждение (веднъж; вижда се от
  /// записалия и председателя).
  Future<void> markSeen(ChurchEvent e) async {
    if (e.assigneeId != currentUser?.id || e.ownerId == e.assigneeId) return;
    if (e.seenAt != null || !_seenSent.add(e.id)) return;
    try {
      final t = await _db.rpc('mark_event_seen', params: {'p_event': e.id});
      if (t is String) {
        e.seenAt = DateTime.tryParse(t)?.toLocal();
        notifyListeners();
      }
    } catch (err) {
      _seenSent.remove(e.id);
      debugPrint('„Видяно“ не се записа: $err');
    }
  }

  /// Приемам или отказвам събитие, записано за мен.
  Future<void> respondAssignment(ChurchEvent e,
      {required bool accept, String reason = '', String? substituteId}) async {
    try {
      final row = await _db.rpc('respond_assignment', params: {
        'p_event': e.id,
        'p_accept': accept,
        'p_reason': reason.trim().isEmpty ? null : reason.trim(),
        'p_substitute': substituteId,
      });
      final saved = _merge(Map<String, dynamic>.from(row as Map));
      notifyListeners();
      if (accept && saved.status == EventStatus.planned) await Notifier.schedule(saved);
    } catch (err) {
      throw AppError(_friendly(err));
    }
    unawaited(_invokeNotify({
      'type': accept ? 'assignment_accepted' : 'assignment_declined',
      'event_id': e.id,
    }));
  }

  /// Председателят решава отказ: прехвърля на [assigneeId] или оставя на
  /// отказалия (ако [assigneeId] е той).
  Future<void> resolveDecline(ChurchEvent e, String assigneeId) async {
    final decliner = e.declinedById;
    try {
      final row = await _db.rpc('resolve_decline', params: {'p_event': e.id, 'p_assignee': assigneeId});
      _merge(Map<String, dynamic>.from(row as Map));
      notifyListeners();
    } catch (err) {
      throw AppError(_friendly(err));
    }
    if (assigneeId == decliner) {
      unawaited(_invokeNotify({'type': 'assignment_kept', 'event_id': e.id}));
    } else if (assigneeId != currentUser?.id) {
      unawaited(_invokeNotify({'type': 'event', 'event_id': e.id, 'change': 'created'}));
    }
    unawaited(rescheduleReminders());
  }

  // ------------------------------------------------------------------
  // Смяна на председателя
  // ------------------------------------------------------------------
  /// Храмове, в които ми предлагат да стана председател.
  List<Church> get chairOffers =>
      myChurches.where((c) => c.pendingChairId == currentUser?.id).toList();

  Future<void> proposeChair(String churchId, String userId) async {
    try {
      await _db.rpc('propose_chair', params: {'p_church': churchId, 'p_user': userId});
      await refresh();
    } catch (e) {
      throw AppError(_friendly(e));
    }
    unawaited(_invokeNotify({'type': 'chair_proposed', 'church_id': churchId}));
  }

  Future<void> cancelChairTransfer(String churchId) async {
    try {
      await _db.rpc('cancel_chair_transfer', params: {'p_church': churchId});
      await refresh();
    } catch (e) {
      throw AppError(_friendly(e));
    }
  }

  /// Приемам или отказвам председателството.
  Future<void> respondChair(String churchId, bool accept) async {
    final String? proposer;
    try {
      proposer = await _db.rpc('respond_chair', params: {'p_church': churchId, 'p_accept': accept}) as String?;
      await refresh();
    } catch (e) {
      throw AppError(_friendly(e));
    }
    if (proposer != null) {
      unawaited(_invokeNotify({
        'type': 'chair_responded',
        'church_id': churchId,
        'proposer_id': proposer,
        'accepted': accept,
      }));
    }
  }

  // ------------------------------------------------------------------
  // Почивки
  // ------------------------------------------------------------------
  /// Моите заявки в храма (всички състояния), най-новите първи.
  LeaveRequest? leaveById(String id) => _leaves.where((l) => l.id == id).firstOrNull;

  List<LeaveRequest> myLeaves(String churchId) => _leaves
      .where((l) => l.churchId == churchId && l.userId == currentUser?.id)
      .toList()
    ..sort((a, b) => b.start.compareTo(a.start));

  /// Чакащи заявки за одобрение (вижда ги председателят).
  List<LeaveRequest> pendingLeaves(String churchId) => isManagerOf(churchId)
      ? (_leaves.where((l) => l.churchId == churchId && l.status == LeaveStatus.pending).toList()
        ..sort((a, b) => a.start.compareTo(b.start)))
      : [];

  /// Одобрените почивки в храма, които още не са минали.
  List<LeaveRequest> approvedLeaves(String churchId) {
    final today = DateTime.now();
    final d = DateTime(today.year, today.month, today.day);
    return _leaves
        .where((l) => l.churchId == churchId && l.status == LeaveStatus.approved && !l.end.isBefore(d))
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));
  }

  /// Почивки в този ден: одобрените (всички), а председателят – и чакащите.
  List<LeaveRequest> leavesOn(String churchId, DateTime day) => _leaves
      .where((l) =>
          l.churchId == churchId &&
          l.covers(day) &&
          (l.status == LeaveStatus.approved ||
              (l.status == LeaveStatus.pending && (isManagerOf(churchId) || l.userId == currentUser?.id))))
      .toList();

  bool isOnLeave(String churchId, String userId, DateTime day) => _leaves.any((l) =>
      l.churchId == churchId &&
      l.userId == userId &&
      l.status == LeaveStatus.approved &&
      l.covers(day));

  Future<void> requestLeave(DateTime start, DateTime end, String note) async {
    String iso(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    try {
      final row = await _db
          .from('leave_requests')
          .insert({
            'church_id': currentChurchId,
            'start_date': iso(start),
            'end_date': iso(end),
            'note': note.trim().isEmpty ? null : note.trim(),
          })
          .select()
          .single();
      final l = LeaveRequest.fromRow(row);
      _leaves.add(l);
      notifyListeners();
      unawaited(_invokeNotify({'type': 'leave_request', 'request_id': l.id}));
    } catch (e) {
      throw AppError(_friendly(e));
    }
  }

  Future<void> decideLeave(LeaveRequest l, bool approve, {String note = ''}) async {
    try {
      await _db.rpc('decide_leave', params: {
        'p_request': l.id,
        'p_approve': approve,
        'p_note': note.trim().isEmpty ? null : note.trim(),
      });
      await refresh();
    } catch (e) {
      throw AppError(_friendly(e));
    }
    unawaited(_invokeNotify({'type': 'leave_decided', 'request_id': l.id}));
  }

  /// Председателят прекратява одобрена почивка: непочналата се отменя
  /// цялата, течащата приключва вчера. Свещеникът получава известие.
  Future<void> endLeave(LeaveRequest l, String note) async {
    try {
      await _db.rpc('end_leave', params: {'p_request': l.id, 'p_note': note.trim().isEmpty ? null : note.trim()});
      await refresh();
    } catch (e) {
      throw AppError(_friendly(e));
    }
    unawaited(_invokeNotify({'type': 'leave_ended', 'request_id': l.id}));
  }

  /// Оттегля (своя чакаща) или отменя (председателят – всяка) заявка.
  Future<void> cancelLeave(LeaveRequest l) async {
    try {
      await _db.rpc('cancel_leave', params: {'p_request': l.id});
      _leaves.removeWhere((x) => x.id == l.id);
      notifyListeners();
    } catch (e) {
      throw AppError(_friendly(e));
    }
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
    // Проведено кръщене/венчавка движи склада на сървъра – обновяваме.
    if (stockForEvent(e.kind).isNotEmpty) unawaited(refresh());
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

  /// Населеното място на храма (за адреса по подразбиране и картата).
  String churchSettlement(String churchId) =>
      _churches.where((c) => c.id == churchId).firstOrNull?.settlement ?? '';

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

  // ------------------------------------------------------------------
  // Архиерейска Литургия: потвърждения от всички свещеници в храма
  // ------------------------------------------------------------------
  Map<String, DateTime> confirmationsFor(String eventId) => _confirmations[eventId] ?? const {};

  /// Потвърдил ли е свещеникът (записалият се брои за потвърдил).
  bool hasConfirmed(ChurchEvent e, String userId) =>
      e.ownerId == userId || confirmationsFor(e.id).containsKey(userId);

  /// Предстоящи Архиерейски Литургии, които още не съм потвърдил.
  List<ChurchEvent> get archieraticToConfirm {
    final me = currentUser?.id;
    if (me == null) return [];
    final now = DateTime.now();
    return _events
        .where((e) =>
            e.kind.occupiesChurch &&
            e.shared &&
            !e.isCancelled &&
            e.endsAt.isAfter(now) &&
            myChurches.any((c) => c.id == e.churchId) &&
            !hasConfirmed(e, me))
        .toList()
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
  }

  Future<void> confirmEvent(ChurchEvent e) async {
    try {
      final t = await _db.rpc('confirm_event', params: {'p_event': e.id});
      (_confirmations[e.id] ??= {})[currentUser!.id] =
          t == null ? DateTime.now() : DateTime.parse(t as String).toLocal();
      notifyListeners();
    } catch (err) {
      throw AppError(_friendly(err));
    }
    unawaited(_invokeNotify({'type': 'event_confirmed', 'event_id': e.id}));
  }

  /// Записва събитието на сървъра. При грешка хвърля [AppError].
  Future<void> saveEvent(ChurchEvent e) async {
    // Архиерейската Литургия е за целия храм: споделена, без отделен свещеник.
    if (e.kind.occupiesChurch) {
      e.shared = true;
      e.assigneeId = e.ownerId;
    }
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
      if (saved.kind.occupiesChurch) {
        // Нова Архиерейска Литургия → известие до всички свещеници в храма.
        if (before == null || before['kind'] != saved.kind.name) {
          unawaited(_invokeNotify({'type': 'church_event', 'event_id': saved.id}));
        }
      } else {
        unawaited(_notifyAssignee(saved, before));
      }
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
