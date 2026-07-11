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

La version actuelle intègre la vidéo HDMI, la SDRAM embarquée, un vrai cœur CPU 68000 `fx68k`, une ROM de diagnostic minimale, une variante utilisant une ROM système locale, une variante chargeant automatiquement la ROM QL depuis la microSD et le clavier USB via le BL616 embarqué. L'overlay OSD visible n'est pas encore raccordé.

### Assistant graphique recommandé

L'assistant multiplateforme centralise la préparation du BL616, de la ROM et de la microSD, la compilation Gowin et la programmation FPGA :

```sh
python tools/nanoql_setup.py
```

Il utilise uniquement Python 3 et Tkinter, sans dépendance `pip`. Sous Linux, installer `python3-tk` avec le gestionnaire de paquets de la distribution si nécessaire. Le bouton **Tout préparer et compiler** enchaîne la validation de la ROM, la conversion du firmware IPC, la préparation de `QL.rom` et `nanoql.ini`, puis la construction du bitstream microSD. Le flash du BL616 reste volontairement confirmé dans FlashCube, car il exige la sélection physique du port série et du mode `UPDATE`.

Fonctionnalités déjà présentes :

- Projet Gowin pour Tang Nano 20K
- Broches JTAG conservées pour le programmateur embarqué avec `set_option -use_jtag_as_gpio 0`, conformément à la configuration Tang Nano 20K de NanoMIG
- PLL HDMI 160 MHz et horloge pixel 32 MHz, basées sur l’implémentation Tang Nano 20K de MiSTeryNano
- Sortie HDMI en mode proche PAL 720x576@50 Hz
- Mise à l'échelle entière de l'image QL 512x256 vers une grille 512x512
- Chaque pixel QL occupe exactement un échantillon HDMI sur deux lignes, sans variation de taille
- Conservation des 512 colonnes et des 256 lignes, sans aucun recadrage
- Centrage avec des marges noires de 104 pixels à gauche et à droite et de 32 lignes en haut et en bas
- Mode CEA 576p 16:9 (VIC 18) annoncé au moniteur dans l'AVI InfoFrame HDMI
- Calcul de la mise à l'échelle HDMI/QL isolé dans `ql_hdmi_window`
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
  - initialisation déterministe des 128 Kio de RAM du QL de base
  - motifs vidéo dans les premiers 64 Kio et mise à zéro des 64 Kio supérieurs, dont la zone de pile JS
  - vérification par relecture des 65 536 mots avant activation du service vidéo
  - lectures vidéo servies directement depuis la SDRAM
- Arbitrage SDRAM à deux clients :
  - lectures vidéo prioritaires afin de respecter les échéances de ligne
  - port système 22 bits avec lecture, écriture 16 bits et masques d'octets
  - pont de bus utilisé par le cœur `fx68k`
- Pont de bus 68000 minimal avec adresse 24 bits en octets, `AS`, `R/W`, `UDS`, `LDS` et `DTACK`
- Pont synchronisé avec le timing réel du 68000 : les écritures attendent l'activation de `UDS` ou `LDS` après `AS`
- Première carte mémoire QL :
  - ROM décodée entre `0x000000` et `0x00FFFF`
  - exactement 128 Kio de RAM de base entre `0x020000` et `0x03FFFF`
  - RAM et mémoire vidéo servies par la SDRAM, notamment l'écran à `0x020000`
  - registres internes non implémentés lus comme zéro et espace absent lu comme bus ouvert `0xFFFF`
  - plages d'E/S et d'extension séparées de la SDRAM
  - registre ZX8301 `mc_stat` décodé à son adresse QL réelle `0x018063`
  - écritures en ROM acquittées mais ignorées
- Cœur `fx68k` cycle-exact issu de MiSTeryNano, cadencé provisoirement à 7,95 MHz par des clock-enables
- ROM de diagnostic autonome, écrite en assembleur 68000 et ne nécessitant aucun clavier
- Test d'endurance exécuté en boucle par le CPU :
  - sélection de l'écran `$28000` et du mode 8 par écriture de `0x88` dans `mc_stat`
  - écriture puis relecture de 48 Kio entre `$30000` et `$3BFFF`, hors VRAM et pile
  - nouveau motif déterministe à chaque passe afin de détecter les bits bloqués et corruptions transitoires
  - lectures vidéo maintenues pendant le test pour exercer l'arbitrage CPU/scanout de la SDRAM
  - signature `0xA55A` après chaque passe valide ou `0xDEAD` dès la première différence
- Mode 8 et sélection de base écran désormais commandés uniquement par le programme 68000
- Première implémentation du ZX8302 :
  - décodage de la zone `$18000-$1803F`
  - lecture des mots RTC et du registre état/interruptions à `$18020`
  - interruption VBlank de niveau 2 reliée aux entrées IPL de `fx68k`
  - acquittement de l'interruption par écriture à `$18021`
  - RTC provisoire dérivée de l'horloge système, encore approximative
  - `ZX8302-lite` autonome pour la variante diagnostic
  - cœur OpenCores `t48` exécutant le firmware IPC 8049 dans la variante système
  - horloge IPC proche de 10,6 MHz obtenue par clock-enable
  - matrice clavier QL 8x8 alimentée par les événements USB HID de FPGA Companion
  - scan de la matrice par les ports `P1` et `DB` du véritable IPC 8049
  - interruptions clavier IPC réinjectées sur les entrées IPL du 68000
- Clavier USB par le BL616 embarqué :
  - événements HID bruts décodés sans émulation d'un port PS/2 physique
  - lettres, chiffres, ponctuation, F1-F10, flèches et modificateurs
  - Retour arrière, Suppr, Home, End et Page Up/Down convertis en combinaisons QL avec temporisation
  - témoin d'activité d'environ une demi-seconde sur le signal LED `leds_n[5]`
- Le diagnostic doit valider la lecture de `$18020`, l'écriture `mc_stat`, l'interruption VBlank et une passe RAM complète
- Validation complète de l'interruption verticale 68000 :
  - vecteur niveau 2 installé à `$000068`
  - autovecteur déclenché par `FC=111` et `VPA`
  - acquittement de VBlank par écriture de `0x08` à `$18021`
  - retour par `RTE` vers le test RAM en cours
- Pile superviseur placée au sommet de la RAM 128 K (`$40000`) pour ne pas écraser les écrans
- Variante ROM système sans redistribution de contenu protégé :
  - dumps binaires utilisateur de 48 Kio ou 64 Kio acceptés
  - conversion big-endian vers un fichier hexadécimal de 64 Kio
  - fenêtre ROM complète `$000000-$00FFFF`
  - fichier généré exclu de Git
  - construction séparée qui refuse de démarrer si la ROM privée est absente
  - ROM Sinclair JS, QDOS 1.10, sélectionnée pour le premier essai matériel
- Chargement expérimental de ROM depuis la microSD :
  - protocole SPI standard FPGA Companion, compatible Tang Nano 20K révisions 3921 et 3923 avec firmware sélectionné par révision
  - configuration FAT/exFAT servie au BL616 et montage automatique de `QL.rom`
  - fichiers ROM de 48 Kio ou 64 Kio acceptés
  - copie dans une zone SDRAM réservée et vérification mot par mot
  - reset 68000 maintenu jusqu'à la validation complète de la ROM
- Carré d'état en haut à gauche : orange pendant le test initial, deux verts alternés à chaque passe réussie, rouge en cas d'échec ; bleu/cyan pour le démarrage système et l'activité IPC
- Flash du mode 8 conforme au principe du ZX8301 : le bit F commute un verrou de couleur, avec une phase changée toutes les 26 images
- Probe de timing QL natif, inspiré du timing PAL/NTSC du `zx8301.v` original, câblé en parallèle pour observation par LED

### Organisation des sources

- `src/nanoql_top.sv` : top-level Tang Nano 20K
- `src/nanoql_hdmi.sv` : wrapper HDMI autour du cœur HDMI de MiSTeryNano
- `src/ql_video_test.sv` : timing HDMI de la démonstration et raccordement du front-end vidéo
- `src/ql_hdmi_window.sv` : mise à l'échelle entière, centrage et coordonnées QL 512x256
- `src/ql_zx8301_lite.sv` : module transitoire de registre/front-end inspiré du ZX8301
- `src/ql_zx8302_lite.sv` : RTC, registre état/IRQ et interruption VBlank de niveau 2
- `src/ql_zx8302_ipc.sv` : variante ZX8302 raccordée au véritable IPC 8049
- `src/ipc/ql_ipc_t48.sv` : raccordement série QL et clock-enable du 8049
- `src/ipc/t48/` : cœur 8049 OpenCores importé du core MiST QL
- `src/ql_video_scanout.sv` : séquenceur de lecture, tampon de ligne et décodeur de pixels QL
- `src/ql_native_timing_probe.sv` : probe de timing QL natif, encore non utilisé pour générer l’HDMI
- `src/ql_test_pattern.sv` : génération des motifs QL mode 4 et mode 8 écrits en SDRAM
- `src/ql_sdram_memory.sv` : initialisation, vérification, rafraîchissement et service des lectures vidéo SDRAM
- `src/ql_cpu_bus_bridge.sv` : conversion des cycles 68000 en transactions du bus système interne
- `src/ql_memory_map.sv` : décodage ROM/SDRAM et du registre ZX8301 à `0x018063`
- `src/ql_boot_rom.sv` : wrapper de la petite ROM diagnostique exécutée par `fx68k`
- `src/rom/ql_diagnostic.s` : source assembleur 68000 du test autonome
- `src/rom/ql_diagnostic_rom.vh` : image Verilog générée et versionnée pour permettre une compilation Gowin directe
- `src/ql_system_rom.sv` : mémoire ROM 64 Kio initialisée depuis le fichier utilisateur généré
- `src/ql_sd_boot_rom.sv` : sélection de la ROM dynamique placée en SDRAM
- `src/companion/` : transport SPI Companion, accès microSD, chargeur ROM et configuration de menu
- `src/companion/ql_companion_hid.sv` : décodage HID Companion et matrice clavier QL
- `src/ql_cpu_fx68k.sv` : wrapper d'horloge, de reset et de bus autour du cœur 68000
- `src/ql_cpu_boot_monitor.sv` : validation de l'écriture `mc_stat` et détection des signatures du programme
- `src/fx68k/` : cœur 68000 cycle-exact, microcode, documentation et licence GPLv3 importés de MiSTeryNano
- `src/sdram/sdram.v` : contrôleur SDRAM Tang Nano 20K importé de MiSTeryNano, sous GPLv3
- `build_common.tcl` : liste et options Gowin communes aux différentes constructions
- `build_system_rom.tcl` : construction expérimentale avec ROM système privée
- `build_sd_rom.tcl` : construction chargeant la ROM QL depuis la microSD
- `tools/prepare_ql_rom.ps1` : validation et conversion du dump binaire utilisateur
- `tools/prepare_ql_ipc_rom.ps1` : validation et conversion Intel HEX du firmware IPC privé
- `tools/build_diagnostic_rom.ps1` : reconstruction optionnelle de l'image diagnostic avec `vasmm68k_mot`
- `tools/prepare_sd_card.ps1` : validation de la ROM et création de `QL.rom` avec son fichier d'auto-montage `nanoql.ini`
- `tools/build_companion_config.ps1` : compression de la configuration XML du Companion
- `tools/prepare_bl616_firmware.ps1` : téléchargement vérifié et préparation du flasher BL616
- `tools/prepare_bl616_firmware.py` : préparation équivalente en Python 3 multiplateforme
- `tools/nanoql_setup.py` : assistant graphique Tkinter pour préparer, compiler et programmer NanoQL
- `tools/prepare_sd_card.py` : préparation multiplateforme de `QL.rom` et `nanoql.ini`
- `tools/prepare_ql_rom.py` : conversion multiplateforme d'une ROM QL locale
- `tools/prepare_ql_ipc_rom.py` : conversion multiplateforme du firmware IPC Intel HEX

### Indicateurs LED

- LED 0 : heartbeat du cœur FPGA
- LED 1 : diagnostic 68000 validé, ou première transaction IPC terminée dans la variante système
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

Après programmation, la mire du second écran doit apparaître de façon stable en mode 8 et la LED 4 doit être active. Le carré reste orange pendant l'initialisation SDRAM et la première passe, puis alterne entre deux verts discrets après chaque écriture/relecture réussie des 48 Kio. Un carré rouge ou la LED 2 indique une différence RAM, une erreur SDRAM ou un underflow vidéo. Laisser fonctionner ce bitstream plusieurs heures constitue un premier burn-in autonome du chemin CPU/SDRAM/vidéo.

L'image générée est déjà fournie. Pour la reconstruire après modification de l'assembleur, installer `vasmm68k_mot`, puis lancer :

```powershell
.\tools\build_diagnostic_rom.ps1 -VasmPath <chemin-vers-vasmm68k_mot.exe>
gw_sh build.tcl
```

#### Variante ROM système expérimentale

La première ROM retenue est la **Sinclair JS, QDOS 1.10**, proposée sur la [page des ROM QL de Dilwyn Jones](https://sinclairql.net/djw/qlrom/index.html). C'est une ROM Sinclair standard et non une variante clavier ou une ROM modifiée, ce qui en fait la base la plus neutre pour le premier démarrage. La page indique que ces ROM sont mises à disposition pour un usage en Europe; vérifiez néanmoins vos droits dans votre juridiction.

Le dépôt Git public ne contient et ne télécharge automatiquement ni la ROM QL ni le firmware IPC 8049. Les fichiers privés peuvent être conservés sous `private/roms/`, dossier ignoré par Git. Empreinte SHA-256 de la ROM JS utilisée pour cette étape : `FC6A683E44570D7E4A144580729E25FF4B3BD293A9EFF5313CFDAE11520D5EFC`.

```powershell
.\tools\prepare_ql_rom.ps1 -InputPath <chemin-vers-votre-rom.bin>
.\tools\prepare_ql_ipc_rom.ps1 -InputPath <chemin-vers-votre-firmware-ipc.hex>
gw_sh build_system_rom.tcl
```

Le convertisseur QL accepte exactement 49 152 ou 65 536 octets. Une ROM de 48 Kio est complétée par `0xFF` jusqu'à 64 Kio. Le convertisseur IPC accepte une image Intel HEX complète de 2 Kio. Les fichiers générés `src/rom/ql_system_rom.hex` et `src/ipc/ql_ipc_rom.hex` sont ignorés par Git. Le bitstream expérimental est `impl\pnr\NanoQL_system_rom.fs`.

Dans cette variante, le carré devient bleu après l'initialisation SDRAM, puis cyan après la première transaction complète entre JS et l'IPC. Un clavier USB relié au BL616 permet désormais de répondre avec `F1` ou `F2` et d'utiliser QDOS.

#### Variante ROM microSD / BL616

Cette variante cible le BL616 embarqué des Tang Nano 20K **révisions 3921 et 3923**. L'assistant graphique est la méthode recommandée :

```sh
python tools/nanoql_setup.py
```

Dans l'onglet `BL616 Companion`, choisir la révision imprimée sur la carte puis le mode normal ou test. La procédure en ligne de commande reste disponible sous Windows :

```powershell
.\tools\prepare_bl616_firmware.ps1 -Launch
```

La préparation équivalente avec Python 3 est disponible sur toutes les plateformes :

```sh
python3 tools/prepare_bl616_firmware.py --revision 3923
```

Sous Windows, ajouter `--launch` ouvre FlashCube. PowerShell Core peut être installé sous macOS, mais cela ne rend pas l'exécutable FlashCube Windows compatible. Sur macOS et Linux, le script Python prépare et vérifie le paquet complet; le flash natif en ligne de commande restera séparé jusqu'à validation matérielle de l'écriture BL616 en deux segments.

Le script télécharge FPGA Companion `v1.4.22` et BouffaloLabFlashCube depuis leurs URL officielles, vérifie chaque empreinte SHA-256 et met les téléchargements en cache dans `private/bl616/`, ignoré par Git. Les configurations générées sont `1_NORMAL_3921_partner_auto.ini`, `2_TEST_3921_companion_only.ini`, `1_NORMAL_3923_partner_auto.ini` et `2_TEST_3923_companion_only.ini`. Les images génériques `nano20k` ciblent le brochage BL616 de la révision 3921 ; les images `nano20k_v3923` ciblent le brochage modifié de la révision 3923. Maintenir ensuite `UPDATE`, connecter l'USB-C, relâcher `UPDATE`, rafraîchir les ports COM, choisir le nouveau port et cliquer sur `Download`. Voir aussi la [procédure FPGA Companion](https://github.com/MiSTle-Dev/.github/wiki/Firmware-Installation-BL616-%C2%B5C), les [versions Tang Nano 20K](https://github.com/MiSTle-Dev/.github/wiki/Versions_TangNano20k) et la [documentation Sipeed](https://en.wiki.sipeed.com/hardware/en/tang/common-doc/update_debugger.html).

La configuration normale conserve le programmateur Gowin et place Companion au second étage. La variante de test démarre Companion même avec un PC connecté, mais remplace temporairement le programmateur Gowin. Le bouton `UPDATE` reste toujours disponible : reflasher ensuite la configuration `1_NORMAL` correspondant à la révision restaure le fonctionnement Partner standard.

Avec le firmware standard à deux étages, une liaison USB de données vers un PC fait démarrer le BL616 en mode programmateur, pas en mode Companion. Pour lancer Companion, programmer d'abord le bitstream NanoQL dans la **Flash FPGA** et non uniquement en SRAM, puis redémarrer la carte depuis une alimentation USB sans hôte de données, par exemple un chargeur USB. La variante `2_TEST_<revision>_companion_only.ini` sert aux diagnostics mais désactive le programmateur intégré tant que la configuration normale correspondante n'est pas restaurée.

Préparer une carte microSD FAT32 ou exFAT et compiler :

```powershell
.\tools\prepare_sd_card.ps1 -RomPath <chemin-vers-votre-rom.bin> -Destination <racine-microSD>
.\tools\prepare_ql_ipc_rom.ps1 -InputPath <chemin-vers-votre-firmware-ipc.hex>
gw_sh build_sd_rom.tcl
```

Sous macOS ou Linux, préparer la ROM sans PowerShell :

```sh
python3 tools/prepare_sd_card.py /chemin/vers/js.rom /Volumes/NOM_CARTE
python3 tools/prepare_ql_ipc_rom.py /chemin/vers/ipc8049.hex
```

La racine de la carte doit contenir `QL.rom` et `nanoql.ini`. Ce dernier contient `drive0 = /sd/QL.rom`, car l'attribut XML `default` configure le sélecteur mais ne monte pas seul le fichier. Le bitstream généré est `impl\pnr\NanoQL_sd_rom.fs`. Pendant le démarrage, deux rangées de huit cases noir et blanc sont affichées. La rangée supérieure se remplit de gauche à droite pour SDRAM, SPI, octets Companion valides, début SYS, STATUS, configuration XML, accès SDC et démarrage du chargeur. La rangée inférieure indique l'avancement de la copie et de la vérification des 128 secteurs. Un damier noir et blanc signale un échec. Le diagnostic disparaît dès que le 68000 exécute la ROM.

Dans Gowin EDA, **Use JTAG as regular IO doit rester décoché**. NanoQL impose aussi ce réglage dans `build_common.tcl`; le bitstream généré contient `JTAGAsRegularIO: OFF`. Réutiliser JTAG comme GPIO couperait le chemin attendu par le programmateur BL616, sans bénéfice pour NanoQL.

### Statistiques de synthèse

Ces statistiques sont mises à jour à chaque étape compilée. Elles proviennent des rapports de placement-routage Gowin V1.9.11.03 Education pour le GW2AR-LV18QN88C8/I7.

| Ressource | Diagnostic `NanoQL` | ROM locale + IPC | ROM microSD + IPC | Disponible |
|---|---:|---:|---:|---:|
| Logique | 8 353 (41 %) | 8 877 (43 %) | 9 633 (47 %) | 20 736 |
| LUT seules | 7 943 | 8 448 | 9 096 | - |
| ALU | 404 | 423 | 483 | - |
| Registres | 3 444 (22 %) | 3 689 (24 %) | 3 957 (25 %) | 15 915 |
| CLS | 5 169 (50 %) | 5 555 (54 %) | 6 056 (59 %) | 10 368 |
| BSRAM | 7 (16 %) | 43 (94 %) | 12 (27 %) | 46 |
| Ports E/S | 26 (40 %) | 26 (40 %) | 26 (40 %) | 66 |
| IOLOGIC | 6 (5 %) | 6 (5 %) | 6 (5 %) | 121 |
| Réseaux PRIMARY | 5 (63 %) | 5 (63 %) | 5 (63 %) | 8 |
| Réseaux locaux LW | 8 (100 %) | 8 (100 %) | 8 (100 %) | 8 |
| CLKDIV | 1 (13 %) | 1 (13 %) | 1 (13 %) | 8 |
| rPLL | 1 (50 %) | 1 (50 %) | 1 (50 %) | 2 |

Horloge principale : 31,800 MHz demandés. Fmax après placement-routage : 58,660 MHz (diagnostic), 60,646 MHz (ROM locale) et 60,660 MHz (microSD). Aucun endpoint de setup n'est signalé en violation. La ROM locale consomme 94 % des BSRAM ; la variante microSD recommandée ramène ce chiffre à 27 % en stockant la ROM système dans la SDRAM.

### Clavier USB et extensions prévues

Le Companion gère maintenant les claviers USB et le système de fichiers. Le firmware BL616 autorise jusqu'à deux hubs USB externes. Pour un clavier sur la prise USB-C de la Tang, utiliser un adaptateur ou hub **USB OTG alimenté** : la Tang doit être le périphérique hôte et recevoir simultanément son alimentation. Avec le firmware `partner auto`, ne pas relier le port amont du hub à un PC, sinon le BL616 démarre en mode programmateur. La souris, les joysticks, l'OSD visible et les sélecteurs de logiciels restent à intégrer au core QL.

Le BL616 interne n'expose pas assez de GPIO libres pour câbler directement une matrice de touches custom ou plusieurs ports DB9. Ces futures entrées physiques seront donc lues par le FPGA, ou par un petit expander/scanner externe, puis présentées au reste du système par l'interface SPI Companion. Une variante PS/2 à deux signaux reste également possible.

Ordre de préférence matériel :

1. **BL616 intégré à la Tang Nano 20K** : solution privilégiée pour les révisions de carte compatibles avec le firmware `bl616_fpga_partner` et FPGA Companion. Elle ne consomme aucune broche des headers et conserve le connecteur microSD de la Tang. Elle demande une mise à jour prudente du firmware du BL616 et un adaptateur ou hub USB OTG pour les périphériques. Le lecteur microSD reste physiquement piloté par le FPGA ; le Companion échange les secteurs avec lui par SPI et gère le système de fichiers.
2. **Ai-Thinker Ai-M62-12F-Kit** : alternative BL616 externe économique au format DIP-30, sur deux rangées au pas de 2,54 mm. Une cible firmware dédiée est nécessaire, mais le portage est réduit puisque le processeur et la pile CherryUSB sont identiques. Brochage SPI proposé : `GPIO0=CS`, `GPIO1=SCK`, `GPIO30=MISO`, `GPIO27=MOSI`, `GPIO28=IRQ`. Le `GPIO13` utilisé par le M0S Dock n'est pas exposé sur ce kit.
3. **Raspberry Pi Pico/RP2040** : solution de repli la plus pérenne et la mieux documentée. FPGA Companion la prend déjà en charge, mais l'USB hôte utilise deux GPIO avec PIO-USB et nécessite un connecteur USB-A et son alimentation 5 V sur la carte porteuse.

Pour l'Ai-M62, les lignes `USB_DP` et `USB_DM` sont disponibles sur les headers. Une carte porteuse finale devra les relier à un connecteur USB-A hôte, fournir un VBUS 5 V protégé et éviter de connecter simultanément deux sources d'alimentation USB. Le connecteur USB-C du kit reste surtout utile pour le flash et le débogage.

Architecture prévue, inspirée de MiSTeryNano et FPGA Companion :

- overlay monochrome 128x64 de 1 Kio mélangé au flux vidéo ;
- touche Menu dédiée interceptée avant la matrice QL, comme F12 dans MiSTeryNano ;
- système de fichiers FAT/exFAT géré par le microcontrôleur Companion ;
- sélection d'une ROM QL de 48 ou 64 Kio depuis la microSD ;
- transfert et validation de la ROM dans une zone réservée de SDRAM avant libération du reset 68000 ;
- paramètres persistants et futurs sélecteurs d'images disque ou de logiciels.

Toute interface GPIO doit rester en logique 3,3 V. Les connecteurs joystick nécessitent des pull-up 3,3 V et une protection adaptée.

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
17. Ajout du ZX8302-lite, lecture de `$18020`, RTC provisoire et interruption VBlank niveau 2.
18. Validation de l'autovecteur, `STOP`, acquittement `$18021` et retour `RTE`.
19. Conversion locale, exclusion Git et construction séparée pour une ROM système utilisateur.
20. Intégrer le cœur IPC 8049 `t48` et valider le démarrage JS sur la carte.
21. Ajouter une mise à l'échelle entière 1x2, centrée et sans recadrage dans un signal CEA VIC 18.
22. Exécuter un burn-in autonome CPU/SDRAM/vidéo avec motifs RAM variables et contrôle permanent de l'intégrité.
23. Rapprocher l'arbitrage SDRAM des créneaux vidéo/CPU et des délais `DTACK` du QL d'origine.
24. Intégrer le transport SPI FPGA Companion et le chargement vérifié de ROM depuis la microSD vers la SDRAM. Validé sur matériel.
25. Ajouter l'overlay OSD et la sélection interactive de fichiers.
26. Ajouter le transport clavier USB vers la matrice du véritable IPC 8049. Étape actuelle, prête pour validation matérielle.
27. Ajouter la souris, les joysticks et les images disque.

### Licence

NanoQL est distribué sous GNU GPL version 3. Voir `LICENSE`. Le dossier `src/fx68k/` conserve la documentation et la licence du cœur de Jorge Cwik. Le contrôleur SDRAM et les modules Companion importés de MiSTeryNano conservent leurs notices GPLv3. Les fichiers `src/ipc/t48/` conservent les en-têtes de licence BSD du cœur OpenCores.

### Références amont

- [MiSTeryNano](https://github.com/MiSTle-Dev/MiSTeryNano) : HDMI, PLL, contraintes Tang Nano 20K et modules Companion
- [FPGA Companion](https://github.com/MiSTle-Dev/FPGA-Companion) : firmware BL616, protocole SPI et système de fichiers
- [mist-devel/ql](https://github.com/mist-devel/ql) : vidéo Sinclair QL / ZX8301

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

The current build integrates HDMI video, on-board SDRAM, a real `fx68k` 68000 CPU core, a minimal diagnostic ROM, a local system-ROM variant, a variant that automatically loads the QL ROM from microSD, and USB keyboard support through the on-board BL616. The visible OSD overlay is not connected yet.

### Recommended Setup Assistant

The cross-platform assistant centralizes BL616 firmware preparation, ROM and microSD preparation, Gowin builds, and FPGA programming:

```sh
python tools/nanoql_setup.py
```

It uses only Python 3 and Tkinter, with no `pip` dependency. On Linux, install your distribution's `python3-tk` package if required. **Tout préparer et compiler** validates the ROM, converts the IPC firmware, prepares `QL.rom` and `nanoql.ini`, and builds the microSD bitstream in sequence. BL616 flashing deliberately remains confirmed in FlashCube because it requires physical serial-port selection and the `UPDATE` boot mode.

Implemented so far:

- Tang Nano 20K Gowin project
- JTAG pins kept for the on-board programmer with `set_option -use_jtag_as_gpio 0`, matching NanoMIG's Tang Nano 20K configuration
- 160 MHz HDMI PLL and 32 MHz pixel clock path, based on the MiSTeryNano Tang Nano 20K implementation
- HDMI output in a PAL-like 720x576@50 Hz mode
- Integer scaling from the 512x256 QL image to a 512x512 grid
- Every QL pixel occupies exactly one HDMI sample by two lines, with no size variation
- All 512 columns and 256 lines retained, with no cropping
- Centered with 104-pixel black margins on both sides and 32 lines above and below
- CEA 576p 16:9 mode (VIC 18) advertised to the monitor in the HDMI AVI InfoFrame
- HDMI/QL scaling calculation isolated in `ql_hdmi_window`
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
  - deterministic initialization of the base QL's complete 128 KiB RAM
  - video patterns in the first 64 KiB and zero-filled upper 64 KiB, including the JS stack area
  - readback verification of all 65,536 words before enabling video service
  - video reads served directly from SDRAM
- Two-client SDRAM arbitration:
  - priority video reads to preserve line deadlines
  - 22-bit system port with reads, 16-bit writes, and byte masks
  - bus bridge used by the `fx68k` core
- Minimal 68000 bus bridge with 24-bit byte addresses, `AS`, `R/W`, `UDS`, `LDS`, and `DTACK`
- Bridge synchronized with real 68000 timing: writes wait for `UDS` or `LDS` to become active after `AS`
- Initial QL memory map:
  - ROM decoded from `0x000000` through `0x00FFFF`
  - exactly 128 KiB of base RAM from `0x020000` through `0x03FFFF`
  - RAM and video memory served by SDRAM, including the screen at `0x020000`
  - unimplemented internal registers read as zero and absent space reads as open bus `0xFFFF`
  - I/O and expansion ranges kept separate from SDRAM
  - ZX8301 `mc_stat` register decoded at its real QL address `0x018063`
  - ROM writes acknowledged and ignored
- Cycle-exact `fx68k` core imported from MiSTeryNano, provisionally clocked at 7.95 MHz through clock enables
- Autonomous diagnostic ROM written in 68000 assembly and requiring no keyboard
- CPU burn-in loop:
  - selects screen `$28000` and QL mode 8 by writing `0x88` to `mc_stat`
  - writes and reads back 48 KiB from `$30000` through `$3BFFF`, outside VRAM and the stack
  - uses a new deterministic pattern on every pass to expose stuck bits and transient corruption
  - keeps video reads active to exercise CPU/scanout SDRAM arbitration
  - writes `0xA55A` after every valid pass or `0xDEAD` on the first mismatch
- Mode 8 and screen-base selection now controlled exclusively by the 68000 program
- Initial ZX8302 implementation:
  - decodes the `$18000-$1803F` region
  - exposes RTC words and the status/interrupt register at `$18020`
  - connects a level-2 VBlank interrupt to the `fx68k` IPL inputs
  - acknowledges the interrupt through a write to `$18021`
  - uses a provisional, still approximate RTC derived from the system clock
  - standalone `ZX8302-lite` for the diagnostic variant
  - OpenCores `t48` running the 8049 IPC firmware in the system variant
  - near-10.6 MHz IPC timing obtained through a clock enable
  - QL 8x8 keyboard matrix fed by FPGA Companion USB HID events
  - matrix scanned through the real 8049 IPC's `P1` and `DB` ports
  - IPC keyboard interrupts fed back to the 68000 IPL inputs
- USB keyboard through the on-board BL616:
  - raw HID events decoded without emulating a physical PS/2 port
  - letters, digits, punctuation, F1-F10, arrows, and modifiers
  - Backspace, Delete, Home, End, and Page Up/Down translated into delayed QL combinations
  - roughly half-second activity indicator on LED signal `leds_n[5]`
- The diagnostic must validate the `$18020` read, `mc_stat` write, VBlank interrupt, and a complete RAM pass
- Complete validation of the 68000 vertical interrupt path:
  - level-2 vector installed at `$000068`
  - autovector triggered through `FC=111` and `VPA`
  - acknowledges VBlank by writing `0x08` to `$18021`
  - returns through `RTE` to the running RAM test
- Supervisor stack moved to the top of 128 KiB RAM (`$40000`) to preserve both screens
- System-ROM variant without redistributing protected content:
  - accepts user-supplied 48 KiB or 64 KiB binary dumps
  - converts big-endian words into a padded 64 KiB hexadecimal file
  - exposes the complete `$000000-$00FFFF` ROM window
  - excludes the generated file from Git
  - uses a separate build that refuses to start when the private ROM is absent
  - selects the Sinclair JS QDOS 1.10 ROM for the first hardware test
- Experimental microSD ROM loading:
  - standard FPGA Companion SPI protocol for Tang Nano 20K revisions 3921 and 3923, with revision-specific firmware
  - FAT/exFAT configuration served to the BL616 and automatic `QL.rom` mount
  - accepts 48 KiB or 64 KiB ROM files
  - copies to reserved SDRAM and verifies every word
  - holds the 68000 in reset until the complete ROM has passed verification
- Top-left status square: orange during the initial test, alternating green shades after every successful pass, red on failure; blue/cyan for system startup and IPC activity
- Mode 8 flash matching the ZX8301 principle: the F bit toggles a color latch, with the phase changing every 26 frames
- Native QL timing probe, inspired by the original `zx8301.v` PAL/NTSC timing, running in parallel and observable through an LED

### Source Layout

- `src/nanoql_top.sv`: Tang Nano 20K top-level
- `src/nanoql_hdmi.sv`: HDMI wrapper around the MiSTeryNano HDMI core
- `src/ql_video_test.sv`: demonstration HDMI timing and video front-end connection
- `src/ql_hdmi_window.sv`: integer scaling, centering, and 512x256 QL coordinates
- `src/ql_zx8301_lite.sv`: transitional ZX8301-inspired register/front-end module
- `src/ql_zx8302_lite.sv`: RTC, status/IRQ register, and level-2 VBlank interrupt
- `src/ql_zx8302_ipc.sv`: ZX8302 variant connected to the real 8049 IPC
- `src/ipc/ql_ipc_t48.sv`: QL serial interface and 8049 clock enable
- `src/ipc/t48/`: OpenCores 8049 core imported from the MiST QL core
- `src/ql_video_scanout.sv`: line-fetch sequencer, line buffer, and QL pixel decoder
- `src/ql_native_timing_probe.sv`: native QL timing probe, not yet used to generate HDMI
- `src/ql_test_pattern.sv`: QL mode 4 and mode 8 pattern generator used to initialize SDRAM
- `src/ql_sdram_memory.sv`: SDRAM initialization, verification, refresh, and video-read service
- `src/ql_cpu_bus_bridge.sv`: converts 68000 cycles into internal system-bus transactions
- `src/ql_memory_map.sv`: decodes ROM/SDRAM and the ZX8301 register at `0x018063`
- `src/ql_boot_rom.sv`: wrapper for the small diagnostic ROM executed by `fx68k`
- `src/rom/ql_diagnostic.s`: 68000 assembly source for the autonomous test
- `src/rom/ql_diagnostic_rom.vh`: generated Verilog image committed for direct Gowin builds
- `src/ql_system_rom.sv`: 64 KiB ROM initialized from the generated user file
- `src/ql_sd_boot_rom.sv`: selects the dynamic ROM stored in SDRAM
- `src/companion/`: Companion SPI transport, microSD access, ROM loader, and menu configuration
- `src/companion/ql_companion_hid.sv`: Companion HID decoding and QL keyboard matrix
- `src/ql_cpu_fx68k.sv`: clock, reset, and bus wrapper around the 68000 core
- `src/ql_cpu_boot_monitor.sv`: validates the `mc_stat` write and detects program signatures
- `src/fx68k/`: cycle-exact 68000 core, microcode, documentation, and GPLv3 license imported from MiSTeryNano
- `src/sdram/sdram.v`: Tang Nano 20K SDRAM controller imported from MiSTeryNano under GPLv3
- `build_common.tcl`: source list and Gowin options shared by all builds
- `build_system_rom.tcl`: experimental private system-ROM build
- `build_sd_rom.tcl`: build loading the QL ROM from microSD
- `tools/prepare_ql_rom.ps1`: validates and converts the user's binary dump
- `tools/prepare_ql_ipc_rom.ps1`: validates and converts the private IPC Intel HEX firmware
- `tools/build_diagnostic_rom.ps1`: optionally rebuilds the diagnostic image with `vasmm68k_mot`
- `tools/prepare_sd_card.ps1`: validates the ROM and creates `QL.rom` with its `nanoql.ini` auto-mount file
- `tools/build_companion_config.ps1`: compresses the Companion XML configuration
- `tools/prepare_bl616_firmware.ps1`: verified BL616 firmware and flasher preparation
- `tools/prepare_bl616_firmware.py`: equivalent cross-platform Python 3 preparation
- `tools/nanoql_setup.py`: Tkinter assistant for NanoQL preparation, building, and programming
- `tools/prepare_sd_card.py`: prepares `QL.rom` and `nanoql.ini` on Windows, macOS, or Linux
- `tools/prepare_ql_rom.py`: cross-platform local QL ROM conversion
- `tools/prepare_ql_ipc_rom.py`: cross-platform Intel HEX IPC firmware conversion

### LED Indicators

- LED 0: FPGA core heartbeat
- LED 1: 68000 diagnostic passed, or first IPC transaction completed in the system variant
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

After programming, the second screen's test image must remain stable in mode 8 and LED 4 must be active. The square stays orange during SDRAM initialization and the first pass, then alternates between two subtle green shades after every successful write/readback of the 48 KiB area. A red square or LED 2 indicates a RAM mismatch, SDRAM error, or video underflow. Leaving this bitstream running for several hours provides an initial autonomous CPU/SDRAM/video burn-in.

The generated image is already included. To rebuild it after editing the assembly source, install `vasmm68k_mot`, then run:

```powershell
.\tools\build_diagnostic_rom.ps1 -VasmPath <path-to-vasmm68k_mot.exe>
gw_sh build.tcl
```

#### Experimental System-ROM Variant

The first selected ROM is **Sinclair JS, QDOS 1.10**, available from [Dilwyn Jones's QL ROM page](https://sinclairql.net/djw/qlrom/index.html). It is a standard Sinclair ROM rather than a keyboard-specific or modified variant, making it the most neutral basis for the first boot. That page states these ROMs are available for use in Europe; nevertheless, check your rights in your jurisdiction.

The public Git repository neither contains nor automatically downloads the QL ROM or the 8049 IPC firmware. Private files may be kept under the Git-ignored `private/roms/` directory. SHA-256 of the JS ROM used for this milestone: `FC6A683E44570D7E4A144580729E25FF4B3BD293A9EFF5313CFDAE11520D5EFC`.

```powershell
.\tools\prepare_ql_rom.ps1 -InputPath <path-to-your-rom.bin>
.\tools\prepare_ql_ipc_rom.ps1 -InputPath <path-to-your-ipc-firmware.hex>
gw_sh build_system_rom.tcl
```

The QL converter accepts exactly 49,152 or 65,536 bytes. A 48 KiB ROM is padded with `0xFF` to 64 KiB. The IPC converter accepts a complete 2 KiB Intel HEX image. The generated `src/rom/ql_system_rom.hex` and `src/ipc/ql_ipc_rom.hex` files are ignored by Git. The experimental bitstream is `impl\pnr\NanoQL_system_rom.fs`.

In this variant, the status square turns blue after SDRAM initialization, then cyan after the first complete transaction between JS and the IPC. A USB keyboard connected to the BL616 can now answer the `F1` or `F2` prompt and operate QDOS.

#### microSD / BL616 ROM Variant

This variant targets the on-board BL616 of Tang Nano 20K **revisions 3921 and 3923**. The graphical assistant is the recommended method:

```sh
python tools/nanoql_setup.py
```

Select the revision printed on the board and either normal or test mode in the `BL616 Companion` tab. The command-line method remains available on Windows:

```powershell
.\tools\prepare_bl616_firmware.ps1 -Launch
```

Equivalent preparation with Python 3 is available on every platform; select the matching board revision:

```sh
python3 tools/prepare_bl616_firmware.py --revision 3923
```

On Windows, append `--launch` to open FlashCube. PowerShell Core can run on macOS, but it does not make the Windows FlashCube executable compatible. On macOS and Linux, the Python script prepares and verifies the complete package; native command-line flashing remains separate until the two-segment BL616 write has been validated on hardware.

The script downloads FPGA Companion `v1.4.22` and BouffaloLabFlashCube from their official URLs, verifies every SHA-256 hash, and caches downloads under the Git-ignored `private/bl616/` directory. It generates `1_NORMAL_3921_partner_auto.ini`, `2_TEST_3921_companion_only.ini`, `1_NORMAL_3923_partner_auto.ini`, and `2_TEST_3923_companion_only.ini`. Generic `nano20k` images target the revision-3921 BL616 pinout; `nano20k_v3923` images target the revised 3923 pinout. Then hold `UPDATE`, connect USB-C to the PC, release `UPDATE`, refresh COM ports, select the new port, and click `Download`. Also see the [FPGA Companion procedure](https://github.com/MiSTle-Dev/.github/wiki/Firmware-Installation-BL616-%C2%B5C), [Tang Nano 20K versions](https://github.com/MiSTle-Dev/.github/wiki/Versions_TangNano20k), and [Sipeed documentation](https://en.wiki.sipeed.com/hardware/en/tang/common-doc/update_debugger.html).

The normal configuration retains the Gowin programmer and places Companion in the second stage. Test mode starts Companion even while a PC is attached, but temporarily replaces the Gowin programmer. The `UPDATE` button remains available; flashing the matching `1_NORMAL` configuration restores the standard Partner setup.

With the standard two-stage firmware, a USB data connection to a PC boots the BL616 as the programmer, not as Companion. To start Companion, first program the NanoQL bitstream into **FPGA Flash**, rather than SRAM only, then power-cycle the board from USB power without a data host, such as a USB charger. The `2_TEST_<revision>_companion_only.ini` variant is useful for diagnosis but disables the integrated programmer until the matching normal configuration is restored.

Prepare a FAT32 or exFAT microSD card and build:

```powershell
.\tools\prepare_sd_card.ps1 -RomPath <path-to-your-rom.bin> -Destination <microSD-root>
.\tools\prepare_ql_ipc_rom.ps1 -InputPath <path-to-your-ipc-firmware.hex>
gw_sh build_sd_rom.tcl
```

On macOS or Linux, prepare the ROM without PowerShell:

```sh
python3 tools/prepare_sd_card.py /path/to/js.rom /Volumes/CARD_NAME
python3 tools/prepare_ql_ipc_rom.py /path/to/ipc8049.hex
```

The card root must contain `QL.rom` and `nanoql.ini`. The latter contains `drive0 = /sd/QL.rom`, because the XML `default` attribute configures the selector but does not mount the file by itself. The resulting bitstream is `impl\pnr\NanoQL_sd_rom.fs`. During startup, two rows of eight black-and-white cells are shown. The top row fills from left to right for SDRAM, SPI, valid Companion bytes, SYS start, STATUS, XML configuration, SDC access, and loader start. The lower row shows progress while all 128 ROM sectors are copied and verified. A full-screen black-and-white checkerboard indicates failure. The display disappears as soon as the 68000 executes the ROM.

In Gowin EDA, **Use JTAG as regular IO must remain unselected**. NanoQL also enforces this in `build_common.tcl`; the generated bitstream contains `JTAGAsRegularIO: OFF`. Reusing JTAG as GPIO would break the expected BL616 programmer path and provides no benefit to NanoQL.

### Synthesis Statistics

These statistics are updated after every compiled milestone. They come from Gowin V1.9.11.03 Education place-and-route reports for the GW2AR-LV18QN88C8/I7.

| Resource | Diagnostic `NanoQL` | Local ROM + IPC | microSD ROM + IPC | Available |
|---|---:|---:|---:|---:|
| Logic | 8,353 (41%) | 8,877 (43%) | 9,633 (47%) | 20,736 |
| LUT only | 7,943 | 8,448 | 9,096 | - |
| ALU | 404 | 423 | 483 | - |
| Registers | 3,444 (22%) | 3,689 (24%) | 3,957 (25%) | 15,915 |
| CLS | 5,169 (50%) | 5,555 (54%) | 6,056 (59%) | 10,368 |
| BSRAM | 7 (16%) | 43 (94%) | 12 (27%) | 46 |
| I/O ports | 26 (40%) | 26 (40%) | 26 (40%) | 66 |
| IOLOGIC | 6 (5%) | 6 (5%) | 6 (5%) | 121 |
| PRIMARY networks | 5 (63%) | 5 (63%) | 5 (63%) | 8 |
| Local LW networks | 8 (100%) | 8 (100%) | 8 (100%) | 8 |
| CLKDIV | 1 (13%) | 1 (13%) | 1 (13%) | 8 |
| rPLL | 1 (50%) | 1 (50%) | 1 (50%) | 2 |

Main clock: 31.800 MHz required. Post-place-and-route Fmax is 58.660 MHz (diagnostic), 60.646 MHz (local ROM), and 60.660 MHz (microSD). No setup endpoint violation is reported. The local-ROM build uses 94% of BSRAM; the recommended microSD build reduces this to 27% by storing the system ROM in SDRAM.

### USB Keyboard And Planned Expansion

Companion now handles USB keyboards and the filesystem. The BL616 firmware permits up to two external USB hubs. To connect a keyboard through the Tang USB-C connector, use a **powered USB OTG hub or adapter**: the Tang must act as USB host while receiving power. With `partner auto` firmware, do not attach the hub upstream port to a PC, or the BL616 will boot into programmer mode. Mouse, joystick, visible OSD, and software-selection support remain to be connected to the QL core.

The on-board BL616 does not expose enough free GPIOs for a custom key matrix or several physical DB9 ports. Those future physical inputs will therefore be scanned by the FPGA or a small external expander, then exposed through the Companion SPI interface. A two-signal PS/2 option also remains possible.

Hardware preference order:

1. **Tang Nano 20K on-board BL616**: preferred on board revisions compatible with the `bl616_fpga_partner` firmware and FPGA Companion. It consumes no header pins and keeps the Tang microSD slot. It requires a careful BL616 firmware update and a USB OTG adapter or hub for peripherals. The microSD slot remains physically driven by the FPGA; the Companion exchanges sectors over SPI and manages the filesystem.
2. **Ai-Thinker Ai-M62-12F-Kit**: inexpensive external BL616 alternative in a DIP-30, dual 2.54 mm header format. It needs a dedicated firmware target, but the port is small because the processor and CherryUSB stack are identical. Proposed SPI mapping: `GPIO0=CS`, `GPIO1=SCK`, `GPIO30=MISO`, `GPIO27=MOSI`, `GPIO28=IRQ`. The M0S Dock's `GPIO13` is not exposed by this kit.
3. **Raspberry Pi Pico/RP2040**: the most durable and best-documented fallback. FPGA Companion already supports it, but USB host uses two GPIO through PIO-USB and requires a USB-A connector with 5 V power on the carrier PCB.

The Ai-M62 exposes `USB_DP` and `USB_DM` on its headers. A final carrier should route them to a USB-A host connector, provide protected 5 V VBUS, and prevent two USB power sources from being connected at once. The kit's USB-C connector remains primarily useful for flashing and debugging.

Planned architecture, based on MiSTeryNano and FPGA Companion:

- 1 KiB monochrome 128x64 overlay mixed into the video stream;
- dedicated Menu key intercepted before the QL matrix, like F12 in MiSTeryNano;
- FAT/exFAT filesystem handled by the Companion microcontroller;
- selection of a 48 or 64 KiB QL ROM from microSD;
- ROM transfer and validation in a reserved SDRAM area before releasing 68000 reset;
- persistent settings and future disk-image or software selectors.

All GPIO interfacing must use 3.3 V logic. Joystick connectors require 3.3 V pull-ups and suitable input protection.

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
17. Add ZX8302-lite, read `$18020`, provide a provisional RTC, and generate a level-2 VBlank interrupt.
18. Validate autovectoring, `STOP`, `$18021` acknowledge, and `RTE`.
19. Add local conversion, Git exclusion, and a separate build for a user-supplied system ROM.
20. Integrate the `t48` 8049 IPC core and validate JS startup on hardware.
21. Add centered, uncropped 1x2 integer scaling inside a CEA VIC 18 signal.
22. Run an autonomous CPU/SDRAM/video burn-in with changing RAM patterns and continuous integrity checks.
23. Move SDRAM arbitration closer to the original QL video/CPU slots and `DTACK` delays.
24. Integrate FPGA Companion SPI transport and verified microSD-to-SDRAM ROM loading. Validated on hardware.
25. Add the visible OSD overlay and interactive file selection.
26. Add USB keyboard transport to the real 8049 IPC matrix. Current step, ready for hardware validation.
27. Add mouse, joysticks, and disk images.

### License

NanoQL is distributed under GNU GPL version 3. See `LICENSE`. The `src/fx68k/` directory retains the documentation and license for Jorge Cwik's core. The SDRAM controller and Companion modules imported from MiSTeryNano retain their GPLv3 notices. Files under `src/ipc/t48/` retain the OpenCores core's BSD license headers.

### Upstream References

- [MiSTeryNano](https://github.com/MiSTle-Dev/MiSTeryNano): Tang Nano 20K HDMI, PLL, constraints, and Companion modules
- [FPGA Companion](https://github.com/MiSTle-Dev/FPGA-Companion): BL616 firmware, SPI protocol, and filesystem
- [mist-devel/ql](https://github.com/mist-devel/ql): Sinclair QL / ZX8301 video reference
