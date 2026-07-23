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
- une extension QSound optionnelle MC6821 + AY-3-8910, chargée depuis la microSD, mixée sur HDMI et validée physiquement ;
- une image 512 x 256 centrée avec quatre largeurs sélectionnables ;
- le contrôleur IPC 8049 et la matrice clavier QL ;
- un clavier USB raccordé par hub au BL616 intégré, avec dispositions USB QWERTY/AZERTY et ROM anglaise/française sélectionnables dans l'OSD ;
- le chargement automatique de `QL.rom` depuis la microSD ;
- un lecteur `MDV1_` pour les images Microdrive QLAY, avec persistance des écritures QDOS dans l'image montée ;
- un menu OSD accessible avec `F12` pour choisir la ROM, la RAM, la vitesse CPU, le cadrage vidéo et réinitialiser le QL.

Le chemin Microdrive reproduit le signal physique QL à 100 kHz sous la forme du flux QLAY sérialisé à 200 kbit/s utilisé par le ZX8302. `DIR`, `LOAD`, `LRUN`, `SAVE` et la persistance après reset sont validés physiquement. Les registres `WRITE` et `ERASE` du ZX8302 reconstruisent les blocs QLAY normalisés avant leur enregistrement dans l'image `MDV1.mdv` montée.

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

Pour installer une [release compilée](https://github.com/pR-0000/NanoQL/releases), Python 3 avec Tkinter et un seul programmateur FPGA suffisent. Choisissez **Gowin Programmer**, fourni avec Gowin EDA, ou [openFPGALoader](https://github.com/trabucayre/openFPGALoader). Gowin Programmer n'est donc pas obligatoire.

Pour modifier ou compiler le HDL, installez également [Git](https://git-scm.com/downloads) et [Gowin EDA Education](https://www.gowinsemi.com/en/support/download_eda/).

Sous Windows, cochez **Add Python to PATH** pendant l'installation. Sous Linux, Tkinter peut nécessiter le paquet `python3-tk`. VS Code n'est pas nécessaire.

### Installation pas à pas

#### 1. Récupérer NanoQL

```sh
git clone https://github.com/pR-0000/NanoQL.git
cd NanoQL
python tools/nanoql_setup.py
```

Vous pouvez aussi télécharger le code source de la dernière [release NanoQL](https://github.com/pR-0000/NanoQL/releases), puis lancer `python tools/nanoql_setup.py` dans le dossier extrait. L'assistant utilise uniquement la bibliothèque standard de Python. Il fonctionne sous Windows, macOS et Linux. Le flash du BL616 avec FlashCube est actuellement disponible sous Windows.

#### 2. Préparer la ROM et la microSD

Vous devez fournir légalement :

- une ROM QL standard de 48 ou 64 Kio ;
- le firmware IPC Sinclair standard `ipc8049.hex` au format Intel HEX, disponible dans le [core QL MiSTer](https://github.com/MiSTer-devel/QL_MiSTer/tree/master/rtl). NanoQL utilise ce firmware d’origine afin de reproduire le comportement du contrôleur 8049 du QL.

Une ROM QSound de 8 Kio est facultative. Le dépôt du [clone QSound/QPrint](https://github.com/alvaroalea/QL_QsoundQprint_clone/tree/main/ROM) propose les versions utilisées pour tester le matériel ; la version 1.40 est le choix classique recommandé et la version 1.94 ajoute les fonctions du lecteur PT3 mais retire QPrint. Si vous êtes autorisé à utiliser l'image choisie, sélectionnez-la dans **Optional 8 KiB QSound ROM**. L'assistant la valide, la copie sous `QSound.rom` et la monte automatiquement. NanoQL ne redistribue aucune ROM QSound.

Dans l'onglet **2. ROM et microSD** :

1. Sélectionnez votre ROM QL.
2. Sélectionnez la racine de la carte microSD.
3. Au premier lancement, sélectionnez `ipc8049.hex`.
4. Cliquez sur **Préparer la microSD** puis sur **Convertir le firmware IPC**.

L'assistant valide la ROM et crée à la racine de la carte :

```text
QL.rom
nanoql.ini
QSound.rom  # seulement si une ROM QSound a été sélectionnée
```

#### 3. Programmer le FPGA avant de modifier le BL616

La carte doit encore utiliser son firmware BL616 Sipeed d'origine, appelé **FPGA Partner**. Ce firmware expose au PC les canaux `USB Debugger A/0` et `A/1` nécessaires au JTAG. Le firmware BL616 NanoQL les remplace par le clavier USB, la microSD et NanoQL Link ; il ne faut donc l'installer qu'après la programmation persistante du FPGA.

Téléchargez `NanoQL-v0.1.0-FPGA.fs` depuis la release, ou compilez-le dans l'onglet **3. FPGA** :

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

#### 4. Installer le firmware BL616 NanoQL

Cette opération n'est nécessaire qu'une fois, après le succès de la programmation persistante du FPGA.

1. Ouvrez l'onglet **1. BL616 Companion**.
2. Sélectionnez la révision `3921` ou `3923`.
3. Gardez le profil **NanoQL**.
4. Cliquez sur **Préparer et ouvrir FlashCube**.
5. Débranchez la carte.
6. Maintenez le bouton **UPDATE**, branchez le câble USB, puis relâchez le bouton.
7. Dans FlashCube, sélectionnez le port série et le fichier `.ini` indiqué.
8. Lancez la programmation, puis débranchez la carte.

Pour reprogrammer plus tard la Flash FPGA par JTAG, restaurez temporairement le profil BL616 **Original**, programmez le `.fs`, puis réinstallez le profil **NanoQL**. Les essais courants ne nécessitent pas cette permutation : NanoQL Link peut charger temporairement un `.bin` en SRAM avec la commande `fpga`.

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

Pour présenter un dossier ordinaire comme cartouche `mdv1_`, créez un sous-dossier dans `NanoQL/Microdrives` sur la microSD et placez-y les fichiers QL. Ouvrez ensuite l'overlay avec `F12`, choisissez **Build MDV1 from:** puis ce sous-dossier. Le BL616 réalise la conversion, monte la cartouche pour la session en cours et redémarre le QL, sans PC ni mode développeur. Utilisez ensuite `DIR mdv1_`, `LOAD mdv1_nom`, `LRUN mdv1_programme_bas` ou les commandes QDOS habituelles de sauvegarde. Les écritures modifient `NanoQL/Drive1/MDV1.mdv`, pas le dossier source ; reconstruire la cartouche depuis le dossier remplace donc ces modifications. L'image générée n'est volontairement pas remontée par `nanoql.ini` au démarrage. La conversion accepte 126 fichiers au maximum, huit niveaux de sous-dossiers et des noms QDOS aplatis en ASCII de 36 caractères au maximum. L'image QLAY produite mesure toujours 174 930 octets, mais sa capacité utile dépend de l'arrondi de chaque fichier par secteurs de 512 octets ; un fichier unique peut contenir au plus 128 960 octets.

Pour une démonstration QSound complète, lancez `python tools/download_qsound_demo.py --sd-root D:\`, montez ensuite `QSoundZ.mdv` comme **Microdrive 1** dans l'overlay et entrez `LRUN mdv1_boot`. L'outil télécharge le musicdisk freeware [QSoundZ de SMFX](https://www.pouet.net/prod.php?which=96940), vérifie son SHA-256 et ne l'ajoute pas au dépôt NanoQL.

### Dépannage court

- **Pas d'image :** vérifiez le câble HDMI, l'entrée de l'écran et la programmation Flash du FPGA.
- **Damier ou écran uni :** la ROM n'est pas montée ; vérifiez `QL.rom`, `nanoql.ini`, la microSD et le firmware BL616 correspondant à la révision.
- **F1/F2 ne répond pas :** utilisez un hub alimenté compatible OTG et démarrez sans connexion USB de données vers l'ordinateur.
- **La programmation FPGA échoue :** utilisez un câble de données et restaurez temporairement le profil BL616 Original.

### Utilisation FPGA

Dernière compilation du build principal :

| Ressource    |            Utilisation |
| ------------ | ---------------------: |
| Logic        | 14 281 / 20 736 (69 %) |
| LUT          |                 13 396 |
| ALU          |                    801 |
| Registres    |                  6 865 |
| CLS          |  8 939 / 10 368 (87 %) |
| BSRAM        |         21 / 46 (46 %) |
| DSP          |         0,5 / 24 (3 %) |
| E/S          |         27 / 66 (41 %) |
| rPLL         |           2 / 2 (100 %) |
| Fmax système | 63,562 MHz pour 31,8 MHz |
| Fmax HDMI    | 74,690 MHz pour 74,25 MHz |
| TNS setup    | 0 ns (système et HDMI) |

Ces valeurs sont mises à jour après les changements significatifs du build principal.

### Architecture

```text
Clavier USB -> BL616 FPGA Companion -> matrice QL -> IPC 8049
microSD -> BL616 FPGA Companion -> ROM, QL-SD, Microdrive et ROM QSound
MC6821 + AY-3-8910 QSound + BEEP QL -> audio HDMI
OSD FPGA Companion + vidéo QL -> HDMI
ROM + SDRAM + ZX8301/ZX8302 -> fx68k
```

La sortie HDMI utilise le mode standard 1280 × 720p50. Le domaine QL/SDRAM reste à 31,8 MHz et un tampon de ligne à double horloge alimente le domaine HDMI à 74,25 MHz. Le cadrage `Monitor` agrandit chaque échantillon du framebuffer QL en un bloc régulier de 2 × 2 pixels carrés. Les cadrages plus larges conservent les 512 × 256 échantillons complets ; `Wide +30%` garde en plus une marge HDMI de 40 pixels à gauche et à droite.

Le module `ql_zx8301` remplace l'ancien chemin `lite` et regroupe maintenant MC_STAT, les modes vidéo, le blanking, le choix de framebuffer, les timings natifs PAL/NTSC et la phase de clignotement. La trame PAL suit QL_MiSTer avec 672 périodes × 312 lignes, dont 256 lignes visibles, 56 lignes de VBL et 6 lignes de VSYNC. Le VSYNC transmis au ZX8302 et la contention RAM proviennent donc de la trame QL native et non du 720p HDMI. Le bit 6 de MC_STAT active également les timings NTSC des ZX8301 CLA2345 récents. Les détails et les limites restantes sont documentés dans [`docs/ZX8301.md`](docs/ZX8301.md).

### NanoQL par rapport à QL_MiSTer

NanoQL est un portage dérivé de QL_MiSTer et de l'ancien core MiST, pas une réécriture sans filiation. Il conserve notamment `fx68k`, le firmware IPC 8049, l'organisation du ZX8302, le modèle de contention `ql_timing`, QLROMEXT et la carte QL-SD virtuelle. NanoQL adapte ces blocs à une carte autonome sans HPS ni Linux.

| Fonction | QL_MiSTer | NanoQL actuel |
| --- | --- | --- |
| Plateforme | MiSTer DE10-Nano avec HPS | Tang Nano 20K seule, avec son BL616 intégré |
| CPU | QL, 16, 24 et 42 MHz | QL et 16 MHz commutables à chaud ; 24/42 MHz planifiés |
| RAM | 896 Kio ou 4 Mio | 128, 640 ou 896 Kio ; 4 Mio et Gold Card planifiés |
| Gold Card, SMSQ/E et RTC | Pris en charge | Pas encore pris en charge |
| ROM et QL-SD | Chargement et montage dynamique par l'environnement MiSTer | Sélection depuis la microSD et l'overlay BL616 ; lecture QXL.WIN validée, écriture à valider |
| Microdrive | Relecture en mémoire d'une image chargée | Flux matériel indépendant du CPU, écriture/effacement QDOS persistants et conversion autonome d'un dossier microSD |
| QSound | Non intégré | Extension optionnelle MC6821 + AY-3-8910 à 0,75 MHz, ROM microSD et mixage HDMI, validée physiquement |
| Développement | Téléchargement par le canal HPS de MiSTer | NanoQL Link par USB : clavier distant, fichiers microSD, RAM 68000, exécution et programmation FPGA |
| Vidéo | Sortie et scaler MiSTer | HDMI 720p50 intégré, quatre géométries QL et trame QL native séparée de la trame HDMI |

Les principaux apports propres à NanoQL sont donc l'utilisation du BL616 embarqué comme compagnon, le fonctionnement sans ordinateur hôte, le Microdrive inscriptible et persistant, la conversion d'un dossier ordinaire en cartouche depuis l'overlay et l'interface USB de développement direct. QL_MiSTer reste plus complet pour les accélérations CPU, les 4 Mio, Gold Card/SMSQ/E, le RTC et plusieurs périphériques établis. La feuille de route vise cette parité sans sacrifier le profil matériel QL fidèle par défaut.

Le mode CPU `QL` utilise des phases 68008 à 7,5 MHz et le modèle de contention RAM `ql_timing` du core QL MiSTer. Le mode `16 MHz` utilise 15,9 MHz avec l'horloge système actuelle et désactive cette contention, comme le mode accéléré de QL MiSTer. La vitesse peut être changée à chaud et reste conservée dans `nanoql.ini`.

Le menu RAM applique les mêmes masques d'adresses et plages d'extension que QL MiSTer : 128 Kio avec repliement sur 256 Kio, 640 Kio ou 896 Kio avec décodage sur 1 Mio. Le choix est conservé dans `nanoql.ini` et appliqué lors d'un reset QL.

Le premier chemin QL-SD reprend QLROMEXT et l'émulateur de carte SD de QL_MiSTer. Le sélecteur `QL-SD image` monte un fichier `QXL.WIN` de la microSD comme carte SDHC virtuelle, avec transport sectoriel en lecture et en écriture. La procédure de validation avec le pilote QL-SD 1.08 ou ultérieur est décrite dans [`docs/QL_SD.md`](docs/QL_SD.md).

Le lecteur Microdrive diffuse une image QLAY de 174 930 octets depuis la microSD avec deux tampons sectoriels, sans la charger entièrement en BSRAM. Son flux sérialisé à 200 kbit/s est dérivé directement de l'horloge système et reste indépendant de la vitesse CPU ; la lecture et l'écriture sont validées physiquement dans les modes QL et 16 MHz. Il conserve les mots de 80 µs et les gaps de 2,8 ms du modèle QL. Les préambules, les gaps et les fenêtres `RX ready` suivent le chemin Microdrive de QL_MiSTer. Pour l'écriture, le FPGA décode le préambule variable produit par QDOS, reconstruit le bloc logique de 612 octets et le réinsère aux positions fixes du format QLAY avant sa sauvegarde sur la microSD. Après un reset, l'écriture en cours se termine puis le transport repart de façon déterministe au début de la bande. Le BL616 peut convertir de manière autonome un dossier de `NanoQL/Microdrives` en `MDV1.mdv` depuis l'overlay, monter l'image pour la session en cours et redémarrer le QL. La commande développeur expérimentale `mdv-sync` permet aussi une reconstruction depuis un PC, mais l'overlay reste la méthode recommandée. La procédure est décrite dans [`docs/NANOQL_LINK.md`](docs/NANOQL_LINK.md).

La SDRAM suit la séquence complète de démarrage du GW2AR-18 : délai de stabilisation de 200 µs, précharge globale, deux auto-refresh, programmation du registre de mode, auto-précharge des accès et refresh périodique.

Au démarrage, `QL.rom` est chargée et vérifiée dans les 64 Kio supérieurs de la SDRAM. Un routeur mémorise le propriétaire de chaque transaction entre NanoQL Link, le chargeur de ROM, les lectures ROM du 68000 et la RAM QL.

Le CPU, le ZX8302 et l'IPC 8049 restent sur un reset commun pendant le chargement. Ils démarrent ensemble uniquement lorsque la ROM est prête, comme lors d'un démarrage à froid du QL.

La ROM du firmware 8049 utilise une sortie synchrone et est synthétisée dans une BSRAM de la Tang Nano 20K. L'IPC reçoit un enable fractionnaire de 11 MHz, comme dans le core QL MiSTer.

Le ZX8302 applique chaque écriture de registre sur la phase négative du 68008 et ne renvoie `DTACK` qu'après sa validation. Ses registres, son lien série IPC et ses interruptions suivent l'organisation du module QL MiSTer.

L'extension QSound optionnelle reproduit sa fenêtre ROM `$C0000-$C1FFF`, son interface MC6821 et le câblage du générateur AY-3-8910. Son horloge de 0,75 MHz reste indépendante de la vitesse CPU et ses trois voies sont mélangées au son QL sur HDMI. Le démarrage de la ROM, les commandes sonores et la sortie HDMI sont validés physiquement. La ROM n'est pas distribuée avec NanoQL. Sa provenance, sa préparation et le test QSoundZ sont décrits dans [`docs/QSOUND.md`](docs/QSOUND.md).

Le HDL et les contraintes sont dans `src/`, l'intégration Companion dans `src/companion/` et les outils utilisateur dans `tools/`.

L'interface de développement USB permettant de charger et d'exécuter directement un binaire 68000 est décrite dans [`docs/NANOQL_LINK.md`](docs/NANOQL_LINK.md). Le firmware BL616 unifié démarre avec le clavier USB normal et passe à NanoQL Link lorsqu'on appuie sur S1 après le démarrage du FPGA. Cette interface peut reconfigurer temporairement la SRAM du FPGA avec le `.bin` produit par Gowin, puis revenir automatiquement en mode Companion. La commande `fpga-flash-native` automatise la programmation persistante avec Gowin Programmer ou openFPGALoader après restauration temporaire du firmware BL616 officiel.

### Références

- [QL MiSTer](https://github.com/MiSTer-devel/QL_MiSTer)
- [QL MiST](https://github.com/mist-devel/ql)
- [MiSTeryNano](https://github.com/MiSTle-Dev/MiSTeryNano)
- [NanoMIG](https://github.com/MiSTle-Dev/NanoMIG)
- [Clone matériel QSound/QPrint](https://github.com/alvaroalea/QL_QsoundQprint_clone)
- [JT49](https://github.com/jotego/jt49)
- [Documentation Tang Nano 20K](https://wiki.sipeed.com/hardware/en/tang/tang-nano-20k/nano-20k.html)

## English

### Project status

NanoQL boots a Sinclair QL ROM from microSD and currently provides:

- an `fx68k` 68000 core;
- live-switchable `QL` and `16 MHz` CPU speeds in the OSD;
- 128, 640, or 896 KiB of selectable QL RAM in the Tang Nano 20K SDRAM;
- QL mode 4 and mode 8 video over 720p50 HDMI;
- QL mono sound on both HDMI channels as 48 kHz PCM;
- a physically validated optional MC6821 + AY-3-8910 QSound expansion loaded from microSD and mixed into HDMI;
- a centered 512 x 256 image with four selectable display widths;
- the 8049 IPC controller and QL keyboard matrix;
- a USB keyboard through the integrated BL616 and a powered USB hub, with OSD-selectable USB QWERTY/AZERTY and English/French ROM layouts;
- automatic loading of `QL.rom` from microSD;
- an `MDV1_` reader for QLAY Microdrive images, with QDOS writes persisted to the mounted image;
- an `F12` on-screen display for ROM, RAM, CPU speed, video framing, and QL reset.

The Microdrive path reproduces the QL's physical 100 kHz signal through the 200 kbit/s serialized QLAY stream consumed by the ZX8302. `DIR`, `LOAD`, `LRUN`, `SAVE`, and persistence across QL reset are physically validated. ZX8302 `WRITE` and `ERASE` rebuild normalized QLAY records before storing them in the mounted `MDV1.mdv` image.

The planned features and their implementation order are documented in the [roadmap](docs/ROADMAP.md).

The video menu provides `Monitor`, `TV`, `Wide +6%`, and `Wide +30%`. Every mode preserves all 512 × 256 QL image samples. `Monitor` uses uniform 2 × 2 HDMI pixel blocks, while the wider modes progressively compensate for the QL's non-square pixel geometry. Fractional enlargement remains nearest-neighbour output, with no smoothing filter in the FPGA.

### Required hardware and software

Required hardware: a Tang Nano 20K revision 3921 or 3923, a FAT32 or exFAT microSD card, an HDMI display and cable, and a USB-C cable for power and programming.

A USB keyboard and powered USB OTG hub are optional. They are only required for direct USB-keyboard input in QDOS; NanoQL can boot and display the QL without them.

To install a prebuilt [NanoQL release](https://github.com/pR-0000/NanoQL/releases), Python 3 with Tkinter and one FPGA programmer are sufficient. Choose either Gowin Programmer, bundled with Gowin EDA, or [openFPGALoader](https://github.com/trabucayre/openFPGALoader). Gowin Programmer is not mandatory. Install [Git](https://git-scm.com/downloads) and [Gowin EDA Education](https://www.gowinsemi.com/en/support/download_eda/) only when modifying or compiling the HDL. VS Code is not required.

### Step-by-step setup

#### 1. Start the assistant

```sh
git clone https://github.com/pR-0000/NanoQL.git
cd NanoQL
python tools/nanoql_setup.py
```

Alternatively, download and extract the latest [NanoQL release](https://github.com/pR-0000/NanoQL/releases), then run `python tools/nanoql_setup.py` in that directory. The assistant uses only Python's standard library and runs on Windows, macOS, and Linux. BL616 flashing through FlashCube currently requires Windows.

#### 2. Prepare the ROM and microSD

Provide a legally obtained 48 or 64 KiB QL ROM and the standard Sinclair IPC firmware `ipc8049.hex` from the [MiSTer QL core](https://github.com/MiSTer-devel/QL_MiSTer/tree/master/rtl). NanoQL uses this original firmware to reproduce the behavior of the QL's 8049 controller. An authorized 8 KiB QSound ROM is optional; the [QSound/QPrint clone ROM folder](https://github.com/alvaroalea/QL_QsoundQprint_clone/tree/main/ROM) contains the hardware-test versions, with 1.40 recommended for classic compatibility and 1.94 providing PT3-player features without QPrint. NanoQL does not redistribute these ROMs. Select the chosen image in **Optional 8 KiB QSound ROM**. In **2. ROM and microSD**, select the required files and microSD root. Click **Prepare microSD**, then **Convert IPC firmware**. The card will contain:

```text
QL.rom
nanoql.ini
QSound.rom  # only when an optional QSound ROM was selected
```

#### 3. Program the FPGA before changing BL616 firmware

The board must still run Sipeed's original BL616 **FPGA Partner** firmware. It exposes the `USB Debugger A/0` and `A/1` channels required for JTAG. NanoQL BL616 firmware replaces those channels with USB keyboard, microSD, and NanoQL Link services, so install it only after persistent FPGA programming succeeds.

Download `NanoQL-v0.1.0-FPGA.fs` from the release, or use **3. FPGA** to build `impl/pnr/NanoQL_sd_rom.fs`.

With Gowin Programmer, select that `.fs` file. Use **SRAM Mode** for a temporary test, or **External Flash Mode**, an erase/program operation, and **Generic Flash** for persistent programming. When openFPGALoader is installed, the assistant's **Program SRAM** and **Program Flash** buttons provide the optional command-line method.

openFPGALoader does not require Gowin Programmer. Persistent native programming still requires the BL616 `ORIGINAL` profile so that the board exposes its standard JTAG interface.

Command-line equivalent:

```sh
gw_sh build_sd_rom.tcl
openFPGALoader -b tangnano20k -f impl/pnr/NanoQL_sd_rom.fs
```

Keep Gowin EDA's **Use JTAG as regular IO** option disabled.

#### 4. Install NanoQL BL616 firmware

After persistent FPGA programming succeeds, open **1. BL616 Companion**, select revision 3921 or 3923 and the **NanoQL** profile, then click **Prepare and open FlashCube**. Disconnect the board, hold **UPDATE** while reconnecting USB, release it, select the displayed serial port and `.ini` file in FlashCube, and program it.

To reprogram persistent FPGA Flash later through JTAG, temporarily restore the BL616 **Original** profile, program the `.fs`, then reinstall **NanoQL**. Routine development does not require this swap: NanoQL Link can load a temporary `.bin` into FPGA SRAM with the `fpga` command.

#### 5. Boot and test

Power the board off, insert the prepared microSD card, connect HDMI, and power the Tang Nano 20K through USB-C. The QL boot screen must appear without any keyboard or hub. For an optional interactive test, attach a USB keyboard through a powered USB OTG hub, press `F1` or `F2`, enter `PRINT 2+2`, and open the NanoQL menu with `F12`.

For an objective CPU-speed check from a PC, enter NanoQL Link mode with S1 and run `python tools/nanoql_link.py --port COMx cpu-status`. Replace `COMx` with the serial port shown by the operating system. The command reports the selected mode and its effective clock rate. Use the QL-SD image described below for reliable QL program transfers.

To expose an ordinary folder as the `mdv1_` cartridge, create a subfolder under `NanoQL/Microdrives` on the microSD and place the QL files inside it. Open the overlay with `F12`, select **Build MDV1 from:**, then select that folder. The BL616 converts it, mounts the cartridge for the current session, and resets the QL without a PC or development mode. Use `DIR mdv1_`, `LOAD mdv1_name`, `LRUN mdv1_program_bas`, or the usual QDOS save commands. Writes modify `NanoQL/Drive1/MDV1.mdv`, not the source folder; rebuilding the cartridge from that folder therefore replaces those changes. The generated image is deliberately not remounted by `nanoql.ini` during startup. Conversion supports up to 126 files, eight nested directory levels, and flattened ASCII QDOS names up to 36 characters. The generated QLAY image is always 174,930 bytes, but usable capacity depends on per-file 512-byte sector rounding; a single file can contain at most 128,960 bytes.

For a complete QSound demonstration, run `python tools/download_qsound_demo.py --sd-root D:\`, mount `QSoundZ.mdv` as **Microdrive 1** in the overlay, and enter `LRUN mdv1_boot`. The tool downloads the freeware [QSoundZ music disk by SMFX](https://www.pouet.net/prod.php?which=96940), verifies its SHA-256, and keeps it outside the NanoQL repository.

### Quick troubleshooting

- **No picture:** check HDMI input and persistent FPGA programming.
- **Checkerboard or solid screen:** check `QL.rom`, `nanoql.ini`, microSD, and that the BL616 firmware matches the board revision.
- **F1/F2 does not respond:** use a powered OTG-compatible hub and boot without a USB data connection to the computer.
- **FPGA programming fails:** use a USB data cable and temporarily restore the Original BL616 profile.

### FPGA utilization

Latest main build:

| Resource      |           Utilization |
| ------------- | --------------------: |
| Logic         | 14,281 / 20,736 (69%) |
| LUT           |                13,396 |
| ALU           |                   801 |
| Registers     |                 6,865 |
| CLS           |  8,939 / 10,368 (87%) |
| BSRAM         |         21 / 46 (46%) |
| DSP           |         0.5 / 24 (3%) |
| I/O           |         27 / 66 (41%) |
| System Fmax   | 63.562 MHz at 31.8 MHz |
| HDMI Fmax     | 74.690 MHz at 74.25 MHz |
| Setup TNS     | 0 ns (system and HDMI) |

### Architecture and references

```text
USB keyboard -> BL616 FPGA Companion -> QL matrix -> 8049 IPC
microSD -> BL616 FPGA Companion -> ROM, QL-SD, Microdrive, and QSound ROM
MC6821 + AY-3-8910 QSound + native QL BEEP -> HDMI audio
FPGA Companion OSD + QL video -> HDMI
ROM + SDRAM + ZX8301/ZX8302 -> fx68k
```

HDMI output uses standard 1280 × 720p50 timings. The QL/SDRAM domain remains at 31.8 MHz, while a dual-clock line buffer feeds the 74.25 MHz HDMI domain. `Monitor` maps each QL sample to a uniform 2 × 2 HDMI block. Wider modes preserve all 512 × 256 source samples, and `Wide +30%` keeps a 40-pixel HDMI safety margin on both sides.

The `ql_zx8301` module replaces the former `lite` path and now owns MC_STAT, video modes, display blanking, framebuffer selection, native PAL/NTSC timing, and flash phase. Its PAL raster follows QL_MiSTer at 672 periods × 312 lines, including 256 visible lines, 56 VBL lines, and a 6-line VSYNC pulse. ZX8302 VSYNC and RAM contention therefore come from the native QL raster rather than the 720p HDMI frame. MC_STAT bit 6 also selects the NTSC timing implemented by later CLA2345 ZX8301 revisions. See [`docs/ZX8301.md`](docs/ZX8301.md) for implementation details and remaining limits.

### NanoQL compared with QL_MiSTer

NanoQL is a port derived from QL_MiSTer and the earlier MiST core, not an unrelated rewrite. It retains `fx68k`, the original 8049 IPC firmware, the ZX8302 structure, the `ql_timing` contention model, QLROMEXT, and the virtual QL-SD card. NanoQL adapts these blocks to a standalone board without an HPS or Linux.

| Feature | QL_MiSTer | Current NanoQL |
| --- | --- | --- |
| Platform | MiSTer DE10-Nano with HPS | Standalone Tang Nano 20K using its integrated BL616 |
| CPU | QL, 16, 24, and 42 MHz | Live-switchable QL and 16 MHz; 24/42 MHz planned |
| RAM | 896 KiB or 4 MiB | 128, 640, or 896 KiB; 4 MiB and Gold Card planned |
| Gold Card, SMSQ/E, and RTC | Supported | Not implemented yet |
| ROM and QL-SD | Dynamic loading and mounting through the MiSTer environment | microSD and BL616-overlay selection; QXL.WIN reads validated, writes pending validation |
| Microdrive | In-memory playback of an uploaded image | CPU-independent physical stream, persistent QDOS write/erase, and autonomous microSD-folder conversion |
| QSound | Not integrated | Physically validated optional 0.75 MHz MC6821 + AY-3-8910 expansion with microSD ROM and HDMI mixing |
| Development | Downloads through MiSTer's HPS channel | NanoQL Link over USB: remote keyboard, microSD files, 68000 RAM, execution, and FPGA programming |
| Video | MiSTer video output and scaler | Integrated 720p50 HDMI, four QL geometries, and a native QL raster independent of HDMI timing |

NanoQL-specific additions are therefore the integrated BL616 companion, standalone operation, writable persistent Microdrive, overlay-driven conversion of an ordinary folder into a cartridge, and direct USB development interface. QL_MiSTer remains more complete for CPU acceleration, 4 MiB, Gold Card/SMSQ/E, RTC, and several established peripherals. The roadmap targets that parity without compromising the faithful default QL hardware profile.

The `QL` CPU mode uses 7.5 MHz 68008 phases and QL MiSTer's `ql_timing` RAM-contention model. The `16 MHz` mode runs at 15.9 MHz with the current system clock and disables this contention, as QL MiSTer's accelerated mode does. CPU speed is live-switchable and persisted in `nanoql.ini`.

The RAM menu applies the same address masks and expansion ranges as QL MiSTer: 128 KiB with 256 KiB wrapping, or 640/896 KiB with 1 MiB decoding. The selection is saved in `nanoql.ini` and applied on QL reset.

The initial QL-SD path ports QL_MiSTer's QLROMEXT and virtual SD-card implementation. The `QL-SD image` selector mounts a microSD `QXL.WIN` file as a read/write virtual SDHC card. Validation with QL-SD driver 1.08 or newer is documented in [`docs/QL_SD.md`](docs/QL_SD.md).

The Microdrive reader streams an exact 174,930-byte QLAY image from microSD through two sector buffers instead of storing it all in BSRAM. Its 200 kbit/s serialized stream comes directly from the fixed system clock and remains independent of CPU speed; reads and writes are physically validated in both QL and 16 MHz modes. It preserves the QL model's 80 us words and 2.8 ms gaps. Preambles, gaps, and `RX ready` windows follow QL_MiSTer's Microdrive path. For writes, the FPGA decodes QDOS's variable preamble, reconstructs the logical 612-byte record, and merges it into the fixed QLAY offsets before saving it to microSD. After QL reset, pending writeback completes before the transport deterministically returns to the beginning of the tape. From the overlay, the BL616 can autonomously convert a folder under `NanoQL/Microdrives` into `MDV1.mdv`, mount it for the current session, and reset the QL. The experimental developer `mdv-sync` command can rebuild from a PC folder, but the overlay is the recommended path. See [`docs/NANOQL_LINK.md`](docs/NANOQL_LINK.md).

The SDRAM follows the complete GW2AR-18 startup sequence: a 200 us stabilization delay, precharge-all, two auto-refresh commands, mode-register programming, access auto-precharge, and periodic refresh.

At startup, `QL.rom` is loaded and verified in the top 64 KiB of SDRAM. A transaction-owner router arbitrates NanoQL Link, the ROM loader, 68000 ROM reads, and QL RAM.

The CPU, ZX8302, and 8049 IPC remain under a common reset while the ROM is loading. They start together only after the ROM is ready, matching a QL cold start.

The 8049 firmware ROM uses a synchronous output and is synthesized into one of the Tang Nano 20K BSRAM blocks. The IPC receives the same fractional 11 MHz enable used by the QL MiSTer core.

The ZX8302 applies each register write on the negative 68008 phase and returns `DTACK` only after it has committed. Its registers, IPC serial link, and interrupts follow the QL MiSTer module structure.

The optional QSound expansion reproduces its `$C0000-$C1FFF` ROM window, MC6821 interface, and AY-3-8910 wiring. Its 0.75 MHz clock remains independent of CPU speed, and all three channels are mixed with native QL audio over HDMI. ROM startup, sound commands, and HDMI output are physically validated. The ROM is not distributed with NanoQL. Its source, preparation, and the QSoundZ test are documented in [`docs/QSOUND.md`](docs/QSOUND.md).

HDL and constraints are under `src/`, Companion integration is under `src/companion/`, and user tools are under `tools/`.

The direct USB development interface is documented in [`docs/NANOQL_LINK.md`](docs/NANOQL_LINK.md). The unified BL616 firmware starts with the normal USB keyboard and switches to NanoQL Link when S1 is pressed after FPGA startup. It can temporarily reconfigure FPGA SRAM with Gowin's generated `.bin` file, then automatically returns to Companion mode. The `fpga-flash-native` command automates persistent programming with Gowin Programmer or openFPGALoader after temporarily restoring the official BL616 firmware.

Reference projects: [QL MiSTer](https://github.com/MiSTer-devel/QL_MiSTer), [QL MiST](https://github.com/mist-devel/ql), [MiSTeryNano](https://github.com/MiSTle-Dev/MiSTeryNano), [NanoMIG](https://github.com/MiSTle-Dev/NanoMIG), the [QSound/QPrint hardware clone](https://github.com/alvaroalea/QL_QsoundQprint_clone), [JT49](https://github.com/jotego/jt49), and the [Tang Nano 20K documentation](https://wiki.sipeed.com/hardware/en/tang/tang-nano-20k/nano-20k.html).
