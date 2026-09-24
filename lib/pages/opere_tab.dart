import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Opere lunghe in HTML (sezione "Scritture" dell'app). Caricare un nuovo
/// file ne incrementa la versione: l'app lo riscarica da sola.
class OpereTab extends StatefulWidget {
  const OpereTab({super.key});

  @override
  State<OpereTab> createState() => _OpereTabState();
}

class _OpereTabState extends State<OpereTab> {
  final _client = Supabase.instance.client;
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = _client
        .from('opere')
        .select()
        .order('ordine')
        .order('created_at')
        .then((rows) => (rows as List).cast<Map<String, dynamic>>());
  }

  Future<void> _openEditor([Map<String, dynamic>? existing]) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _OperaEditor(existing: existing),
    );
    if (saved == true) setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('Nuova opera'),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
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
            return const Center(child: Text('Nessuna opera. Aggiungine una con +.'));
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
            children: [
              for (final r in rows)
                Card(
                  child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.auto_stories)),
                    title: Text(r['titolo'] as String),
                    subtitle: Text('${r['file_path']}  ·  versione ${r['versione']}'
                        '${(r['attiva'] as bool? ?? true) ? '' : '  ·  NON ATTIVA'}'),
                    trailing: const Icon(Icons.edit),
                    onTap: () => _openEditor(r),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _OperaEditor extends StatefulWidget {
  const _OperaEditor({this.existing});
  final Map<String, dynamic>? existing;

  @override
  State<_OperaEditor> createState() => _OperaEditorState();
}

class _OperaEditorState extends State<_OperaEditor> {
  final _formKey = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _c;
  late bool _attiva;
  PlatformFile? _nuovoFile;
  bool _busy = false;
  String? _error;

  static const _campi = {
    'titolo': 'Titolo',
    'sottotitolo': 'Sottotitolo',
    'autore': 'Autore (es. «a cura di …»)',
    'descrizione': 'Descrizione per la card',
    'slug': 'Slug (anche nome del file)',
    'colore': 'Colore della card (es. #070E1C)',
    'ordine': 'Ordine',
  };

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _c = {
      for (final k in _campi.keys)
        k: TextEditingController(text: (e?[k])?.toString() ?? (k == 'ordine' ? '0' : '')),
    };
    _attiva = e?['attiva'] as bool? ?? true;
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickFile() async {
    final r = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['html', 'htm'],
      withData: true,
    );
    if (r != null && r.files.isNotEmpty) setState(() => _nuovoFile = r.files.first);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final e = widget.existing;
    if (e == null && _nuovoFile == null) {
      setState(() => _error = 'Per una nuova opera serve il file HTML.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final slug = _c['slug']!.text.trim();
      final filePath = '$slug.html';
      var versione = (e?['versione'] as int?) ?? 0;
      if (_nuovoFile != null) {
        await _client.storage.from('opere').uploadBinary(
              filePath,
              _nuovoFile!.bytes!,
              fileOptions: const FileOptions(
                  contentType: 'text/html; charset=utf-8', upsert: true),
            );
        versione += 1;
      }
      String? testo(String k) =>
          _c[k]!.text.trim().isEmpty ? null : _c[k]!.text.trim();
      final payload = {
        'titolo': _c['titolo']!.text.trim(),
        'sottotitolo': testo('sottotitolo'),
        'autore': testo('autore'),
        'descrizione': testo('descrizione'),
        'slug': slug,
        'colore': testo('colore'),
        'ordine': int.tryParse(_c['ordine']!.text.trim()) ?? 0,
        'attiva': _attiva,
        'file_path': filePath,
        'versione': versione < 1 ? 1 : versione,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      if (e != null) {
        await _client.from('opere').update(payload).eq('id', e['id']);
      } else {
        await _client.from('opere').insert(payload);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (err) {
      setState(() => _error = 'Salvataggio non riuscito: $err');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  SupabaseClient get _client => Supabase.instance.client;

  @override
  Widget build(BuildContext context) {
    final e = widget.existing;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text(e == null ? 'Nuova opera' : 'Modifica opera',
                        style: Theme.of(context).textTheme.titleLarge),
                    const Spacer(),
                    const Text('Attiva'),
                    Switch(value: _attiva, onChanged: (v) => setState(() => _attiva = v)),
                    IconButton(
                        onPressed: () => Navigator.pop(context, false),
                        icon: const Icon(Icons.close)),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        for (final entry in _campi.entries) ...[
                          TextFormField(
                            controller: _c[entry.key],
                            maxLines: entry.key == 'descrizione' ? 3 : 1,
                            enabled: !(entry.key == 'slug' && e != null),
                            decoration: InputDecoration(
                                labelText: entry.value,
                                border: const OutlineInputBorder()),
                            validator: (v) => (['titolo', 'slug'].contains(entry.key) &&
                                    (v == null || v.trim().isEmpty))
                                ? 'Obbligatorio'
                                : null,
                          ),
                          const SizedBox(height: 12),
                        ],
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.html),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(_nuovoFile != null
                                    ? '${_nuovoFile!.name} — verrà caricato come nuova versione'
                                    : e != null
                                        ? 'File attuale: versione ${e['versione']}'
                                        : 'Nessun file scelto'),
                              ),
                              FilledButton.tonalIcon(
                                onPressed: _pickFile,
                                icon: const Icon(Icons.upload_file, size: 18),
                                label: Text(e == null ? 'Scegli HTML' : 'Sostituisci HTML'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Il file deve essere autonomo: font e immagini incorporati '
                          '(vedi contenuti/opere/incorpora_font.py nel repo dell\'app).',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
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
                      icon: const Icon(Icons.save),
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
