import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Gestione delle campagne di raccolta fondi (sezione "Dona" dell'app):
/// testo, link di donazione, importi aggiornati a mano e foto.
class CampagneTab extends StatefulWidget {
  const CampagneTab({super.key});

  @override
  State<CampagneTab> createState() => _CampagneTabState();
}

String _euro(num? v) => v == null
    ? '—'
    : NumberFormat.currency(locale: 'it_IT', symbol: '€', decimalDigits: 0)
        .format(v);

class _CampagneTabState extends State<CampagneTab> {
  final _client = Supabase.instance.client;
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = _client
        .from('campagne')
        .select()
        .order('ordine')
        .order('created_at', ascending: false)
        .then((rows) => (rows as List).cast<Map<String, dynamic>>());
  }

  Future<void> _openEditor([Map<String, dynamic>? existing]) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CampagnaEditor(existing: existing),
    );
    if (saved == true) setState(_reload);
  }

  Future<void> _updateAmounts(Map<String, dynamic> row) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _ImportiDialog(row: row),
    );
    if (saved == true) setState(_reload);
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminare la campagna?'),
        content: Text('«${row['titolo']}». Se vuoi solo nasconderla, '
            'disattivala dall\'editor.'),
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
    await _client.from('campagne').delete().eq('id', row['id']);
    setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('Nuova campagna'),
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
              return Center(
                child: Text('Errore: ${snapshot.error}\n\n'
                    'Hai eseguito supabase/aggiornamento4_campagne.sql?'),
              );
            }
            final rows = snapshot.data ?? [];
            if (rows.isEmpty) {
              return const Center(
                  child: Text('Nessuna campagna. Aggiungine una con +.'));
            }
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
              itemCount: rows.length,
              itemBuilder: (context, i) {
                final r = rows[i];
                final attiva = r['attiva'] as bool? ?? true;
                final foto = (r['immagini'] as List?)?.length ?? 0;
                final agg = r['importi_aggiornati_il'] as String?;
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor:
                          attiva ? Colors.pink.shade50 : Colors.grey.shade200,
                      child: Icon(Icons.volunteer_activism,
                          color: attiva ? Colors.pink : Colors.grey),
                    ),
                    title: Text(r['titolo'] as String),
                    subtitle: Text(
                      '${_euro(r['raccolto'] as num?)} su ${_euro(r['obiettivo'] as num?)}'
                      '${r['numero_donazioni'] != null ? '  ·  ${r['numero_donazioni']} donazioni' : ''}'
                      '${agg != null ? '  ·  al ${DateFormat('d/M/y').format(DateTime.parse(agg))}' : ''}'
                      '  ·  $foto foto'
                      '${attiva ? '' : '  ·  NON ATTIVA'}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton.icon(
                          onPressed: () => _updateAmounts(r),
                          icon: const Icon(Icons.euro, size: 18),
                          label: const Text('Aggiorna importi'),
                        ),
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

/// Aggiornamento rapido di raccolto e donazioni (l'operazione più frequente):
/// la data di aggiornamento diventa oggi.
class _ImportiDialog extends StatefulWidget {
  const _ImportiDialog({required this.row});
  final Map<String, dynamic> row;

  @override
  State<_ImportiDialog> createState() => _ImportiDialogState();
}

class _ImportiDialogState extends State<_ImportiDialog> {
  late final TextEditingController _raccolto;
  late final TextEditingController _donazioni;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _raccolto = TextEditingController(
        text: (widget.row['raccolto'] as num?)?.toString() ?? '');
    _donazioni = TextEditingController(
        text: (widget.row['numero_donazioni'] as num?)?.toString() ?? '');
  }

  @override
  void dispose() {
    _raccolto.dispose();
    _donazioni.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final raccolto = num.tryParse(_raccolto.text.replaceAll(',', '.'));
    if (raccolto == null) {
      setState(() => _error = 'Importo raccolto non valido.');
      return;
    }
    setState(() => _busy = true);
    try {
      await Supabase.instance.client.from('campagne').update({
        'raccolto': raccolto,
        'numero_donazioni': int.tryParse(_donazioni.text),
        'importi_aggiornati_il': DateFormat('yyyy-MM-dd').format(DateTime.now()),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', widget.row['id']);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _busy = false;
        _error = 'Salvataggio non riuscito: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Aggiorna importi'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Copia i valori dalla pagina della campagna '
                '(GoFundMe non li comunica in automatico).',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            TextField(
              controller: _raccolto,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'Raccolto (€)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _donazioni,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                  labelText: 'Numero di donazioni', border: OutlineInputBorder()),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla')),
        FilledButton(
            onPressed: _busy ? null : _save, child: const Text('Salva')),
      ],
    );
  }
}

class _CampagnaEditor extends StatefulWidget {
  const _CampagnaEditor({this.existing});
  final Map<String, dynamic>? existing;

  @override
  State<_CampagnaEditor> createState() => _CampagnaEditorState();
}

class _CampagnaEditorState extends State<_CampagnaEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titolo;
  late final TextEditingController _sottotitolo;
  late final TextEditingController _slug;
  late final TextEditingController _link;
  late final TextEditingController _obiettivo;
  late final TextEditingController _raccolto;
  late final TextEditingController _donazioni;
  late final TextEditingController _ordine;
  late final TextEditingController _testo;
  late bool _attiva;
  late List<String> _immagini;
  String? _copertina;
  bool _busy = false;
  bool _uploading = false;
  String? _error;

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    String t(String k) => (e?[k])?.toString() ?? '';
    _titolo = TextEditingController(text: t('titolo'));
    _sottotitolo = TextEditingController(text: t('sottotitolo'));
    _slug = TextEditingController(text: t('slug'));
    _link = TextEditingController(text: t('link_donazione'));
    _obiettivo = TextEditingController(text: t('obiettivo'));
    _raccolto = TextEditingController(text: e == null ? '0' : t('raccolto'));
    _donazioni = TextEditingController(text: t('numero_donazioni'));
    _ordine = TextEditingController(text: e == null ? '0' : t('ordine'));
    _testo = TextEditingController(text: t('testo'));
    _attiva = e?['attiva'] as bool? ?? true;
    _immagini = List<String>.from((e?['immagini'] as List?) ?? const []);
    _copertina = e?['immagine_copertina'] as String?;
    if (_isNew) _titolo.addListener(_autoSlug);
  }

  /// Per una campagna nuova lo slug segue il titolo finché non lo si tocca.
  void _autoSlug() {
    final s = _titolo.text
        .toLowerCase()
        .replaceAll(RegExp(r'[àáâä]'), 'a')
        .replaceAll(RegExp(r'[èéêë]'), 'e')
        .replaceAll(RegExp(r'[ìíîï]'), 'i')
        .replaceAll(RegExp(r'[òóôö]'), 'o')
        .replaceAll(RegExp(r'[ùúûü]'), 'u')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    _slug.text = s.length > 40 ? s.substring(0, 40) : s;
  }

  @override
  void dispose() {
    for (final c in [
      _titolo, _sottotitolo, _slug, _link, _obiettivo,
      _raccolto, _donazioni, _ordine, _testo,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _uploadImages() async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final slug = _slug.text.trim().isEmpty ? 'senza-slug' : _slug.text.trim();
    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      final storage = Supabase.instance.client.storage.from('immagini');
      var n = 0;
      for (final file in result.files) {
        final bytes = file.bytes;
        if (bytes == null) continue;
        final ext = (file.extension ?? 'jpg').toLowerCase();
        final path =
            'campagne/$slug/${DateTime.now().millisecondsSinceEpoch}_${n++}.$ext';
        await storage.uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
              contentType: ext == 'png' ? 'image/png' : 'image/jpeg',
              upsert: true),
        );
        final url = storage.getPublicUrl(path);
        setState(() => _immagini.add(url));
      }
    } catch (e) {
      setState(() => _error = 'Caricamento non riuscito: $e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    num? numero(TextEditingController c) =>
        num.tryParse(c.text.trim().replaceAll(',', '.'));
    final e = widget.existing;
    final importiCambiati = e == null ||
        numero(_raccolto) != (e['raccolto'] as num?) ||
        numero(_donazioni) != (e['numero_donazioni'] as num?);
    final payload = {
      'titolo': _titolo.text.trim(),
      'sottotitolo':
          _sottotitolo.text.trim().isEmpty ? null : _sottotitolo.text.trim(),
      'slug': _slug.text.trim(),
      'link_donazione': _link.text.trim(),
      'obiettivo': numero(_obiettivo),
      'raccolto': numero(_raccolto) ?? 0,
      'numero_donazioni': numero(_donazioni)?.toInt(),
      'ordine': numero(_ordine)?.toInt() ?? 0,
      'testo': _testo.text.trim().isEmpty ? null : _testo.text.trim(),
      'attiva': _attiva,
      'immagini': _immagini,
      'immagine_copertina':
          (_copertina != null && _immagini.contains(_copertina)) ? _copertina : null,
      if (importiCambiati)
        'importi_aggiornati_il': DateFormat('yyyy-MM-dd').format(DateTime.now()),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    try {
      final table = Supabase.instance.client.from('campagne');
      if (e != null) {
        await table.update(payload).eq('id', e['id']);
      } else {
        await table.insert(payload);
      }
      if (mounted) Navigator.pop(context, true);
    } on PostgrestException catch (err) {
      setState(() => _error = err.code == '23505'
          ? 'Esiste già una campagna con questo slug.'
          : err.message);
    } catch (err) {
      setState(() => _error = 'Salvataggio non riuscito: $err');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _campo(TextEditingController c, String label,
      {bool obbligatorio = false,
      bool numerico = false,
      int righe = 1,
      String? aiuto}) {
    return TextFormField(
      controller: c,
      minLines: righe,
      maxLines: righe == 1 ? 1 : righe * 3,
      keyboardType: numerico
          ? const TextInputType.numberWithOptions(decimal: true)
          : null,
      decoration: InputDecoration(
        labelText: label,
        helperText: aiuto,
        alignLabelWithHint: righe > 1,
        border: const OutlineInputBorder(),
      ),
      validator: (v) {
        final s = v?.trim() ?? '';
        if (obbligatorio && s.isEmpty) return 'Obbligatorio';
        if (numerico && s.isNotEmpty && num.tryParse(s.replaceAll(',', '.')) == null) {
          return 'Numero non valido';
        }
        return null;
      },
    );
  }

  Widget _galleria() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Foto (${_immagini.length}) — la stella sceglie la copertina; '
                  'senza stella vale la prima. Consigliate max 1600 px.',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: _uploading ? null : _uploadImages,
                icon: _uploading
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.add_photo_alternate, size: 18),
                label: const Text('Carica foto'),
              ),
            ],
          ),
          if (_immagini.isNotEmpty) ...[
            const SizedBox(height: 12),
            ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: true,
              onReorderItem: (a, b) => setState(
                  () => _immagini.insert(b, _immagini.removeAt(a))),
              children: [
                for (final url in _immagini)
                  ListTile(
                    key: ValueKey(url),
                    contentPadding: EdgeInsets.zero,
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.network(url,
                          width: 64, height: 48, fit: BoxFit.cover),
                    ),
                    title: Text(Uri.parse(url).pathSegments.last,
                        style: const TextStyle(fontSize: 12)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Usa come copertina',
                          onPressed: () => setState(
                              () => _copertina = _copertina == url ? null : url),
                          icon: Icon(
                              _copertina == url ? Icons.star : Icons.star_border,
                              color: Colors.amber),
                        ),
                        IconButton(
                          tooltip: 'Togli dalla campagna',
                          onPressed: () => setState(() => _immagini.remove(url)),
                          icon: const Icon(Icons.close),
                        ),
                        const SizedBox(width: 24),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 760),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text(_isNew ? 'Nuova campagna' : 'Modifica campagna',
                        style: Theme.of(context).textTheme.titleLarge),
                    const Spacer(),
                    const Text('Attiva'),
                    Switch(
                        value: _attiva,
                        onChanged: (v) => setState(() => _attiva = v)),
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
                        _campo(_titolo, 'Titolo', obbligatorio: true),
                        const SizedBox(height: 12),
                        _campo(_sottotitolo, 'Sottotitolo (facoltativo)'),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _campo(_slug, 'Slug', obbligatorio: true,
                                  aiuto: 'identificativo, anche per la cartella foto'),
                            ),
                            const SizedBox(width: 12),
                            SizedBox(
                              width: 120,
                              child: _campo(_ordine, 'Ordine', numerico: true),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _campo(_link, 'Link di donazione (es. GoFundMe)',
                            obbligatorio: true),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                                child: _campo(_obiettivo, 'Obiettivo (€)',
                                    numerico: true)),
                            const SizedBox(width: 12),
                            Expanded(
                                child: _campo(_raccolto, 'Raccolto (€)',
                                    numerico: true)),
                            const SizedBox(width: 12),
                            Expanded(
                                child: _campo(_donazioni, 'N. donazioni',
                                    numerico: true)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _campo(_testo, 'Racconto (paragrafi separati da una riga vuota)',
                            righe: 8),
                        const SizedBox(height: 16),
                        _galleria(),
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
                      onPressed: _busy || _uploading ? null : _save,
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
