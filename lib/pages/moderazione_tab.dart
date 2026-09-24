import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:just_audio/just_audio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Moderazione: elenco cronologico di tutte le riflessioni (anche nascoste),
/// con le segnalazioni degli utenti, ascolto degli audio e azioni
/// nascondi / ripubblica / elimina. Tre segnalazioni nascondono una
/// riflessione da sole; ripubblicarla archivia le segnalazioni.
class ModerazioneTab extends StatefulWidget {
  const ModerazioneTab({super.key});

  @override
  State<ModerazioneTab> createState() => _ModerazioneTabState();
}

class _ModerazioneTabState extends State<ModerazioneTab> {
  final _client = Supabase.instance.client;
  late Future<List<Map<String, dynamic>>> _future;
  bool _soloSegnalate = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = _client
        .from('riflessioni')
        .select('*, segnalazioni(motivo, created_at)')
        .order('data_creazione', ascending: false)
        .then((rows) => (rows as List).cast<Map<String, dynamic>>());
  }

  Future<void> _setStato(Map<String, dynamic> row, String stato) async {
    await _client.from('riflessioni').update({'stato': stato}).eq('id', row['id']);
    // Ripubblicare = l'admin l'ha rivista: le segnalazioni vecchie si archiviano.
    if (stato == 'pubblicato') await _archiviaSegnalazioni(row, ricarica: false);
    setState(_reload);
  }

  Future<void> _archiviaSegnalazioni(Map<String, dynamic> row,
      {bool ricarica = true}) async {
    await _client.from('segnalazioni').delete().eq('riflessione_id', row['id']);
    if (ricarica) setState(_reload);
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminare la riflessione?'),
        content: const Text('L\'operazione è definitiva.'),
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
    // Rimuove anche il file audio dallo Storage, se presente.
    if (row['tipo'] == 'audio' && row['audio_url'] != null) {
      final path = _objectPathFromUrl(row['audio_url'] as String);
      if (path != null) {
        try {
          await _client.storage.from('audio').remove([path]);
        } catch (_) {/* il file potrebbe non esistere più */}
      }
    }
    await _client.from('riflessioni').delete().eq('id', row['id']);
    setState(_reload);
  }

  /// Estrae il percorso interno al bucket dall'URL pubblico.
  String? _objectPathFromUrl(String url) {
    const marker = '/audio/';
    final i = url.indexOf(marker);
    return i == -1 ? null : url.substring(i + marker.length);
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
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
          final tutte = snapshot.data ?? [];
          final segnalate = tutte
              .where((r) => ((r['segnalazioni'] as List?) ?? const []).isNotEmpty)
              .length;
          final rows = _soloSegnalate
              ? tutte
                  .where((r) =>
                      ((r['segnalazioni'] as List?) ?? const []).isNotEmpty)
                  .toList()
              : tutte;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  FilterChip(
                    selected: _soloSegnalate,
                    onSelected: (v) => setState(() => _soloSegnalate = v),
                    avatar: const Icon(Icons.flag, size: 18),
                    label: Text('Solo segnalate ($segnalate)'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 80),
                  child: Center(child: Text('Niente da mostrare.')),
                ),
              for (final r in rows)
                _ModCard(
                  row: r,
                  onHide: () => _setStato(r, 'nascosto'),
                  onShow: () => _setStato(r, 'pubblicato'),
                  onDelete: () => _delete(r),
                  onArchive: () => _archiviaSegnalazioni(r),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ModCard extends StatelessWidget {
  const _ModCard({
    required this.row,
    required this.onHide,
    required this.onShow,
    required this.onDelete,
    required this.onArchive,
  });

  final Map<String, dynamic> row;
  final VoidCallback onHide;
  final VoidCallback onShow;
  final VoidCallback onDelete;
  final VoidCallback onArchive;

  @override
  Widget build(BuildContext context) {
    final isAudio = row['tipo'] == 'audio';
    final nascosto = row['stato'] == 'nascosto';
    final date = DateTime.parse(row['data_creazione'] as String);
    final segnalazioni =
        ((row['segnalazioni'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final motivi = <String, int>{};
    for (final s in segnalazioni) {
      motivi.update(s['motivo'] as String, (n) => n + 1, ifAbsent: () => 1);
    }
    return Card(
      color: nascosto ? Colors.grey.shade200 : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(isAudio ? Icons.mic : Icons.notes, size: 18),
                const SizedBox(width: 8),
                Text(row['nome_autore'] as String,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                Text(
                  DateFormat('d MMM y, HH:mm', 'it_IT').format(date),
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
                const Spacer(),
                if (nascosto)
                  const Chip(
                    label: Text('Nascosto'),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            if (segnalazioni.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.flag, size: 18, color: Colors.red.shade400),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${segnalazioni.length} '
                        '${segnalazioni.length == 1 ? 'segnalazione' : 'segnalazioni'}: '
                        '${motivi.entries.map((e) => e.value > 1 ? '${e.key} (${e.value})' : e.key).join(', ')}',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    TextButton(
                      onPressed: onArchive,
                      child: const Text('Archivia'),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            if (isAudio)
              _AudioPreview(url: row['audio_url'] as String)
            else
              Text(row['testo'] as String),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (nascosto)
                  TextButton.icon(
                    onPressed: onShow,
                    icon: const Icon(Icons.visibility),
                    label: const Text('Ripubblica'),
                  )
                else
                  TextButton.icon(
                    onPressed: onHide,
                    icon: const Icon(Icons.visibility_off),
                    label: const Text('Nascondi'),
                  ),
                TextButton.icon(
                  onPressed: onDelete,
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Elimina'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AudioPreview extends StatefulWidget {
  const _AudioPreview({required this.url});
  final String url;

  @override
  State<_AudioPreview> createState() => _AudioPreviewState();
}

class _AudioPreviewState extends State<_AudioPreview> {
  final _player = AudioPlayer();
  bool _loaded = false;

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (!_loaded) {
      await _player.setUrl(widget.url);
      _loaded = true;
    }
    if (_player.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton.filled(
          onPressed: _toggle,
          icon: Icon(_player.playing ? Icons.pause : Icons.play_arrow),
        ),
        const SizedBox(width: 8),
        const Text('Messaggio vocale'),
      ],
    );
  }
}
