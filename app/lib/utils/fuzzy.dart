/// String helpers shared by food matching (Module 7) and allergen matching
/// (Module 8).
class Fuzzy {
  Fuzzy._();

  static int levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    var prev = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final cur = List<int>.filled(b.length + 1, 0);
      cur[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        cur[j] = [cur[j - 1] + 1, prev[j] + 1, prev[j - 1] + cost].reduce((x, y) => x < y ? x : y);
      }
      prev = cur;
    }
    return prev[b.length];
  }

  /// Edits tolerated for a dictionary word of length [n]. Short words must
  /// match exactly to avoid false alarms.
  static int maxEdits(int n) => n <= 5 ? 0 : (n <= 8 ? 1 : 2);

  /// True when [token] is within the edit budget of dictionary word [term].
  static bool wordsMatch(String term, String token) {
    if (term == token) return true;
    final budget = maxEdits(term.length);
    if (budget == 0) return false;
    if ((term.length - token.length).abs() > budget) return false;
    return levenshtein(term, token) <= budget;
  }

  /// 0..1, where 1 is identical.
  static double similarity(String a, String b) {
    if (a.isEmpty && b.isEmpty) return 1;
    final longest = a.length > b.length ? a.length : b.length;
    return 1 - levenshtein(a, b) / longest;
  }

  /// Lower-case, strip punctuation, collapse whitespace.
  static String normalize(String s) {
    return s
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static List<String> tokens(String s) {
    final n = normalize(s);
    return n.isEmpty ? <String>[] : n.split(' ');
  }

  /// Undo common OCR digit/letter confusions inside a word that otherwise has
  /// letters (e.g. `mi1k` → `milk`, `s0y` → `soy`).
  static String deOcr(String word) {
    if (!RegExp(r'[a-z]').hasMatch(word) || !RegExp(r'[0-9]').hasMatch(word)) return word;
    return word.replaceAll('0', 'o').replaceAll('1', 'l').replaceAll('5', 's').replaceAll('3', 'e');
  }

  /// Crude singular form ("eggs" → "egg", "berries" → "berry").
  static String singular(String w) {
    if (w.length > 4 && w.endsWith('ies')) return '${w.substring(0, w.length - 3)}y';
    if (w.length > 4 && w.endsWith('es') && (w.endsWith('ches') || w.endsWith('shes') || w.endsWith('oes'))) {
      return w.substring(0, w.length - 2);
    }
    if (w.length > 3 && w.endsWith('s') && !w.endsWith('ss')) return w.substring(0, w.length - 1);
    return w;
  }
}
