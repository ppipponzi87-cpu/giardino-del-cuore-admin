import 'dart:convert';

import 'package:http/http.dart' as http;

/// Risultato della composizione automatica di un brano.
class ComposeResult {
  final String italian; // Diodati
  final String greek; // Textus Receptus
  const ComposeResult({required this.italian, required this.greek});
}

class ComposeException implements Exception {
  final String message;
  ComposeException(this.message);
  @override
  String toString() => message;
}

/// Compone il testo di un brano a partire dalla citazione (es. "Marco 4, 35-41"):
/// recupera l'italiano (Diodati) e il greco (Textus Receptus) da getbible.net,
/// entrambi accessibili dal browser (CORS aperto).
class GospelFetcher {
  static const _base = 'https://api.getbible.net/v2';

  Future<ComposeResult> compose(String reference) async {
    final ref = _parse(reference);
    final italian = await _fetch('giovanni', ref);
    final greek = await _fetch('textusreceptus', ref);
    if (italian.isEmpty && greek.isEmpty) {
      throw ComposeException(
          'Nessun versetto trovato per "$reference". Controlla la citazione.');
    }
    return ComposeResult(italian: italian, greek: greek);
  }

  Future<String> _fetch(String translation, _Ref ref) async {
    final url = '$_base/$translation/${ref.book}/${ref.chapter}.json';
    final resp = await http.get(Uri.parse(url));
    if (resp.statusCode != 200) {
      throw ComposeException(
          'Impossibile scaricare il testo (${ref.chapter}). Riprova.');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final raw = data['verses'] ?? data['chapter'];
    final list = raw is List ? raw : (raw as Map).values.toList();
    final buf = <String>[];
    for (final v in list) {
      final m = v as Map<String, dynamic>;
      final n = (m['verse'] is int)
          ? m['verse'] as int
          : int.tryParse('${m['verse']}') ?? 0;
      if (n < ref.from || n > ref.to) continue;
      buf.add((m['text'] as String).trim());
    }
    return buf.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  _Ref _parse(String input) {
    final s = input.trim();
    // Cattura: [ordinale] Nome  capitolo [ , : verso [ - verso ] ]
    final m = RegExp(
      r"^([1-3]|i{1,3}|I{1,3})?\s*([A-Za-zÀ-ÿ.’' ]+?)\s+(\d+)\s*(?:[,:]\s*(\d+)\s*(?:[-–]\s*(\d+))?)?\s*$",
    ).firstMatch(s);
    if (m == null) {
      throw ComposeException(
          'Citazione non riconosciuta. Usa un formato come "Marco 4, 35-41".');
    }
    final ordinale = _ordinale(m.group(1));
    final nomeGrezzo = m.group(2)!;
    final chapter = int.parse(m.group(3)!);
    final from = m.group(4) != null ? int.parse(m.group(4)!) : 1;
    final to = m.group(5) != null ? int.parse(m.group(5)!) : (m.group(4) != null ? from : 999);

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

  // Nome normalizzato (senza spazi/accenti, ordinale come cifra) -> numero libro.
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
  final int book;
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
