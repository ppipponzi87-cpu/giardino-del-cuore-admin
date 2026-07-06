import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  late DateTime _data;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _titolo = TextEditingController(text: e?['titolo_vangelo'] as String? ?? '');
    _vangelo = TextEditingController(text: e?['testo_vangelo'] as String? ?? '');
    _commento = TextEditingController(text: e?['testo_commento'] as String? ?? '');
    _data = e != null
        ? DateTime.parse(e['data_pubblicazione'] as String)
        : DateTime.now();
  }

  @override
  void dispose() {
    _titolo.dispose();
    _vangelo.dispose();
    _commento.dispose();
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
    final payload = {
      'data_pubblicazione':
          DateFormat('yyyy-MM-dd').format(_data),
      'titolo_vangelo': _titolo.text.trim(),
      'testo_vangelo': _vangelo.text.trim(),
      'testo_commento': _commento.text.trim(),
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
                            labelText: 'Riferimento biblico (es. Marco 4, 35-41)',
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) =>
                              (v == null || v.trim().isEmpty) ? 'Obbligatorio' : null,
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
