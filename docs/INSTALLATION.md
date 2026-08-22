# Installation de NanoQL / Installing NanoQL

## Français

### Matériel et fichiers

Matériel minimal :

- Tang Nano 20K révision 3921 ou 3923 ;
- carte microSD ;
- écran HDMI ;
- câble USB-C avec données.

Un clavier USB et un hub OTG sont facultatifs.

NanoQL ne distribue pas les ROM. Préparez :

- une ROM QL légale de 48 ou 64 Kio depuis une source telle que [l'archive des ROM QL](https://sinclairql.net/djw/qlrom/index.html) ;
- un firmware IPC de 2 Kio, standard ou [Hermes](http://firshman.co.uk/ql/hermes.htm) ;
- facultativement, une ROM QSound de 8 Kio depuis le [projet QSound/QPrint](https://github.com/alvaroalea/QL_QsoundQprint_clone/tree/main/ROM).

L'IPC peut être un fichier brut `.bin`/`.rom` de 2 048 octets, un fichier Intel HEX complet ou une liste textuelle de 2 048 octets hexadécimaux.

### Logiciels

Installez [Python 3](https://www.python.org/downloads/). Sous Windows, activez **Add Python to PATH**. L'installeur Python officiel pour macOS contient Tkinter. Avec Python installé par Homebrew, installez également la formule `python-tk` correspondant à sa version. Sous Debian/Ubuntu, installez aussi Tkinter :

```sh
sudo apt install python3 python3-tk
```

Pour une récupération JTAG, utilisez au choix :

- [openFPGALoader](https://trabucayre.github.io/openFPGALoader/guide/install.html) ;
- Gowin Programmer, inclus dans Gowin EDA.

L'installation et les mises à jour normales passent directement par NanoQL Link et ne nécessitent aucun de ces programmateurs. Gowin EDA reste nécessaire uniquement pour recompiler le cœur FPGA.

Le bouton **Install openFPGALoader** de l'assistant effectue directement l'installation avec Homebrew sous macOS. Il détecte `/opt/homebrew/bin` sur Apple Silicon et `/usr/local/bin` sur les Mac Intel, même lorsque l'assistant n'a pas hérité du `PATH` du Terminal.

Installation manuelle d'openFPGALoader :

```sh
# macOS
brew install openfpgaloader

# Debian/Ubuntu
sudo apt install openfpgaloader

# Arch Linux
sudo pacman -S openfpgaloader
```

Sous Windows, suivez le [guide officiel openFPGALoader](https://trabucayre.github.io/openFPGALoader/guide/install.html). La méthode MSYS2 utilise :

```sh
pacman -S mingw-w64-ucrt-x86_64-openFPGALoader
```

Le pilote FTDI installé par défaut ne permet pas à openFPGALoader d'ouvrir le JTAG. Dans l'onglet **3. FPGA**, cliquez une seule fois sur **Install Windows JTAG driver**. Dans Zadig, activez **Options > List All Devices**, choisissez uniquement **USB Serial Converter A** ou **Dual RS232-HS (Interface 0)**, vérifiez `0403:6010` et `MI_00`, sélectionnez **WinUSB**, puis remplacez le pilote. Ne modifiez jamais **Interface 1/B**, qui doit conserver son pilote série FTDI. Débranchez et rebranchez ensuite la Tang Nano.

### Assistant graphique

Depuis le dossier NanoQL :

```sh
python tools/nanoql_setup.pyw
```

Sous macOS/Linux, utilisez `python3` si nécessaire. L'assistant installe automatiquement PySerial, affiche les ports série dans des listes détaillées, vérifie les outils, prépare la microSD, programme le FPGA et prépare le firmware BL616.

Le sélecteur **Language** du premier onglet bascule immédiatement toute l'interface entre le français et l'anglais. Ce choix est mémorisé avec les autres réglages. Les illustrations intégrées montrent les boutons **UPDATE** et **S1** à utiliser ; aucun fichier image externe n'est requis.

Dans **Commencer**, sélectionnez une seule fois le dossier extrait `NanoQL-vX.Y.Z-Complete-3921` ou `NanoQL-vX.Y.Z-Complete-3923`. Après le choix de la révision de carte, l'assistant renseigne automatiquement le firmware BL616 `.bin` et le bitstream FPGA `.fs` dans leurs onglets respectifs. Les sélecteurs manuels de chaque onglet restent disponibles pour les utilisateurs avancés.

### Ordre de première installation

Respectez cet ordre pour une première installation :

1. Préparez la microSD dans **1. ROMs and microSD**.
2. Dans **2. BL616**, installez le firmware **NanoQL** avec le bouton matériel **UPDATE**.
3. Dans **3. FPGA**, programmez le bitstream en Flash persistante via NanoQL Link. Si aucun core NanoQL valide n'est présent, le firmware BL616 ouvre automatiquement son port de récupération.
4. Insérez la microSD et redémarrez la carte.

Le firmware BL616 NanoQL fournit le clavier USB, la microSD, l'overlay, NanoQL Link et la programmation directe de la SRAM ou de la Flash FPGA. Le firmware Sipeed d'origine et son JTAG externe restent disponibles comme solution de récupération.

### Préparer la microSD

Dans **1. ROMs and microSD** :

1. choisissez d'abord la racine de la microSD ;
2. choisissez la ROM QL ;
3. choisissez un seul firmware IPC, soit l'original, soit Hermes ;
4. ajoutez éventuellement QSound ;
5. cliquez sur **Prepare microSD**.

Les noms `QL.rom`, `IPC.rom` et `QSound.rom` sont de simples valeurs par défaut. Vous pouvez copier d'autres ROM directement sur la carte et les choisir avec l'overlay `F12`.

Le format recommandé est une partition unique **FAT32 avec une table de partitions MBR**. Sous macOS, choisissez **MS-DOS (FAT)** et **Master Boot Record** dans Utilitaire de disque. exFAT reste pris en charge et est pratique pour les cartes de plus de 32 Go. La compatibilité dépend toutefois du contrôleur interne de la microSD, pas seulement de sa capacité, de sa classe, de sa marque ou du système de fichiers. Une carte correctement formatée peut néanmoins bloquer lors d'une écriture. Si la sauvegarde des réglages, la création d'un Microdrive ou un transfert NanoQL Link se fige, essayez une autre carte avant de reflasher NanoQL.

### Programmer le FPGA

Pour une mise à jour normale, laissez le firmware BL616 **NanoQL** installé :

1. démarrez NanoQL et attendez l'image HDMI ou les LED ;
2. appuyez brièvement une fois sur **S1**, sans le maintenir au démarrage ;
3. dans **3. FPGA**, vérifiez le fichier `.fs` renseigné automatiquement depuis le dossier choisi dans **Commencer** ; vous pouvez aussi le remplacer manuellement ;
4. choisissez le port **NanoQL Link** ;
5. cliquez sur **Programmer la Flash (permanente)**, ou sur **Programmer la SRAM (temporaire)** pour un essai qui disparaîtra à la prochaine coupure d'alimentation.

La programmation permanente efface, écrit et vérifie la Flash de configuration, puis redémarre NanoQL. Ne débranchez ni l'USB ni l'alimentation pendant cette opération. Le bouton **Détecter la Flash de configuration** est une vérification facultative sans écriture. Un fichier `.fs` peut aussi être choisi directement : NanoQL Link le valide et le convertit sans Gowin EDA. Les firmwares `BL616-3921.bin` et `BL616-3923.bin` sont refusés dans cet onglet.

Pour une récupération, utilisez la section **JTAG externe** du même onglet avec le firmware BL616 **Sipeed d'origine**. L'assistant peut alors appeler openFPGALoader 1.1.1 ou plus récent, ou Gowin Programmer sous Windows. Avec le profil Sipeed actif, l'écran peut afficher `BL616 COMPANION NOT READY` : c'est normal, car le BL616 expose alors le JTAG au PC.

```sh
openFPGALoader -b tangnano20k -f /chemin/vers/NanoQL-vX.Y.Z-FPGA.fs
```

Avec Gowin Programmer, utilisez `USB Debugger A/1`, **External Flash Mode**, une opération d'effacement/programmation et **Generic Flash**.

Dans Gowin EDA, laissez **Use JTAG as regular IO** décoché.

### Programmer le BL616

Lors de la première installation, effectuez cette opération avant le FPGA. Dans **2. BL616** :

1. reliez la Tang Nano 20K à l'ordinateur avec un câble USB-C de données ; cette étape programme le BL616 par USB ;
2. sélectionnez la révision 3921 ou 3923 ;
3. vérifiez que le champ **Firmware BL616 NanoQL** contient le `.bin` détecté dans le dossier de release ;
4. débranchez la carte ;
5. maintenez **UPDATE**, reconnectez l'USB puis relâchez **UPDATE** ;
6. cliquez sur **Actualiser**, puis choisissez le nouveau port série du bootloader ;
7. cliquez sur **Installer / mettre à jour le firmware NanoQL**.

Le second bouton, **Restaurer le firmware Sipeed d'origine**, sert uniquement à une récupération ou à l'utilisation d'un programmateur JTAG externe. Dans les deux cas, **UPDATE** désigne le bouton matériel du BL616 ; **S1** n'est pas utilisé pour flasher le BL616.

L'assistant installe automatiquement `bflb-mcu-tool-uart`, l'outil UART multiplateforme de Bouffalo Lab. Avec Python 3.13 ou plus récent, il installe aussi le module de compatibilité requis depuis la suppression de `telnetlib`. macOS utilise 230400 bauds ; Windows et Linux utilisent 2000000 bauds avec de petits blocs acquittés pour fiabiliser l'USB. Une tentative interrompue impose de débrancher la carte et de rentrer de nouveau dans le mode UPDATE avant de recommencer. Commande équivalente :

```sh
python3 tools/prepare_bl616_firmware.py --revision 3923 --profile nanoql --flash --port PORT --yes
```

Remplacez `PORT` par `COMx`, `/dev/ttyACMx`, `/dev/ttyUSBx`, `/dev/cu.usbmodem*` ou `/dev/cu.usbserial*`. Utilisez `3921` pour cette révision. Cette méthode doit encore être validée physiquement sur chaque OS. FlashCube reste disponible comme solution de récupération sous Windows.

### Mettre NanoQL à jour

Dans **Commencer**, choisissez **Mettre NanoQL à jour**. Le parcours normal ne remplace plus le firmware BL616 deux fois :

1. mettez à jour le firmware BL616 NanoQL depuis **2. BL616** avec **UPDATE** ;
2. démarrez NanoQL, appuyez brièvement sur **S1**, puis programmez le nouveau bitstream FPGA depuis **3. FPGA**.

La microSD et ses réglages sont conservés. Si NanoQL Link est inaccessible ou si la Flash FPGA est endommagée, restaurez le firmware Sipeed avec **UPDATE**, puis utilisez le JTAG externe :

```sh
python3 tools/prepare_bl616_firmware.py --revision 3923 --profile original --flash --port PORT --yes
```

Commande directe équivalente pour une mise à jour permanente :

```sh
python3 tools/nanoql_link.py --port PORT fpga-flash path/to/extracted-release-folder --yes
```

Remplacez `fpga-flash` par `fpga` pour programmer uniquement la SRAM.

### Premier démarrage

1. Éteignez la carte.
2. Insérez la microSD.
3. Branchez HDMI.
4. Alimentez par USB-C.
5. Si NanoQL demande des ROM, ouvrez `F12`, choisissez **QL ROM** et **IPC ROM**, puis redémarrez le QL.

Le QL doit démarrer sans clavier ni hub. Pour le développement, connectez la carte à l'ordinateur, attendez le démarrage du FPGA, appuyez brièvement sur S1 et utilisez **4. NanoQL Link > Connexion et clavier distant**. Le clavier distant fonctionne sous Windows, macOS et Linux. Sur macOS/Linux, le script installe automatiquement `pynput` lors de la première utilisation. macOS peut demander d'autoriser Terminal ou Python dans **Réglages Système > Confidentialité et sécurité > Surveillance de l'entrée** et **Accessibilité**. Si la console affiche `This process is not trusted`, ajoutez également l'exécutable Python réellement affiché par la commande, par exemple celui du dossier `venv/bin`, puis quittez complètement et relancez Terminal. Sur macOS, l'interception Quartz autorisée empêche les touches et séquences de contrôle de s'afficher dans Terminal. Les événements en attente sont vidés avant de rendre la main avec `F6`.

NanoQL propose six profils vidéo dans `Display > Video mode`. Les profils 50 Hz utilisent le VIC CEA 19 et conservent la cadence PAL native du QL. Les profils 60 Hz utilisent le VIC CEA 4 pour les moniteurs qui refusent le 50 Hz ; la VRAM QL reste mise à jour à 50 Hz, ce qui produit une répétition périodique perceptible dans les mouvements. `Sharp` affiche 1024×698 et double exactement chaque colonne QL, `Large` utilise 844×576, tandis que `Fit` utilise 990×675 avec une marge de sécurité contre l'overscan parfois appliqué par les modes TV 16:9. Les trois profils sont centrés et reproduisent le rapport historique approximatif de 4,4:3 des pixels non carrés du QL.

Les deux cadences émettent un véritable flux HDMI à 74,25 MHz avec AVI InfoFrame 16:9. Si un moniteur ancien grise son réglage d'aspect ou déforme le 720p50, essayez d'abord `60 Hz Large`. Pour des pixels fidèles, désactivez l'overscan, la réduction de bruit, l'interpolation de mouvement et les renforcements de netteté.

Dans l'overlay, `USB layout` concerne exclusivement le clavier USB local connecté au BL616 ; `QL ROM layout` sélectionne la table attendue par la ROM. Le clavier distant de l'onglet **4. Remote keyboard** est traduit en caractères par Windows, macOS ou Linux, ignore `USB layout` et utilise un état de matrice indépendant du clavier USB.

## English

### Hardware and files

Minimal hardware:

- revision 3921 or 3923 Tang Nano 20K;
- microSD card;
- HDMI display;
- data-capable USB-C cable.

A USB keyboard and OTG hub are optional.

NanoQL does not distribute ROMs. Prepare:

- a legally obtained 48 or 64 KiB QL ROM from a source such as the [QL ROM archive](https://sinclairql.net/djw/qlrom/index.html);
- a 2 KiB standard IPC firmware or [Hermes](http://firshman.co.uk/ql/hermes.htm);
- optionally, an 8 KiB QSound ROM from the [QSound/QPrint project](https://github.com/alvaroalea/QL_QsoundQprint_clone/tree/main/ROM).

IPC firmware may be a raw 2,048-byte `.bin`/`.rom`, complete Intel HEX, or a text list containing 2,048 hexadecimal bytes.

### Software

Install [Python 3](https://www.python.org/downloads/). Enable **Add Python to PATH** on Windows. The official Python macOS installer includes Tkinter. If Python came from Homebrew, also install the matching `python-tk` formula. On Debian/Ubuntu, install Tkinter too:

```sh
sudo apt install python3 python3-tk
```

For JTAG recovery, use either:

- [openFPGALoader](https://trabucayre.github.io/openFPGALoader/guide/install.html);
- Gowin Programmer, included with Gowin EDA.

Normal installation and updates go directly through NanoQL Link and require neither programmer. Gowin EDA is only required to compile the FPGA core.

The assistant's **Install openFPGALoader** button installs it directly through Homebrew on macOS. It checks `/opt/homebrew/bin` on Apple Silicon and `/usr/local/bin` on Intel Macs even when the GUI did not inherit Terminal's `PATH`.

Manual openFPGALoader installation:

```sh
# macOS
brew install openfpgaloader

# Debian/Ubuntu
sudo apt install openfpgaloader

# Arch Linux
sudo pacman -S openfpgaloader
```

On Windows, follow the [official openFPGALoader guide](https://trabucayre.github.io/openFPGALoader/guide/install.html). The MSYS2 route uses:

```sh
pacman -S mingw-w64-ucrt-x86_64-openFPGALoader
```

The default FTDI driver does not let openFPGALoader access JTAG. In **3. FPGA**, click **Install Windows JTAG driver** once. In Zadig, enable **Options > List All Devices**, select only **USB Serial Converter A** or **Dual RS232-HS (Interface 0)**, verify `0403:6010` and `MI_00`, select **WinUSB**, then replace the driver. Never modify **Interface 1/B**, which must keep its FTDI serial driver. Disconnect and reconnect the Tang Nano afterward.

### Graphical assistant

Run from the NanoQL directory:

```sh
python tools/nanoql_setup.pyw
```

Use `python3` on macOS/Linux when needed. The assistant installs PySerial automatically, presents detailed serial-port lists, checks tools, prepares the microSD, programs the FPGA, and prepares BL616 firmware.

The first tab's **Language** selector immediately switches the complete interface between English and French. The choice is stored with the other settings. Embedded illustrations identify the **UPDATE** and **S1** buttons; no external image file is required.

In **Start here**, select the extracted `NanoQL-vX.Y.Z-Complete-3921` or `NanoQL-vX.Y.Z-Complete-3923` folder once. After selecting the board revision, the assistant automatically fills the matching BL616 `.bin` and FPGA `.fs` fields in their respective tabs. Independent manual selectors remain available for advanced users.

### First-install order

Follow this order for first installation:

1. Prepare the microSD in **1. ROMs and microSD**.
2. In **2. BL616**, install **NanoQL** firmware with the hardware **UPDATE** button.
3. In **3. FPGA**, program the bitstream into persistent Flash through NanoQL Link. If no valid NanoQL core is present, BL616 firmware automatically exposes its recovery port.
4. Insert the microSD and restart the board.

NanoQL BL616 firmware provides the USB keyboard, microSD, overlay, NanoQL Link, and direct FPGA SRAM or Flash programming. Sipeed original firmware and external JTAG remain available as a recovery route.

### Prepare the microSD

In **1. ROMs and microSD**:

1. select the microSD root first;
2. select the QL ROM;
3. select one IPC firmware, either original or Hermes;
4. optionally add QSound;
5. click **Prepare microSD**.

`QL.rom`, `IPC.rom`, and `QSound.rom` are convenient defaults. Other ROMs may be copied directly to the card and selected through the `F12` overlay.

The preferred format is one **FAT32 partition using an MBR partition table**. On macOS, select **MS-DOS (FAT)** and **Master Boot Record** in Disk Utility. exFAT remains supported and is convenient for cards larger than 32 GB. Compatibility still depends on the microSD card's internal controller, not only its capacity, speed class, brand, or filesystem. A correctly formatted card may stall during writes. If saving settings, building a Microdrive, or a NanoQL Link transfer hangs, try another card before reflashing NanoQL.

### Program the FPGA

For a normal update, leave the **NanoQL** BL616 firmware installed:

1. start NanoQL and wait for HDMI output or the LEDs;
2. briefly press **S1** once; do not hold it during power-on;
3. in **3. FPGA**, verify the `.fs` file automatically filled from the folder selected under **Start here**; you may also replace it manually;
4. select the **NanoQL Link** port;
5. click **Program Flash (permanent)**, or **Program SRAM (temporary)** for a test that disappears after power-off.

Persistent programming erases, writes, and verifies configuration Flash, then restarts NanoQL. Keep USB and power connected throughout the operation. **Detect configuration Flash** is an optional read-only check. You may also select a `.fs` file directly: NanoQL Link validates and converts it without Gowin EDA. `BL616-3921.bin` and `BL616-3923.bin` firmware files are rejected in this tab.

For recovery, use **External JTAG** in the same tab while the BL616 runs **Sipeed original** firmware. The assistant can then call openFPGALoader 1.1.1 or newer, or Gowin Programmer on Windows. With Sipeed firmware active, the display may report `BL616 COMPANION NOT READY`; this is expected because the BL616 is exposing JTAG to the computer.

```sh
openFPGALoader -b tangnano20k -f /path/to/NanoQL-vX.Y.Z-FPGA.fs
```

With Gowin Programmer, select `USB Debugger A/1`, **External Flash Mode**, an erase/program operation, and **Generic Flash**.

Keep Gowin EDA's **Use JTAG as regular IO** option disabled.

### Program the BL616

On first installation, do this before programming the FPGA. In **2. BL616**:

1. connect the Tang Nano 20K to the computer with a USB-C data cable; this step programs the BL616 over USB;
2. select revision 3921 or 3923;
3. verify that **NanoQL BL616 firmware** contains the `.bin` detected in the release folder;
4. disconnect the board;
5. hold **UPDATE**, reconnect USB, then release **UPDATE**;
6. click **Refresh**, then select the new bootloader serial port;
7. click **Install / update NanoQL firmware**.

The second button, **Restore Sipeed original firmware**, is only for recovery or an external JTAG programmer. In both cases, **UPDATE** means the BL616 hardware button; **S1** is not used to flash BL616 firmware.

The assistant automatically installs Bouffalo Lab's cross-platform `bflb-mcu-tool-uart` loader. On Python 3.13 or newer it also installs the compatibility module needed since `telnetlib` was removed. macOS uses 230400 baud; Windows and Linux use 2000000 baud with small acknowledged blocks for reliable USB transfers. After an interrupted attempt, disconnect the board and enter UPDATE mode again before retrying. Command-line equivalent:

```sh
python3 tools/prepare_bl616_firmware.py --revision 3923 --profile nanoql --flash --port PORT --yes
```

Replace `PORT` with `COMx`, `/dev/ttyACMx`, `/dev/ttyUSBx`, `/dev/cu.usbmodem*`, or `/dev/cu.usbserial*`. Use `3921` for that revision. This route still requires physical validation on each operating system. FlashCube remains available as a Windows recovery option.

### Update NanoQL

Select **Update NanoQL** under **Start here**. The normal path no longer replaces BL616 firmware twice:

1. update NanoQL BL616 firmware from **2. BL616** with **UPDATE**;
2. start NanoQL, briefly press **S1**, then program the new FPGA bitstream from **3. FPGA**.

The microSD and its settings are preserved. If NanoQL Link is unavailable or FPGA Flash is damaged, restore Sipeed firmware with **UPDATE**, then use external JTAG:

```sh
python3 tools/prepare_bl616_firmware.py --revision 3923 --profile original --flash --port PORT --yes
```

Direct command for a persistent update:

```sh
python3 tools/nanoql_link.py --port PORT fpga-flash path/to/extracted-release-folder --yes
```

Replace `fpga-flash` with `fpga` to program SRAM only.

### First boot

1. Power the board off.
2. Insert the microSD.
3. Connect HDMI.
4. Power the board through USB-C.
5. If NanoQL requests ROMs, open `F12`, select **QL ROM** and **IPC ROM**, then restart the QL.

The QL must boot without a keyboard or hub. For development, connect the board to the computer, wait for FPGA startup, briefly press S1, and use **4. NanoQL Link > Connection and remote keyboard**. The remote keyboard works on Windows, macOS, and Linux. On macOS/Linux the script automatically installs `pynput` on first use. macOS may ask you to allow Terminal or Python under **System Settings > Privacy & Security > Input Monitoring** and **Accessibility**. If the console reports `This process is not trusted`, also add the actual Python executable shown by the command, for example the one under `venv/bin`, then fully quit and restart Terminal. On macOS, the authorized Quartz event tap prevents keys and control sequences from being echoed into Terminal. Pending events are flushed before `F6` returns control.

NanoQL provides six video profiles under `Display > Video mode`. The 50 Hz profiles use CEA VIC 19 and preserve the QL's native PAL cadence. The 60 Hz profiles use CEA VIC 4 for displays that reject 50 Hz; QL VRAM is still updated at 50 Hz, causing a periodic repeated frame during motion. `Sharp` uses 1024×698 and doubles every QL source column exactly, `Large` uses 844×576, while `Fit` uses 990×675 with a safety margin for overscan sometimes applied by TV-style 16:9 modes. All three are centered and reproduce the QL's approximately 4.4:3 historical geometry with non-square pixels.

Both rates are true 74.25 MHz HDMI streams with a 16:9 AVI InfoFrame. If an older display disables its aspect control or distorts 720p50, try `60 Hz Large` first. Disable overscan, noise reduction, motion interpolation, and sharpness enhancement for faithful pixels.

In the overlay, `USB layout` applies exclusively to the local USB keyboard connected to the BL616; `QL ROM layout` selects the table expected by the ROM. The remote keyboard in the **4. Remote keyboard** tab is translated into characters by Windows, macOS, or Linux, ignores `USB layout`, and uses matrix state independent from the USB keyboard.
