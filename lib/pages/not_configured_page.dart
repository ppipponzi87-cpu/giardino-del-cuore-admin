import 'package:flutter/material.dart';

/// Mostrata quando le chiavi Supabase non sono state iniettate nel build.
class NotConfiguredPage extends StatelessWidget {
  const NotConfiguredPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.settings, size: 48),
                const SizedBox(height: 16),
                Text('Pannello non ancora configurato',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                const Text(
                  'Le chiavi Supabase non sono state impostate al momento '
                  'della pubblicazione. Aggiungi i GitHub Secrets '
                  'SUPABASE_URL e SUPABASE_ANON_KEY al repository del pannello '
                  'e ripubblica.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
