# NanoQL Link v1

## Français

NanoQL Link est l'interface de développement direct du core. Elle permet d'arrêter le fx68k, d'écrire un programme dans les 128 Kio de RAM du QL, puis de le démarrer avec un pointeur de pile et un compteur ordinal choisis par le développeur. Ce premier mode est volontairement bare-metal : il ne dépend ni de SuperBASIC, ni des microdrives, ni des structures internes d'une version particulière de QDOS.

Le transport suit ce chemin : PC en USB CDC, BL616, SPI interne cible 4, arbitre SDRAM, puis fx68k. Le firmware BL616 unifié démarre normalement en mode USB hôte pour le clavier. Un appui sur S1 après la configuration du FPGA, y compris lorsque QDOS fonctionne déjà, déconnecte le clavier USB hôte et fait apparaître le port série `NanoQL Link`. Le FPGA, QDOS, la SDRAM, la microSD et l'overlay ne sont pas réinitialisés. La tâche Companion continue de servir la microSD et les images QL-SD avec une priorité inférieure à NanoQL Link. Le clavier distant prend alors le relais.

S1 est aussi la broche MODE0 du FPGA Gowin. Ne le maintenez pas pendant la mise sous tension. Appuyez brièvement sur S1 seulement après l'apparition de l'image HDMI ou l'allumage des LED NanoQL. S2 n'est pas utilisé par NanoQL Link.

Ce mode CDC n'est pas le périphérique double canal `SIPEED USB Debugger` du firmware FPGA Partner officiel et ne peut donc pas être utilisé directement par Gowin Programmer. Pour le développement courant, la commande `fpga` ci-dessous programme la SRAM du FPGA sans changer de firmware BL616. Gowin Programmer nécessite de restaurer temporairement le profil FPGA Partner officiel.

Carte mémoire v1 :

- RAM accessible : `0x020000` à `0x03ffff`.
- Adresse de chargement conseillée : `0x030000`.
- Pile conseillée : `0x03fff0`.
- La mémoire écran QL commence à `0x020000`.
- Les adresses et les données suivent l'ordre big-endian du 68000.

Commandes SPI de la cible 4 :

- `00` : état et signature `NQL1`.
- `01` : arrêt et reset maintenu du 68000.
- `02 A2 A1 A0 LEN DATA...` : écriture de 1 à 8 octets.
- `03 SSP[31:0] PC[31:0]` : installation des vecteurs et exécution.
- `04` : désactivation des vecteurs injectés et redémarrage de QDOS.
- `05 KEY` : événement clavier HID distant.
- `06 A2 A1 A0 LEN` : demande de lecture de 1 à 8 octets.
- `07` : récupération du résultat de lecture.

Le script PC est `tools/nanoql_link.py`. Le firmware unifié est construit à partir des sources de `firmware/bl616/nanoql_companion` pour les révisions 3921 et 3923.

### Premier essai matériel

1. Flashez une fois le firmware BL616 NanoQL unifié correspondant à la révision de la carte.
2. Démarrez normalement NanoQL et attendez QDOS.
3. Reliez l'USB-C de la carte au PC avec un câble de données, attendez le démarrage du FPGA, puis appuyez brièvement sur S1.
4. Attendez l'apparition du port série `NanoQL Link`, puis exécutez `python tools/nanoql_link.py --port COMx status`.
5. Utilisez `python tools/nanoql_link.py --port COMx keyboard` pour le clavier distant ou `python tools/nanoql_link.py --port COMx demo` pour la mire bare-metal. Le profil QL est choisi automatiquement d'après la disposition Windows ; `--ql-layout fr` et `--ql-layout uk` permettent de le forcer. Le clavier distant traduit les caractères vers la disposition de la ROM choisie et maintient les touches dans la matrice QL jusqu'à leur relâchement, ce qui permet les jeux et les appuis simultanés.

La démo arrête QDOS, charge un court programme 68000 à `0x030000`, écrit une seule fois une bande verte de 32 lignes au centre de la VRAM, puis s'arrête sur une boucle locale. Elle évite ainsi de saturer l'arbitre SDRAM pendant le balayage HDMI. Utilisez `python tools/nanoql_link.py --port COMx qdos` pour quitter le programme injecté et redémarrer QDOS. Un redémarrage électrique restaure le mode USB hôte normal.

La commande `python tools/nanoql_link.py --port COMx cpu-status` affiche le mode CPU actif et mesure sa fréquence effective. Pour vérifier la stabilité USB sans modifier l'état du QL, exécutez `python tools/nanoql_link.py --port COMx link-stress` ; le test dure 30 secondes par défaut.

### Utiliser un dossier comme Microdrive

Le chemin recommandé ne nécessite ni NanoQL Link ni connexion au PC. Sur la microSD, créez un sous-dossier par cartouche dans `NanoQL/Microdrives`, par exemple `NanoQL/Microdrives/Benchmark`, puis placez-y les fichiers QL. Dans l'overlay `F12`, choisissez **Build MDV1 from:** puis `Benchmark`. Le BL616 convertit récursivement ce dossier en image QLAY, monte celle-ci comme `mdv1_` pour la session en cours et redémarre uniquement le QL.

Les sous-dossiers sont aplatis avec `_` ; `tests/README.md` devient `tests_README_md`. Les noms résultants doivent utiliser des caractères ASCII et tenir sur 36 caractères. La conversion accepte au plus 126 fichiers et huit niveaux de sous-dossiers. Une image QLAY mesure toujours 174 930 octets, mais 253 secteurs de 512 octets seulement sont allouables aux en-têtes et aux données. La condition exacte est `ceil((nombre_fichiers + 1) × 64 / 512) + somme(ceil((taille_fichier + 64) / 512)) <= 253` ; un fichier unique peut donc contenir au plus 128 960 octets. À l'invite QDOS, utilisez `DIR mdv1_`, puis par exemple `LRUN mdv1_programme_bas`.

Les commandes matérielles `WRITE` et `ERASE` du ZX8302 sont prises en charge. Les secteurs modifiés par QDOS sont réécrits dans `NanoQL/Drive1/MDV1.mdv` sur la microSD ; `SAVE`, la relecture et la persistance après reset sont validés physiquement. Le dossier source n'est pas un partage dynamique et n'est pas modifié. Ne relancez donc pas **Build MDV1 from:** après une sauvegarde importante, car la reconstruction remplace l'image et ses modifications.

Pour tester l'écriture depuis SuperBASIC, montez d'abord une cartouche créée avec **Build MDV1 from:**, puis saisissez :

```text
100 PRINT "NANOQL MICRODRIVE WRITE OK"
110 PRINT 2+2
SAVE mdv1_write_test_bas
DIR mdv1_
NEW
LRUN mdv1_write_test_bas
```

Le programme doit afficher le texte puis `4`. Après un reset QL, `DIR mdv1_` et `LRUN mdv1_write_test_bas` doivent toujours fonctionner. Après une coupure complète, sélectionnez manuellement `NanoQL/Drive1/MDV1.mdv` dans **Microdrive 1:** avant de refaire le test de lecture, car l'image générée n'est pas remontée automatiquement au démarrage.

### Gérer les fichiers de la microSD en mode développeur

Le dossier utilisateur est `NanoQL/Drive1` sur la microSD. Il est créé automatiquement par l'outil de préparation et peut être rempli directement depuis Windows, Linux ou macOS. En mode NanoQL Link, les mêmes fichiers sont accessibles sans retirer la carte :

```text
python tools/nanoql_link.py --port COMx sd-list
python tools/nanoql_link.py --port COMx sd-put programme_bin
python tools/nanoql_link.py --port COMx sd-get programme_bin
python tools/nanoql_link.py --port COMx sd-mkdir demos
python tools/nanoql_link.py --port COMx sd-delete ancien_bin --yes
```

`sd-put` accepte un second argument pour choisir un chemin relatif, par exemple `sd-put programme_bin demos/programme_bin`. Le firmware limite toutes les opérations à `NanoQL/Drive1`. Un upload est d'abord écrit dans un fichier temporaire, vérifié par sa taille et son CRC32, puis renommé.

Pour synchroniser directement un dossier du PC sans retirer la carte, utilisez la commande développeur :

```text
python tools/nanoql_link.py --port COMx mdv-sync chemin/vers/dossier --name NANOQL
```

Cette commande de développement expérimentale convertit récursivement le dossier en cartouche QLAY, démonte l'ancienne image, envoie `MDV1.mdv`, la remonte pour la session en cours, puis redémarre uniquement le QL. Elle ne maintient plus le QL en reset pendant le transfert, afin qu'une interruption USB ne puisse pas bloquer la carte. Pour l'usage courant, préférez **Build MDV1 from:** dans l'overlay, qui ne dépend pas du PC ni du transport USB CDC.

Le dossier du PC n'est pas un partage en temps réel : relancez `mdv-sync` après chaque modification. La commande avancée `sd-build-mdv` reste disponible pour reconstruire une image à partir des fichiers déjà présents dans `NanoQL/Drive1`.

Pour extraire les fichiers d'une image QLAY locale, sans carte ni port COM :

```text
python tools/nanoql_link.py mdv-extract MDV1.mdv MDV1_files
```

Pour télécharger puis extraire une image située dans `NanoQL/Drive1` :

```text
python tools/nanoql_link.py --port COMx mdv-extract MDV1.mdv MDV1_files --remote
```

Les octets des fichiers QDOS sont conservés tels quels. `nanoql_manifest.json` mémorise également leurs noms QDOS, leur type exécutable et leur taille de dataspace.

### Charger un programme SuperBASIC

Placez le QL à l'invite SuperBASIC, activez NanoQL Link avec S1, puis chargez n'importe quel fichier texte dont chaque ligne commence par un numéro :

```text
python tools/nanoql_link.py --port COMx basic chemin/vers/programme_bas
```

Le script saisit `NEW`, transmet les lignes au clavier distant afin que QDOS les tokenise fidèlement dans sa propre RAM, puis saisit `RUN`. Ajoutez `--no-run` pour charger sans démarrer. Cette méthode ne dépend pas de la structure mémoire privée d'une ROM QDOS et ne nécessite encore ni Microdrive ni QL-SD.

Le benchmark QL de Lawrence Woodman est inclus sous licence MIT et dispose d'une commande expérimentale :

```text
python tools/nanoql_link.py --port COMx benchmark
```

Ses sept tests durent chacun 20 secondes. La saisie de longs listings par clavier distant reste un outil de développement ; préférez QL-SD pour transférer et exécuter des programmes de façon fiable.

Pour reconfigurer temporairement la SRAM du FPGA sans remplacer le firmware BL616, utilisez le fichier `.bin` produit par Gowin :

```text
python tools/nanoql_link.py --port COMx fpga impl/pnr/NanoQL_sd_rom.bin
```

Le bitstream passe directement de l'USB au moteur JTAG du BL616, sans fichier temporaire et sans écriture sur la microSD. Sa taille et son CRC sont vérifiés avant la finalisation du FPGA. Après l'accusé de réception, le BL616 redémarre automatiquement en mode Companion et le port COM disparaît. Cette commande est destinée aux essais de développement ; après une coupure d'alimentation, le bitstream conservé dans la Flash FPGA redémarre.

La programmation persistante ne passe pas par le moteur SPI expérimental du BL616. Restaurez temporairement le profil BL616 `ORIGINAL` correspondant à la révision de la carte, fermez Gowin Programmer s'il est ouvert, puis utilisez le fichier `.fs` validé :

```text
python tools/nanoql_link.py fpga-flash-native impl/pnr/NanoQL_sd_rom.fs --yes
```

Sous Windows, le script utilise Gowin Programmer et sélectionne par défaut `USB Debugger A/1`. L'option `--location` permet d'indiquer l'identifiant du câble si sa détection automatique échoue. Sous Linux et macOS, openFPGALoader est utilisé lorsqu'il est installé. Après la programmation, réinstallez le profil BL616 `NANOQL` pour retrouver le clavier USB, la microSD et NanoQL Link.

## English

NanoQL Link is the core's direct development interface. It can hold the fx68k in reset, write a program into the QL's 128 KiB RAM, and start it with developer-provided stack and program-counter values. This first mode is intentionally bare-metal and does not depend on SuperBASIC, microdrives, or private data structures from a particular QDOS release.

The transport path is PC USB CDC, BL616, internal SPI target 4, SDRAM arbiter, then fx68k. The unified BL616 firmware normally starts as a USB host for the keyboard. Pressing S1 after FPGA configuration, including while QDOS is already running, disconnects the USB-host keyboard and enumerates the `NanoQL Link` serial port. The FPGA, QDOS, SDRAM, microSD, and overlay are not reset. The Companion task continues serving the microSD and QL-SD images below NanoQL Link's priority. The remote keyboard can then take over.

S1 is also the Gowin FPGA MODE0 pin. Do not hold it while powering the board. Briefly press S1 only after the HDMI image appears or the NanoQL LEDs turn on. S2 is not used by NanoQL Link.

This CDC device is not the official FPGA Partner firmware's dual-channel `SIPEED USB Debugger`, so Gowin Programmer cannot use it directly. For normal development, the `fpga` command below programs FPGA SRAM without changing BL616 firmware. Gowin Programmer requires temporarily restoring the official FPGA Partner profile.

The PC utility is `tools/nanoql_link.py`. Unified firmware sources are in `firmware/bl616/nanoql_companion` and support board revisions 3921 and 3923.

Flash the matching unified BL616 firmware once, boot NanoQL normally, connect the board to the PC with a USB data cable, wait for FPGA startup, and briefly press S1. Once the `NanoQL Link` serial port appears, run `python tools/nanoql_link.py --port COMx status`, followed by either `keyboard` or `demo`. Keyboard mode automatically selects the QL layout from the active Windows layout; `--ql-layout fr` and `--ql-layout uk` override it. It translates printable characters for the selected ROM layout and holds every key in the QL matrix until release, allowing games and simultaneous inputs. The demo writes one central 32-line green band and then stops writing SDRAM. Use the `qdos` command to leave injected code and restart QDOS. A power cycle restores normal USB-host mode.

Run `python tools/nanoql_link.py --port COMx cpu-status` to display the selected CPU mode and measure its effective clock rate. The non-destructive `python tools/nanoql_link.py --port COMx link-stress` command checks USB stability for 30 seconds by default.

### Using a folder as a Microdrive

The recommended path requires neither NanoQL Link nor a PC connection. Create one cartridge subfolder under `NanoQL/Microdrives` on the microSD, for example `NanoQL/Microdrives/Benchmark`, and place the QL files inside it. In the `F12` overlay, select **Build MDV1 from:** and then `Benchmark`. The BL616 recursively converts that folder to a QLAY image, mounts it as `mdv1_` for the current session, and resets only the QL.

Subdirectories are flattened with `_`; for example, `tests/README.md` becomes `tests_README_md`. Resulting names must be ASCII and no longer than 36 characters. Conversion accepts up to 126 files and eight nested directory levels. A QLAY image is always 174,930 bytes, but only 253 512-byte sectors are allocatable to headers and data. The exact condition is `ceil((file_count + 1) × 64 / 512) + sum(ceil((file_size + 64) / 512)) <= 253`; a single file can therefore contain at most 128,960 bytes. At the QDOS prompt, enter `DIR mdv1_`, followed by a command such as `LRUN mdv1_program_bas`.

The ZX8302 hardware `WRITE` and `ERASE` commands are implemented. Sectors changed by QDOS are written back to `NanoQL/Drive1/MDV1.mdv`; `SAVE`, reload, and persistence across QL reset are physically validated. The source folder is not a live share and is not modified. Do not run **Build MDV1 from:** again after an important save, because rebuilding replaces the image and its changes.

To test writes from SuperBASIC, first mount a cartridge created with **Build MDV1 from:**, then enter:

```text
100 PRINT "NANOQL MICRODRIVE WRITE OK"
110 PRINT 2+2
SAVE mdv1_write_test_bas
DIR mdv1_
NEW
LRUN mdv1_write_test_bas
```

The program must print the message followed by `4`. After a QL reset, `DIR mdv1_` and `LRUN mdv1_write_test_bas` must still work. After a complete power cycle, manually select `NanoQL/Drive1/MDV1.mdv` under **Microdrive 1:** before repeating the read test, because the generated image is not automatically remounted during startup.

### Managing microSD files in development mode

The user folder is `NanoQL/Drive1` on the microSD. The preparation tool creates it automatically, and users can populate it directly from Windows, Linux, or macOS. NanoQL Link provides access without removing the card:

```text
python tools/nanoql_link.py --port COMx sd-list
python tools/nanoql_link.py --port COMx sd-put program_bin
python tools/nanoql_link.py --port COMx sd-get program_bin
python tools/nanoql_link.py --port COMx sd-mkdir demos
python tools/nanoql_link.py --port COMx sd-delete old_bin --yes
```

Pass a second argument to `sd-put` to select a relative destination such as `sd-put program_bin demos/program_bin`. The firmware confines every operation to `NanoQL/Drive1`. Uploads use a temporary file and are verified by size and CRC32 before the final rename.

To synchronize a PC folder directly without removing the card, use the developer command:

```text
python tools/nanoql_link.py --port COMx mdv-sync path/to/folder --name NANOQL
```

This experimental developer command recursively converts the folder to a QLAY cartridge, unmounts the previous image, uploads `MDV1.mdv`, mounts it for the current session, and resets only the QL. It no longer holds the QL in reset during transfer, so a USB interruption cannot leave the board blocked. For normal use, prefer **Build MDV1 from:** in the overlay; it does not depend on a PC or USB CDC.

This is a synchronization operation rather than a live PC share, so rerun `mdv-sync` after changing the source folder. The advanced `sd-build-mdv` command remains available to rebuild an image from files already stored under `NanoQL/Drive1`.

Extract files from a local QLAY image without a board or serial port:

```text
python tools/nanoql_link.py mdv-extract MDV1.mdv MDV1_files
```

Download and extract an image stored under `NanoQL/Drive1`:

```text
python tools/nanoql_link.py --port COMx mdv-extract MDV1.mdv MDV1_files --remote
```

QDOS file bytes are preserved exactly. `nanoql_manifest.json` also records their QDOS names, executable types, and dataspace sizes.

To load a numbered SuperBASIC text file, leave the QL at its SuperBASIC prompt and run `python tools/nanoql_link.py --port COMx basic path/to/program_bas`. NanoQL Link enters `NEW`, sends every source line through the remote keyboard so QDOS performs its own ROM-compatible tokenization, and then enters `RUN`. Add `--no-run` to load only. The included MIT-licensed benchmark has the experimental shortcut `python tools/nanoql_link.py --port COMx benchmark`. Remote typing is a development convenience; prefer QL-SD for reliable program transfer and execution.

The command `python tools/nanoql_link.py --port COMx fpga impl/pnr/NanoQL_sd_rom.bin` streams Gowin's `.bin` output directly from USB into FPGA SRAM through the BL616 JTAG engine, without writing the microSD. After acknowledging completion, the BL616 automatically restarts in Companion mode and the COM port disappears. It is temporary development programming; the FPGA Flash bitstream returns after power cycling.

Persistent programming does not use the experimental BL616 SPI engine. Temporarily restore the `ORIGINAL` BL616 profile for the board revision, close Gowin Programmer if it is open, and program the validated `.fs` file:

```text
python tools/nanoql_link.py fpga-flash-native impl/pnr/NanoQL_sd_rom.fs --yes
```

On Windows, the script uses Gowin Programmer and selects `USB Debugger A/1` by default. Use `--location` if automatic cable-location detection fails. On Linux and macOS, it uses openFPGALoader when installed. Reinstall the `NANOQL` BL616 profile afterward to restore the USB keyboard, microSD, and NanoQL Link.
