# Il Giardino del Cuore — Pannello Admin

App web (Flutter) per amministrare i contenuti del Giardino del Cuore:

- **Letture**: inserimento e modifica del Vangelo del giorno e del commento,
  con **data di pubblicazione programmabile** (i contenuti futuri compaiono
  come "programmati" e diventano visibili nell'app alla loro data).
- **Moderazione**: elenco cronologico di tutte le riflessioni della comunità,
  ascolto dei messaggi vocali, e azioni nascondi / ripubblica / elimina.

L'accesso è riservato agli account con ruolo `admin` (verificato lato server
dalle Row Level Security di Supabase). La chiave `anon` inclusa nel build è
pubblica per definizione e non concede alcun potere di amministrazione.

## Pubblicazione

Pubblicato automaticamente su **GitHub Pages** a ogni push su `main`
(workflow `deploy-pages.yml`). Richiede due **GitHub Secrets** nel repository:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`

e Pages impostato su **GitHub Actions** (Settings → Pages → Source: GitHub Actions).

## Sviluppo locale

```bash
flutter run -d chrome \
  --dart-define=SUPABASE_URL=... \
  --dart-define=SUPABASE_ANON_KEY=...
```
