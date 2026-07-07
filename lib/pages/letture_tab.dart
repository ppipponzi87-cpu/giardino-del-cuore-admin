import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../gospel_fetcher.dart';

/// Gestione editoriale delle letture: elenco (inclusi i contenuti programmati
/// per il futuro), creazione e modifica con data di pubblicazione.
class LettureTab extends StatefulWidget {
  const LettureTab({super.key});

  @override
  State<LettureTab> createState() => _LettureTabState();
}

class _LettureTabState extends State<LettureTab> {
  final _client = Supabase.instance.client;
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = _client
        .from('letture')
        .select()
        .order('data_pubblicazione', ascending: false)
        .then((rows) => (rows as List).cast<Map<String, dynamic>>());
  }

  Future<void> _openEditor([Map<String, dynamic>? existing]) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _LetturaEditor(existing: existing),
    );
    if (saved == true) setState(_reload);
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminare la lettura?'),
        content: Text('«${row['titolo_vangelo']}» del '
            '${row['data_pubblicazione']} verrà rimossa.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annulla')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Elimina')),
        ],
      ),
    );
    if (ok != true) return;
    await _client.from('letture').delete().eq('id', row['id']);
    setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('Nuova lettura'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => setState(_reload),
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Errore: ${snapshot.error}'));
            }
            final rows = snapshot.data ?? [];
            if (rows.isEmpty) {
              return const Center(
                  child: Text('Nessuna lettura. Aggiungine una con il pulsante +.'));
            }
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
              itemCount: rows.length,
              itemBuilder: (context, i) {
                final r = rows[i];
                final date = DateTime.parse(r['data_pubblicazione'] as String);
                final future = date.isAfter(DateTime(today.year, today.month, today.day));
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: future
                          ? Colors.orange.shade100
                          : Colors.green.shade100,
                      child: Icon(future ? Icons.schedule : Icons.check,
                          color: future ? Colors.orange : Colors.green),
                    ),
                    title: Text(r['titolo_vangelo'] as String),
                    subtitle: Text(
                      '${DateFormat('EEEE d MMMM y', 'it_IT').format(date)}'
                      '${future ? '  ·  programmata' : ''}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                            onPressed: () => _openEditor(r),
                            icon: const Icon(Icons.edit)),
                        IconButton(
                            onPressed: () => _delete(r),
                            icon: const Icon(Icons.delete_outline)),
                      ],
                    ),
                    onTap: () => _openEditor(r),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _LetturaEditor extends StatefulWidget {
  const _LetturaEditor({this.existing});
  final Map<String, dynamic>? existing;

  @override
  State<_LetturaEditor> createState() => _LetturaEditorState();
}

class _LetturaEditorState extends State<_LetturaEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titolo;
  late final TextEditingController _vangelo;
  late final TextEditingController _commento;
  late final TextEditingController _originale;
  late final TextEditingController _lingua;
  late final TextEditingController _tags;
  final List<_KeyWordRow> _parole = [];
  late DateTime _data;
  bool _busy = false;
  String? _error;
  bool _composing = false;
  String? _composeError;

  Future<void> _compose() async {
    final ref = _titolo.text.trim();
    if (ref.isEmpty) {
      setState(() => _composeError = 'Scrivi prima la citazione qui sopra.');
      return;
    }
    setState(() {
      _composing = true;
      _composeError = null;
    });
    try {
      final res = await GospelFetcher().compose(ref);
      setState(() {
        _vangelo.text = res.italian;
        _originale.text = res.original;
        if (res.original.isNotEmpty) {
          _lingua.text = res.originalLanguage;
        }
        // Precompila le parole chiave solo se non ce ne sono già.
        if (_parole.every((p) => p.greco.text.trim().isEmpty) &&
            res.suggestions.isNotEmpty) {
          for (final p in _parole) {
            p.dispose();
          }
          _parole
            ..clear()
            ..addAll(res.suggestions.map((s) => _KeyWordRow.from({
                  'greco': s.original,
                  'traslitterazione': s.translit,
                })));
        }
      });
    } on ComposeException catch (e) {
      setState(() => _composeError = e.message);
    } catch (_) {
      setState(() => _composeError = 'Composizione non riuscita. Riprova.');
    } finally {
      if (mounted) setState(() => _composing = false);
    }
  }

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _titolo = TextEditingController(text: e?['titolo_vangelo'] as String? ?? '');
    _vangelo = TextEditingController(text: e?['testo_vangelo'] as String? ?? '');
    _commento = TextEditingController(text: e?['testo_commento'] as String? ?? '');
    _originale = TextEditingController(text: e?['testo_originale'] as String? ?? '');
    _lingua = TextEditingController(
        text: e?['lingua_originale'] as String? ?? 'Greco (Textus Receptus)');
    final tagList = (e?['tags'] as List?)?.map((t) => t.toString()).toList();
    _tags = TextEditingController(text: (tagList ?? const []).join(', '));
    final parole = (e?['parole_chiave'] as List?)?.cast<Map<String, dynamic>>();
    if (parole != null) {
      for (final p in parole) {
        _parole.add(_KeyWordRow.from(p));
      }
    }
    _data = e != null
        ? DateTime.parse(e['data_pubblicazione'] as String)
        : DateTime.now();
  }

  @override
  void dispose() {
    _titolo.dispose();
    _vangelo.dispose();
    _commento.dispose();
    _originale.dispose();
    _lingua.dispose();
    _tags.dispose();
    for (final p in _parole) {
      p.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _data,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _data = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final client = Supabase.instance.client;
    final parole = _parole
        .where((p) => p.greco.text.trim().isNotEmpty)
        .map((p) => p.toJson())
        .toList();
    final tags = _tags.text
        .split(RegExp(r'[,\n]'))
        .map((t) => t.trim().toLowerCase().replaceAll('#', ''))
        .where((t) => t.isNotEmpty)
        .toSet()
        .toList();
    final payload = {
      'data_pubblicazione':
          DateFormat('yyyy-MM-dd').format(_data),
      'titolo_vangelo': _titolo.text.trim(),
      'testo_vangelo': _vangelo.text.trim(),
      'testo_commento': _commento.text.trim(),
      'testo_originale':
          _originale.text.trim().isEmpty ? null : _originale.text.trim(),
      'lingua_originale':
          _originale.text.trim().isEmpty ? null : _lingua.text.trim(),
      'parole_chiave': parole,
      'tags': tags,
    };
    try {
      if (widget.existing != null) {
        await client
            .from('letture')
            .update(payload)
            .eq('id', widget.existing!['id']);
      } else {
        await client.from('letture').insert(payload);
      }
      if (mounted) Navigator.pop(context, true);
    } on PostgrestException catch (e) {
      // 23505 = violazione unique (data già usata)
      setState(() => _error = e.code == '23505'
          ? 'Esiste già una lettura per questa data.'
          : e.message);
    } catch (e) {
      setState(() => _error = 'Salvataggio non riuscito: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text(
                      widget.existing == null
                          ? 'Nuova lettura'
                          : 'Modifica lettura',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Spacer(),
                    IconButton(
                        onPressed: () => Navigator.pop(context, false),
                        icon: const Icon(Icons.close)),
                  ],
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_today, size: 18),
                  label: Text('Data di pubblicazione: '
                      '${DateFormat('d MMMM y', 'it_IT').format(_data)}'),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _titolo,
                          decoration: const InputDecoration(
                            labelText:
                                'Riferimento (es. Marco 4, 35-41 · Corano 2, 255)',
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) =>
                              (v == null || v.trim().isEmpty) ? 'Obbligatorio' : null,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            FilledButton.tonalIcon(
                              onPressed: _composing ? null : _compose,
                              icon: _composing
                                  ? const SizedBox(
                                      height: 16,
                                      width: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))
                                  : const Icon(Icons.auto_fix_high, size: 18),
                              label: const Text('Componi testo e originale'),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _composeError ??
                                    'Riempie da solo il testo e la lingua originale (Bibbia: Diodati + greco · Corano: Piccardo + arabo).',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _composeError != null
                                      ? Colors.red
                                      : Colors.grey,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _vangelo,
                          minLines: 4,
                          maxLines: 10,
                          decoration: const InputDecoration(
                            labelText: 'Testo del Vangelo',
                            alignLabelWithHint: true,
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) =>
                              (v == null || v.trim().isEmpty) ? 'Obbligatorio' : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _commento,
                          minLines: 5,
                          maxLines: 14,
                          decoration: const InputDecoration(
                            labelText: 'Commento del giorno',
                            alignLabelWithHint: true,
                            border: OutlineInputBorder(),
                            helperText:
                                'Vai a capo per separare i paragrafi.',
                          ),
                          validator: (v) =>
                              (v == null || v.trim().isEmpty) ? 'Obbligatorio' : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _tags,
                          decoration: const InputDecoration(
                            labelText: 'Hashtag tematici (separati da virgola)',
                            hintText: 'es. misericordia, paura, perdono',
                            prefixIcon: Icon(Icons.tag),
                            border: OutlineInputBorder(),
                            helperText:
                                'Servono per la ricerca tematica nell\'app.',
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Divider(),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Alla radice delle parole (facoltativo)',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Testo originale a fronte e parole chiave. Se lasci '
                            'tutto vuoto, la sezione non appare nell\'app.',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _originale,
                          minLines: 2,
                          maxLines: 8,
                          decoration: const InputDecoration(
                            labelText: 'Testo originale (greco/aramaico)',
                            alignLabelWithHint: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _lingua,
                          decoration: const InputDecoration(
                            labelText: 'Etichetta lingua (es. Greco — Textus Receptus)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        ..._parole.asMap().entries.map((entry) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _KeyWordEditor(
                                row: entry.value,
                                index: entry.key + 1,
                                onRemove: () =>
                                    setState(() => _parole.removeAt(entry.key)),
                              ),
                            )),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            onPressed: () =>
                                setState(() => _parole.add(_KeyWordRow())),
                            icon: const Icon(Icons.add),
                            label: const Text('Aggiungi parola chiave'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!,
                      style: const TextStyle(color: Colors.red, fontSize: 13)),
                ],
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Annulla')),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _busy ? null : _save,
                      icon: _busy
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.save),
                      label: const Text('Salva'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Gruppo di controller per una riga "parola chiave" nel form.
class _KeyWordRow {
  final TextEditingController greco;
  final TextEditingController traslit;
  final TextEditingController significato;
  final TextEditingController nota;

  _KeyWordRow()
      : greco = TextEditingController(),
        traslit = TextEditingController(),
        significato = TextEditingController(),
        nota = TextEditingController();

  _KeyWordRow.from(Map<String, dynamic> p)
      : greco = TextEditingController(text: p['greco'] as String? ?? ''),
        traslit =
            TextEditingController(text: p['traslitterazione'] as String? ?? ''),
        significato =
            TextEditingController(text: p['significato'] as String? ?? ''),
        nota = TextEditingController(text: p['nota'] as String? ?? '');

  Map<String, dynamic> toJson() => {
        'greco': greco.text.trim(),
        'traslitterazione': traslit.text.trim(),
        'significato': significato.text.trim(),
        if (nota.text.trim().isNotEmpty) 'nota': nota.text.trim(),
      };

  void dispose() {
    greco.dispose();
    traslit.dispose();
    significato.dispose();
    nota.dispose();
  }
}

class _KeyWordEditor extends StatelessWidget {
  const _KeyWordEditor({
    required this.row,
    required this.index,
    required this.onRemove,
  });

  final _KeyWordRow row;
  final int index;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text('Parola $index',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(
                onPressed: onRemove,
                icon: const Icon(Icons.close, size: 18),
                tooltip: 'Rimuovi',
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: row.greco,
                  decoration: const InputDecoration(
                    labelText: 'Originale (es. λαῖλαψ)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: row.traslit,
                  decoration: const InputDecoration(
                    labelText: 'Traslitterazione',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: row.significato,
            decoration: const InputDecoration(
              labelText: 'Senso letterale',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: row.nota,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Nota (facoltativa)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ],
      ),
    );
  }
}
