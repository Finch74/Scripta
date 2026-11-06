# Scripta

Scripta è un editor di scrittura per macOS dedicato a **sceneggiature** (formato [Fountain](https://fountain.io/syntax)), **prosa** (Markdown) e **script per fumetti/graphic novel**. Il motore di parsing e analisi è una libreria Swift indipendente dall'interfaccia, quindi funziona anche su **Linux**, sia con un'interfaccia grafica nativa (GTK 4) sia da riga di comando. Il supporto a **Windows** è in preparazione (`ScriptaWin`, per ora a riga di comando).

**Repository:** [github.com/Finch74/Scripta](https://github.com/Finch74/Scripta) · **Download:** [ultima release](https://github.com/Finch74/Scripta/releases/latest)

```bash
git clone https://github.com/Finch74/Scripta.git
cd Scripta
```

## Funzionalità

- **Due modalità di scrittura**: sceneggiatura (Fountain) e prosa (Markdown), con evidenziazione della sintassi in tempo reale.
- **Supporto graphic novel**: tavole (`# Tav. 1`), vignette (`.Vig. 1`) e balloon (`**NOME**: testo`) in entrambe le modalità.
- **Outline navigabile**: scene, sezioni, titoli, tavole e vignette.
- **Analisi dei personaggi**: numero di battute e parole per ciascun personaggio.
- **Export** in PDF (US Letter o A4) su macOS e Linux; HTML, Markdown e Fountain solo su macOS.
- **Anteprima Quick Look** dei file `.fountain` nel Finder (solo macOS).
- **CLI `scripta`** multi-piattaforma per statistiche e outline da terminale.
- **GUI per Linux `scripta-gtk`** (GTK 4): editor con evidenziazione, outline navigabile, personaggi, statistiche ed export PDF.

## Struttura del progetto

```
Package.swift
Sources/
├── ScriptaCore/   Libreria condivisa: parser Fountain/Markdown, outline, analisi personaggi (tutte le piattaforme)
├── ScriptaApp/    App macOS: interfaccia SwiftUI/AppKit, editor ed export (solo macOS)
├── ScriptaCLI/    Eseguibile `scripta` (tutte le piattaforme)
├── ScriptaGTK/    App Linux `scripta-gtk`: interfaccia GTK 4 (solo Linux)
├── ScriptaWin/    Front end Windows `ScriptaWin` (solo Windows, per ora a riga di comando)
├── CGtk/          Modulo di sistema che espone GTK 4 a Swift (pkg-config `gtk4`)
├── CWebKit/       Modulo di sistema WebKitGTK 6.0, per l'export PDF (pkg-config `webkitgtk-6.0`)
└── CPoppler/      Modulo di sistema Poppler GLib, per numeri di pagina e metadati del PDF
QuickLook/         Estensione Quick Look (macOS)
Resources/         Info.plist del bundle dell'app
Resources/Linux/   File .desktop, icona, install.sh e AppRun per la GUI Linux
Examples/          File di esempio (.fountain, .md)
LICENSE            Licenza MIT
build-app.sh       Build di Scripta.app (macOS)
build-linux.sh     Build della CLI (Linux, ma funziona anche su macOS)
package-dmg.sh     Pacchetto Scripta-macOS-arm64.dmg
package-linux-gui.sh  Pacchetto Scripta-GUI-Linux-x86_64.tar.gz (e AppImage opzionale)
package-deb.sh     Pacchetto Debian/Ubuntu scripta-gtk_<versione>_<arch>.deb
package-rpm.sh     Pacchetto Fedora/RHEL scripta-gtk-<versione>-<release>.<arch>.rpm
scripta-gtk.spec   Specifica RPM usata da package-rpm.sh
build-windows.ps1  Installazione dipendenze (WinGet) e build di ScriptaWin (Windows)
.github/workflows/windows-build.yml  Build di ScriptaWin su GitHub Actions (windows-latest)
```

### Matrice di compatibilità

| Prodotto SwiftPM | Target        | macOS 15+ (Apple Silicon) | Linux x86_64 / arm64 | Windows 10/11 x64 |
|------------------|---------------|:-------------------------:|:--------------------:|:-----------------:|
| `ScriptaCore`    | `ScriptaCore` | ✅ | ✅ | ✅ |
| `scripta` (CLI)  | `ScriptaCLI`  | ✅ | ✅ | ✅ ¹ |
| `ScriptaApp`     | `ScriptaApp`  | ✅ | — | — |
| `scripta-gtk`    | `ScriptaGTK`  | — | ✅ (GTK 4, WebKitGTK 6.0, Poppler) | — |
| `ScriptaWin`     | `ScriptaWin`  | — | — | 🚧 anteprima a riga di comando |

¹ Compila con la toolchain Swift per Windows, ma non ha ancora uno script di build dedicato.

| Funzionalità                      | macOS | Linux (GTK) | Windows |
|-----------------------------------|:-----:|:-----------:|:-------:|
| Editor con evidenziazione         | ✅ | ✅ | — |
| Outline, personaggi, statistiche  | ✅ | ✅ | statistiche (console) |
| Export PDF                        | ✅ | ✅ | — |
| Export HTML, Markdown, Fountain   | ✅ | — | — |
| Anteprima Quick Look              | ✅ | — | — |

| Pacchetto                                 | Piattaforma                     | Script                 |
|-------------------------------------------|---------------------------------|------------------------|
| `Scripta-macOS-arm64.dmg`                 | macOS 15+, Apple Silicon        | `package-dmg.sh`       |
| `scripta-gtk_<versione>-1_amd64.deb`      | Debian 12+, Ubuntu 24.04+       | `package-deb.sh`       |
| `scripta-gtk-<versione>-1.<dist>.x86_64.rpm` | Fedora 39+, RHEL 10 e derivate | `package-rpm.sh`       |
| `Scripta-GUI-Linux-x86_64.tar.gz`, AppImage | Linux x86_64 con GTK 4        | `package-linux-gui.sh` |
| `ScriptaWin.exe` (artefatto di build)     | Windows x64                     | `build-windows.ps1`, GitHub Actions |

Le interfacce grafiche sono dichiarate in `Package.swift` in base al sistema su cui si compila: `ScriptaApp` solo su macOS, `ScriptaGTK` (con i moduli di sistema `CGtk`, `CWebKit` e `CPoppler`) solo su Linux, `ScriptaWin` (solo `ScriptaCore`) solo su Windows. Entrambe usano `ScriptaCore` per parsing, outline, personaggi e statistiche (`DocumentStatistics`, condivisa anche con la CLI). Su Linux, `swift build` senza `--product` compila anche la GUI e richiede quindi GTK 4; `swift build --product scripta` compila solo la CLI.

## Requisiti

- **macOS**: macOS 15 o successivo, Apple Silicon, Xcode o Command Line Tools con Swift 6.0+.
- **Linux**: toolchain Swift 6.0+ ([swift.org/install](https://www.swift.org/install/)).
- **GUI Linux**: in più, GTK 4.6 o successivo, WebKitGTK 6.0 e Poppler (per l'esportazione PDF) con i file di sviluppo e `pkg-config` (Ubuntu 24.04+, Debian 12+, Fedora 39+).
- **Windows**: Windows 10/11 x64, Visual Studio 2022 (MSVC x64/ARM64 e Windows 11 SDK) e la toolchain Swift, entrambi installati da `build-windows.ps1` con WinGet.

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

## Compilare e usare la GUI su Linux (GTK 4)

`scripta-gtk` è l'interfaccia grafica nativa per Linux. È scritta in Swift e chiama direttamente l'API C di GTK 4 attraverso il modulo `CGtk`, senza dipendenze esterne. Tutta la logica (parsing Fountain/Markdown, outline, analisi dei personaggi, statistiche) viene da `ScriptaCore`.

Installa prima GTK 4 e `pkg-config`:

```bash
sudo apt install libgtk-4-dev libwebkitgtk-6.0-dev libpoppler-glib-dev pkg-config     # Debian/Ubuntu
sudo dnf install gtk4-devel webkitgtk6.0-devel poppler-glib-devel pkgconf-pkg-config   # Fedora
```

Poi compila e avvia:

```bash
swift build -c release --product scripta-gtk
.build/release/scripta-gtk Examples/Esempio.fountain
```

Funzionalità della GUI:

- editor con evidenziazione della sintassi e impaginazione da sceneggiatura (personaggi, dialoghi e transizioni rientrati), aggiornata mentre scrivi;
- barra laterale con **Outline** (clic su una voce per raggiungerla), **Personaggi** e **Statistiche**, gli stessi dati della CLI;
- scelta della modalità (Sceneggiatura/Prosa), dedotta all'apertura dall'estensione o dal contenuto;
- apertura e salvataggio con richiesta di conferma per le modifiche non salvate; ogni file passato da riga di comando si apre in una finestra separata;
- scorciatoie: `Ctrl+N` nuova finestra, `Ctrl+O` apri, `Ctrl+S` salva, `Ctrl+Shift+S` salva con nome, `Ctrl+Q` esci.

- **Esporta PDF…** dal menu (WebKitGTK impagina l'HTML, Poppler aggiunge numeri di pagina e metadati); anche da terminale, senza aprire finestre: `scripta-gtk --export Examples/Esempio.fountain out.pdf --paper a4`.

L'export HTML, Markdown e Fountain resta per ora esclusivo dell'app macOS.

La GUI richiede almeno GTK 4.6. Alcune API usate (`GtkFileChooserNative`, `GtkMessageDialog`) sono deprecate nelle versioni successive di GTK ma continuano a funzionare.

## Compilare su Windows (anteprima)

`ScriptaWin` è il punto di partenza del front end Windows: per ora è un programma da console che stampa le statistiche di un file con `ScriptaCore`. Da PowerShell, nella cartella del progetto:

```powershell
.\build-windows.ps1              # installa Visual Studio 2022 e Swift con WinGet, poi compila
.\build-windows.ps1 -SkipSetup   # solo compilazione (dipendenze già installate)
```

Lo script installa i componenti con WinGet (serve l'elevazione UAC per Visual Studio):

```powershell
winget install --id Microsoft.VisualStudio.2022.Community --exact --force --custom "--add Microsoft.VisualStudio.Component.Windows11SDK.22621 --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 --add Microsoft.VisualStudio.Component.VC.Tools.ARM64" --source winget
winget install --id Swift.Toolchain -e --source winget
```

e poi esegue `swift build -c release --product ScriptaWin`. L'eseguibile viene creato in `.build\release\ScriptaWin.exe`:

```powershell
.build\release\ScriptaWin.exe Examples\Esempio.fountain
```

Il workflow [`.github/workflows/windows-build.yml`](.github/workflows/windows-build.yml) esegue lo stesso script su un runner `windows-latest` a ogni push su `main` e a ogni pull request, prova l'eseguibile sull'esempio e lo pubblica (con `LICENSE`) come artefatto `ScriptaWin-windows-x64`. Nessun `.exe` è salvato nel repository.

## Pacchetti di distribuzione

Ogni release pubblicata nella pagina [Releases](https://github.com/Finch74/Scripta/releases) fornisce tre pacchetti pronti all'uso. I link qui sotto puntano sempre all'ultima release:

| Pacchetto | Contenuto | Piattaforma |
|-----------|-----------|-------------|
| [`Scripta-macOS-arm64.dmg`](https://github.com/Finch74/Scripta/releases/latest/download/Scripta-macOS-arm64.dmg) | `Scripta.app` + collegamento ad Applicazioni | macOS 15+, Apple Silicon |
| [`Scripta-Linux-x86_64.zip`](https://github.com/Finch74/Scripta/releases/latest/download/Scripta-Linux-x86_64.zip) | eseguibile `scripta` + cartella `Examples/` | Linux x86_64 (glibc) |
| [`Scripta-GUI-Linux-x86_64.tar.gz`](https://github.com/Finch74/Scripta/releases/latest/download/Scripta-GUI-Linux-x86_64.tar.gz) | GUI `scripta-gtk`, file `.desktop`, icona, `install.sh`, `Examples/` | Linux x86_64 (glibc) con GTK 4.6+ |

Se la release include anche `Scripta-GUI-x86_64.AppImage`, è la stessa GUI in un singolo file eseguibile (richiede comunque GTK 4 installato nel sistema).

Per una versione specifica sostituisci `latest/download` con `download/<tag>`. Per esempio:
`https://github.com/Finch74/Scripta/releases/download/v1.0.0/Scripta-macOS-arm64.dmg`

Download da terminale (Linux):

```bash
curl -LO https://github.com/Finch74/Scripta/releases/latest/download/Scripta-Linux-x86_64.zip
```

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

**Linux, GUI.** Anche qui il runtime Swift è incluso; serve invece GTK 4, già presente nei desktop GNOME recenti (altrimenti `sudo apt install libgtk-4-1` o `sudo dnf install gtk4`).

```bash
tar -xzf Scripta-GUI-Linux-x86_64.tar.gz
cd Scripta-GUI-Linux-x86_64
./scripta-gtk Examples/Esempio.fountain   # prova senza installare
./install.sh                              # installa in ~/.local con voce nel menu delle applicazioni
./install.sh --uninstall                  # rimuove
```

Per installarla per tutti gli utenti: `sudo PREFIX=/usr/local ./install.sh`.

**Debian/Ubuntu (.deb).** Installa `scripta-gtk` in `/usr/bin`, con voce nel menu delle applicazioni:

```bash
sudo apt install ./scripta-gtk_1.0-1_amd64.deb
```

**Fedora/RHEL (.rpm).** Stessa installazione per le distribuzioni basate su RPM:

```bash
sudo dnf install ./scripta-gtk-1.0-1.fc43.x86_64.rpm   # il suffisso dipende dalla distribuzione di build
```

In entrambi i casi il runtime Swift è incluso nell'eseguibile; dopo l'installazione il pacchetto controlla se Swift è presente e, se manca, prova a installarlo con [swiftly](https://www.swift.org/install/) per l'utente che ha lanciato `sudo` (serve solo per ricompilare Scripta, non per usarlo; un errore viene segnalato ma non blocca l'installazione).

L'AppImage si avvia direttamente: `chmod +x Scripta-GUI-x86_64.AppImage && ./Scripta-GUI-x86_64.AppImage`.

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

**Archivio della GUI per Linux** (ed eventuale AppImage):

```bash
./package-linux-gui.sh              # crea build/Scripta-GUI-Linux-<arch>.tar.gz
APPIMAGE=1 ./package-linux-gui.sh   # crea anche build/Scripta-GUI-<arch>.AppImage
```

- **Su Linux** usa la toolchain Swift locale e richiede GTK 4 con i file di sviluppo (`libgtk-4-dev`) e `pkg-config`.
- **Su macOS (o altri sistemi)** compila con Docker per `linux/amd64`. La prima volta lo script crea l'immagine locale `scripta-gtk-builder` (l'immagine `swift:6.0` più `libgtk-4-dev`); le volte successive la riusa.
- Il runtime Swift e Foundation sono collegati staticamente, GTK 4 dinamicamente: il sistema di destinazione deve avere GTK 4.6+. Neanche l'AppImage include GTK.
- Con `APPIMAGE=1` lo script scarica [appimagetool](https://github.com/AppImage/appimagetool) (serve la rete) e lo esegue senza FUSE, quindi anche dentro Docker. Su Linux puoi indicarne uno già installato con `APPIMAGETOOL=/percorso/appimagetool`.
- Valgono anche qui `SWIFT_IMAGE` e `USE_DOCKER=1`. La build usa la cartella `.build-linux-gui/`.

**Pacchetto Debian/Ubuntu**, da eseguire su Debian o Ubuntu come utente normale (non con `sudo`):

```bash
./package-deb.sh    # crea scripta-gtk_<versione>-1_<arch>.deb nella cartella del progetto
```

Se mancano, installa Swift con swiftly e le dipendenze di build con `apt-get` (`INSTALL_DEPS=0` per disattivarlo). Variabili: `VERSION`, `REVISION`, `MAINTAINER`.

**Pacchetto RPM (Fedora/RHEL)**, da eseguire come utente normale con `rpm-build` installato:

```bash
sudo dnf install rpm-build
./package-rpm.sh    # crea scripta-gtk-<versione>-1.<dist>.<arch>.rpm nella cartella del progetto
```

Lo script installa Swift con swiftly e le dipendenze di build (`gtk4-devel`, `webkitgtk6.0-devel`, `poppler-glib-devel`) con `dnf` se mancano, crea l'archivio dei sorgenti dai file tracciati da git e lancia `rpmbuild` con [`scripta-gtk.spec`](scripta-gtk.spec) in `build/rpm`, cancellata alla fine. Variabili: `VERSION`, `INSTALL_DEPS=0`, `NODEPS=1`. Funziona anche su Debian/Ubuntu (salta il controllo delle `BuildRequires`), ma l'RPM risultante richiede la glibc della macchina di build: per distribuirlo, compilalo sulla versione di Fedora/RHEL di destinazione (anche in un container o con `mock`).

### Pubblicare una release

I link di download funzionano solo se i file allegati alla release hanno esattamente i nomi `Scripta-macOS-arm64.dmg`, `Scripta-Linux-x86_64.zip` e `Scripta-GUI-Linux-x86_64.tar.gz`. Sono i nomi che producono gli script. Per esempio, con la [GitHub CLI](https://cli.github.com):

```bash
./package-dmg.sh
./package-linux.sh
APPIMAGE=1 ./package-linux-gui.sh
git tag v1.0.0 && git push origin v1.0.0
gh release create v1.0.0 --repo Finch74/Scripta --title "Scripta 1.0.0" --generate-notes \
    build/Scripta-macOS-arm64.dmg build/Scripta-Linux-x86_64.zip \
    build/Scripta-GUI-Linux-x86_64.tar.gz build/Scripta-GUI-x86_64.AppImage
```

## Usare ScriptaCore in un altro progetto

```swift
.package(url: "https://github.com/Finch74/Scripta.git", from: "1.0.0"),
// ...
.target(name: "MyTool", dependencies: [.product(name: "ScriptaCore", package: "Scripta")])
```

```swift
import ScriptaCore

let outline = DocumentOutline.items(in: text, mode: .screenplay)
let characters = CharacterAnalysis.statistics(text: text, mode: .screenplay)
let stats = DocumentStatistics(text: text, mode: .screenplay)   // parole, scene, outline, personaggi…
```

## License

Scripta è software open source distribuito con licenza MIT: il testo completo è nel file [LICENSE](LICENSE). © 2026 Finch74.
