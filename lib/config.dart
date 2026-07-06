/// Configurazione Supabase del pannello admin.
///
/// Stessi valori dell'app mobile (Project URL + chiave anon public).
/// Vengono iniettati a build time con --dart-define dai GitHub Secrets;
/// la chiave anon è pubblica per definizione (i poteri di admin sono
/// protetti lato server dalle RLS che verificano il ruolo).
class Config {
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  static bool get isConfigured => supabaseUrl.isNotEmpty;
}
