// Shared helper for the automated test cases (ATC) documented in the report's Chapter 5.
//
// Every case has a unique Test Case ID (ATC-M<module>-<U|F|B|I><nn>) that is part of the test's name, so the Requirement Traceability Matrix
// can be checked against the code. When the environment variable ATC_LOG names a file, each case appends one JSON line to it with what the
// case was meant to do (objective, input, expected result), what it actually observed, and whether it matched. The report is generated
// from those lines, so the tables in the report are the results of real runs, never typed in by hand.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// What a case observed. [ok] says whether it matched the expected result; [actual] is the observation in plain words.
class Out {
  final bool ok;
  final String actual;
  const Out(this.ok, this.actual);
}

void _record(Map<String, Object?> m) {
  final path = Platform.environment['ATC_LOG'];
  if (path == null || path.isEmpty) return;
  File(path).writeAsStringSync('${jsonEncode(m)}\n', mode: FileMode.append, flush: true);
}

Map<String, Object?> _entry(String id, String req, String objective, String input, String expected, Out o, String? table, Map<String, String>? conds, String? actions) => {
      'id': id,
      'req': req,
      'objective': objective,
      'input': input,
      'expected': expected,
      'actual': o.actual,
      'ok': o.ok,
      'tool': 'Flutter test (Dart)',
      if (table != null) 'table': table,
      if (conds != null) 'conds': conds,
      if (actions != null) 'actions': actions,
    };

/// A logic (unit / business-rule / integration) case.
void atc(
  String id, {
  required String req,
  required String objective,
  required String input,
  required String expected,
  required FutureOr<Out> Function() run,
  String? table,
  Map<String, String>? conds,
  String? actions,
}) {
  test('$id $objective', () async {
    final o = await run();
    _record(_entry(id, req, objective, input, expected, o, table, conds, actions));
    expect(o.ok, isTrue, reason: o.actual);
  });
}

/// A case that needs a widget tree (functional tests of real screens).
void atcWidget(
  String id, {
  required String req,
  required String objective,
  required String input,
  required String expected,
  required Future<Out> Function(WidgetTester tester) run,
}) {
  testWidgets('$id $objective', (tester) async {
    final o = await run(tester);
    _record(_entry(id, req, objective, input, expected, o, null, null, null));
    expect(o.ok, isTrue, reason: o.actual);
  });
}

/// Compares two values and describes the observation: "got X" when they match, "got X, expected Y" when they do not.
Out same(Object? got, Object? want, {String? say}) => Out(got == want, say ?? 'Returned $got');

/// True/false check with the observed value in the text.
Out check(bool ok, String actual) => Out(ok, actual);
