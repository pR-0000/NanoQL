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

Pour programmer le FPGA, utilisez au choix :

- [openFPGALoader](https://trabucayre.github.io/openFPGALoader/guide/install.html) ;
- Gowin Programmer, inclus dans Gowin EDA.

Gowin Programmer et Gowin EDA ne sont pas nécessaires pour installer une version compilée si openFPGALoader fonctionne. Gowin EDA reste nécessaire pour recompiler le cœur FPGA.

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

Le pilote FTDI installé par défaut ne permet pas à openFPGALoader d'ouvrir le JTAG. Dans l'onglet **2. FPGA**, cliquez une seule fois sur **Install Windows JTAG driver**. Dans Zadig, activez **Options > List All Devices**, choisissez uniquement **USB Serial Converter A** ou **Dual RS232-HS (Interface 0)**, vérifiez `0403:6010` et `MI_00`, sélectionnez **WinUSB**, puis remplacez le pilote. Ne modifiez jamais **Interface 1/B**, qui doit conserver son pilote série FTDI. Débranchez et rebranchez ensuite la Tang Nano.

### Assistant graphique

Depuis le dossier NanoQL :

```sh
python tools/nanoql_setup.pyw
```

Sous macOS/Linux, utilisez `python3` si nécessaire. L'assistant installe automatiquement PySerial, affiche les ports série dans des listes détaillées, vérifie les outils, prépare la microSD, programme le FPGA et prépare le firmware BL616.

Le sélecteur **Language** du premier onglet bascule immédiatement toute l'interface entre le français et l'anglais. Ce choix est mémorisé avec les autres réglages. Les illustrations intégrées montrent les boutons **UPDATE** et **S1** à utiliser ; aucun fichier image externe n'est requis.

### Ordre de première installation

Respectez cet ordre. Il évite de perdre temporairement l'accès JTAG :

1. Préparez la microSD dans **1. ROMs and microSD**.
2. Laissez le BL616 avec son firmware Sipeed **FPGA Partner**.
3. Dans **2. FPGA**, sélectionnez le fichier précompilé `NanoQL-*-FPGA.fs` de la release et programmez-le en Flash persistante.
4. Installez seulement ensuite le profil BL616 **NanoQL** depuis **3. BL616**.
5. Insérez la microSD et redémarrez la carte.

FPGA Partner expose les canaux JTAG utilisés par Gowin Programmer et openFPGALoader. Le firmware BL616 NanoQL remplace cette fonction par le clavier USB, la microSD, l'overlay et NanoQL Link.

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

Dans **2. FPGA**, utilisez **Browse** pour sélectionner `NanoQL-*-FPGA.fs`. Une release précompilée ne nécessite ni Gowin EDA ni le bouton **Build**. Tant que FPGA Partner est installé, l'assistant peut appeler openFPGALoader. Équivalent manuel :

Reliez directement la Tang Nano 20K à l'ordinateur avec un câble USB-C de données pendant cette étape : le fichier FPGA est programmé par cette connexion USB, indépendamment de la microSD.

L'assistant utilise de préférence openFPGALoader v1.1.1 ou plus récent sous Windows, macOS et Linux. Cette version contient les corrections nécessaires au firmware de programmation Sipeed. Gowin Programmer reste utilisable manuellement sous Windows, mais ses outils en ligne de commande ne gèrent pas fiablement le câble BL616. Cliquez sur **Detect programmer** avant la programmation ; si aucune interface n'est trouvée, restaurez le profil BL616 ORIGINAL, débranchez et rebranchez la carte, puis recommencez.

Avec le profil ORIGINAL actif, l'écran NanoQL peut afficher `BL616 COMPANION NOT READY`. C'est normal pendant la programmation : le BL616 expose alors le JTAG au PC au lieu de fournir les services Companion au FPGA.

```sh
openFPGALoader -b tangnano20k -f /chemin/vers/NanoQL-vX.Y.Z-FPGA.fs
```

Avec Gowin Programmer, utilisez `USB Debugger A/1`, **External Flash Mode**, une opération d'effacement/programmation et **Generic Flash**.

Dans Gowin EDA, laissez **Use JTAG as regular IO** décoché.

### Programmer le BL616

Cette opération vient après le FPGA. Dans **3. BL616** :

1. reliez la Tang Nano 20K à l'ordinateur avec un câble USB-C de données ; cette étape programme le BL616 par USB ;
2. sélectionnez la révision 3921 ou 3923 ;
3. sélectionnez le profil **NanoQL** ;
4. débranchez la carte ;
5. maintenez **UPDATE**, reconnectez l'USB puis relâchez **UPDATE** ;
6. cliquez sur **Refresh**, puis choisissez le nouveau port série du bootloader dans la liste ;
7. cliquez sur **Flash firmware**.

L'assistant installe automatiquement `bflb-mcu-tool-uart`, l'outil UART multiplateforme de Bouffalo Lab. Avec Python 3.13 ou plus récent, il installe aussi le module de compatibilité requis depuis la suppression de `telnetlib`. macOS utilise 230400 bauds ; Windows et Linux utilisent 2000000 bauds avec de petits blocs acquittés pour fiabiliser l'USB. Une tentative interrompue impose de débrancher la carte et de rentrer de nouveau dans le mode UPDATE avant de recommencer. Commande équivalente :

```sh
python3 tools/prepare_bl616_firmware.py --revision 3923 --profile nanoql --flash --port PORT --yes
```

Remplacez `PORT` par `COMx`, `/dev/ttyACMx`, `/dev/ttyUSBx`, `/dev/cu.usbmodem*` ou `/dev/cu.usbserial*`. Utilisez `3921` pour cette révision. Cette méthode doit encore être validée physiquement sur chaque OS. FlashCube reste disponible comme solution de récupération sous Windows.

### Mettre NanoQL à jour

Le firmware NanoQL n'expose pas le JTAG standard. Pour modifier la Flash FPGA :

1. restaurez temporairement le profil BL616 **Original** ;
2. programmez le nouveau `.fs` ;
3. réinstallez le profil BL616 **NanoQL**.

La restauration multiplateforme utilise :

```sh
python3 tools/prepare_bl616_firmware.py --revision 3923 --profile original --flash --port PORT --yes
```

Pour un essai temporaire sans changer le BL616, NanoQL Link peut charger le fichier FPGA `.bin` en SRAM.

### Premier démarrage

1. Éteignez la carte.
2. Insérez la microSD.
3. Branchez HDMI.
4. Alimentez par USB-C.
5. Si NanoQL demande des ROM, ouvrez `F12`, choisissez **QL ROM** et **IPC ROM**, puis redémarrez le QL.

Le QL doit démarrer sans clavier ni hub. Pour le développement, connectez la carte à l'ordinateur, attendez le démarrage du FPGA, appuyez brièvement sur S1 et utilisez l'onglet **4. Remote keyboard**. Le clavier distant fonctionne sous Windows, macOS et Linux. Sur macOS/Linux, le script installe automatiquement `pynput` lors de la première utilisation. macOS peut demander d'autoriser Terminal ou Python dans **Réglages Système > Confidentialité et sécurité > Surveillance de l'entrée** et **Accessibilité**. Si la console affiche `This process is not trusted`, ajoutez également l'exécutable Python réellement affiché par la commande, par exemple celui du dossier `venv/bin`, puis quittez complètement et relancez Terminal. Sur macOS, l'interception Quartz autorisée empêche les touches et séquences de contrôle de s'afficher dans Terminal. Les événements en attente sont vidés avant de rendre la main avec `F6`.

NanoQL propose six profils vidéo dans `Display > Video mode`. Les profils 50 Hz utilisent le VIC CEA 19 et conservent la cadence PAL native du QL. Les profils 60 Hz utilisent le VIC CEA 4 pour les moniteurs qui refusent le 50 Hz ; la VRAM QL reste mise à jour à 50 Hz, ce qui produit une répétition périodique perceptible dans les mouvements. `Sharp` affiche 564×384, `Large` 844×576 et constitue le compromis recommandé, tandis que `Fit` utilise 990×675 avec une marge de sécurité contre l'overscan parfois appliqué par les modes TV 16:9. Les trois profils sont centrés et reproduisent le rapport historique approximatif de 4,4:3 des pixels non carrés du QL.

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

Program the FPGA with either:

- [openFPGALoader](https://trabucayre.github.io/openFPGALoader/guide/install.html);
- Gowin Programmer, included with Gowin EDA.

Gowin Programmer and Gowin EDA are not required to install a compiled release when openFPGALoader works. Gowin EDA is still required to compile the FPGA core.

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

The default FTDI driver does not let openFPGALoader access JTAG. In **2. FPGA**, click **Install Windows JTAG driver** once. In Zadig, enable **Options > List All Devices**, select only **USB Serial Converter A** or **Dual RS232-HS (Interface 0)**, verify `0403:6010` and `MI_00`, select **WinUSB**, then replace the driver. Never modify **Interface 1/B**, which must keep its FTDI serial driver. Disconnect and reconnect the Tang Nano afterward.

### Graphical assistant

Run from the NanoQL directory:

```sh
python tools/nanoql_setup.pyw
```

Use `python3` on macOS/Linux when needed. The assistant installs PySerial automatically, presents detailed serial-port lists, checks tools, prepares the microSD, programs the FPGA, and prepares BL616 firmware.

The first tab's **Language** selector immediately switches the complete interface between English and French. The choice is stored with the other settings. Embedded illustrations identify the **UPDATE** and **S1** buttons; no external image file is required.

### First-install order

Follow this order to avoid temporarily losing JTAG access:

1. Prepare the microSD in **1. ROMs and microSD**.
2. Keep Sipeed's **FPGA Partner** BL616 firmware installed.
3. In **2. FPGA**, select the release's precompiled `NanoQL-*-FPGA.fs` and program it into persistent Flash.
4. Only then install the **NanoQL** BL616 profile from **3. BL616**.
5. Insert the microSD and restart the board.

FPGA Partner exposes the JTAG channels used by Gowin Programmer and openFPGALoader. NanoQL BL616 firmware replaces them with USB keyboard, microSD, overlay, and NanoQL Link services.

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

In **2. FPGA**, use **Browse** to select `NanoQL-*-FPGA.fs`. A precompiled release does not require Gowin EDA or the **Build** button. While FPGA Partner remains installed, the assistant can call openFPGALoader. Manual equivalent:

Connect the Tang Nano 20K directly to the computer with a USB-C data cable during this step: the FPGA file is programmed through this USB connection, independently of the microSD card.

The assistant prefers openFPGALoader v1.1.1 or newer on Windows, macOS, and Linux. This release contains the fixes required for Sipeed programmer firmware. Gowin Programmer remains available for manual Windows use, but its command-line tools do not handle the BL616 cable reliably. On Windows, first use **Install Windows JTAG driver** as described above. Click **Detect programmer** before programming; if no interface is found, restore the BL616 ORIGINAL profile, disconnect and reconnect the board, then try again.

With the ORIGINAL profile active, NanoQL may display `BL616 COMPANION NOT READY`. This is expected while programming: the BL616 exposes JTAG to the computer instead of providing Companion services to the FPGA.

```sh
openFPGALoader -b tangnano20k -f /path/to/NanoQL-vX.Y.Z-FPGA.fs
```

With Gowin Programmer, select `USB Debugger A/1`, **External Flash Mode**, an erase/program operation, and **Generic Flash**.

Keep Gowin EDA's **Use JTAG as regular IO** option disabled.

### Program the BL616

Do this after programming the FPGA. In **3. BL616**:

1. connect the Tang Nano 20K to the computer with a USB-C data cable; this step programs the BL616 over USB;
2. select revision 3921 or 3923;
3. select the **NanoQL** profile;
4. disconnect the board;
5. hold **UPDATE**, reconnect USB, then release **UPDATE**;
6. click **Refresh**, then select the new bootloader serial port from the list;
7. click **Flash firmware**.

The assistant automatically installs Bouffalo Lab's cross-platform `bflb-mcu-tool-uart` loader. On Python 3.13 or newer it also installs the compatibility module needed since `telnetlib` was removed. macOS uses 230400 baud; Windows and Linux use 2000000 baud with small acknowledged blocks for reliable USB transfers. After an interrupted attempt, disconnect the board and enter UPDATE mode again before retrying. Command-line equivalent:

```sh
python3 tools/prepare_bl616_firmware.py --revision 3923 --profile nanoql --flash --port PORT --yes
```

Replace `PORT` with `COMx`, `/dev/ttyACMx`, `/dev/ttyUSBx`, `/dev/cu.usbmodem*`, or `/dev/cu.usbserial*`. Use `3921` for that revision. This route still requires physical validation on each operating system. FlashCube remains available as a Windows recovery option.

### Update NanoQL

NanoQL BL616 firmware does not expose standard JTAG. To update persistent FPGA Flash:

1. temporarily restore the BL616 **Original** profile;
2. program the new `.fs`;
3. reinstall the BL616 **NanoQL** profile.

Cross-platform restore command:

```sh
python3 tools/prepare_bl616_firmware.py --revision 3923 --profile original --flash --port PORT --yes
```

For temporary testing without changing BL616 firmware, NanoQL Link can load the FPGA `.bin` file into SRAM.

### First boot

1. Power the board off.
2. Insert the microSD.
3. Connect HDMI.
4. Power the board through USB-C.
5. If NanoQL requests ROMs, open `F12`, select **QL ROM** and **IPC ROM**, then restart the QL.

The QL must boot without a keyboard or hub. For development, connect the board to the computer, wait for FPGA startup, briefly press S1, and use the **4. Remote keyboard** tab. The remote keyboard works on Windows, macOS, and Linux. On macOS/Linux the script automatically installs `pynput` on first use. macOS may ask you to allow Terminal or Python under **System Settings > Privacy & Security > Input Monitoring** and **Accessibility**. If the console reports `This process is not trusted`, also add the actual Python executable shown by the command, for example the one under `venv/bin`, then fully quit and restart Terminal. On macOS, the authorized Quartz event tap prevents keys and control sequences from being echoed into Terminal. Pending events are flushed before `F6` returns control.

NanoQL provides six video profiles under `Display > Video mode`. The 50 Hz profiles use CEA VIC 19 and preserve the QL's native PAL cadence. The 60 Hz profiles use CEA VIC 4 for displays that reject 50 Hz; QL VRAM is still updated at 50 Hz, causing a periodic repeated frame during motion. `Sharp` displays 564×384, `Large` uses 844×576 and is the recommended compromise, while `Fit` uses 990×675 with a safety margin for overscan sometimes applied by TV-style 16:9 modes. All three are centered and reproduce the QL's approximately 4.4:3 historical geometry with non-square pixels.

Both rates are true 74.25 MHz HDMI streams with a 16:9 AVI InfoFrame. If an older display disables its aspect control or distorts 720p50, try `60 Hz Large` first. Disable overscan, noise reduction, motion interpolation, and sharpness enhancement for faithful pixels.

In the overlay, `USB layout` applies exclusively to the local USB keyboard connected to the BL616; `QL ROM layout` selects the table expected by the ROM. The remote keyboard in the **4. Remote keyboard** tab is translated into characters by Windows, macOS, or Linux, ignores `USB layout`, and uses matrix state independent from the USB keyboard.
