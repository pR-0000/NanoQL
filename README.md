# NanoQL

Portage progressif du Sinclair QL sur Sipeed Tang Nano 20K.

**Ce projet est généré par Chat GPT 5.6 Sol.**

## Français

### État du projet

NanoQL démarre une ROM Sinclair QL depuis la carte microSD et fournit :

- un cœur 68000 `fx68k` ;
- 128 Kio de RAM QL dans la SDRAM de la Tang Nano 20K ;
- les modes vidéo QL 4 et 8 sur HDMI 576p ;
- une image 512 x 256 centrée, sans pixels déformés ;
- le contrôleur IPC 8049 et la matrice clavier QL ;
- un clavier USB raccordé par hub au BL616 intégré ;
- le chargement automatique de `QL.rom` depuis la microSD ;
- un menu OSD accessible avec `F12` pour choisir la ROM et réinitialiser le QL.

Les lecteurs Microdrive et leurs images ne sont pas encore implémentés.

### Matériel nécessaire

- Sipeed Tang Nano 20K, révision 3921 ou 3923 ;
- carte microSD formatée en FAT32 ou exFAT ;
- écran HDMI ;
- clavier USB ;
- hub USB alimenté compatible USB OTG ;
- un câble USB de données pour la programmation.

La révision est imprimée sur la carte, par exemple `3923`.

### Logiciels

Installez :

1. [Git](https://git-scm.com/downloads)
2. [Python 3](https://www.python.org/downloads/) avec Tkinter
3. [Gowin EDA Education](https://www.gowinsemi.com/en/support/download_eda/)

Facultatif : [openFPGALoader](https://github.com/trabucayre/openFPGALoader), uniquement si vous préférez programmer la carte depuis l'assistant ou en ligne de commande.

Sous Windows, cochez **Add Python to PATH** pendant l'installation. Sous Linux, Tkinter peut nécessiter le paquet `python3-tk`. VS Code n'est pas nécessaire. Gowin Programmer est inclus avec Gowin EDA et suffit pour programmer la carte ; il n'est donc pas nécessaire d'installer `openFPGALoader`.

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
3. Gardez le mode **Normal**.
4. Cliquez sur **Préparer et ouvrir FlashCube**.
5. Débranchez la carte.
6. Maintenez le bouton **UPDATE**, branchez le câble USB, puis relâchez le bouton.
7. Dans FlashCube, sélectionnez le port série de la carte et le fichier `.ini` indiqué par l'assistant.
8. Lancez la programmation, puis débranchez la carte.

Le mode Normal conserve la programmation FPGA par ordinateur et active automatiquement FPGA Companion lorsque la carte démarre sans liaison USB de données.

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
4. Branchez le clavier sur un hub USB alimenté compatible OTG.
5. Reliez le hub à la Tang Nano 20K, puis alimentez l'ensemble.
6. Attendez l'écran QL et appuyez sur `F1` pour le mode moniteur ou `F2` pour le mode TV.
7. À l'invite QL, testez par exemple `PRINT 2+2`, puis Entrée.
8. Appuyez sur `F12` pour ouvrir ou fermer le menu NanoQL.

### Dépannage court

- **Pas d'image :** vérifiez le câble HDMI, l'entrée de l'écran et la programmation Flash du FPGA.
- **Damier ou écran uni :** la ROM n'est pas montée ; vérifiez `QL.rom`, `nanoql.ini`, la microSD et le firmware BL616 correspondant à la révision.
- **F1/F2 ne répond pas :** utilisez un hub alimenté compatible OTG et démarrez sans connexion USB de données vers l'ordinateur.
- **La programmation FPGA échoue :** utilisez un câble de données et vérifiez que le BL616 est en mode Normal.

### Utilisation FPGA

Dernière compilation du build principal :

| Ressource    |            Utilisation |
| ------------ | ---------------------: |
| Logic        | 10 724 / 20 736 (52 %) |
| LUT          |                 10 103 |
| ALU          |                    555 |
| Registres    |                  4 449 |
| CLS          |  6 780 / 10 368 (66 %) |
| BSRAM        |         45 / 46 (98 %) |
| E/S          |         26 / 66 (40 %) |
| Fmax mesurée |             51,717 MHz |
| TNS setup    |                   0 ns |

Ces valeurs sont mises à jour après les changements significatifs du build principal.

### Architecture

```text
Clavier USB -> BL616 FPGA Companion -> matrice QL -> IPC 8049
microSD -> BL616 FPGA Companion -> chargeur ROM -> BSRAM dédiée
OSD FPGA Companion + vidéo QL -> HDMI
ROM + SDRAM + ZX8301/ZX8302 -> fx68k
```

Le CPU utilise des phases 68008 à 7,5 MHz, le repliement matériel de l'espace d'adressage 128 Kio sur 256 Kio et le modèle de contention RAM `ql_timing` du core QL MiSTer.

La SDRAM suit la séquence complète de démarrage du GW2AR-18 : délai de stabilisation de 200 µs, précharge globale, deux auto-refresh, programmation du registre de mode, auto-précharge des accès et refresh périodique.

Au démarrage, `QL.rom` est chargée et vérifiée dans une BSRAM réinscriptible dédiée. La ROM et la RAM vidéo ne se disputent donc pas le même port SDRAM.

Le CPU, le ZX8302 et l'IPC 8049 restent sur un reset commun pendant le chargement. Ils démarrent ensemble uniquement lorsque la ROM est prête, comme lors d'un démarrage à froid du QL.

La ROM du firmware 8049 utilise une sortie synchrone et est synthétisée dans une BSRAM de la Tang Nano 20K. L'IPC reçoit un enable fractionnaire de 11 MHz, comme dans le core QL MiSTer.

Le ZX8302 applique chaque écriture de registre sur la phase négative du 68008 et ne renvoie `DTACK` qu'après sa validation. Ses registres, son lien série IPC et ses interruptions suivent l'organisation du module QL MiSTer.

Le HDL et les contraintes sont dans `src/`, l'intégration Companion dans `src/companion/` et les outils utilisateur dans `tools/`.

L'interface de développement USB permettant de charger et d'exécuter directement un binaire 68000 est décrite dans [`docs/NANOQL_LINK.md`](docs/NANOQL_LINK.md). Elle utilise un profil BL616 séparé afin de ne pas perturber le clavier, la microSD et l'OSD du fonctionnement normal.

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
- 128 KiB of QL RAM in the Tang Nano 20K SDRAM;
- QL mode 4 and mode 8 video over 576p HDMI;
- a centered 512 x 256 image with uniform pixels;
- the 8049 IPC controller and QL keyboard matrix;
- a USB keyboard through the integrated BL616 and a powered USB hub;
- automatic loading of `QL.rom` from microSD;
- an `F12` on-screen display for ROM selection and QL reset.

Microdrives and their images are not implemented yet.

### Required hardware and software

Hardware: a Tang Nano 20K revision 3921 or 3923, a FAT32 or exFAT microSD card, HDMI display, USB keyboard, powered USB OTG hub, and a USB data cable.

Install [Git](https://git-scm.com/downloads), [Python 3](https://www.python.org/downloads/) with Tkinter, and [Gowin EDA Education](https://www.gowinsemi.com/en/support/download_eda/). Gowin Programmer is included with Gowin EDA and is sufficient to program the board. [openFPGALoader](https://github.com/trabucayre/openFPGALoader) is an optional alternative. VS Code is not required.

### Step-by-step setup

#### 1. Start the assistant

```sh
git clone https://github.com/pR-0000/NanoQL.git
cd NanoQL
python tools/nanoql_setup.py
```

The assistant uses only Python's standard library and runs on Windows, macOS, and Linux. The initial BL616 FlashCube operation currently requires Windows.

#### 2. Prepare the integrated BL616

In **1. BL616 Companion**, select board revision 3921 or 3923, keep **Normal** mode, and click **Prepare and open FlashCube**. Disconnect the board, hold **UPDATE** while reconnecting USB, then release it. In FlashCube, select the serial port and the `.ini` file displayed by the assistant, and program it. This is normally a one-time operation.

#### 3. Prepare the ROM and microSD

Provide a legally obtained 48 or 64 KiB QL ROM and the standard Sinclair IPC firmware `ipc8049.hex` from the [MiSTer QL core](https://github.com/MiSTer-devel/QL_MiSTer/tree/master/rtl). NanoQL uses this original firmware to reproduce the behavior of the QL's 8049 controller. In **2. ROM and microSD**, select the ROM, microSD root, and IPC file. Click **Prepare microSD**, then **Convert IPC firmware**. The card will contain:

```text
QL.rom
nanoql.ini
```

#### 4. Build and program NanoQL

In **3. FPGA**, check the `gw_sh` path and click **Build**. The resulting bitstream is `impl/pnr/NanoQL_sd_rom.fs`.

With Gowin Programmer, select that `.fs` file. Use **SRAM Mode** for a temporary test, or **External Flash Mode**, an erase/program operation, and **Generic Flash** for persistent programming. When openFPGALoader is installed, the assistant's **Program SRAM** and **Program Flash** buttons provide the optional command-line method.

Command-line equivalent:

```sh
gw_sh build_sd_rom.tcl
openFPGALoader -b tangnano20k -f impl/pnr/NanoQL_sd_rom.fs
```

Keep Gowin EDA's **Use JTAG as regular IO** option disabled.

#### 5. Boot and test

Power the board off, insert the prepared microSD card, connect HDMI, and attach the keyboard through a powered USB OTG hub. Power it on without a USB data connection to the computer. At the QL boot screen, press `F1` for monitor mode or `F2` for TV mode. At the prompt, type `PRINT 2+2` and press Enter. Press `F12` to open or close the NanoQL menu.

### Quick troubleshooting

- **No picture:** check HDMI input and persistent FPGA programming.
- **Checkerboard or solid screen:** check `QL.rom`, `nanoql.ini`, microSD, and that the BL616 firmware matches the board revision.
- **F1/F2 does not respond:** use a powered OTG-compatible hub and boot without a USB data connection to the computer.
- **FPGA programming fails:** use a USB data cable and Normal BL616 mode.

### FPGA utilization

Latest main build:

| Resource      |           Utilization |
| ------------- | --------------------: |
| Logic         | 10,724 / 20,736 (52%) |
| LUT           |                10,103 |
| ALU           |                   555 |
| Registers     |                 4,449 |
| CLS           |  6,780 / 10,368 (66%) |
| BSRAM         |         45 / 46 (98%) |
| I/O           |         26 / 66 (40%) |
| Measured Fmax |            51.717 MHz |
| Setup TNS     |                  0 ns |

### Architecture and references

```text
USB keyboard -> BL616 FPGA Companion -> QL matrix -> 8049 IPC
microSD -> BL616 FPGA Companion -> ROM loader -> dedicated BSRAM
FPGA Companion OSD + QL video -> HDMI
ROM + SDRAM + ZX8301/ZX8302 -> fx68k
```

The CPU uses 7.5 MHz 68008 phases, the base machine's 128 KiB RAM address-space wrapping at 256 KiB, and QL MiSTer's `ql_timing` RAM-contention model.

The SDRAM follows the complete GW2AR-18 startup sequence: a 200 us stabilization delay, precharge-all, two auto-refresh commands, mode-register programming, access auto-precharge, and periodic refresh.

At startup, `QL.rom` is loaded and verified in dedicated runtime-writable BSRAM, so ROM and video RAM no longer share the same SDRAM port.

The CPU, ZX8302, and 8049 IPC remain under a common reset while the ROM is loading. They start together only after the ROM is ready, matching a QL cold start.

The 8049 firmware ROM uses a synchronous output and is synthesized into one of the Tang Nano 20K BSRAM blocks. The IPC receives the same fractional 11 MHz enable used by the QL MiSTer core.

The ZX8302 applies each register write on the negative 68008 phase and returns `DTACK` only after it has committed. Its registers, IPC serial link, and interrupts follow the QL MiSTer module structure.

HDL and constraints are under `src/`, Companion integration is under `src/companion/`, and user tools are under `tools/`.

Reference projects: [QL MiSTer](https://github.com/MiSTer-devel/QL_MiSTer), [QL MiST](https://github.com/mist-devel/ql), [MiSTeryNano](https://github.com/MiSTle-Dev/MiSTeryNano), [NanoMIG](https://github.com/MiSTle-Dev/NanoMIG), and the [Tang Nano 20K documentation](https://wiki.sipeed.com/hardware/en/tang/tang-nano-20k/nano-20k.html).
