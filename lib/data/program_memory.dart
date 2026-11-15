import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'program_doc.dart';

/// Запомнен човек за програмите.
class KnownPerson {
  String rank;
  String name;
  String role; // обичайна роля
  bool? serves; // последен избор в „Добави от пътуващите“
  KnownPerson(this.name, {this.rank = '', this.role = '', this.serves});

  String get fullName => rank.trim().isEmpty ? name.trim() : '${rank.trim()} ${name.trim()}';
  String get key => name.trim().toLowerCase();

  Map<String, dynamic> toJson() => {'rank': rank, 'name': name, 'role': role, 'serves': serves};
  factory KnownPerson.fromJson(Map<String, dynamic> j) => KnownPerson('${j['name'] ?? ''}',
      rank: '${j['rank'] ?? ''}', role: '${j['role'] ?? ''}', serves: j['serves'] as bool?);
}

/// Запомнена кола (с обичаен шофьор).
class KnownCar {
  String vehicle;
  String brand;
  String reg;
  String driver; // име на обичайния шофьор (по желание)
  KnownCar({this.vehicle = '', this.brand = '', this.reg = '', this.driver = ''});

  String get label => [
        vehicle.trim(),
        if (brand.trim().isNotEmpty) '„${brand.trim()}“',
        reg.trim().toUpperCase(),
      ].where((x) => x.isNotEmpty).join(' ');
  String get key => reg.trim().toUpperCase().replaceAll(' ', '');

  Map<String, dynamic> toJson() => {'vehicle': vehicle, 'brand': brand, 'reg': reg, 'driver': driver};
  factory KnownCar.fromJson(Map<String, dynamic> j) => KnownCar(
      vehicle: '${j['vehicle'] ?? ''}',
      brand: '${j['brand'] ?? ''}',
      reg: '${j['reg'] ?? ''}',
      driver: '${j['driver'] ?? ''}');
}

/// Паметта на пробата – само в този браузър (не отива в базата).
class ProgramMemory {
  static const _kPeople = 'program_people_v1';
  static const _kCars = 'program_cars_v1';
  final Map<String, KnownPerson> people = {};
  final Map<String, KnownCar> cars = {};

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      for (final j in (jsonDecode(p.getString(_kPeople) ?? '[]') as List)) {
        final k = KnownPerson.fromJson(Map<String, dynamic>.from(j as Map));
        if (k.key.isNotEmpty) people[k.key] = k;
      }
      for (final j in (jsonDecode(p.getString(_kCars) ?? '[]') as List)) {
        final c = KnownCar.fromJson(Map<String, dynamic>.from(j as Map));
        if (c.key.isNotEmpty) cars[c.key] = c;
      }
    } catch (_) {}
  }

  Future<void> save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kPeople, jsonEncode(people.values.map((e) => e.toJson()).toList()));
      await p.setString(_kCars, jsonEncode(cars.values.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }

  /// Хора, чието име или фамилия започва с написаното.
  List<KnownPerson> findPeople(String q) {
    final t = q.trim().toLowerCase();
    if (t.isEmpty) return [];
    final out = people.values
        .where((k) => k.name.toLowerCase().split(RegExp(r'\s+')).any((w) => w.startsWith(t)) ||
            k.name.toLowerCase().startsWith(t))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return out.take(12).toList();
  }

  /// Коли по марка, вид или номер.
  List<KnownCar> findCars(String q) {
    final t = q.trim().toLowerCase().replaceAll(' ', '');
    final all = cars.values.toList()..sort((a, b) => a.label.compareTo(b.label));
    if (t.isEmpty) return all;
    return all
        .where((c) =>
            c.brand.toLowerCase().contains(t) ||
            c.vehicle.toLowerCase().contains(t) ||
            c.key.toLowerCase().contains(t))
        .toList();
  }

  /// Дали човекът да е отбелязан в „Добави от пътуващите“.
  bool servesByDefault(ProgramPerson p) => people[p.name.trim().toLowerCase()]?.serves ?? p.clergy;

  /// Запомня всичко от програмата (хора, коли, обичайни шофьори).
  void learn(ProgramDoc d) {
    void person(ProgramPerson p, {bool keepRole = true}) {
      final key = p.name.trim().toLowerCase();
      if (key.isEmpty) return;
      final k = people[key] ?? KnownPerson(p.name.trim());
      k.name = p.name.trim();
      k.rank = p.rank;
      if (keepRole && p.role.trim().isNotEmpty) k.role = p.role.trim();
      people[key] = k;
    }

    for (final g in d.groups) {
      for (final p in g.people) {
        person(p);
      }
      final car = KnownCar(vehicle: g.vehicle.trim(), brand: g.brand.trim(), reg: g.reg.trim().toUpperCase());
      if (car.key.isNotEmpty) {
        final drv = g.people.where((p) => p.role.trim() == 'шофьор' && p.name.trim().isNotEmpty).firstOrNull;
        car.driver = drv?.name.trim() ?? cars[car.key]?.driver ?? '';
        cars[car.key] = car;
      }
    }
    for (final l in d.lists) {
      for (final p in l.people) {
        person(p, keepRole: false);
      }
    }
  }
}
