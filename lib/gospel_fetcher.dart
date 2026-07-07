import 'dart:convert';

import 'package:http/http.dart' as http;

/// Risultato della composizione automatica di un brano.
class ComposeResult {
  final String italian; // traduzione italiana
  final String original; // testo originale (greco o arabo)
  final String originalLanguage; // etichetta della lingua originale
  const ComposeResult({
    required this.italian,
    required this.original,
    required this.originalLanguage,
  });
}

class ComposeException implements Exception {
  final String message;
  ComposeException(this.message);
  @override
  String toString() => message;
}

/// Compone il testo di un brano a partire dalla citazione.
///
/// - Bibbia (es. "Marco 4, 35-41"): italiano Diodati + greco Textus Receptus
///   da getbible.net.
/// - Corano (es. "Corano 2, 255" o "Sura 2, 255"): italiano (Piccardo) + arabo
///   da alquran.cloud.
///
/// Entrambe le fonti sono accessibili dal browser (CORS aperto).
class GospelFetcher {
  Future<ComposeResult> compose(String reference) async {
    final s = reference.trim();
    if (_isQuran(s)) return _composeQuran(s);
    return _composeBible(s);
  }

  // ==================== BIBBIA ====================
  static const _bibleBase = 'https://api.getbible.net/v2';

  Future<ComposeResult> _composeBible(String reference) async {
    final ref = _parseBible(reference);
    final italian = await _fetchBible('giovanni', ref);
    final greek = await _fetchBible('textusreceptus', ref);
    if (italian.isEmpty && greek.isEmpty) {
      throw ComposeException(
          'Nessun versetto trovato per "$reference". Controlla la citazione.');
    }
    return ComposeResult(
      italian: italian,
      original: greek,
      originalLanguage: 'Greco (Textus Receptus)',
    );
  }

  Future<String> _fetchBible(String translation, _Ref ref) async {
    final url = '$_bibleBase/$translation/${ref.book}/${ref.chapter}.json';
    final resp = await http.get(Uri.parse(url));
    if (resp.statusCode != 200) {
      throw ComposeException('Impossibile scaricare il testo. Riprova.');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final raw = data['verses'] ?? data['chapter'];
    final list = raw is List ? raw : (raw as Map).values.toList();
    return _joinRange(list, 'verse', 'text', ref.from, ref.to);
  }

  // ==================== CORANO ====================
  static const _quranBase = 'https://api.alquran.cloud/v1';

  Future<ComposeResult> _composeQuran(String reference) async {
    final ref = _parseQuran(reference);
    final italian = await _fetchQuran('it.piccardo', ref);
    final arabic = await _fetchQuran('quran-uthmani', ref);
    if (italian.isEmpty && arabic.isEmpty) {
      throw ComposeException(
          'Nessun versetto trovato per "$reference". Controlla la citazione.');
    }
    return ComposeResult(
      italian: italian,
      original: arabic,
      originalLanguage: 'Arabo (testo coranico)',
    );
  }

  Future<String> _fetchQuran(String edition, _Ref ref) async {
    final url = '$_quranBase/surah/${ref.book}/$edition';
    final resp = await http.get(Uri.parse(url));
    if (resp.statusCode != 200) {
      throw ComposeException('Impossibile scaricare il testo del Corano. Riprova.');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final ayahs = (data['data']?['ayahs']) as List? ?? const [];
    return _joinRange(ayahs, 'numberInSurah', 'text', ref.from, ref.to);
  }

  // ==================== util ====================
  String _joinRange(
      List list, String numKey, String textKey, int from, int to) {
    final buf = <String>[];
    for (final v in list) {
      final m = v as Map<String, dynamic>;
      final n = (m[numKey] is int)
          ? m[numKey] as int
          : int.tryParse('${m[numKey]}') ?? 0;
      if (n < from || n > to) continue;
      buf.add((m[textKey] as String).trim());
    }
    return buf.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  bool _isQuran(String s) {
    final head = s.toLowerCase().trimLeft();
    return head.startsWith('corano') ||
        head.startsWith('quran') ||
        head.startsWith('sura') ||
        head.startsWith('surah');
  }

  _Ref _parseQuran(String input) {
    // "Corano 2, 255" | "Sura 2:255" | "Corano 2, 1-5" | "Corano 1"
    final m = RegExp(
      r'^(?:corano|quran|surah|sura)\s+(\d+)\s*(?:[,:]\s*(\d+)\s*(?:[-–]\s*(\d+))?)?\s*$',
      caseSensitive: false,
    ).firstMatch(input.trim());
    if (m == null) {
      throw ComposeException(
          'Citazione del Corano non riconosciuta. Usa "Corano 2, 255".');
    }
    final surah = int.parse(m.group(1)!);
    if (surah < 1 || surah > 114) {
      throw ComposeException('Sura inesistente: $surah (1–114).');
    }
    final from = m.group(2) != null ? int.parse(m.group(2)!) : 1;
    final to = m.group(3) != null
        ? int.parse(m.group(3)!)
        : (m.group(2) != null ? from : 999);
    return _Ref(book: surah, chapter: 0, from: from, to: to);
  }

  _Ref _parseBible(String input) {
    final m = RegExp(
      r"^([1-3]|i{1,3}|I{1,3})?\s*([A-Za-zÀ-ÿ.’' ]+?)\s+(\d+)\s*(?:[,:]\s*(\d+)\s*(?:[-–]\s*(\d+))?)?\s*$",
    ).firstMatch(input.trim());
    if (m == null) {
      throw ComposeException(
          'Citazione non riconosciuta. Usa un formato come "Marco 4, 35-41".');
    }
    final ordinale = _ordinale(m.group(1));
    final nomeGrezzo = m.group(2)!;
    final chapter = int.parse(m.group(3)!);
    final from = m.group(4) != null ? int.parse(m.group(4)!) : 1;
    final to = m.group(5) != null
        ? int.parse(m.group(5)!)
        : (m.group(4) != null ? from : 999);
    final key = ordinale + _normalize(nomeGrezzo);
    final book = _books[key] ?? _books[_normalize(nomeGrezzo)];
    if (book == null) {
      throw ComposeException('Libro non riconosciuto: "$nomeGrezzo".');
    }
    return _Ref(book: book, chapter: chapter, from: from, to: to);
  }

  String _ordinale(String? g) {
    if (g == null) return '';
    final t = g.toLowerCase();
    if (t == '1' || t == 'i') return '1';
    if (t == '2' || t == 'ii') return '2';
    if (t == '3' || t == 'iii') return '3';
    return '';
  }

  String _normalize(String s) {
    var t = s.toLowerCase().trim();
    const accents = {
      'à': 'a', 'á': 'a', 'è': 'e', 'é': 'e', 'ì': 'i', 'í': 'i',
      'ò': 'o', 'ó': 'o', 'ù': 'u', 'ú': 'u',
    };
    accents.forEach((k, v) => t = t.replaceAll(k, v));
    return t.replaceAll(RegExp(r"[^a-z]"), '');
  }

  static const Map<String, int> _books = {
    'genesi': 1, 'esodo': 2, 'levitico': 3, 'numeri': 4, 'deuteronomio': 5,
    'giosue': 6, 'giudici': 7, 'rut': 8, '1samuele': 9, '2samuele': 10,
    '1re': 11, '2re': 12, '1cronache': 13, '2cronache': 14, 'esdra': 15,
    'neemia': 16, 'ester': 17, 'giobbe': 18, 'salmi': 19, 'salmo': 19,
    'proverbi': 20, 'ecclesiaste': 21, 'cantico': 22, 'canticodeicantici': 22,
    'isaia': 23, 'geremia': 24, 'lamentazioni': 25, 'ezechiele': 26,
    'daniele': 27, 'osea': 28, 'gioele': 29, 'amos': 30, 'abdia': 31,
    'giona': 32, 'michea': 33, 'nahum': 34, 'abacuc': 35, 'sofonia': 36,
    'aggeo': 37, 'zaccaria': 38, 'malachia': 39,
    'matteo': 40, 'marco': 41, 'luca': 42, 'giovanni': 43,
    'atti': 44, 'attidegliapostoli': 44, 'romani': 45,
    '1corinzi': 46, '2corinzi': 47, 'galati': 48, 'efesini': 49,
    'filippesi': 50, 'colossesi': 51, '1tessalonicesi': 52, '2tessalonicesi': 53,
    '1timoteo': 54, '2timoteo': 55, 'tito': 56, 'filemone': 57, 'ebrei': 58,
    'giacomo': 59, '1pietro': 60, '2pietro': 61, '1giovanni': 62,
    '2giovanni': 63, '3giovanni': 64, 'giuda': 65, 'apocalisse': 66,
  };
}

class _Ref {
  final int book; // libro biblico o numero sura
  final int chapter;
  final int from;
  final int to;
  const _Ref({
    required this.book,
    required this.chapter,
    required this.from,
    required this.to,
  });
}
