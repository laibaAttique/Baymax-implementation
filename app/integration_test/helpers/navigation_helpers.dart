// Bounded waits for the real-device tests. Several Baymax screens animate continuously (camera preview, waveform, rest
// timers), so pumpAndSettle would never return there; every wait below has a deadline and fails with a clear message.
import 'package:app/widgets/glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps frames for [d] in 100 ms steps (real time passes on the device).
Future<void> pumpFor(WidgetTester t, Duration d) async {
  final end = DateTime.now().add(d);
  while (DateTime.now().isBefore(end)) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// Pumps until [f] finds at least one widget, or throws after [timeout].
Future<void> waitFor(WidgetTester t, Finder f, {Duration timeout = const Duration(seconds: 20), String? what}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await t.pump(const Duration(milliseconds: 100));
    if (f.evaluate().isNotEmpty) return;
  }
  debugPrint('[device-step] timeout waiting for ${what ?? f.describeMatch(Plurality.one)}');
  throw TestFailure('Timed out after ${timeout.inSeconds} s waiting for ${what ?? f.describeMatch(Plurality.one)}');
}

/// Pumps until [f] finds nothing, or throws after [timeout].
Future<void> waitGone(WidgetTester t, Finder f, {Duration timeout = const Duration(seconds: 20), String? what}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await t.pump(const Duration(milliseconds: 100));
    if (f.evaluate().isEmpty) return;
  }
  throw TestFailure('Timed out after ${timeout.inSeconds} s waiting for ${what ?? 'a widget'} to disappear');
}

/// Scrolls [f] into view (if needed) and taps it, then pumps a few frames.
Future<void> tapOn(WidgetTester t, Finder f, {String? what}) async {
  debugPrint('[device-step] tap ${what ?? f.describeMatch(Plurality.one)}');
  await waitFor(t, f, what: what);
  await t.ensureVisible(f.first);
  await t.pump(const Duration(milliseconds: 200));
  await t.tap(f.first, warnIfMissed: false);
  await pumpFor(t, const Duration(milliseconds: 600));
}

/// Scrolls the visible vertical list under [within] (or the top screen) until [f] is visible. Horizontal scrollables
/// (tab pagers, chip rows) are skipped.
Future<void> scrollTo(WidgetTester t, Finder f, {Finder? within, double step = 300}) async {
  final vertical = find.descendant(
      of: within ?? find.byType(Scaffold).last,
      matching: find.byWidgetPredicate((w) => w is Scrollable && axisDirectionToAxis(w.axisDirection) == Axis.vertical));
  final onScreen = vertical.hitTestable();
  final scrollable = onScreen.evaluate().isNotEmpty ? onScreen.first : vertical.first;
  await t.scrollUntilVisible(f, step, scrollable: scrollable, maxScrolls: 60);
  await t.pump(const Duration(milliseconds: 200));
}

/// The bottom-bar tab with [label] (avoids matching an AppBar title with the same text).
Finder navTab(String label) => find.descendant(of: find.byType(GlassNavBar), matching: find.text(label)).hitTestable();

int count(Finder f) => f.evaluate().length;

/// A widget whose semantic label matches [pattern] (works without enabling the semantics tree).
Finder bySemantics(Pattern pattern) => find.byWidgetPredicate((w) {
      final label = w is Semantics ? w.properties.label : null;
      if (label == null) return false;
      return pattern is RegExp ? pattern.hasMatch(label) : label == pattern;
    }, description: 'semantics "$pattern"');
