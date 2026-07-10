# NanoQL

## Français

NanoQL est un port FPGA progressif du Sinclair QL pour la carte Sipeed Tang Nano 20K.

**Provenance : ce projet est généré par Chat GPT 5.6 Sol.**

### Cible matérielle

- Sipeed Tang Nano 20K
- FPGA Gowin GW2AR-LV18QN88C8/I7
- Horloge embarquée 27 MHz
- Sortie HDMI embarquée

### État actuel

La version actuelle est une mise en route vidéo HDMI autonome utilisant la SDRAM embarquée comme mémoire d'écran. Elle n’intègre pas encore le CPU 68000, la ROM QL, le clavier, la microSD, l’IPC ni le système QL complet.

Fonctionnalités déjà présentes :

- Projet Gowin pour Tang Nano 20K
- PLL HDMI 160 MHz et horloge pixel 32 MHz, basées sur l’implémentation Tang Nano 20K de MiSTeryNano
- Sortie HDMI en mode proche PAL 720x576@50 Hz
- Zone active centrée de style Sinclair QL en 512x256
- Calcul de la fenêtre HDMI/QL isolé dans `ql_hdmi_window`
- `ql_zx8301_lite`, un front-end transitoire inspiré du ZX8301 :
  - registre write-only `mc_stat`
  - bit 7 : sélection de base écran
  - bit 3 : sélection du mode vidéo, mode 4 ou mode 8
  - bit 1 : blank vidéo
- Scanout vidéo QL avec une interface mémoire proche du ZX8301 :
  - adresse mot 19 bits
  - requête de lecture conservée jusqu'à `ready`
  - réponse 16 bits signalée séparément par `data_valid`
  - requêtes et réponses ordonnées, avec latence mémoire variable possible
- Préchargement séquentiel de chaque ligne QL :
  - 64 lectures de mots 16 bits par ligne, au lieu d'une lecture par pixel HDMI
  - double tampon de ligne 2x64x16 bits implémenté dans une seule BSRAM Gowin
  - préchargement d'une ligne pendant que la ligne précédente est affichée
- Détection de ligne incomplète : zone QL magenta et LED 2 allumée en cas d'underflow
- Contrôleur de la SDRAM embarquée adapté de MiSTeryNano :
  - bus physique interne 32 bits et horloge proche de 32 MHz
  - initialisation et rafraîchissements périodiques
  - génération puis écriture des deux écrans QL de 16 384 mots
  - vérification par relecture des 32 768 mots avant activation du service vidéo
  - lectures vidéo servies directement depuis la SDRAM
- Carré d'état SDRAM en haut à gauche : orange pendant l'initialisation, vert en cas de succès, rouge en cas d'erreur
- Bascule automatique HDMI entre mode 4 et mode 8 par écriture du registre `mc_stat`
- Test périodique bref du bit `blank`, visible sur l'écran et sur la LED 3
- Flash du mode 8 conforme au principe du ZX8301 : le bit F commute un verrou de couleur, avec une phase changée toutes les 26 images
- Probe de timing QL natif, inspiré du timing PAL/NTSC du `zx8301.v` original, câblé en parallèle pour observation par LED

### Organisation des sources

- `src/nanoql_top.sv` : top-level Tang Nano 20K
- `src/nanoql_hdmi.sv` : wrapper HDMI autour du cœur HDMI de MiSTeryNano
- `src/ql_video_test.sv` : timing de test HDMI et écritures automatiques dans `mc_stat`
- `src/ql_hdmi_window.sv` : fenêtre visible HDMI et coordonnées de la zone QL 512x256
- `src/ql_zx8301_lite.sv` : module transitoire de registre/front-end inspiré du ZX8301
- `src/ql_video_scanout.sv` : séquenceur de lecture, tampon de ligne et décodeur de pixels QL
- `src/ql_native_timing_probe.sv` : probe de timing QL natif, encore non utilisé pour générer l’HDMI
- `src/ql_test_pattern.sv` : génération des motifs QL mode 4 et mode 8 écrits en SDRAM
- `src/ql_sdram_memory.sv` : initialisation, vérification, rafraîchissement et service des lectures vidéo SDRAM
- `src/sdram/sdram.v` : contrôleur SDRAM Tang Nano 20K importé de MiSTeryNano, sous GPLv3

### Indicateurs LED

- LED 0 : heartbeat du cœur FPGA
- LED 1 : PLL verrouillée et initialisation/vérification SDRAM terminée sans erreur
- LED 2 : erreur SDRAM ou underflow du tampon vidéo
- LED 3 : blank vidéo actif
- LED 4 : mode QL 8 actif
- LED 5 : probe de trames du timing QL natif

### Compilation

Ouvrir un terminal dans le dossier racine du projet, puis lancer :

```powershell
gw_sh build.tcl
```

Si `gw_sh` n'est pas présent dans le `PATH`, utiliser l'exécutable `gw_sh` du dossier `IDE/bin` de l'installation Gowin, ou ouvrir le projet `NanoQL.gprj` dans Gowin IDE et lancer **Run All**.

Le bitstream généré se trouve ici :

```text
impl\pnr\NanoQL.fs
```

Pour les essais rapides, programmer la carte avec Gowin Programmer en mode SRAM.

### Feuille de route

1. Mise en route HDMI avec image de test.
2. Scanout VRAM simulée QL mode 4.
3. Scanout VRAM simulée QL mode 8.
4. Front-end compatible ZX8301 minimal avec registre `mc_stat`.
5. Probe de timing QL natif.
6. Remplacement des grosses VRAMs de test par une mémoire procédurale légère.
7. Séparation de la fenêtre HDMI, test du blank et adaptation du verrou de flash mode 8 du vrai `zx8301.v`.
8. Préchargement séquentiel des 64 mots de chaque ligne dans un tampon BSRAM.
9. Protocole mémoire avec `ready`/`data_valid`, back-pressure simulé et détection d'underflow.
10. Initialisation et autotest matériel de la SDRAM embarquée.
11. Écriture, vérification et affichage des deux écrans QL depuis la SDRAM avec double tampon. Étape actuelle.
12. Ajouter l'arbitrage SDRAM pour une mémoire partagée CPU/vidéo.
13. Rapprocher le séquenceur vidéo des créneaux de bus du vrai `zx8301.v`.
14. Ajouter 68000, ROM, carte mémoire et séquence de reset.
15. Ajouter clavier/IPC, stockage et OSD éventuel quand vidéo et CPU seront stables.

### Références amont

- MiSTeryNano : référence HDMI, PLL et contraintes Tang Nano 20K
- mist-devel/ql : référence vidéo Sinclair QL / ZX8301

---

## English

NanoQL is an incremental Sinclair QL FPGA port for the Sipeed Tang Nano 20K board.

**Provenance: this project is generated by Chat GPT 5.6 Sol.**

### Hardware Target

- Sipeed Tang Nano 20K
- Gowin GW2AR-LV18QN88C8/I7 FPGA
- On-board 27 MHz clock
- On-board HDMI output

### Current Status

The current build is a standalone HDMI video bring-up using the on-board SDRAM as screen memory. It does not include the 68000 CPU, QL ROM, keyboard, microSD, IPC, or complete QL system yet.

Implemented so far:

- Tang Nano 20K Gowin project
- 160 MHz HDMI PLL and 32 MHz pixel clock path, based on the MiSTeryNano Tang Nano 20K implementation
- HDMI output in a PAL-like 720x576@50 Hz mode
- Centered Sinclair QL-style 512x256 active display area
- HDMI/QL window calculation isolated in `ql_hdmi_window`
- `ql_zx8301_lite`, a transitional ZX8301-inspired front-end:
  - write-only `mc_stat` register
  - bit 7: screen base select
  - bit 3: video mode select, mode 4 or mode 8
  - bit 1: video blank
- QL video scanout with a ZX8301-like memory interface:
  - 19-bit word address
  - read request held until `ready`
  - separate 16-bit response indicated by `data_valid`
  - ordered requests and responses, allowing variable memory latency
- Sequential QL line prefetch:
  - 64 reads of 16-bit words per line instead of one read per HDMI pixel
  - 2x64x16-bit double line buffer implemented in a single Gowin BSRAM
  - one line prefetched while the previous line is displayed
- Incomplete-line detection: magenta QL area and LED 2 lit on underflow
- On-board SDRAM controller adapted from MiSTeryNano:
  - internal 32-bit physical bus and near-32 MHz clock
  - initialization and periodic refresh operations
  - generation and write of both 16,384-word QL screens
  - readback verification of all 32,768 words before enabling video service
  - video reads served directly from SDRAM
- On-screen SDRAM status square at the top left: orange while initializing, green on success, red on error
- Automatic HDMI test switching between mode 4 and mode 8 by writing the `mc_stat` register
- Short periodic test of the `blank` bit, visible on screen and on LED 3
- Mode 8 flash matching the ZX8301 principle: the F bit toggles a color latch, with the phase changing every 26 frames
- Native QL timing probe, inspired by the original `zx8301.v` PAL/NTSC timing, running in parallel and observable through an LED

### Source Layout

- `src/nanoql_top.sv`: Tang Nano 20K top-level
- `src/nanoql_hdmi.sv`: HDMI wrapper around the MiSTeryNano HDMI core
- `src/ql_video_test.sv`: HDMI test timing and automatic `mc_stat` writes
- `src/ql_hdmi_window.sv`: HDMI visible window and 512x256 QL-area coordinates
- `src/ql_zx8301_lite.sv`: transitional ZX8301-inspired register/front-end module
- `src/ql_video_scanout.sv`: line-fetch sequencer, line buffer, and QL pixel decoder
- `src/ql_native_timing_probe.sv`: native QL timing probe, not yet used to generate HDMI
- `src/ql_test_pattern.sv`: QL mode 4 and mode 8 pattern generator used to initialize SDRAM
- `src/ql_sdram_memory.sv`: SDRAM initialization, verification, refresh, and video-read service
- `src/sdram/sdram.v`: Tang Nano 20K SDRAM controller imported from MiSTeryNano under GPLv3

### LED Indicators

- LED 0: FPGA core heartbeat
- LED 1: PLL locked and SDRAM initialization/verification completed without error
- LED 2: SDRAM error or video line-buffer underflow
- LED 3: video blank active
- LED 4: QL mode 8 active
- LED 5: native QL timing frame probe

### Build

Open a terminal in the project root directory, then run:

```powershell
gw_sh build.tcl
```

If `gw_sh` is not available in `PATH`, invoke the `gw_sh` executable from the Gowin installation's `IDE/bin` directory, or open `NanoQL.gprj` in Gowin IDE and select **Run All**.

The generated bitstream is:

```text
impl\pnr\NanoQL.fs
```

Program the board with Gowin Programmer in SRAM mode for quick tests.

### Roadmap

1. HDMI bring-up with a test image.
2. Simulated QL mode 4 VRAM scanout.
3. Simulated QL mode 8 VRAM scanout.
4. Minimal ZX8301-compatible front-end with the `mc_stat` register.
5. Native QL timing probe.
6. Replace large test VRAMs with lightweight procedural memory.
7. Separate the HDMI window, test blanking, and adapt the real `zx8301.v` mode 8 flash latch.
8. Sequentially prefetch each line's 64 words into a BSRAM line buffer.
9. Add a `ready`/`data_valid` memory protocol, simulated back-pressure, and underflow detection.
10. Initialize and run a hardware self-test on the on-board SDRAM.
11. Write, verify, and display both QL screens from SDRAM with double buffering. Current step.
12. Add SDRAM arbitration for shared CPU/video memory.
13. Move the video sequencer closer to the real `zx8301.v` bus slots.
14. Add 68000, ROM, memory map, and reset sequencing.
15. Add keyboard/IPC, storage, and optional OSD once video and CPU boot are stable.

### Upstream References

- MiSTeryNano: Tang Nano 20K HDMI, PLL, and board constraints reference
- mist-devel/ql: Sinclair QL / ZX8301 video reference
