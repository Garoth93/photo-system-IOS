# Sweep — pulizia della galleria, una foto alla volta (iOS)

App iOS nativa (Swift + SwiftUI, grafica Material 3) per fare pulizia nelle foto
e negli album dell'iPhone. Ti mostra una foto alla volta:

- **scorri a sinistra** → la tieni e passi alla successiva;
- **scorri a destra** → va nel cestino e passi alla successiva.

Sviluppata senza Mac: compilata da GitHub Actions e installata sull'iPhone con
un account Apple gratuito tramite Sideloadly o SideStore.

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
.github/workflows/   build-simulator, build-ipa, test-linux
CLAUDE.md            convenzioni e regole di lavoro per Claude Code
```

## Installare l'app sull'iPhone

### 1. Scaricare il `.ipa`

1. Pagina **Actions** della repo → workflow **build-ipa**.
2. Apri l'ultimo run verde (o avvialo con **Run workflow**).
3. In fondo alla pagina, sezione **Artifacts**, scarica `Sweep-unsigned-ipa`
   (uno zip che contiene `Sweep-unsigned.ipa`) ed estrailo. Resta disponibile 30 giorni.

### 2. Firmare e installare con Sideloadly

1. Collega l'iPhone via USB, sbloccalo e scegli "Autorizza".
2. Apri Sideloadly, trascina `Sweep-unsigned.ipa` nella finestra.
3. Inserisci il tuo Apple ID (account gratuito) e premi **Start**.
4. Sull'iPhone: Impostazioni → Generali → **VPN e gestione dispositivo** → il tuo
   Apple ID → **Autorizza**. Serve anche la **Modalità sviluppatore** attiva
   (Impostazioni → Privacy e sicurezza).

### 3. Primo avvio

Tocca **Consenti accesso alle foto** e scegli **Consenti accesso completo**: con
l'accesso limitato Sweep vede solo le foto che selezioni.

### 4. Limiti dell'account gratuito

- La firma scade dopo **7 giorni**: rifirma lo stesso `.ipa` con Sideloadly
  (il bundle ID `com.garoth93.sweep` non cambia, i progressi restano).
- Massimo 3 app firmate contemporaneamente per Apple ID.
- Lo stato di Sweep (foto già viste, cestino) sta nella sandbox dell'app: se
  elimini l'app ricominci da zero. Le foto nella galleria non vengono toccate.
