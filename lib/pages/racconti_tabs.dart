import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Schede "Storie" e "Animazioni" (sezione Racconti dell'app). Stessa
/// struttura: elenco per data di pubblicazione (le future sono
/// "programmate") ed editor in una finestra.

/// Carica un file scelto dall'utente nello Storage e ne restituisce l'URL
/// pubblico, o null se l'utente annulla.
Future<String?> caricaFile({
  required String bucket,
  required String cartella,
  required FileType tipo,
}) async {
  final r = await FilePicker.pickFiles(type: tipo, withData: true);
  if (r == null || r.files.isEmpty || r.files.first.bytes == null) return null;
  final f = r.files.first;
  final ext = (f.extension ?? '').toLowerCase();
  final path = '$cartella/${DateTime.now().millisecondsSinceEpoch}.$ext';
  final contentType = switch (ext) {
    'png' => 'image/png',
    'jpg' || 'jpeg' => 'image/jpeg',
    'webp' => 'image/webp',
    'mp3' => 'audio/mpeg',
    'm4a' || 'aac' => 'audio/mp4',
    _ => 'application/octet-stream',
  };
  final storage = Supabase.instance.client.storage.from(bucket);
  await storage.uploadBinary(path, f.bytes!,
      fileOptions: FileOptions(contentType: contentType, upsert: true));
  return storage.getPublicUrl(path);
}

/// Elenco generico di una tabella con data di pubblicazione.
class _ElencoTab extends StatefulWidget {
  const _ElencoTab({
    required this.tabella,
    required this.etichettaNuovo,
    required this.icona,
    required this.sottotitolo,
    required this.editor,
  });

  final String tabella;
  final String etichettaNuovo;
  final IconData icona;
  final String Function(Map<String, dynamic> r) sottotitolo;
  final Widget Function(Map<String, dynamic>? existing) editor;

  @override
  State<_ElencoTab> createState() => _ElencoTabState();
}

class _ElencoTabState extends State<_ElencoTab> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = Supabase.instance.client
        .from(widget.tabella)
        .select()
        .order('data_pubblicazione', ascending: false)
        .then((rows) => (rows as List).cast<Map<String, dynamic>>());
  }

  Future<void> _open([Map<String, dynamic>? r]) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => widget.editor(r),
    );
    if (saved == true) setState(_reload);
  }

  Future<void> _delete(Map<String, dynamic> r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminare?'),
        content: Text('«${r['titolo']}»'),
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
    await Supabase.instance.client.from(widget.tabella).delete().eq('id', r['id']);
    setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    final oggi = DateTime.now();
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(),
        icon: const Icon(Icons.add),
        label: Text(widget.etichettaNuovo),
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
            return const Center(child: Text('Ancora niente. Aggiungi con +.'));
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
            children: [
              for (final r in rows)
                Builder(builder: (context) {
                  final data = DateTime.parse(r['data_pubblicazione'] as String);
                  final futura =
                      data.isAfter(DateTime(oggi.year, oggi.month, oggi.day));
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: futura
                            ? Colors.orange.shade100
                            : Colors.purple.shade50,
                        child: Icon(futura ? Icons.schedule : widget.icona,
                            color: futura ? Colors.orange : Colors.purple),
                      ),
                      title: Text(r['titolo'] as String),
                      subtitle: Text(
                          '${DateFormat('d MMMM y', 'it_IT').format(data)}'
                          '${futura ? '  ·  programmata' : ''}'
                          '  ·  ${widget.sottotitolo(r)}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                              onPressed: () => _open(r),
                              icon: const Icon(Icons.edit)),
                          IconButton(
                              onPressed: () => _delete(r),
                              icon: const Icon(Icons.delete_outline)),
                        ],
                      ),
                      onTap: () => _open(r),
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }
}

class StorieTab extends StatelessWidget {
  const StorieTab({super.key});

  @override
  Widget build(BuildContext context) => _ElencoTab(
        tabella: 'storie',
        etichettaNuovo: 'Nuova storia',
        icona: Icons.menu_book,
        sottotitolo: (r) => [
          r['fonte'],
          if (r['audio_url'] != null) 'audio',
          if (r['immagine_url'] != null) 'immagine',
        ].whereType<String>().join('  ·  '),
        editor: (e) => _Editor(
          tabella: 'storie',
          titolo: 'storia',
          existing: e,
          campi: const [
            _Campo('titolo', 'Titolo', obbligatorio: true),
            _Campo('autore', 'Autore'),
            _Campo('fonte', 'Libro / fonte'),
            _Campo('testo', 'Testo (paragrafi separati da una riga vuota)',
                obbligatorio: true, righe: 12),
          ],
          file: const [
            _File('immagine_url', 'Immagine', 'immagini', 'storie', FileType.image),
            _File('audio_url', 'Lettura audio', 'audio', 'storie', FileType.audio),
          ],
        ),
      );
}

class AnimazioniTab extends StatelessWidget {
  const AnimazioniTab({super.key});

  @override
  Widget build(BuildContext context) => _ElencoTab(
        tabella: 'animazioni',
        etichettaNuovo: 'Nuova animazione',
        icona: Icons.movie,
        sottotitolo: (r) => [
          r['serie'],
          if (r['episodio'] != null) 'ep. ${r['episodio']}',
        ].whereType<String>().join(' '),
        editor: (e) => _Editor(
          tabella: 'animazioni',
          titolo: 'animazione',
          existing: e,
          campi: const [
            _Campo('titolo', 'Titolo', obbligatorio: true),
            _Campo('serie', 'Serie (es. Datteri di Montagna)'),
            _Campo('episodio', 'Numero episodio', numero: true),
            _Campo('video_url', 'Link al video (YouTube, Vimeo, Bunny o .mp4)',
                obbligatorio: true),
            _Campo('durata_secondi', 'Durata in secondi', numero: true),
            _Campo('descrizione', 'Descrizione', righe: 5),
          ],
          file: const [
            _File('anteprima_url', 'Immagine di anteprima', 'immagini',
                'animazioni', FileType.image),
          ],
        ),
      );
}

class _Campo {
  const _Campo(this.chiave, this.etichetta,
      {this.obbligatorio = false, this.numero = false, this.righe = 1});
  final String chiave;
  final String etichetta;
  final bool obbligatorio;
  final bool numero;
  final int righe;
}

class _File {
  const _File(this.chiave, this.etichetta, this.bucket, this.cartella, this.tipo);
  final String chiave;
  final String etichetta;
  final String bucket;
  final String cartella;
  final FileType tipo;
}

class _Editor extends StatefulWidget {
  const _Editor({
    required this.tabella,
    required this.titolo,
    required this.existing,
    required this.campi,
    required this.file,
  });

  final String tabella;
  final String titolo;
  final Map<String, dynamic>? existing;
  final List<_Campo> campi;
  final List<_File> file;

  @override
  State<_Editor> createState() => _EditorState();
}

class _EditorState extends State<_Editor> {
  final _formKey = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _c;
  late final Map<String, String?> _url;
  late DateTime _data;
  String? _caricando;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _c = {
      for (final f in widget.campi)
        f.chiave: TextEditingController(text: (e?[f.chiave])?.toString() ?? ''),
    };
    _url = {for (final f in widget.file) f.chiave: e?[f.chiave] as String?};
    _data = e != null
        ? DateTime.parse(e['data_pubblicazione'] as String)
        : DateTime.now();
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _carica(_File f) async {
    setState(() {
      _caricando = f.chiave;
      _error = null;
    });
    try {
      final url =
          await caricaFile(bucket: f.bucket, cartella: f.cartella, tipo: f.tipo);
      if (url != null) setState(() => _url[f.chiave] = url);
    } catch (e) {
      setState(() => _error = 'Caricamento non riuscito: $e');
    } finally {
      if (mounted) setState(() => _caricando = null);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final payload = <String, dynamic>{
      for (final f in widget.campi)
        f.chiave: _c[f.chiave]!.text.trim().isEmpty
            ? null
            : (f.numero
                ? int.tryParse(_c[f.chiave]!.text.trim())
                : _c[f.chiave]!.text.trim()),
      ..._url,
      'data_pubblicazione': DateFormat('yyyy-MM-dd').format(_data),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    try {
      final t = Supabase.instance.client.from(widget.tabella);
      if (widget.existing != null) {
        await t.update(payload).eq('id', widget.existing!['id']);
      } else {
        await t.insert(payload);
      }
      if (mounted) Navigator.pop(context, true);
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
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 760),
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
                        '${widget.existing == null ? 'Nuova' : 'Modifica'} ${widget.titolo}',
                        style: Theme.of(context).textTheme.titleLarge),
                    const Spacer(),
                    IconButton(
                        onPressed: () => Navigator.pop(context, false),
                        icon: const Icon(Icons.close)),
                  ],
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _data,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (d != null) setState(() => _data = d);
                  },
                  icon: const Icon(Icons.calendar_today, size: 18),
                  label: Text('Pubblicazione: '
                      '${DateFormat('d MMMM y', 'it_IT').format(_data)}'),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        for (final f in widget.campi) ...[
                          TextFormField(
                            controller: _c[f.chiave],
                            minLines: f.righe,
                            maxLines: f.righe == 1 ? 1 : f.righe * 2,
                            keyboardType: f.numero ? TextInputType.number : null,
                            decoration: InputDecoration(
                              labelText: f.etichetta,
                              alignLabelWithHint: f.righe > 1,
                              border: const OutlineInputBorder(),
                            ),
                            validator: (v) {
                              final s = v?.trim() ?? '';
                              if (f.obbligatorio && s.isEmpty) return 'Obbligatorio';
                              if (f.numero && s.isNotEmpty && int.tryParse(s) == null) {
                                return 'Numero intero';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                        ],
                        for (final f in widget.file)
                          Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                if (_url[f.chiave] != null && f.tipo == FileType.image)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 10),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: Image.network(_url[f.chiave]!,
                                          width: 64, height: 44, fit: BoxFit.cover),
                                    ),
                                  )
                                else
                                  Padding(
                                    padding: const EdgeInsets.only(right: 10),
                                    child: Icon(
                                        _url[f.chiave] != null
                                            ? Icons.check_circle
                                            : Icons.attach_file,
                                        color: _url[f.chiave] != null
                                            ? Colors.green
                                            : Colors.grey),
                                  ),
                                Expanded(
                                  child: Text(_url[f.chiave] != null
                                      ? '${f.etichetta}: caricato'
                                      : '${f.etichetta} (facoltativo)'),
                                ),
                                if (_url[f.chiave] != null)
                                  TextButton(
                                    onPressed: () =>
                                        setState(() => _url[f.chiave] = null),
                                    child: const Text('Rimuovi'),
                                  ),
                                FilledButton.tonalIcon(
                                  onPressed:
                                      _caricando != null ? null : () => _carica(f),
                                  icon: _caricando == f.chiave
                                      ? const SizedBox(
                                          height: 16,
                                          width: 16,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2))
                                      : const Icon(Icons.upload, size: 18),
                                  label: Text(_url[f.chiave] != null
                                      ? 'Sostituisci'
                                      : 'Carica'),
                                ),
                              ],
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
                      onPressed: _busy || _caricando != null ? null : _save,
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
