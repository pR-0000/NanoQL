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

La version actuelle intègre la vidéo HDMI, la SDRAM embarquée, un vrai cœur CPU 68000 `fx68k` et une ROM de diagnostic minimale. Elle n’intègre pas encore la ROM système QL, le clavier, la microSD, l’IPC ni le système QL complet.

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
- Arbitrage SDRAM à deux clients :
  - lectures vidéo prioritaires afin de respecter les échéances de ligne
  - port système 22 bits avec lecture, écriture 16 bits et masques d'octets
  - pont de bus utilisé par le cœur `fx68k`
- Pont de bus 68000 minimal avec adresse 24 bits en octets, `AS`, `R/W`, `UDS`, `LDS` et `DTACK`
- Pont synchronisé avec le timing réel du 68000 : les écritures attendent l'activation de `UDS` ou `LDS` après `AS`
- Première carte mémoire QL :
  - ROM décodée entre `0x000000` et `0x00BFFF`
  - RAM et mémoire vidéo servies par la SDRAM, notamment l'écran à `0x020000`
  - registre ZX8301 `mc_stat` décodé à son adresse QL réelle `0x018063`
  - écritures en ROM acquittées mais ignorées
- Cœur `fx68k` cycle-exact issu de MiSTeryNano, cadencé provisoirement à 7,95 MHz par des clock-enables
- ROM de démarrage diagnostique avec vecteur de pile, vecteur de reset et programme 68000 à partir de `0x000100`
- Programme diagnostic exécuté par le CPU :
  - écriture d'un mot rouge dans la VRAM mode 4
  - relecture du mot depuis la SDRAM
  - comparaison par instruction `CMPI`
  - écriture d'un marqueur rouge dans le second écran
  - écriture octet de `0x88` dans `mc_stat` pour sélectionner l'écran `$28000` et le mode 8
  - branchement vers une signature de succès `0xA55A` ou d'échec `0xDEAD`
- Mode 8 et sélection de base écran désormais commandés uniquement par le programme 68000
- Bloc rouge 8x8 fixe à partir de la ligne 130 du mode 8, dessiné par huit écritures du programme
- Premier `ZX8302-lite` :
  - décodage de la zone `$18000-$1803F`
  - lecture des mots RTC et du registre état/interruptions à `$18020`
  - interruption VBlank de niveau 2 reliée aux entrées IPL de `fx68k`
  - acquittement de l'interruption par écriture à `$18021`
  - RTC provisoire dérivée de l'horloge système, encore approximative
- Le programme diagnostic doit lire `$18020` avant que sa signature de succès soit acceptée
- Carré d'état en haut à gauche : orange pendant l'initialisation et le démarrage CPU, vert après la signature de succès, rouge en cas d'erreur
- Flash du mode 8 conforme au principe du ZX8301 : le bit F commute un verrou de couleur, avec une phase changée toutes les 26 images
- Probe de timing QL natif, inspiré du timing PAL/NTSC du `zx8301.v` original, câblé en parallèle pour observation par LED

### Organisation des sources

- `src/nanoql_top.sv` : top-level Tang Nano 20K
- `src/nanoql_hdmi.sv` : wrapper HDMI autour du cœur HDMI de MiSTeryNano
- `src/ql_video_test.sv` : timing HDMI de la démonstration et raccordement du front-end vidéo
- `src/ql_hdmi_window.sv` : fenêtre visible HDMI et coordonnées de la zone QL 512x256
- `src/ql_zx8301_lite.sv` : module transitoire de registre/front-end inspiré du ZX8301
- `src/ql_zx8302_lite.sv` : RTC, registre état/IRQ et interruption VBlank de niveau 2
- `src/ql_video_scanout.sv` : séquenceur de lecture, tampon de ligne et décodeur de pixels QL
- `src/ql_native_timing_probe.sv` : probe de timing QL natif, encore non utilisé pour générer l’HDMI
- `src/ql_test_pattern.sv` : génération des motifs QL mode 4 et mode 8 écrits en SDRAM
- `src/ql_sdram_memory.sv` : initialisation, vérification, rafraîchissement et service des lectures vidéo SDRAM
- `src/ql_cpu_bus_bridge.sv` : conversion des cycles 68000 en transactions du bus système interne
- `src/ql_memory_map.sv` : décodage ROM/SDRAM et du registre ZX8301 à `0x018063`
- `src/ql_boot_rom.sv` : petite image ROM diagnostique exécutée par `fx68k`
- `src/ql_cpu_fx68k.sv` : wrapper d'horloge, de reset et de bus autour du cœur 68000
- `src/ql_cpu_boot_monitor.sv` : validation de l'écriture `mc_stat` et détection des signatures du programme
- `src/fx68k/` : cœur 68000 cycle-exact, microcode, documentation et licence GPLv3 importés de MiSTeryNano
- `src/sdram/sdram.v` : contrôleur SDRAM Tang Nano 20K importé de MiSTeryNano, sous GPLv3

### Indicateurs LED

- LED 0 : heartbeat du cœur FPGA
- LED 1 : PLL, SDRAM et démarrage du programme 68000 terminés avec succès
- LED 2 : erreur SDRAM, échec du programme 68000 ou underflow du tampon vidéo
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

Après programmation, la mire du second écran doit apparaître de façon stable en mode 8. La LED 4 doit être active. Le carré d'état passe de l'orange au vert lorsque le 68000 a vérifié la SDRAM, écrit `0x88` dans `mc_stat` à `0x018063` et produit la signature correcte. Un bloc rouge fixe apparaît à gauche de la ligne 130. La LED 3 reste inactive puisque le programme laisse le bit `blank` à zéro.

### Statistiques de synthèse

Ces statistiques sont mises à jour à chaque étape compilée. Elles proviennent de `impl/pnr/NanoQL.rpt.txt` et de `impl/gwsynthesis/NanoQL_syn.rpt.html`, avec Gowin V1.9.11.03 Education pour le GW2AR-LV18QN88C8/I7.

| Ressource | Utilisée | Disponible | Taux |
|---|---:|---:|---:|
| Logique | 7 331 | 20 736 | 36 % |
| LUT seules | 6 948 | - | - |
| ALU | 383 | - | - |
| Registres | 2 901 | 15 915 | 19 % |
| CLS | 4 422 | 10 368 | 43 % |
| BSRAM | 5 | 46 | 11 % |
| Ports E/S | 15 | 66 | 23 % |
| IOLOGIC | 6 | 121 | 5 % |
| Réseaux PRIMARY | 4 | 8 | 50 % |
| Réseaux locaux LW | 8 | 8 | 100 % |
| CLKDIV | 1 | 8 | 13 % |
| rPLL | 1 | 2 | 50 % |

Horloge principale : 31,800 MHz demandés, Fmax estimée à 74,822 MHz. Le remplissage de 100 % des réseaux `LW` est un point de vigilance pour les futurs blocs : NanoQL doit continuer à utiliser des clock-enables plutôt que de nouvelles horloges dérivées.

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
11. Écriture, vérification et affichage des deux écrans QL depuis la SDRAM avec double tampon.
12. Arbitrage SDRAM partagé entre le scanout prioritaire et un port système lecture/écriture.
13. Pont de bus 68000 avec `DTACK` et maître de test écriture/relecture.
14. Carte mémoire QL et ROM diagnostique vérifiée par des lectures de bus 68000.
15. Remplacement du maître de test par `fx68k`, exécution d'un programme et validation lecture/écriture SDRAM.
16. Décodage de `mc_stat` à `0x018063` et contrôle du mode vidéo par le programme 68000.
17. Ajout du ZX8302-lite, lecture de `$18020`, RTC provisoire et interruption VBlank niveau 2. Étape actuelle.
18. Rapprocher le séquenceur vidéo des créneaux de bus du vrai `zx8301.v`.
19. Charger une ROM système QL et compléter les registres matériels nécessaires au premier démarrage.
20. Ajouter clavier/IPC, stockage et OSD éventuel.

### Licence

NanoQL est distribué sous GNU GPL version 3. Voir `LICENSE`. Le dossier `src/fx68k/` conserve la documentation et la licence du cœur de Jorge Cwik. Le contrôleur SDRAM importé de MiSTeryNano conserve également son en-tête GPLv3.

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

The current build integrates HDMI video, on-board SDRAM, a real `fx68k` 68000 CPU core, and a minimal diagnostic ROM. It does not include the QL system ROM, keyboard, microSD, IPC, or complete QL system yet.

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
- Two-client SDRAM arbitration:
  - priority video reads to preserve line deadlines
  - 22-bit system port with reads, 16-bit writes, and byte masks
  - bus bridge used by the `fx68k` core
- Minimal 68000 bus bridge with 24-bit byte addresses, `AS`, `R/W`, `UDS`, `LDS`, and `DTACK`
- Bridge synchronized with real 68000 timing: writes wait for `UDS` or `LDS` to become active after `AS`
- Initial QL memory map:
  - ROM decoded from `0x000000` through `0x00BFFF`
  - RAM and video memory served by SDRAM, including the screen at `0x020000`
  - ZX8301 `mc_stat` register decoded at its real QL address `0x018063`
  - ROM writes acknowledged and ignored
- Cycle-exact `fx68k` core imported from MiSTeryNano, provisionally clocked at 7.95 MHz through clock enables
- Diagnostic boot ROM with initial stack and reset vectors and a 68000 program starting at `0x000100`
- Diagnostic program executed by the CPU:
  - writes a red word into mode 4 VRAM
  - reads the word back from SDRAM
  - compares it using a `CMPI` instruction
  - writes a red marker into the second screen
  - byte-writes `0x88` to `mc_stat`, selecting the `$28000` screen and mode 8
  - branches to a `0xA55A` success signature or `0xDEAD` failure signature
- Mode 8 and screen-base selection now controlled exclusively by the 68000 program
- Fixed red 8x8 block starting on mode 8 line 130, drawn by eight program writes
- Initial `ZX8302-lite` implementation:
  - decodes the `$18000-$1803F` region
  - exposes RTC words and the status/interrupt register at `$18020`
  - connects a level-2 VBlank interrupt to the `fx68k` IPL inputs
  - acknowledges the interrupt through a write to `$18021`
  - uses a provisional, still approximate RTC derived from the system clock
- The diagnostic program must read `$18020` before its success signature is accepted
- Top-left status square: orange during initialization and CPU startup, green after the success signature, red on error
- Mode 8 flash matching the ZX8301 principle: the F bit toggles a color latch, with the phase changing every 26 frames
- Native QL timing probe, inspired by the original `zx8301.v` PAL/NTSC timing, running in parallel and observable through an LED

### Source Layout

- `src/nanoql_top.sv`: Tang Nano 20K top-level
- `src/nanoql_hdmi.sv`: HDMI wrapper around the MiSTeryNano HDMI core
- `src/ql_video_test.sv`: demonstration HDMI timing and video front-end connection
- `src/ql_hdmi_window.sv`: HDMI visible window and 512x256 QL-area coordinates
- `src/ql_zx8301_lite.sv`: transitional ZX8301-inspired register/front-end module
- `src/ql_zx8302_lite.sv`: RTC, status/IRQ register, and level-2 VBlank interrupt
- `src/ql_video_scanout.sv`: line-fetch sequencer, line buffer, and QL pixel decoder
- `src/ql_native_timing_probe.sv`: native QL timing probe, not yet used to generate HDMI
- `src/ql_test_pattern.sv`: QL mode 4 and mode 8 pattern generator used to initialize SDRAM
- `src/ql_sdram_memory.sv`: SDRAM initialization, verification, refresh, and video-read service
- `src/ql_cpu_bus_bridge.sv`: converts 68000 cycles into internal system-bus transactions
- `src/ql_memory_map.sv`: decodes ROM/SDRAM and the ZX8301 register at `0x018063`
- `src/ql_boot_rom.sv`: small diagnostic ROM image executed by `fx68k`
- `src/ql_cpu_fx68k.sv`: clock, reset, and bus wrapper around the 68000 core
- `src/ql_cpu_boot_monitor.sv`: validates the `mc_stat` write and detects program signatures
- `src/fx68k/`: cycle-exact 68000 core, microcode, documentation, and GPLv3 license imported from MiSTeryNano
- `src/sdram/sdram.v`: Tang Nano 20K SDRAM controller imported from MiSTeryNano under GPLv3

### LED Indicators

- LED 0: FPGA core heartbeat
- LED 1: PLL, SDRAM, and 68000 diagnostic program completed successfully
- LED 2: SDRAM error, 68000 program failure, or video line-buffer underflow
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

After programming, the second screen's test image should remain stable in mode 8. LED 4 must be active. The status square changes from orange to green after the 68000 has checked SDRAM, written `0x88` to `mc_stat` at `0x018063`, and produced the correct signature. A fixed red block appears at the left of line 130. LED 3 remains inactive because the program leaves `blank` cleared.

### Synthesis Statistics

These statistics are updated after every compiled milestone. They come from `impl/pnr/NanoQL.rpt.txt` and `impl/gwsynthesis/NanoQL_syn.rpt.html`, using Gowin V1.9.11.03 Education for the GW2AR-LV18QN88C8/I7.

| Resource | Used | Available | Utilization |
|---|---:|---:|---:|
| Logic | 7,331 | 20,736 | 36% |
| LUT only | 6,948 | - | - |
| ALU | 383 | - | - |
| Registers | 2,901 | 15,915 | 19% |
| CLS | 4,422 | 10,368 | 43% |
| BSRAM | 5 | 46 | 11% |
| I/O ports | 15 | 66 | 23% |
| IOLOGIC | 6 | 121 | 5% |
| PRIMARY networks | 4 | 8 | 50% |
| Local LW networks | 8 | 8 | 100% |
| CLKDIV | 1 | 8 | 13% |
| rPLL | 1 | 2 | 50% |

Main clock: 31.800 MHz required, estimated Fmax 74.822 MHz. The 100% use of local `LW` networks is a design watch point for future blocks: NanoQL should keep using clock enables instead of introducing additional derived clocks.

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
11. Write, verify, and display both QL screens from SDRAM with double buffering.
12. Share SDRAM between priority scanout reads and a system read/write port.
13. Add a 68000 bus bridge with `DTACK` and a write/readback test master.
14. Add a QL memory map and diagnostic ROM checked through 68000 bus reads.
15. Replace the test master with `fx68k`, execute a program, and validate SDRAM reads and writes.
16. Decode `mc_stat` at `0x018063` and control video mode from 68000 software.
17. Add ZX8302-lite, read `$18020`, provide a provisional RTC, and generate a level-2 VBlank interrupt. Current step.
18. Move the video sequencer closer to the real `zx8301.v` bus slots.
19. Load a QL system ROM and complete the hardware registers required for the first boot.
20. Add keyboard/IPC, storage, and optional OSD.

### License

NanoQL is distributed under GNU GPL version 3. See `LICENSE`. The `src/fx68k/` directory retains the documentation and license for Jorge Cwik's core. The SDRAM controller imported from MiSTeryNano also retains its GPLv3 header.

### Upstream References

- MiSTeryNano: Tang Nano 20K HDMI, PLL, and board constraints reference
- mist-devel/ql: Sinclair QL / ZX8301 video reference
