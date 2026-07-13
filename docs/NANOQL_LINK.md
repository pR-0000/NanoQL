# NanoQL Link v1

## Français

NanoQL Link est l'interface de développement direct du core. Elle permet d'arrêter le fx68k, d'écrire un programme dans les 128 Kio de RAM du QL, puis de le démarrer avec un pointeur de pile et un compteur ordinal choisis par le développeur. Ce premier mode est volontairement bare-metal : il ne dépend ni de SuperBASIC, ni des microdrives, ni des structures internes d'une version particulière de QDOS.

Le transport est le suivant : PC en USB CDC, BL616, SPI interne cible 4, arbitre SDRAM, puis fx68k. Le BL616 fonctionne alors comme périphérique USB et le clavier USB hôte n'est pas disponible pendant la session de développement. Un redémarrage en profil Companion normal restaure le clavier, la microSD et l'overlay.

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

Le script PC est `tools/nanoql_link.py`. Le firmware source dédié se trouve dans `firmware/bl616/nanoql_link`. Il est construit séparément pour les révisions 3921 et 3923 par le workflow `Build BL616 NanoQL Link`, sans publier de ROM ni de binaire dans l'historique Git.

### Premier essai matériel

1. Téléchargez l'artefact du workflow correspondant à la révision de la carte.
2. Préparez le paquet FlashCube en passant le binaire au script `prepare_bl616_firmware.py` avec `--link-3921` ou `--link-3923`.
3. Flashez le fichier `3_LINK_..._usb_cdc.ini` en maintenant `UPDATE` lors du branchement.
4. Programmez le bitstream NanoQL courant dans la mémoire Flash du FPGA avant d'activer le profil Link, car ce profil ne fournit pas le programmateur Gowin.
5. Rebranchez normalement la carte au PC. Un port série nommé `NanoQL Link` doit apparaître.
6. Exécutez `python tools/nanoql_link.py status`, puis `python tools/nanoql_link.py demo`.

La démo arrête QDOS, charge un court programme 68000 à `0x030000` et remplit la VRAM avec une mire. Pour revenir au démarrage QDOS sans reflasher le FPGA, utilisez `python tools/nanoql_link.py qdos`. Pour retrouver le clavier, la microSD et l'OSD, reflashez ensuite le profil BL616 `1_NORMAL`.

## English

NanoQL Link is the core's direct development interface. It can hold the fx68k in reset, write a program into the QL's 128 KiB RAM, and start it with developer-provided stack and program-counter values. This first mode is intentionally bare-metal and does not depend on SuperBASIC, microdrives, or private data structures from a particular QDOS release.

The transport path is PC USB CDC, BL616, internal SPI target 4, SDRAM arbiter, then fx68k. In this profile the BL616 is a USB device, so USB-host keyboard support is unavailable during the development session. Rebooting into the normal Companion profile restores keyboard, microSD, and overlay operation.

The PC utility is `tools/nanoql_link.py`. Its dedicated source firmware lives in `firmware/bl616/nanoql_link` and is built separately for board revisions 3921 and 3923 by the `Build BL616 NanoQL Link` workflow. Generated firmware, ROMs, and bitstreams are not committed.

Build or download the workflow artifact for the correct revision, add it to a FlashCube package with `prepare_bl616_firmware.py --link-3921` or `--link-3923`, and flash the generated `3_LINK_..._usb_cdc.ini`. The FPGA bitstream must already be stored in FPGA Flash. After reconnecting the board, run `python tools/nanoql_link.py status` and then `python tools/nanoql_link.py demo`. Reflash the BL616 `1_NORMAL` profile to restore keyboard, microSD, OSD, and the Gowin programmer.
