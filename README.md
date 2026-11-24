# Sweep — pulizia della galleria, una foto alla volta (iOS)

App iOS nativa (Swift + SwiftUI, grafica Material 3) per fare pulizia nelle foto
e negli album dell'iPhone. Ti mostra una foto alla volta:

- **scorri a sinistra** → la tieni e passi alla successiva;
- **scorri a destra** → va nel cestino e passi alla successiva.

Sviluppata senza Mac: compilata da GitHub Actions e distribuita con
**TestFlight**. Il `.ipa` non firmato per Sideloadly resta come ripiego.

[![testflight](https://github.com/Garoth93/photo-system-IOS/actions/workflows/testflight.yml/badge.svg)](https://github.com/Garoth93/photo-system-IOS/actions/workflows/testflight.yml)
[![build-ipa](https://github.com/Garoth93/photo-system-IOS/actions/workflows/build-ipa.yml/badge.svg)](https://github.com/Garoth93/photo-system-IOS/actions/workflows/build-ipa.yml)
[![test-linux](https://github.com/Garoth93/photo-system-IOS/actions/workflows/test-linux.yml/badge.svg)](https://github.com/Garoth93/photo-system-IOS/actions/workflows/test-linux.yml)

## Cosa fa

- **Tutte le foto**, le **raccolte** (Screenshot, Selfie, Video, Live Photo,
  Raffiche, Panoramiche, Preferiti…) e i **tuoi album**, ognuno con la sua barra
  di avanzamento.
- Card grande con la foto intera, data, risoluzione, peso del file e badge
  (preferita, screenshot, Live Photo, durata video). I video si avviano con un tocco.
- Mentre trascini compaiono i timbri **TIENI** / **ELIMINA**, con vibrazione
  quando superi la soglia. Pulsanti grandi in basso e **Annulla** illimitato.
- **Cestino**: iOS chiede una conferma per ogni eliminazione fatta da un'app,
  quindi le foto scartate si accumulano nel cestino di Sweep e le elimini tutte
  insieme con **una sola conferma** (a fine album, dalla home o dal cestino).
  Dal cestino puoi ripescare quelle eliminate per sbaglio.
- **Riprendi da dove eri**: le foto già tenute non ti vengono più riproposte,
  in nessun album. "Rivedi da capo" le ripropone.
- Filtro **Tutto / Foto / Video** e ordine **Recenti / Vecchie / Casuale**.
- Totali: foto eliminate, spazio liberato, foto tenute.
- Tema chiaro/scuro automatico.

Le foto eliminate finiscono in **Eliminati di recente** dell'app Foto e restano
recuperabili per 30 giorni.

## Struttura

```
apps/Sweep/          app SwiftUI (project.yml per XcodeGen, Sources/, Resources/)
packages/SweepCore/  logica non grafica, testata con `swift test` anche su Linux
.github/workflows/   testflight, build-ipa (ripiego), build-simulator, test-linux
scripts/             API App Store Connect usate da testflight.yml
CLAUDE.md            convenzioni e regole di lavoro per Claude Code
```

## Installare l'app sull'iPhone

### TestFlight (consigliato)

1. Installa **TestFlight** dall'App Store e accedi con l'Apple ID del gruppo
   di test interni.
2. Ogni push su `main` o `claude/**` che tocca l'app carica una nuova build
   (workflow **testflight**); dopo 5-30 minuti compare in TestFlight.
   Si può anche avviare a mano: Actions › testflight › *Run workflow*.
3. Le build scadono dopo 90 giorni: il workflow si ripete da solo ogni ~60
   giorni.

Al primo avvio tocca **Consenti accesso alle foto** e scegli **Consenti
accesso completo**: con l'accesso limitato Sweep vede solo le foto che selezioni.

### Ripiego: Sideloadly (account gratuito)

1. Actions › **build-ipa** › ultimo run verde › Artifacts › `Sweep-unsigned-ipa`.
2. Sideloadly: trascina `Sweep-unsigned.ipa`, inserisci l'Apple ID, **Start**.
3. Sull'iPhone: Impostazioni › Generali › VPN e gestione dispositivo ›
   Autorizza; Modalità sviluppatore attiva.

Limiti: firma valida 7 giorni, massimo 3 app per Apple ID gratuito, backup
iCloud non disponibile.
