import 'package:flutter_test/flutter_test.dart';
import 'package:kairos/data/program_doc.dart';

void main() {
  test('бройки с думи и групи', () {
    expect(countWords(3), 'трима човека');
    expect(countWords(4), 'четирима човека');
    expect(countWords(25), '25 човека');
    expect(groupOrdinal(0), 'I-ва');
    expect(groupOrdinal(2), 'III-та');
  });

  test('документът на програмата', () {
    final d = ProgramDoc.sample()..date = DateTime(2023, 10, 14);
    final h = programHtml(d);
    expect(d.groups.first.count, 4); // владиката + трима
    expect(h, contains('14.10.2023 г.'));
    expect(h, contains('събота'));
    expect(h, contains('Митрополит Киприан отпътува'));
    expect(h, contains('(Общо: четирима човека)'));
    expect(h, contains('(Общо пътуващи ${d.total} човека)'));
    expect(h, contains('Иван Иванов – шофьор.'));
    expect(h, contains('К И П Р И А Н'));
    expect(h, contains('Иподякон Димитър Димитров – шофьор,'));
    expect(h, isNot(contains('<script')));
  });

  test('часът се наследява от предишната група', () {
    final d = ProgramDoc(date: DateTime(2026, 1, 1), groups: [
      ProgramGroup(time: '08:30', withBishop: true),
      ProgramGroup(time: '08:00', timeManual: true),
      ProgramGroup(),
      ProgramGroup(time: '07:00'), // не е сменян ръчно – наследява
    ]);
    expect(d.times, ['08:30', '08:00', '08:00', '08:00']);
  });
}
