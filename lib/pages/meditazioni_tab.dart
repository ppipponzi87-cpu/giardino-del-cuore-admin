import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Gestione delle meditazioni giornaliere: scritto meditativo e/o audio guidato,
/// con data di pubblicazione programmabile.
class MeditazioniTab extends StatefulWidget {
  const MeditazioniTab({super.key});

  @override
  State<MeditazioniTab> createState() => _MeditazioniTabState();
}

class _MeditazioniTabState extends State<MeditazioniTab> {
  final _client = Supabase.instance.client;
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = _client
        .from('meditazioni')
        .select()
        .order('data_pubblicazione', ascending: false)
        .then((rows) => (rows as List).cast<Map<String, dynamic>>());
  }

  Future<void> _openEditor([Map<String, dynamic>? existing]) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _MeditazioneEditor(existing: existing),
    );
    if (saved == true) setState(_reload);
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminare la meditazione?'),
        content: Text('«${row['titolo']}» del ${row['data_pubblicazione']}.'),
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
    await _client.from('meditazioni').delete().eq('id', row['id']);
    setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('Nuova meditazione'),
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
                  child: Text('Nessuna meditazione. Aggiungine una con +.'));
            }
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
              itemCount: rows.length,
              itemBuilder: (context, i) {
                final r = rows[i];
                final date = DateTime.parse(r['data_pubblicazione'] as String);
                final future = date
                    .isAfter(DateTime(today.year, today.month, today.day));
                final hasAudio = (r['audio_url'] as String?)?.isNotEmpty ?? false;
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor:
                          future ? Colors.orange.shade100 : Colors.blue.shade100,
                      child: Icon(future ? Icons.schedule : Icons.self_improvement,
                          color: future ? Colors.orange : Colors.blue),
                    ),
                    title: Text(r['titolo'] as String),
                    subtitle: Text(
                      '${DateFormat('EEEE d MMMM y', 'it_IT').format(date)}'
                      '${future ? '  ·  programmata' : ''}'
                      '${hasAudio ? '  ·  audio' : ''}',
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

class _MeditazioneEditor extends StatefulWidget {
  const _MeditazioneEditor({this.existing});
  final Map<String, dynamic>? existing;

  @override
  State<_MeditazioneEditor> createState() => _MeditazioneEditorState();
}

class _MeditazioneEditorState extends State<_MeditazioneEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titolo;
  late final TextEditingController _testo;
  late DateTime _data;
  String? _audioUrl;
  bool _busy = false;
  bool _uploading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _titolo = TextEditingController(text: e?['titolo'] as String? ?? '');
    _testo = TextEditingController(text: e?['testo'] as String? ?? '');
    _audioUrl = e?['audio_url'] as String?;
    _data = e != null
        ? DateTime.parse(e['data_pubblicazione'] as String)
        : DateTime.now();
  }

  @override
  void dispose() {
    _titolo.dispose();
    _testo.dispose();
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

  Future<void> _uploadAudio() async {
    final result = await FilePicker.pickFiles(
      type: FileType.audio,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;
    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      final ext = (file.extension ?? 'mp3').toLowerCase();
      final objectPath =
          'meditazioni/${DateTime.now().millisecondsSinceEpoch}.$ext';
      await Supabase.instance.client.storage.from('audio').uploadBinary(
            objectPath,
            bytes,
            fileOptions: FileOptions(contentType: 'audio/$ext', upsert: true),
          );
      final url =
          Supabase.instance.client.storage.from('audio').getPublicUrl(objectPath);
      setState(() => _audioUrl = url);
    } catch (e) {
      setState(() => _error = 'Caricamento audio non riuscito: $e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if ((_testo.text.trim().isEmpty) && (_audioUrl == null)) {
      setState(() => _error = 'Inserisci almeno un testo o un audio.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final payload = {
      'data_pubblicazione': DateFormat('yyyy-MM-dd').format(_data),
      'titolo': _titolo.text.trim(),
      'testo': _testo.text.trim().isEmpty ? null : _testo.text.trim(),
      'audio_url': _audioUrl,
    };
    try {
      if (widget.existing != null) {
        await Supabase.instance.client
            .from('meditazioni')
            .update(payload)
            .eq('id', widget.existing!['id']);
      } else {
        await Supabase.instance.client.from('meditazioni').insert(payload);
      }
      if (mounted) Navigator.pop(context, true);
    } on PostgrestException catch (e) {
      setState(() => _error = e.code == '23505'
          ? 'Esiste già una meditazione per questa data.'
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
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 620),
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
                          ? 'Nuova meditazione'
                          : 'Modifica meditazione',
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
                  label: Text('Data: '
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
                            labelText: 'Titolo della meditazione',
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Obbligatorio'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _testo,
                          minLines: 5,
                          maxLines: 16,
                          decoration: const InputDecoration(
                            labelText: 'Scritto meditativo (facoltativo)',
                            alignLabelWithHint: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _audioUrl != null
                                    ? Icons.check_circle
                                    : Icons.audiotrack,
                                color: _audioUrl != null
                                    ? Colors.green
                                    : Colors.grey,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _audioUrl != null
                                      ? 'Audio caricato'
                                      : 'Nessun audio (facoltativo)',
                                ),
                              ),
                              if (_audioUrl != null)
                                TextButton(
                                  onPressed: () =>
                                      setState(() => _audioUrl = null),
                                  child: const Text('Rimuovi'),
                                ),
                              FilledButton.tonalIcon(
                                onPressed: _uploading ? null : _uploadAudio,
                                icon: _uploading
                                    ? const SizedBox(
                                        height: 16,
                                        width: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2))
                                    : const Icon(Icons.upload, size: 18),
                                label: Text(_audioUrl != null
                                    ? 'Sostituisci'
                                    : 'Carica audio'),
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
