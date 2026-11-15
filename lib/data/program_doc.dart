/// Програма за архиерейско служение („Списък на придружаващите…“) –
/// данни и документ за печат във вида на бланката на митрополията.
/// Засега само проба: нищо не се записва в базата.
library;

/// Сановете в падащото меню („“ – без сан).
const programRanks = [
  'Митрополит', 'Епископ', 'Архимандрит', 'Иеромонах', 'Протосингел', 'Протойерей', 'Иконом',
  'Свещеноиконом', 'Свещеник', 'Протодякон', 'Дякон', 'Иподякон', '',
];

/// Готовите роли (може и своя).
const programRoles = ['шофьор', 'видеооператор', 'фотограф', 'певец', 'хор – квартет', 'поканен'];

class ProgramPerson {
  String rank; // „Иконом“ („“ – без сан)
  String name; // „Иван Иванов“
  String role; // „шофьор“, „видеооператор“… (по желание)
  int rev = 0; // смяна отвън (подсказване) – полетата се създават наново
  ProgramPerson(this.name, {this.rank = '', this.role = ''});

  /// „Иконом Иван Иванов“.
  String get fullName => rank.trim().isEmpty ? name.trim() : '${rank.trim()} ${name.trim()}';
  bool get clergy => rank.trim().isNotEmpty;
}

class ProgramGroup {
  String time; // „08:30“ (важи, ако е първата група или часът е сменян ръчно)
  bool timeManual; // false – взема часа на предишната група
  bool withBishop; // владиката пътува в тази група
  String vehicle; // „лек автомобил“, „микробус“…
  String brand; // „Мерцедес“
  String reg; // „СТ7241РН“
  String from;
  String to;
  String note;
  List<ProgramPerson> people;
  ProgramGroup({
    this.time = '',
    this.timeManual = false,
    this.withBishop = false,
    this.vehicle = 'лек автомобил',
    this.brand = '',
    this.reg = '',
    this.from = '',
    this.to = '',
    this.note = '',
    List<ProgramPerson>? people,
  }) : people = people ?? [];

  /// Колко души пътуват в групата (владиката се брои).
  int get count => people.where((p) => p.name.trim().isNotEmpty).length + (withBishop ? 1 : 0);
}

class ProgramList {
  String title; // „Списък на служещите Водосвета от 11:00 часа.“
  List<ProgramPerson> people;
  ProgramList(this.title, [List<ProgramPerson>? people]) : people = people ?? [];
}

class ProgramDoc {
  String bishopTitle; // „Старозагорски Митрополит“
  String bishopName; // „КИПРИАН“
  String honorific; // „Негово Високопреосвещенство Старозагорския митрополит“
  String occasion; // „при посещението му в храм „…“ – с. …, … духовна околия.“
  DateTime date;
  List<ProgramGroup> groups;
  List<ProgramList> lists;
  List<String> notes;
  String preparedBy;
  ProgramDoc({
    this.bishopTitle = '',
    this.bishopName = '',
    this.honorific = '',
    this.occasion = '',
    required this.date,
    List<ProgramGroup>? groups,
    List<ProgramList>? lists,
    List<String>? notes,
    this.preparedBy = '',
  })  : groups = groups ?? [],
        lists = lists ?? [],
        notes = notes ?? [];

  int get total => groups.fold(0, (a, g) => a + g.count);

  /// Часът на всяка група: своя, ако е първата или е сменян ръчно, иначе на предишната.
  List<String> get times {
    final out = <String>[];
    for (var i = 0; i < groups.length; i++) {
      final g = groups[i];
      out.add(i == 0 || g.timeManual ? g.time : out[i - 1]);
    }
    return out;
  }

  /// Примерна програма с измислени имена – за да има какво да се види веднага.
  factory ProgramDoc.sample() => ProgramDoc(
        bishopTitle: 'Старозагорски Митрополит',
        bishopName: 'КИПРИАН',
        honorific: 'Негово Високопреосвещенство Старозагорския митрополит',
        occasion: 'при посещението му в храм „Св. Петка“ – с. Черганово, Казанлъшка духовна околия.',
        date: DateTime.now().add(const Duration(days: 7)),
        groups: [
          ProgramGroup(
            time: '08:30',
            withBishop: true,
            vehicle: 'лек автомобил',
            brand: 'Ауди',
            reg: 'СТ0000АА',
            from: 'Старозагорска митрополия',
            to: 'храм „Св. Петка“ – с. Черганово, Казанлъшка духовна околия',
            people: [
              ProgramPerson('Петър Петров', rank: 'Протодякон'),
              ProgramPerson('Георги Георгиев', rank: 'Иподякон'),
              ProgramPerson('Иван Иванов', role: 'шофьор'),
            ],
          ),
          ProgramGroup(
            time: '08:00',
            timeManual: true,
            vehicle: 'микробус',
            brand: 'Мерцедес',
            reg: 'СТ1111ББ',
            from: 'Старозагорската митрополия',
            to: 'храм „Св. Петка“ – с. Черганово, Казанлъшка духовна околия',
            people: [
              ProgramPerson('Николай Николов', rank: 'Архимандрит'),
              ProgramPerson('Стефан Стефанов', rank: 'Иконом'),
              ProgramPerson('Тодор Тодоров', rank: 'Свещеник'),
              ProgramPerson('Христо Христов', rank: 'Дякон'),
              ProgramPerson('Димитър Димитров', rank: 'Иподякон', role: 'шофьор'),
              ProgramPerson('Атанас Атанасов', role: 'видеооператор'),
            ],
          ),
        ],
        lists: [
          ProgramList('Списък на служещите Водосвета от 11:00 часа.', [
            ProgramPerson('КИПРИАН', rank: 'Митрополит'),
            ProgramPerson('Николай Николов', rank: 'Архимандрит'),
            ProgramPerson('Стефан Стефанов', rank: 'Иконом'),
            ProgramPerson('Тодор Тодоров', rank: 'Свещеник'),
          ]),
        ],
        notes: ['Водосветът ще започне в 11:00 часа.'],
        preparedBy: 'Петър Петров',
      );
}

const _weekdays = ['понеделник', 'вторник', 'сряда', 'четвъртък', 'петък', 'събота', 'неделя'];
const _ordinals = ['I-ва', 'II-ра', 'III-та', 'IV-та', 'V-та', 'VI-та', 'VII-ма', 'VIII-ма', 'IX-та', 'X-та'];
const _countWords = {
  1: 'един човек', 2: 'двама човека', 3: 'трима човека', 4: 'четирима човека', 5: 'пет човека',
  6: 'шест човека', 7: 'седем човека', 8: 'осем човека', 9: 'девет човека', 10: 'десет човека',
  11: 'единадесет човека', 12: 'дванадесет човека', 13: 'тринадесет човека', 14: 'четиринадесет човека',
  15: 'петнадесет човека', 16: 'шестнадесет човека', 17: 'седемнадесет човека',
  18: 'осемнадесет човека', 19: 'деветнадесет човека', 20: 'двадесет човека',
};

String weekdayBg(DateTime d) => _weekdays[d.weekday - 1];
String groupOrdinal(int i) => i < _ordinals.length ? _ordinals[i] : '${i + 1}-а';
String countWords(int n) => _countWords[n] ?? '$n човека';

/// „КИПРИАН“ → „Киприан“.
String _titleCase(String s) {
  final t = s.trim();
  if (t.isEmpty) return t;
  return t.split(RegExp(r'\s+')).map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase()).join(' ');
}

String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

String _dd(int n) => n.toString().padLeft(2, '0');

/// Номериран списък: запетая след всеки, точка след последния.
String _peopleList(List<ProgramPerson> people) {
  final ps = people.where((p) => p.name.trim().isNotEmpty).toList();
  if (ps.isEmpty) return '';
  final items = <String>[];
  for (var i = 0; i < ps.length; i++) {
    final p = ps[i];
    final role = p.role.trim().isEmpty ? '' : ' – ${_esc(p.role.trim())}';
    items.add('<li>${_esc(p.fullName)}$role${i == ps.length - 1 ? '.' : ','}</li>');
  }
  return '<ol>${items.join()}</ol>';
}

/// Цялата програма като HTML страница A4, готова за печат.
String programHtml(ProgramDoc d) {
  final b = StringBuffer();
  final date = '${_dd(d.date.day)}.${_dd(d.date.month)}.${d.date.year} г.';
  final spaced = d.bishopName.trim().toUpperCase().split('').join(' ');
  b.write('''<!doctype html><html lang="bg"><head><meta charset="utf-8">
<title>Програма ${_esc(date)}</title>
<style>
@page { size: A4; margin: 20mm 18mm 18mm 22mm; }
* { box-sizing: border-box; }
body { margin: 0; background: #e9e9e9; font-family: "Times New Roman", Tinos, "Liberation Serif", serif; font-size: 13pt; line-height: 1.32; color: #000; }
.bar { position: sticky; top: 0; background: #1b2740; color: #fff; padding: 10px 16px; display: flex; gap: 14px; align-items: center; font-family: Arial, sans-serif; font-size: 14px; }
.bar button { font-size: 15px; font-weight: 700; padding: 8px 18px; border-radius: 8px; border: 0; background: #e0ad2c; color: #1d1606; cursor: pointer; }
.page { width: 210mm; min-height: 297mm; margin: 16px auto; background: #fff; padding: 20mm 18mm 18mm 22mm; box-shadow: 0 2px 12px rgba(0,0,0,.2); }
.approve { margin-left: 2.5cm; }
.approve .sig { margin-left: 3.2cm; font-style: italic; }
.head { text-align: center; margin-top: 10pt; }
.name { letter-spacing: 3pt; font-weight: bold; }
.date { text-align: center; margin-top: 12pt; }
.date u { display: inline-block; }
h4 { font-weight: normal; font-style: italic; text-decoration: underline; margin: 10pt 0 0; font-size: 13pt; }
p { margin: 0; text-align: justify; }
.lead { text-indent: 1.25cm; }
ol { margin: 0; padding-left: 1.25cm; }
.total { text-align: center; font-style: italic; margin: 2pt 0 6pt; }
.grand { text-align: center; font-style: italic; margin: 10pt 0; }
.list h5 { text-align: center; text-decoration: underline; font-weight: normal; font-size: 13pt; margin: 12pt 0 4pt; }
.note { font-style: italic; margin-top: 8pt; }
.prep { margin-top: 26pt; margin-left: 55%; }
.prep .who { margin-left: 2cm; font-style: italic; }
@media print { body { background: #fff; } .bar { display: none; } .page { margin: 0; padding: 0; width: auto; min-height: 0; box-shadow: none; } }
</style></head><body>
<div class="bar"><button onclick="window.print()">Печат / PDF</button><span>Проба от Кайрос · данните не се записват</span></div>
<div class="page">
<p class="approve">УТВЪРЖДАВАМЕ:……………………………………</p>
<p class="approve"><span class="sig">† ${_esc(d.bishopTitle.trim())} ${_esc(d.bishopName.trim().toUpperCase())}</span></p>
<div class="head">
<p style="text-align:center">Списък на придружаващите</p>
<p style="text-align:center">${_esc(d.honorific.trim())}</p>
<p style="text-align:center" class="name">${_esc(spaced)}</p>
<p style="text-align:center">${_esc(d.occasion.trim())}</p>
</div>
<p class="date"><u>${_esc(date)}</u><br>${weekdayBg(d.date)}</p>
''');
  final bishop = 'Митрополит ${_titleCase(d.bishopName)}';
  final times = d.times;
  for (var i = 0; i < d.groups.length; i++) {
    final g = d.groups[i];
    final car = [
      g.vehicle.trim(),
      if (g.brand.trim().isNotEmpty) '„${g.brand.trim()}“',
      if (g.reg.trim().isNotEmpty) 'рег. № ${g.reg.trim().toUpperCase()}',
    ].join(' ');
    final from = g.from.trim().isEmpty ? '' : ' от ${_esc(g.from.trim())}';
    final to = g.to.trim().isEmpty ? '' : ' за ${_esc(g.to.trim())}';
    final time = times[i].trim().isEmpty ? '' : '<b>${_esc(times[i].trim())} часа</b> – ';
    b.write('<h4>${groupOrdinal(i)} група</h4>');
    if (g.withBishop) {
      b.write('<p class="lead">$time${_esc(bishop)} отпътува с <i>${_esc(car)}</i>$from$to.</p>');
      if (g.people.any((p) => p.name.trim().isNotEmpty)) b.write('<p>Придружават го:</p>');
    } else {
      b.write('<p class="lead">${time}отпътуват с <i>${_esc(car)}</i>$from$to.</p>');
    }
    b.write(_peopleList(g.people));
    b.write('<p class="total">(Общо: ${countWords(g.count)})</p>');
    if (g.note.trim().isNotEmpty) b.write('<p class="note">*** Забележка – ${_esc(g.note.trim())}</p>');
  }
  if (d.groups.isNotEmpty) b.write('<p class="grand">(Общо пътуващи ${d.total} човека)</p>');
  for (final l in d.lists) {
    if (l.title.trim().isEmpty && l.people.every((p) => p.name.trim().isEmpty)) continue;
    b.write('<div class="list"><h5>${_esc(l.title.trim())}</h5>${_peopleList(l.people)}</div>');
  }
  for (final n in d.notes) {
    if (n.trim().isEmpty) continue;
    b.write('<p class="note">Забележка: ${_esc(n.trim())}</p>');
  }
  b.write('<div class="prep"><p>Изготвил:……………………………</p>'
      '<p class="who">/${_esc(d.preparedBy.trim())}/</p></div>');
  b.write('</div></body></html>');
  return b.toString();
}
