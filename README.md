# Scripta

Scripta è un editor di scrittura per macOS dedicato a **sceneggiature** (formato [Fountain](https://fountain.io/syntax)), **prosa** (Markdown) e **script per fumetti/graphic novel**. Il motore di parsing e analisi è una libreria Swift indipendente dall'interfaccia, quindi funziona anche su **Linux** tramite un'interfaccia a riga di comando.

## Funzionalità

- **Due modalità di scrittura**: sceneggiatura (Fountain) e prosa (Markdown), con evidenziazione della sintassi in tempo reale.
- **Supporto graphic novel**: tavole (`# Tav. 1`), vignette (`.Vig. 1`) e balloon (`**NOME**: testo`) in entrambe le modalità.
- **Outline navigabile**: scene, sezioni, titoli, tavole e vignette.
- **Analisi dei personaggi**: numero di battute e parole per ciascun personaggio.
- **Export** in PDF (US Letter o A4), HTML, Markdown e Fountain (solo macOS).
- **Anteprima Quick Look** dei file `.fountain` nel Finder (solo macOS).
- **CLI `scripta`** multi-piattaforma per statistiche e outline da terminale.

## Struttura del progetto

```
Package.swift
Sources/
├── ScriptaCore/   Libreria condivisa: parser Fountain/Markdown, outline, analisi personaggi (macOS + Linux)
├── ScriptaApp/    App macOS: interfaccia SwiftUI/AppKit, editor ed export (solo macOS)
└── ScriptaCLI/    Eseguibile `scripta` (macOS + Linux)
QuickLook/         Estensione Quick Look (macOS)
Resources/         Info.plist del bundle dell'app
Examples/          File di esempio (.fountain, .md)
build-app.sh       Build di Scripta.app (macOS)
build-linux.sh     Build della CLI (Linux, ma funziona anche su macOS)
package-dmg.sh     Pacchetto Scripta-macOS-arm64.dmg
package-linux.sh   Pacchetto Scripta-Linux-x86_64.zip
```

| Prodotto SwiftPM | Target        | Piattaforme     |
|------------------|---------------|-----------------|
| `ScriptaCore`    | `ScriptaCore` | macOS, Linux    |
| `scripta`        | `ScriptaCLI`  | macOS, Linux    |
| `ScriptaApp`     | `ScriptaApp`  | solo macOS      |

Il target `ScriptaApp` viene dichiarato in `Package.swift` solo quando si compila su macOS, quindi su Linux `swift build` compila soltanto la libreria e la CLI.

## Requisiti

- **macOS**: macOS 15 o successivo, Apple Silicon, Xcode o Command Line Tools con Swift 6.0+.
- **Linux**: toolchain Swift 6.0+ ([swift.org/install](https://www.swift.org/install/)).

## Compilare l'app su macOS

```bash
./build-app.sh            # build di release
./build-app.sh debug      # build di debug, più rapida
```

Lo script:

1. compila il prodotto `ScriptaApp` con Swift Package Manager (arm64);
2. assembla il bundle in `build/Scripta.app`;
3. compila e incorpora l'estensione Quick Look (`Contents/PlugIns/ScriptaQuickLook.appex`);
4. firma il bundle (firma ad-hoc) e lo registra presso Launch Services.

Per avviare l'app:

```bash
open build/Scripta.app
```

L'eseguibile dell'app supporta anche l'export da terminale:

```bash
build/Scripta.app/Contents/MacOS/Scripta --export Examples/Esempio.fountain out.pdf --paper a4
```

## Compilare e usare la CLI su Linux

```bash
./build-linux.sh          # build di release
./build-linux.sh debug    # build di debug
```

In alternativa si può usare direttamente SwiftPM:

```bash
swift build -c release --product scripta
swift run scripta Examples/Esempio.fountain
```

L'eseguibile viene creato in `.build/release/scripta`. Per installarlo nel `PATH`:

```bash
sudo install -m 755 .build/release/scripta /usr/local/bin/scripta
```

La stessa CLI si compila e funziona anche su macOS.

### Uso

```
scripta [--mode screenplay|prose] <file>
```

La modalità si deduce dall'estensione (`.fountain`/`.spmd` → sceneggiatura, `.md`/`.markdown` → prosa). Per le altre estensioni viene dedotta dal contenuto. `--mode` la forza.

Esempio:

```
$ scripta Examples/Esempio.fountain
Scripta — Esempio.fountain
L'ULTIMA BOBINA

STATISTICHE
  Modalità              Sceneggiatura
  Parole                102
  Caratteri             950
  Righe non vuote       33
  Scene                 2
  Sezioni               1
  Personaggi            2
  Battute               5
  Righe di dialogo      5

PERSONAGGI
  GIULIO  2 battute, 12 parole (11.8%)
  MARTA   3 battute, 7 parole (6.9%)

OUTLINE
  § Atto primo
    1. INT. CINEMA ABBANDONATO - NOTTE
    2. EXT. TETTO DEL CINEMA - ALBA
```

Per i file di prosa la CLI riporta il numero di titoli e una stima del tempo di lettura. Se il file contiene tavole e vignette, ne riporta anche il conteggio.

## Pacchetti di distribuzione

Ogni release fornisce due pacchetti pronti all'uso:

| Pacchetto                   | Contenuto                                           | Piattaforma                  |
|-----------------------------|-----------------------------------------------------|------------------------------|
| `Scripta-macOS-arm64.dmg`   | `Scripta.app` + collegamento ad Applicazioni        | macOS 15+, Apple Silicon     |
| `Scripta-Linux-x86_64.zip`  | eseguibile `scripta` + cartella `Examples/`         | Linux x86_64 (glibc)         |

### Installare da un pacchetto

**macOS.** Apri `Scripta-macOS-arm64.dmg` e trascina **Scripta** nella cartella **Applicazioni**. L'app ha solo una firma ad-hoc e non è notarizzata. Al primo avvio, quindi, macOS la blocca: fai clic destro su Scripta e scegli **Apri**, oppure rimuovi l'attributo di quarantena:

```bash
xattr -dr com.apple.quarantine /Applications/Scripta.app
```

**Linux.** L'eseguibile include il runtime Swift e Foundation (link statico), quindi non serve installare Swift.

```bash
unzip Scripta-Linux-x86_64.zip
cd Scripta-Linux-x86_64
./scripta Examples/Esempio.fountain
sudo install -m 755 scripta /usr/local/bin/scripta   # opzionale
```

### Generare i pacchetti

I pacchetti vengono creati nella cartella `build/`.

**DMG per macOS**, da eseguire su un Mac:

```bash
./package-dmg.sh
```

Lo script esegue `./build-app.sh` in modalità release e copia l'app in una cartella temporanea insieme al collegamento `Applications`. Poi crea un'immagine compressa (UDZO) con `diskutil image`, oppure con `hdiutil` sulle versioni di macOS precedenti, e infine la verifica. Risultato: `build/Scripta-macOS-arm64.dmg`.

**ZIP per Linux**:

```bash
./package-linux.sh
```

- **Su Linux** usa la toolchain Swift locale. Il nome dell'archivio riflette l'architettura della macchina (es. `Scripta-Linux-x86_64.zip`). Richiede il comando `zip`.
- **Su macOS (o altri sistemi)** compila dentro l'immagine Docker ufficiale `swift:6.0` per `linux/amd64` e produce `Scripta-Linux-x86_64.zip`. Richiede Docker. Su Apple Silicon la compilazione avviene in emulazione ed è quindi più lenta.

Variabili utili:

```bash
SWIFT_IMAGE=swift:6.1 ./package-linux.sh   # usa un'altra immagine Swift
USE_DOCKER=1 ./package-linux.sh            # forza Docker anche su Linux
```

La build Linux usa la cartella `.build-linux/`, separata da `.build/`, così non interferisce con la build macOS.

## Usare ScriptaCore in un altro progetto

```swift
.package(path: "../Scripta"),
// ...
.target(name: "MyTool", dependencies: [.product(name: "ScriptaCore", package: "Scripta")])
```

```swift
import ScriptaCore

let outline = DocumentOutline.items(in: text, mode: .screenplay)
let characters = CharacterAnalysis.statistics(text: text, mode: .screenplay)
```
