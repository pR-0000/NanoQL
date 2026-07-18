# NanoQL

Portage progressif du Sinclair QL sur Sipeed Tang Nano 20K.

**Ce projet est généré par Chat GPT 5.6 Sol.**

## Français

### État du projet

NanoQL démarre une ROM Sinclair QL depuis la carte microSD et fournit :

- un cœur 68000 `fx68k` ;
- les vitesses CPU `QL` et `16 MHz`, commutables à chaud depuis l'OSD ;
- 128, 640 ou 896 Kio de RAM QL sélectionnables dans la SDRAM de la Tang Nano 20K ;
- les modes vidéo QL 4 et 8 sur HDMI 720p50 ;
- le son mono du QL sur les deux canaux HDMI en PCM 48 kHz ;
- une image 512 x 256 centrée avec quatre largeurs sélectionnables ;
- le contrôleur IPC 8049 et la matrice clavier QL ;
- un clavier USB raccordé par hub au BL616 intégré ;
- le chargement automatique de `QL.rom` depuis la microSD ;
- un lecteur `MDV1_` validé pour les images Microdrive QLAY ;
- un menu OSD accessible avec `F12` pour choisir la ROM, la RAM, la vitesse CPU, le cadrage vidéo et réinitialiser le QL.

Le chemin Microdrive reproduit le signal physique QL à 100 kHz sous la forme du flux QLAY sérialisé à 200 kbit/s utilisé par le ZX8302. Il est validé en lecture avec `DIR`, `LOAD` et `LRUN` ; les écritures effectuées par QDOS ne sont pas encore conservées.

Les objectifs et leur ordre d'intégration sont détaillés dans [la feuille de route](docs/ROADMAP.md).

Le menu vidéo propose `Monitor`, `TV`, `Wide +6%` et `Wide +30%`. Tous affichent les 512 × 256 échantillons de l'image QL sans supprimer de ligne ni de colonne. `Monitor` utilise des blocs réguliers de 2 × 2 pixels HDMI, tandis que les modes larges corrigent progressivement la géométrie particulière des pixels du QL. Leur agrandissement fractionnaire reste un rendu au plus proche voisin, sans filtre de lissage dans le FPGA.

### Matériel nécessaire

- Sipeed Tang Nano 20K, révision 3921 ou 3923 ;
- carte microSD formatée en FAT32 ou exFAT ;
- écran et câble HDMI ;
- câble USB-C pour l'alimentation et la programmation.

Un clavier USB et un hub USB alimenté compatible USB OTG sont optionnels. Ils sont uniquement nécessaires pour utiliser directement le clavier USB avec QDOS ; NanoQL peut démarrer et afficher le QL sans eux.

La révision est imprimée sur la carte, par exemple `3923`.

### Logiciels

Installez :

1. [Git](https://git-scm.com/downloads)
2. [Python 3](https://www.python.org/downloads/) avec Tkinter
3. [Gowin EDA Education](https://www.gowinsemi.com/en/support/download_eda/) pour compiler le HDL

Pour programmer le FPGA, choisissez une seule solution : **Gowin Programmer**, installé avec Gowin EDA, ou [openFPGALoader](https://github.com/trabucayre/openFPGALoader). Gowin Programmer n'est pas obligatoire. Si vous utilisez un bitstream NanoQL déjà compilé, openFPGALoader permet de se passer entièrement de Gowin EDA pour la programmation.

Sous Windows, cochez **Add Python to PATH** pendant l'installation. Sous Linux, Tkinter peut nécessiter le paquet `python3-tk`. VS Code n'est pas nécessaire.

### Installation pas à pas

#### 1. Récupérer NanoQL

```sh
git clone https://github.com/pR-0000/NanoQL.git
cd NanoQL
python tools/nanoql_setup.py
```

L'assistant utilise uniquement la bibliothèque standard de Python. Il fonctionne sous Windows, macOS et Linux. Le flash initial du BL616 avec FlashCube est actuellement disponible sous Windows.

#### 2. Préparer le BL616 intégré

Cette opération n'est nécessaire qu'une fois.

1. Ouvrez l'onglet **1. BL616 Companion**.
2. Sélectionnez la révision `3921` ou `3923`.
3. Gardez le profil **NanoQL**.
4. Cliquez sur **Préparer et ouvrir FlashCube**.
5. Débranchez la carte.
6. Maintenez le bouton **UPDATE**, branchez le câble USB, puis relâchez le bouton.
7. Dans FlashCube, sélectionnez le port série de la carte et le fichier `.ini` indiqué par l'assistant.
8. Lancez la programmation, puis débranchez la carte.

Le profil NanoQL fournit le clavier USB, la microSD et NanoQL Link. Le profil Original restaure temporairement FPGA Partner lorsqu'une programmation persistante avec Gowin Programmer est nécessaire.

#### 3. Préparer la ROM et la microSD

Vous devez fournir légalement :

- une ROM QL standard de 48 ou 64 Kio ;
- le firmware IPC Sinclair standard `ipc8049.hex` au format Intel HEX, disponible dans le [core QL MiSTer](https://github.com/MiSTer-devel/QL_MiSTer/tree/master/rtl). NanoQL utilise ce firmware d’origine afin de reproduire le comportement du contrôleur 8049 du QL.

Dans l'onglet **2. ROM et microSD** :

1. Sélectionnez votre ROM QL.
2. Sélectionnez la racine de la carte microSD.
3. Au premier lancement, sélectionnez `ipc8049.hex`.
4. Cliquez sur **Préparer la microSD** puis sur **Convertir le firmware IPC**.

L'assistant valide la ROM et crée à la racine de la carte :

```text
QL.rom
nanoql.ini
```

#### 4. Compiler et programmer le FPGA

Dans l'onglet **3. FPGA** :

1. Vérifiez le chemin de `gw_sh`.
2. Cliquez sur **Compiler**.
3. Programmez le bitstream avec Gowin Programmer ou, si vous l'avez installé, avec `openFPGALoader`.

Le bitstream produit est :

```text
impl/pnr/NanoQL_sd_rom.fs
```

Le bouton **Tout préparer et compiler** peut enchaîner la conversion IPC, la préparation de la microSD et la compilation.

Avec Gowin Programmer, ouvrez `impl/pnr/NanoQL_sd_rom.fs`. Pour un essai temporaire, choisissez **SRAM Mode**. Pour conserver NanoQL après extinction, choisissez **External Flash Mode**, l'opération d'effacement/programmation et **Generic Flash**. `openFPGALoader` n'est pas requis pour cette méthode.

Avec openFPGALoader, aucune installation de Gowin Programmer n'est nécessaire. Le profil BL616 `ORIGINAL` doit néanmoins être actif pour exposer l'interface JTAG standard lors d'une programmation persistante.

Compilation manuelle :

```sh
gw_sh build_sd_rom.tcl
openFPGALoader -b tangnano20k -f impl/pnr/NanoQL_sd_rom.fs
```

Dans Gowin EDA, l'option **Use JTAG as regular IO** doit rester décochée.

#### 5. Démarrer et tester

1. Éteignez et débranchez la carte.
2. Insérez la microSD préparée.
3. Reliez HDMI à l'écran.
4. Facultatif : pour utiliser un clavier USB, branchez-le sur un hub USB alimenté compatible OTG.
5. Alimentez la Tang Nano 20K par USB-C ; si vous utilisez un clavier, reliez plutôt le hub à la carte et alimentez l'ensemble par le hub.
6. Vérifiez que l'écran de démarrage du QL apparaît.
7. Facultatif avec un clavier : appuyez sur `F1` ou `F2`, puis testez `PRINT 2+2` et ouvrez le menu NanoQL avec `F12`.

Pour vérifier objectivement la vitesse CPU depuis un PC, passez en mode NanoQL Link avec S1 puis mesurez les phases du processeur :

```text
python tools/nanoql_link.py --port COMx cpu-status
```

La commande affiche le mode sélectionné et sa fréquence effective. Pour charger des programmes QL de manière fiable, utilisez l'image QL-SD décrite plus bas.

Pour présenter un dossier ordinaire comme cartouche `mdv1_`, créez un sous-dossier dans `NanoQL/Microdrives` sur la microSD et placez-y les fichiers QL. Ouvrez ensuite l'overlay avec `F12`, choisissez **Build MDV1 from:** puis ce sous-dossier. Le BL616 réalise la conversion, monte la cartouche pour la session en cours et redémarre le QL, sans PC ni mode développeur. Utilisez ensuite `DIR mdv1_`, `LOAD mdv1_nom` ou `LRUN mdv1_programme_bas`. L'image générée n'est volontairement pas remontée par `nanoql.ini` au démarrage. La conversion accepte 126 fichiers au maximum, huit niveaux de sous-dossiers et des noms QDOS aplatis en ASCII de 36 caractères au maximum. L'image QLAY produite mesure toujours 174 930 octets, mais sa capacité utile dépend de l'arrondi de chaque fichier par secteurs de 512 octets ; un fichier unique peut contenir au plus 128 960 octets.

### Dépannage court

- **Pas d'image :** vérifiez le câble HDMI, l'entrée de l'écran et la programmation Flash du FPGA.
- **Damier ou écran uni :** la ROM n'est pas montée ; vérifiez `QL.rom`, `nanoql.ini`, la microSD et le firmware BL616 correspondant à la révision.
- **F1/F2 ne répond pas :** utilisez un hub alimenté compatible OTG et démarrez sans connexion USB de données vers l'ordinateur.
- **La programmation FPGA échoue :** utilisez un câble de données et restaurez temporairement le profil BL616 Original.

### Utilisation FPGA

Dernière compilation du build principal :

| Ressource    |            Utilisation |
| ------------ | ---------------------: |
| Logic        | 12 698 / 20 736 (62 %) |
| LUT          |                 11 897 |
| ALU          |                    735 |
| Registres    |                  6 110 |
| CLS          |  8 174 / 10 368 (79 %) |
| BSRAM        |         15 / 46 (33 %) |
| E/S          |         27 / 66 (41 %) |
| rPLL         |           2 / 2 (100 %) |
| Fmax système | 62,965 MHz pour 31,8 MHz |
| Fmax HDMI    | 74,494 MHz pour 74,25 MHz |
| TNS setup    | 0 ns (système et HDMI) |

Ces valeurs sont mises à jour après les changements significatifs du build principal.

### Architecture

```text
Clavier USB -> BL616 FPGA Companion -> matrice QL -> IPC 8049
microSD -> BL616 FPGA Companion -> ROM, QL-SD et image Microdrive
OSD FPGA Companion + vidéo QL -> HDMI
ROM + SDRAM + ZX8301/ZX8302 -> fx68k
```

La sortie HDMI utilise le mode standard 1280 × 720p50. Le domaine QL/SDRAM reste à 31,8 MHz et un tampon de ligne à double horloge alimente le domaine HDMI à 74,25 MHz. Le cadrage `Monitor` agrandit chaque échantillon du framebuffer QL en un bloc régulier de 2 × 2 pixels carrés. Les cadrages plus larges conservent les 512 × 256 échantillons complets ; `Wide +30%` garde en plus une marge HDMI de 40 pixels à gauche et à droite.

Le mode CPU `QL` utilise des phases 68008 à 7,5 MHz et le modèle de contention RAM `ql_timing` du core QL MiSTer. Le mode `16 MHz` utilise 15,9 MHz avec l'horloge système actuelle et désactive cette contention, comme le mode accéléré de QL MiSTer. La vitesse peut être changée à chaud et reste conservée dans `nanoql.ini`.

Le menu RAM applique les mêmes masques d'adresses et plages d'extension que QL MiSTer : 128 Kio avec repliement sur 256 Kio, 640 Kio ou 896 Kio avec décodage sur 1 Mio. Le choix est conservé dans `nanoql.ini` et appliqué lors d'un reset QL.

Le premier chemin QL-SD reprend QLROMEXT et l'émulateur de carte SD de QL_MiSTer. Le sélecteur `QL-SD image` monte un fichier `QXL.WIN` de la microSD comme carte SDHC virtuelle, avec transport sectoriel en lecture et en écriture. La procédure de validation avec le pilote QL-SD 1.08 ou ultérieur est décrite dans [`docs/QL_SD.md`](docs/QL_SD.md).

Le lecteur Microdrive diffuse une image QLAY de 174 930 octets depuis la microSD avec deux tampons sectoriels, sans la charger entièrement en BSRAM. Son flux sérialisé à 200 kbit/s est dérivé directement de l'horloge système et reste indépendant de la vitesse CPU ; le fonctionnement a été validé physiquement dans les modes QL et 16 MHz. Il conserve les mots de 80 µs et les gaps de 2,8 ms du modèle QL. Les préambules, les gaps et les fenêtres `RX ready` suivent le chemin Microdrive de QL_MiSTer. Le BL616 peut convertir de manière autonome un dossier de `NanoQL/Microdrives` en `MDV1.mdv` depuis l'overlay, monter l'image pour la session en cours et redémarrer le QL. La commande développeur `mdv-sync` reste disponible pour synchroniser directement un dossier du PC. La procédure est décrite dans [`docs/NANOQL_LINK.md`](docs/NANOQL_LINK.md).

La SDRAM suit la séquence complète de démarrage du GW2AR-18 : délai de stabilisation de 200 µs, précharge globale, deux auto-refresh, programmation du registre de mode, auto-précharge des accès et refresh périodique.

Au démarrage, `QL.rom` est chargée et vérifiée dans les 64 Kio supérieurs de la SDRAM. Un routeur mémorise le propriétaire de chaque transaction entre NanoQL Link, le chargeur de ROM, les lectures ROM du 68000 et la RAM QL.

Le CPU, le ZX8302 et l'IPC 8049 restent sur un reset commun pendant le chargement. Ils démarrent ensemble uniquement lorsque la ROM est prête, comme lors d'un démarrage à froid du QL.

La ROM du firmware 8049 utilise une sortie synchrone et est synthétisée dans une BSRAM de la Tang Nano 20K. L'IPC reçoit un enable fractionnaire de 11 MHz, comme dans le core QL MiSTer.

Le ZX8302 applique chaque écriture de registre sur la phase négative du 68008 et ne renvoie `DTACK` qu'après sa validation. Ses registres, son lien série IPC et ses interruptions suivent l'organisation du module QL MiSTer.

Le HDL et les contraintes sont dans `src/`, l'intégration Companion dans `src/companion/` et les outils utilisateur dans `tools/`.

L'interface de développement USB permettant de charger et d'exécuter directement un binaire 68000 est décrite dans [`docs/NANOQL_LINK.md`](docs/NANOQL_LINK.md). Le firmware BL616 unifié démarre avec le clavier USB normal et passe à NanoQL Link lorsqu'on appuie sur S1 après le démarrage du FPGA. Cette interface peut reconfigurer temporairement la SRAM du FPGA avec le `.bin` produit par Gowin, puis revenir automatiquement en mode Companion. La commande `fpga-flash-native` automatise la programmation persistante avec Gowin Programmer ou openFPGALoader après restauration temporaire du firmware BL616 officiel.

### Références

- [QL MiSTer](https://github.com/MiSTer-devel/QL_MiSTer)
- [QL MiST](https://github.com/mist-devel/ql)
- [MiSTeryNano](https://github.com/MiSTle-Dev/MiSTeryNano)
- [NanoMIG](https://github.com/MiSTle-Dev/NanoMIG)
- [Documentation Tang Nano 20K](https://wiki.sipeed.com/hardware/en/tang/tang-nano-20k/nano-20k.html)

## English

### Project status

NanoQL boots a Sinclair QL ROM from microSD and currently provides:

- an `fx68k` 68000 core;
- live-switchable `QL` and `16 MHz` CPU speeds in the OSD;
- 128, 640, or 896 KiB of selectable QL RAM in the Tang Nano 20K SDRAM;
- QL mode 4 and mode 8 video over 720p50 HDMI;
- QL mono sound on both HDMI channels as 48 kHz PCM;
- a centered 512 x 256 image with four selectable display widths;
- the 8049 IPC controller and QL keyboard matrix;
- a USB keyboard through the integrated BL616 and a powered USB hub;
- automatic loading of `QL.rom` from microSD;
- a validated `MDV1_` reader for QLAY Microdrive images;
- an `F12` on-screen display for ROM, RAM, CPU speed, video framing, and QL reset.

The Microdrive path reproduces the QL's physical 100 kHz signal through the 200 kbit/s serialized QLAY stream consumed by the ZX8302. `DIR`, `LOAD`, and `LRUN` are validated; QDOS writes are not persisted yet.

The planned features and their implementation order are documented in the [roadmap](docs/ROADMAP.md).

The video menu provides `Monitor`, `TV`, `Wide +6%`, and `Wide +30%`. Every mode preserves all 512 × 256 QL image samples. `Monitor` uses uniform 2 × 2 HDMI pixel blocks, while the wider modes progressively compensate for the QL's non-square pixel geometry. Fractional enlargement remains nearest-neighbour output, with no smoothing filter in the FPGA.

### Required hardware and software

Required hardware: a Tang Nano 20K revision 3921 or 3923, a FAT32 or exFAT microSD card, an HDMI display and cable, and a USB-C cable for power and programming.

A USB keyboard and powered USB OTG hub are optional. They are only required for direct USB-keyboard input in QDOS; NanoQL can boot and display the QL without them.

Install [Git](https://git-scm.com/downloads), [Python 3](https://www.python.org/downloads/) with Tkinter, and [Gowin EDA Education](https://www.gowinsemi.com/en/support/download_eda/) to compile the HDL. FPGA programming requires either Gowin Programmer, which is bundled with Gowin EDA, or [openFPGALoader](https://github.com/trabucayre/openFPGALoader). Gowin Programmer is not mandatory. When using a prebuilt NanoQL bitstream, openFPGALoader removes the need to install Gowin EDA for FPGA programming. VS Code is not required.

### Step-by-step setup

#### 1. Start the assistant

```sh
git clone https://github.com/pR-0000/NanoQL.git
cd NanoQL
python tools/nanoql_setup.py
```

The assistant uses only Python's standard library and runs on Windows, macOS, and Linux. The initial BL616 FlashCube operation currently requires Windows.

#### 2. Prepare the integrated BL616

In **1. BL616 Companion**, select board revision 3921 or 3923, keep the **NanoQL** profile, and click **Prepare and open FlashCube**. Disconnect the board, hold **UPDATE** while reconnecting USB, then release it. In FlashCube, select the serial port and the `.ini` file displayed by the assistant, and program it. The NanoQL profile provides the USB keyboard, microSD, and NanoQL Link. The Original profile temporarily restores FPGA Partner when persistent Gowin programming is required.

#### 3. Prepare the ROM and microSD

Provide a legally obtained 48 or 64 KiB QL ROM and the standard Sinclair IPC firmware `ipc8049.hex` from the [MiSTer QL core](https://github.com/MiSTer-devel/QL_MiSTer/tree/master/rtl). NanoQL uses this original firmware to reproduce the behavior of the QL's 8049 controller. In **2. ROM and microSD**, select the ROM, microSD root, and IPC file. Click **Prepare microSD**, then **Convert IPC firmware**. The card will contain:

```text
QL.rom
nanoql.ini
```

#### 4. Build and program NanoQL

In **3. FPGA**, check the `gw_sh` path and click **Build**. The resulting bitstream is `impl/pnr/NanoQL_sd_rom.fs`.

With Gowin Programmer, select that `.fs` file. Use **SRAM Mode** for a temporary test, or **External Flash Mode**, an erase/program operation, and **Generic Flash** for persistent programming. When openFPGALoader is installed, the assistant's **Program SRAM** and **Program Flash** buttons provide the optional command-line method.

openFPGALoader does not require Gowin Programmer. Persistent native programming still requires the BL616 `ORIGINAL` profile so that the board exposes its standard JTAG interface.

Command-line equivalent:

```sh
gw_sh build_sd_rom.tcl
openFPGALoader -b tangnano20k -f impl/pnr/NanoQL_sd_rom.fs
```

Keep Gowin EDA's **Use JTAG as regular IO** option disabled.

#### 5. Boot and test

Power the board off, insert the prepared microSD card, connect HDMI, and power the Tang Nano 20K through USB-C. The QL boot screen must appear without any keyboard or hub. For an optional interactive test, attach a USB keyboard through a powered USB OTG hub, press `F1` or `F2`, enter `PRINT 2+2`, and open the NanoQL menu with `F12`.

For an objective CPU-speed check from a PC, enter NanoQL Link mode with S1 and run `python tools/nanoql_link.py --port COMx cpu-status`. Replace `COMx` with the serial port shown by the operating system. The command reports the selected mode and its effective clock rate. Use the QL-SD image described below for reliable QL program transfers.

To expose an ordinary folder as the `mdv1_` cartridge, create a subfolder under `NanoQL/Microdrives` on the microSD and place the QL files inside it. Open the overlay with `F12`, select **Build MDV1 from:**, then select that folder. The BL616 converts it, mounts the cartridge for the current session, and resets the QL without a PC or development mode. Use `DIR mdv1_`, `LOAD mdv1_name`, or `LRUN mdv1_program_bas`. The generated image is deliberately not remounted by `nanoql.ini` during startup. Conversion supports up to 126 files, eight nested directory levels, and flattened ASCII QDOS names up to 36 characters. The generated QLAY image is always 174,930 bytes, but usable capacity depends on per-file 512-byte sector rounding; a single file can contain at most 128,960 bytes.

### Quick troubleshooting

- **No picture:** check HDMI input and persistent FPGA programming.
- **Checkerboard or solid screen:** check `QL.rom`, `nanoql.ini`, microSD, and that the BL616 firmware matches the board revision.
- **F1/F2 does not respond:** use a powered OTG-compatible hub and boot without a USB data connection to the computer.
- **FPGA programming fails:** use a USB data cable and temporarily restore the Original BL616 profile.

### FPGA utilization

Latest main build:

| Resource      |           Utilization |
| ------------- | --------------------: |
| Logic         | 12,698 / 20,736 (62%) |
| LUT           |                11,897 |
| ALU           |                   735 |
| Registers     |                 6,110 |
| CLS           |  8,174 / 10,368 (79%) |
| BSRAM         |         15 / 46 (33%) |
| I/O           |         27 / 66 (41%) |
| System Fmax   | 62.965 MHz at 31.8 MHz |
| HDMI Fmax     | 74.494 MHz at 74.25 MHz |
| Setup TNS     | 0 ns (system and HDMI) |

### Architecture and references

```text
USB keyboard -> BL616 FPGA Companion -> QL matrix -> 8049 IPC
microSD -> BL616 FPGA Companion -> ROM, QL-SD, and Microdrive image
FPGA Companion OSD + QL video -> HDMI
ROM + SDRAM + ZX8301/ZX8302 -> fx68k
```

HDMI output uses standard 1280 × 720p50 timings. The QL/SDRAM domain remains at 31.8 MHz, while a dual-clock line buffer feeds the 74.25 MHz HDMI domain. `Monitor` maps each QL sample to a uniform 2 × 2 HDMI block. Wider modes preserve all 512 × 256 source samples, and `Wide +30%` keeps a 40-pixel HDMI safety margin on both sides.

The `QL` CPU mode uses 7.5 MHz 68008 phases and QL MiSTer's `ql_timing` RAM-contention model. The `16 MHz` mode runs at 15.9 MHz with the current system clock and disables this contention, as QL MiSTer's accelerated mode does. CPU speed is live-switchable and persisted in `nanoql.ini`.

The RAM menu applies the same address masks and expansion ranges as QL MiSTer: 128 KiB with 256 KiB wrapping, or 640/896 KiB with 1 MiB decoding. The selection is saved in `nanoql.ini` and applied on QL reset.

The initial QL-SD path ports QL_MiSTer's QLROMEXT and virtual SD-card implementation. The `QL-SD image` selector mounts a microSD `QXL.WIN` file as a read/write virtual SDHC card. Validation with QL-SD driver 1.08 or newer is documented in [`docs/QL_SD.md`](docs/QL_SD.md).

The Microdrive reader streams an exact 174,930-byte QLAY image from microSD through two sector buffers instead of storing it all in BSRAM. Its 200 kbit/s serialized stream comes directly from the fixed system clock and remains independent of CPU speed; physical operation is validated in both QL and 16 MHz modes. It preserves the QL model's 80 us words and 2.8 ms gaps. Preambles, gaps, and `RX ready` windows follow QL_MiSTer's Microdrive path. From the overlay, the BL616 can autonomously convert a folder under `NanoQL/Microdrives` into `MDV1.mdv`, mount it for the current session, and reset the QL. The developer-only `mdv-sync` command remains available for direct PC-folder synchronization. See [`docs/NANOQL_LINK.md`](docs/NANOQL_LINK.md).

The SDRAM follows the complete GW2AR-18 startup sequence: a 200 us stabilization delay, precharge-all, two auto-refresh commands, mode-register programming, access auto-precharge, and periodic refresh.

At startup, `QL.rom` is loaded and verified in the top 64 KiB of SDRAM. A transaction-owner router arbitrates NanoQL Link, the ROM loader, 68000 ROM reads, and QL RAM.

The CPU, ZX8302, and 8049 IPC remain under a common reset while the ROM is loading. They start together only after the ROM is ready, matching a QL cold start.

The 8049 firmware ROM uses a synchronous output and is synthesized into one of the Tang Nano 20K BSRAM blocks. The IPC receives the same fractional 11 MHz enable used by the QL MiSTer core.

The ZX8302 applies each register write on the negative 68008 phase and returns `DTACK` only after it has committed. Its registers, IPC serial link, and interrupts follow the QL MiSTer module structure.

HDL and constraints are under `src/`, Companion integration is under `src/companion/`, and user tools are under `tools/`.

The direct USB development interface is documented in [`docs/NANOQL_LINK.md`](docs/NANOQL_LINK.md). The unified BL616 firmware starts with the normal USB keyboard and switches to NanoQL Link when S1 is pressed after FPGA startup. It can temporarily reconfigure FPGA SRAM with Gowin's generated `.bin` file, then automatically returns to Companion mode. The `fpga-flash-native` command automates persistent programming with Gowin Programmer or openFPGALoader after temporarily restoring the official BL616 firmware.

Reference projects: [QL MiSTer](https://github.com/MiSTer-devel/QL_MiSTer), [QL MiST](https://github.com/mist-devel/ql), [MiSTeryNano](https://github.com/MiSTle-Dev/MiSTeryNano), [NanoMIG](https://github.com/MiSTle-Dev/NanoMIG), and the [Tang Nano 20K documentation](https://wiki.sipeed.com/hardware/en/tang/tang-nano-20k/nano-20k.html).
