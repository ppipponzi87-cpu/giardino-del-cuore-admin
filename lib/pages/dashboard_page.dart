import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'campagne_tab.dart';
import 'letture_tab.dart';
import 'meditazioni_tab.dart';
import 'moderazione_tab.dart';

/// Contenitore autenticato: verifica il ruolo admin e mostra le sezioni
/// (letture, meditazioni, campagne, moderazione).
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  bool _loading = true;
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _checkRole();
  }

  Future<void> _checkRole() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    try {
      final row = await Supabase.instance.client
          .from('profili')
          .select('ruolo')
          .eq('id', uid!)
          .maybeSingle();
      setState(() {
        _isAdmin = row?['ruolo'] == 'admin';
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _isAdmin = false;
        _loading = false;
      });
    }
  }

  Future<void> _logout() => Supabase.instance.client.auth.signOut();

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!_isAdmin) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 48),
              const SizedBox(height: 12),
              const Text('Questo account non ha i permessi di amministratore.'),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: _logout, child: const Text('Esci')),
            ],
          ),
        ),
      );
    }

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Il Giardino del Cuore — Amministrazione'),
          actions: [
            IconButton(
              onPressed: _logout,
              icon: const Icon(Icons.logout),
              tooltip: 'Esci',
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.menu_book), text: 'Letture'),
              Tab(icon: Icon(Icons.self_improvement), text: 'Meditazioni'),
              Tab(icon: Icon(Icons.volunteer_activism), text: 'Campagne'),
              Tab(icon: Icon(Icons.forum), text: 'Moderazione'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            LettureTab(),
            MeditazioniTab(),
            CampagneTab(),
            ModerazioneTab(),
          ],
        ),
      ),
    );
  }
}
