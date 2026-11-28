# CLAUDE.md — regole di lavoro per questa repo

Repo di app iOS **native (Swift + SwiftUI)** personali, sviluppate senza Mac:
il codice viene scritto su Linux (Claude Code) e compilato **solo** su GitHub
Actions con runner macOS. Le app non vanno su App Store: l'utente installa
l'app da **TestFlight** (account Apple a pagamento, firma automatica in CI);
il `.ipa` non firmato per Sideloadly resta come ripiego.

Stessa impostazione delle repo `Garoth93/tessere-IOS` (TestFlight, backup
iCloud), `Garoth93/montagna-360` e `Garoth93/tracking-maintenance`.

## Vincoli fissi

- Nativo vero: Swift/SwiftUI. Niente WebView, niente framework cross-platform,
  salvo richiesta esplicita dell'utente.
- Nessun `.xcodeproj` committato: il progetto è generato in CI da
  `apps/<app>/project.yml` con XcodeGen. `.gitignore` lo esclude.
- La repo è **pubblica**: mai committare segreti, chiavi API, certificati,
  profili di provisioning, dati personali, Team ID reali. I test usano solo
  dati **sintetici** (identificativi `TEST-…`), mai backup reali.
- Firma solo in `testflight.yml` (automatica, chiave API App Store Connect).
  Mai certificati, profili o `.p8` nella repo; Team ID solo nei secrets.
  `build-ipa.yml` compila senza firma (`CODE_SIGNING_ALLOWED=NO`).
- Non modificare impostazioni della repo o secrets: spiegare all'utente cosa
  configurare.

## Struttura repo

```
apps/<NomeApp>/            un'app per cartella
  project.yml              spec XcodeGen (target, bundle id, deployment target)
  Sources/                 codice SwiftUI dell'app (solo strato UI + glue)
  Resources/               Assets.xcassets e altre risorse
  Info.plist               GENERATO da XcodeGen (git-ignored)
packages/<NomePackage>/    Swift Package con la logica NON grafica
  Package.swift            tools-version 5.9, nessuna dipendenza da UIKit/SwiftUI
  Sources/<NomePackage>/   modelli, regole, persistenza (Foundation only)
  Tests/<NomePackage>Tests/ XCTest, eseguiti anche su Linux
.github/workflows/         CI (vedi sotto)
.github/actions/setup-xcode/ composite action: seleziona Xcode, installa XcodeGen, genera il progetto
```

App presenti:

| App   | Package logica | Bundle ID             | Deployment target |
|-------|----------------|-----------------------|-------------------|
| Sweep | SweepCore      | `com.garoth93.sweep`  | iOS 26.0 (SDK iOS 27.2) |

Sweep: pulizia della galleria foto, una foto alla volta. **Scorri a sinistra =
tieni e vai avanti; scorri a destra = metti nel cestino e vai avanti** (scelta
esplicita dell'utente, non invertire). In più: **su = decidi dopo** (la foto
torna in fondo alla coda, `Move.later`), **giù = Preferita** (cuore in Foto con
`PHAssetChangeRequest.isFavorite` e tenuta; Annulla toglie il cuore se l'ha
messo Sweep). Asse dominante del trascinamento; pulsanti equivalenti in basso. **Zoom**: pizzico o doppio tocco
sulla card (fino a 5×, non sui video); da ingrandita il trascinamento sposta
l'immagine invece di fare swipe e `AssetImage` chiede a Foto una versione 3×
più nitida; ogni scelta o Annulla azzera lo zoom. `PhotoViewer` (lente nei
doppioni) è la stessa cosa a schermo intero. Le foto scartate non vengono eliminate a
ogni swipe perché iOS chiede una conferma per ogni richiesta di eliminazione:
finiscono nel cestino interno (`SweepState.trash`) e si eliminano insieme con
una sola conferma (fine album, card cestino in home, schermata Cestino). Le
foto tenute (`SweepState.kept`) non vengono più riproposte in nessun album
("Rivedi da capo" le dimentica). Sorgenti: tutta la libreria, raccolte smart
(Screenshot, Selfie, Video…) e album utente; filtro Tutto/Foto/Video e ordine
Recenti/Vecchie/Più pesanti/Casuale. Accesso a Photos in `PhotoLibrary.swift`; logica in
`packages/SweepCore` (`SweepState`, `ReviewSession`, `SweepFormat`,
`CloudBackup`, palette Material 3 `MaterialScheme`). Stato salvato come JSON
in Application Support (`AppModel` + `JSONFileStore`), con salvataggio
differito per non rallentare lo swipe; preferenze (filtro, ordine, backup
on/off) in UserDefaults. Impostazioni in `SettingsView` (ingranaggio in home).

Strumenti in home (`ToolCard`):

- **Doppioni e simili** (`SimilarScanner` + `SimilarView`): per ogni foto un
  dHash a 64 bit da una miniatura locale 9×8 in grigio (`fastFormat`, niente
  download da iCloud), in cache in `Application Support/Sweep/hashes.json`
  (si calcola solo per le foto nuove). Raggruppamento in
  `SweepCore.Similarity`: scatti entro 180 s concatenati con distanza ≤ 10
  bit + hash identici in tutta la libreria, stessa forma (±5%); `best` =
  preferita, poi più pixel, più pesante, più recente. `pending` nasconde i
  gruppi con una sola foto fuori dal cestino o già tutti tenuti. Un gruppo
  alla volta: tocchi le foto da tenere, le altre vanno nel cestino; Salta e
  Annulla.
- **Video più pesanti** (`SweepSource.largeVideos`): tutti i video, sempre in
  ordine `largestFirst`. Lo stesso ordine "Più pesanti" è scelto anche per le
  altre sorgenti dai chip in home. Pesi dei file in `SizeIndex` (risorse
  `PHAssetResource`, calcolati una volta fuori dal main thread, cache in
  `Application Support/Sweep/sizes.json`, tolti dopo l'eliminazione).

### Backup iCloud Drive

Stessa procedura di tessere-IOS / montagna-360: container **condiviso**
`iCloud.com.garoth93.backup`, sottocartella `Sweep`, visibile in File come
*iCloud Drive › Backup › Sweep*.

- Configurazione: `Sweep.entitlements` (iCloud Documents sul container,
  usato da `testflight.yml`), `Sweep.sideload.entitlements` vuoto (preferito
  da `build-ipa.yml`: l'account gratuito non ha iCloud); `project.yml` con
  `SystemCapabilities` iCloud + BackgroundModes, `NSUbiquitousContainers`
  (nome `Backup`, pubblico), `UIBackgroundModes: [fetch]`,
  `BGTaskSchedulerPermittedIdentifiers: [com.garoth93.sweep.backup]`.
- File: `Sweep-backup-yyyy-MM-dd.json` (uno al giorno, ultimi 30) +
  `Sweep-backup-latest.json`. Formato `BackupFile` (package, campo `version`,
  oggi 1; decodifica tollerante ai campi mancanti, rifiuta app diversa e
  versioni future): foto tenute e cestino come `PhotoRef`, totali
  (eliminate, spazio liberato), riepilogo album (`AlbumSummary`: titolo,
  tipo, totale, viste; solo informativo), impostazioni (`SweepSettings`).
  **Mai** foto, miniature, token o dati sensibili.
- `PhotoRef` = `PHAsset.localIdentifier` (valido solo su quell'iPhone) +
  identificativo **Foto di iCloud** (`PHCloudIdentifier.stringValue`, quando la
  foto è in Foto di iCloud). Al ripristino `restoredState(existing:cloudToLocal:)`
  usa l'id locale se esiste ancora, altrimenti rimappa l'id iCloud
  (`localIdentifierMappings`): così le scelte valgono anche su un iPhone nuovo.
  Gli id iCloud sono calcolati a lotti di 500 fuori dal main thread e tenuti
  in cache in `Application Support/Sweep/cloud-ids.json`.
- Logica pura (formato, nomi file, pulizia, impronta per non riscrivere se
  nulla è cambiato, rimappatura) in `CloudBackup.swift` del package, con test.
  I/O in `CloudBackupService.swift`: `url(forUbiquityContainerIdentifier:)`
  sempre fuori dal main thread, `NSFileCoordinator`, segnaposto `.icloud`
  scaricati con `startDownloadingUbiquitousItem`.
- Quando: 8 s dopo l'ultima modifica (`AppModel.onDataChanged`), all'uscita in
  background (con `beginBackgroundTask`), `BGAppRefreshTask` ogni ~6 h.
  Un'app vuota (niente tenute, cestino ed eliminate) non sovrascrive mai i backup.
- Ripristino: Impostazioni › Ripristina da iCloud (`CloudRestoreView`, elenco,
  anteprima, conferma se l'app ha già dati), e guidato al primo avvio se l'app
  è vuota e in iCloud c'è un backup (chiesto una volta sola, dopo il permesso
  Foto). Export/import manuale dello stesso JSON da Impostazioni › File.

Per aggiungere un'app: creare `apps/<Nome>/project.yml` + `Sources/` +
`Resources/`; i workflow scoprono automaticamente le cartelle in `apps/`
e i `Package.swift` in `packages/`. Il nome della cartella deve coincidere
con `name`, target e scheme nel `project.yml`.

## Convenzioni di codice

- Swift 5 language mode (`SWIFT_VERSION: 5.0` nel project.yml), tools-version
  5.9 nei package, in modo che Linux (`swift:6.0`) e Xcode 26 compilino lo
  stesso codice. Il package dichiara `.iOS(.v17)` come minimo: è solo il suo
  minimo, l'app può avere un target più alto.
- Logica, modelli e persistenza nel package: tipi `struct` value-type,
  `Codable`, `Equatable`, `Sendable`, senza `import SwiftUI`/`UIKit`.
  Tutto ciò che è testabile va lì e ha un test.
- Nell'app: `@Observable` (framework Observation) + `@MainActor`, iniettato
  con `.environment(...)` e letto con `@Environment(Tipo.self)`; viste piccole,
  una per file; stringhe UI in italiano. Target iOS 26.0: si possono usare
  SwiftData, Liquid Glass e le API SwiftUI di iOS 26 senza `#available`.
- Persistenza: JSON in Application Support tramite `JSONFileStore` (o
  SwiftData/UserDefaults quando serve, decidere caso per caso e documentarlo).
- Nessuna dipendenza esterna salvo necessità motivata; se serve, dichiararla
  nel `Package.swift` o in `project.yml > packages`, mai vendorizzare binari.
- Commit piccoli e descrittivi, in italiano o inglese ma coerenti; un commit
  per argomento. Niente identificatori di modello AI nei commit.

## Xcode e runner

- Runner: `xcode-27` (immagine macOS 27 con Xcode 27.x; `macos-26` arriva solo
  a Xcode 26.6 / SDK iOS 26.5, non più accettato da App Store Connect da aprile
  2027). Xcode fissato con `XCODE_VERSION: "27.2"` (SDK iOS 27.2) (env in ogni
  workflow) e selezionato con `xcode-select`. Se GitHub ritira la versione,
  la composite action fallisce elencando le Xcode disponibili: aggiornare il
  valore in tutti i workflow, in `project.yml` (`xcodeVersion`) e qui.
  Versioni installate: `images/macos/xcode-27-arm64-Readme.md` della repo
  `actions/runner-images`. Deployment target dell'app: iOS 26.0.
- Toolchain Linux per i test: immagine Docker `swift:6.0-noble`.
- XcodeGen e xcbeautify installati con Homebrew a ogni run.

## CI (GitHub Actions)

| Workflow | Trigger | Cosa fa |
|----------|---------|---------|
| `build-simulator.yml` | push su ogni branch, PR, manuale | `xcodebuild build` per iOS Simulator, senza firma. Serve a vedere gli errori di compilazione. |
| `build-ipa.yml` | push su `main` e `claude/**`, manuale | ripiego Sideloadly: build Release per dispositivo con `CODE_SIGNING_ALLOWED=NO`, firma ad-hoc con `<App>.sideload.entitlements` (o `<App>.entitlements`) se presente, impacchetta `Payload/<App>.app` in `<App>-unsigned.ipa` e lo carica come artifact (30 giorni). |
| `test-linux.yml` | push su ogni branch, PR, manuale | `swift test` su ogni package in `packages/`. |
| `testflight.yml` | manuale, push su `main` e `claude/**` (solo `apps/`, `packages/`, `scripts/`), ogni ~60 giorni | archive firmato + export App Store + upload su TestFlight (vedi sotto). Il 15 di ogni mese un job `keepalive` riattiva il workflow via API. |

### TestFlight

Già configurato a mano (una volta) dall'utente:

- developer.apple.com: App ID esplicito `com.garoth93.sweep` con la sola
  capability **iCloud** (CloudKit) e il container `iCloud.com.garoth93.backup`
  assegnato (*Configure*). Niente App Group (Sweep non ha widget).
- App Store Connect: scheda "Sweep – Pulizia Foto", SKU `sweep-ios`, bundle
  `com.garoth93.sweep`; TestFlight › gruppo di test interni con
  distribuzione automatica.
- Secrets della repo: `APPLE_TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID`,
  `ASC_KEY_P8` (chiave API con ruolo Admin, la stessa delle altre repo).

Come funziona (stessa procedura di tessere-IOS): `xcodebuild archive` con
firma automatica (`-allowProvisioningUpdates` + chiave API; crea al volo un
certificato di sviluppo sul runner, revocato dallo step finale con
`scripts/asc_revoke_certs.py`), poi `-exportArchive` con
`method=app-store-connect`, `destination=upload` (firma di distribuzione
gestita da Apple e upload diretto). Build number = `github.run_number` del
workflow; `MARKETING_VERSION` nel `project.yml` va alzato a mano per le nuove
versioni. La build compare in TestFlight dopo 5-30 minuti. Lo step
"App ID capabilities" (`scripts/asc_bundle_ids.py`) stampa capability e
profili e cancella quelli senza il container iCloud, così Xcode li rigenera.
Log di archive/export nell'artifact `testflight-logs`.

Le build TestFlight scadono dopo 90 giorni: il cron `17 4 1 */2 *` le
rinnova (gira sul branch di default della repo). GitHub disattiva i workflow
programmati delle repo pubbliche dopo 60 giorni senza attività: il job
`keepalive` (cron `43 5 15 * *`) chiama l'API "enable workflow" per azzerare
il contatore. Se il workflow risultasse comunque disattivato: Actions ›
testflight › *Enable workflow*, oppure un commit qualsiasi.

Errori tipici: "doesn't match the entitlements file's value" = container
iCloud non assegnato all'App ID su developer.apple.com; 90474 = manca
`UIRequiresFullScreen` (l'app è solo verticale).

Nota: nei repo pubblici i workflow con `schedule` vengono disattivati dopo 60
giorni senza commit. Se in futuro si aggiunge un rebuild periodico (utile per
la scadenza a 7 giorni della firma gratuita), prevedere un riattivatore o usare
`workflow_dispatch`.

### Come leggere i log di CI

Con `gh` (se il token è valido):

```bash
gh run list --limit 10
gh run view <run-id> --log-failed
gh run watch <run-id>
gh run download <run-id> -n Sweep-unsigned-ipa   # ripiego Sideloadly
```

Con gli strumenti GitHub MCP disponibili a Claude Code (quando `gh` non è
autenticato): `actions_list` con `list_workflow_runs` per trovare il run,
`list_workflow_jobs` per i job, `get_job_logs` con `failed_only=true` e
`return_content=true` per i log dei job falliti. I log raw di `xcodebuild`
sono anche caricati come artifact `xcodebuild-*-log-<App>`.

Gli errori Swift compaiono come annotazioni `::error file=...` grazie a
`xcbeautify --renderer github-actions`.

## Regole di lavoro (per Claude)

1. Dopo **ogni push** controllare l'esito della CI e correggere da soli gli
   errori di compilazione fino a build verde. Mai dichiarare "funziona" se la
   CI non è verde: riportare l'esito reale con il link al run.
2. Non si può vedere l'interfaccia: nelle scelte grafiche ambigue usare il
   comportamento standard e dire all'utente cosa verificare sul telefono.
3. Commit piccoli e descrittivi. Mai segreti. Mai toccare impostazioni repo o
   secrets: indicare all'utente cosa configurare.
4. I test del package si possono eseguire in locale con Docker:
   `docker run --rm -v "$PWD":/src -w /src swift:6.0-noble swift test --package-path packages/SweepCore`
   (avviare `dockerd` se non è attivo). L'app SwiftUI si compila solo in CI.
