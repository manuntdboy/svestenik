import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';

/// „Как работи Кайрос“ – за хората, на които приложението не е представено лично.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  static const _sections = <(IconData, String, List<String>)>[
    (Icons.church_outlined, 'Какво е Кайрос', [
      'Кайрос е общото място на свещениците от един храм: кой какво служи и кога, кой е дежурен, кой е в почивка, касата и складът на храма и разговорите помежду ви.',
      'Работи на телефон (Android) и на компютър – в браузъра на адрес manuntdboy.github.io/svestenik. Данните са едни и същи навсякъде.',
      'Колега иска Кайрос? Профил → „Покани колега“ показва QR код – сканира го с телефона си и сваля приложението (или отваря сайта на iPhone). Без покани по имейл и без App Tester.',
      'Може да сте в няколко храма. „Смени“ горе превключва между тях, а със звездичката ☆ избирате основния – Кайрос винаги се отваря в него.',
    ]),
    (Icons.badge_outlined, 'Кой какво може', [
      'Свещеник – вижда календара, дежурствата и почивките на храма, пише в чата, иска почивка и размяна на дежурство.',
      'Председател – всичко от горното, плюс: одобрява влизането на нови хора, прави графика на дежурствата, одобрява почивки и размени, управлява касата и склада.',
      'Касиер – води касата и склада заедно с председателя.',
      'Касата и складът се виждат само от председателя и касиера. Никой друг – нито колегите, нито митрополията, нито създателят на приложението – не вижда сумите.',
    ]),
    (Icons.login_rounded, 'Влизане в храм', [
      'При регистрация избирате епархията си. После въвеждате кода на храма, който ви дава председателят, и чакате той да ви одобри.',
      'Нов храм се създава с име, населено място и духовна околия. Който го създаде, става председател.',
      'В профила на храма председателят попълва точния адрес и Булстат. Бутоните Google Maps и Waze водят направо до храма.',
    ]),
    (Icons.calendar_month_outlined, 'Календар', [
      'Изгледи „Ден“, „Седмица“ и „Месец“. Точките под датите показват, че има събития.',
      '„Ново събитие“: вид (кръщене, венчавка, погребение, панихида, водосвет, служба, архиерейска литургия, изповед, маслосвет, курбан и др.), дата, час, за кого и кой свещеник служи.',
      '„В храма“ или „Извън храма“. Събитие в храма по подразбиране е „Споделено с храма“ – виждат го всички колеги. „Само аз“ го вижда само този, който го е записал.',
      'Свещеникът, на когото е събитието, получава известие и го потвърждава с „ОК“. Може да си сложи напомняне с аларма.',
      'Когато събитието е извършено и има приход, той влиза направо в касата.',
      'Търсачката (лупата) намира събитие по име, вид или дата.',
      'Искате събитията и в Google Calendar или в календара на iPhone (и в уиджета на телефона)? Профил → „Календар в Google и iPhone“.',
    ]),
    (Icons.event_available_rounded, 'Календар в Google и iPhone', [
      'Събитията от Кайрос могат да се виждат и в календара на телефона ви – и в уиджета му на началния екран. Записвате само в Кайрос; Google и iPhone само ги показват.',
      'Отворете Профил → „Календар в Google и iPhone“. Изберете „Моите“ (вашите събития, дежурства и почивки) или „Целият храм“ (и споделените събития и дежурствата на колегите).',
      '„С имената“: включено – в календара пише и за кого е събитието; изключено – само вида и часа (напр. „Кръщене“).',
      'Android (Google Calendar): 1) Профил → „Календар в Google и iPhone“. 2) „Добави в Google Calendar“. 3) Ако пита – изберете Google профила от телефона. 4) „Добавяне“. 5) Отворете Google Calendar → ☰ → „Настройки“. 6) „Кайрос“ → включете „Синхронизиране“. Готово – виждате ги и в уиджета.',
      'iPhone: 1) Профил → „Календар в Google и iPhone“. 2) „Добави в календара на iPhone“. 3) „Абониране“ → „Добави“. Готово.',
      'Google обновява такива календари през няколко часа – ново събитие може да се появи там по-късно. За последния момент гледайте в Кайрос; известията идват веднага.',
      'Връзката е лична – не я споделяйте. Ако сте я пратили по погрешка, натиснете „Нова връзка“ и старата спира веднага.',
    ]),
    (Icons.shield_outlined, 'Дежурства', [
      'Председателят прави графика. Дежурният се вижда в календара със зелена лента за всеки ден.',
      'Размяна: свещеникът предлага на колега, колегата приема и председателят одобрява. Всеки получава известие на всяка стъпка.',
    ]),
    (Icons.beach_access_outlined, 'Почивки', [
      'Подавате молба за почивка с дати. Председателят я одобрява или отказва (с причина).',
      'Одобрените почивки се виждат в календара, за да не се записват събития на човек, който отсъства.',
    ]),
    (Icons.payments_outlined, 'Каса', [
      'Приходи и разходи, в брой и в банка. Всеки запис има номер, дата, категория и кой го е въвел.',
      'Разход до 100 € на ден влиза направо. Над това чака одобрение от другия от двамата (председател или касиер). Получавате известие със специален звук.',
      'Грешен запис не се трие – прави се сторно, за да остане следа. Върнат запис показва и причината.',
      'В края на месеца касата се приключва. „Справки“ показва приходите и разходите за месец или година, по видове и със сравнение.',
    ]),
    (Icons.inventory_2_outlined, 'Склад', [
      'Свещи и други артикули: зареждане, изписване и изписване за събитие. Наличността се смята сама.',
      'Изписването чака одобрение от другия от двамата, както в касата. Под зададения минимум Кайрос предупреждава.',
      'Ревизия: въвеждате преброеното и Кайрос показва разликата с книгата – само за сведение.',
    ]),
    (Icons.chat_bubble_outline_rounded, 'Чат', [
      '„Чат на храма“ е общият разговор на всички колеги. Има и лични разговори с всеки колега от храма.',
      'Под вашето съобщение се вижда кой го е видял. Можете да заглушите разговор с камбанката горе.',
      'Съобщенията са само текст и се пазят 6 месеца.',
    ]),
    (Icons.home_outlined, 'Начало', [
      '„Чака вас“ събира всичко, което иска вашето решение или „ОК“: нови хора, почивки, размени, записи в касата и склада, събития.',
      'Червена точка при „смени“ значи, че нещо ви чака в друг ваш храм.',
    ]),
    (Icons.notifications_active_outlined, 'Известия', [
      'Кайрос изпраща известие при всяко ново събитие, решение или съобщение, което ви засяга.',
      'Чакащите одобрение записи са със специален звук, а отказаните – с друг, за да ги разпознавате, без да гледате.',
      'Нова версия: приложението само ви казва, когато има обновление.',
    ]),
    (Icons.computer_outlined, 'Кайрос за компютър', [
      'Отворете manuntdboy.github.io/svestenik и влезте със същия профил.',
      'Горе: храмът (смяна от чипа), търсачка – Ctrl K, камбанка с чакащите и меню с вашето име.',
      'Касата е таблица – щракнете ред, за да отворите записа. До всяко съобщение в чата има ⋮ за действията.',
    ]),
    (Icons.phone_iphone_rounded, 'iPhone', [
      'Приложението е за Android. С iPhone работите през сайта: отворете manuntdboy.github.io/svestenik в Safari и влезте със същия профил. На телефона сайтът изглежда и работи като приложението.',
      'За да се отваря като приложение: в Safari натиснете „Сподели“ → „Добави към началния екран“. На екрана ще се появи иконката на Кайрос.',
      'Известия през сайта засега няма – проверявайте „Начало“ и чата сами. Подготвям известия и за iPhone.',
      'Напомнянията и алармата за събития работят само в приложението за Android – браузърът не може да звъни, когато е затворен.',
    ]),
    (Icons.forum_outlined, 'Предложения и грешки', [
      'Кайрос се прави заедно с вас. Всяко предложение, въпрос или забелязана грешка ми помага – пишете ми смело, дори за дреболия.',
      'В приложението: Профил → „Обратна връзка“ – съобщението стига направо до мен. Можете да приложите и снимка на екрана.',
      'По Viber: 0888 177 738 – Димитър Костадинов, създателят на Кайрос. Напишете ми какво сте правили, какво сте очаквали и какво се случи; снимка на екрана помага най-много.',
      'Отговарям и поправям възможно най-бързо. Новата версия идва сама – приложението ви казва, когато е готова.',
    ]),
    (Icons.lock_outline_rounded, 'Поверителност', [
      'Виждате само храмовете, в които сте одобрени. Касата и складът – само ако сте председател или касиер.',
      'Подробности има в „Лични данни и поверителност“ в профила.',
    ]),
  ];

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Как работи Кайрос')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
            Text('Кратко ръководство за всичко, което Кайрос може за храма. Натиснете раздел, за да го отворите.',
                style: TextStyle(fontSize: 15.5, color: p.textMuted)),
            const SizedBox(height: 12),
            for (final (icon, title, lines) in _sections)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: p.surface,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16), side: BorderSide(color: p.border)),
                  clipBehavior: Clip.antiAlias,
                  child: ExpansionTile(
                    shape: const Border(),
                    leading: Icon(icon, color: p.primary),
                    title: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final l in lines)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 8, right: 10),
                              child: Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(color: p.primary, shape: BoxShape.circle)),
                            ),
                            Expanded(child: _Linked(l, style: const TextStyle(fontSize: 15.5, height: 1.4))),
                          ]),
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),
            _Linked('Нещо не е ясно или не работи? Пишете на създателя на приложението от „Обратна връзка“ в профила или ми пишете по Viber на 0888 177 738.',
                style: TextStyle(fontSize: 14.5, color: p.textMuted)),
          ]),
        ),
      ),
    );
  }
}


/// Текст, в който адресът на сайта и Viber номерът се натискат.
class _Linked extends StatefulWidget {
  final String text;
  final TextStyle style;
  const _Linked(this.text, {required this.style});

  @override
  State<_Linked> createState() => _LinkedState();
}

class _LinkedState extends State<_Linked> {
  static const _site = 'manuntdboy.github.io/svestenik';
  static const _viber = '0888 177 738';
  final _taps = <TapGestureRecognizer>[];

  @override
  void dispose() {
    for (final t in _taps) {
      t.dispose();
    }
    super.dispose();
  }

  Future<void> _open(Uri uri) async {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    for (final t in _taps) {
      t.dispose();
    }
    _taps.clear();
    final p = Palette.of(context);
    final link = widget.style.copyWith(
        color: p.primary, fontWeight: FontWeight.w700, decoration: TextDecoration.underline);
    final spans = <InlineSpan>[];
    var rest = widget.text;
    while (rest.isNotEmpty) {
      final a = rest.indexOf(_site);
      final b = rest.indexOf(_viber);
      final i = [a, b].where((x) => x >= 0).fold<int>(-1, (m, x) => m < 0 || x < m ? x : m);
      if (i < 0) {
        spans.add(TextSpan(text: rest));
        break;
      }
      if (i > 0) spans.add(TextSpan(text: rest.substring(0, i)));
      final isSite = i == a;
      final word = isSite ? _site : _viber;
      final tap = TapGestureRecognizer()
        ..onTap = () => _open(isSite
            ? Uri.parse('https://$_site/')
            : Uri.parse('viber://chat?number=%2B359888177738'));
      _taps.add(tap);
      spans.add(TextSpan(text: word, style: link, recognizer: tap));
      rest = rest.substring(i + word.length);
    }
    return Text.rich(TextSpan(style: widget.style, children: spans));
  }
}
