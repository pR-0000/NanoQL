# QSound

## Français

NanoQL reproduit la partie sonore de la carte QSound/QPrint comme une extension matérielle optionnelle du QL. Cette implémentation est validée physiquement sur Tang Nano 20K.

Elle comprend :

- la ROM de 8 Kio à l'adresse QL `$C0000-$C1FFF` ;
- un MC6821 PIA à partir de `$C2000`, avec ses quatre registres sélectionnés par A0/A1 et répétés dans la fenêtre de la carte ;
- le bus de données 8 bits entre le port A du PIA et l'AY-3-8910 ;
- `BC1` sur PB0 et `BDIR` sur PB2, conformément au schéma de la carte ;
- une horloge AY de 0,75 MHz dérivée de l'horloge QL native et indépendante de la vitesse CPU ;
- les trois voies, le bruit et les enveloppes AY, mixés en mono avec le `BEEP` QL sur les deux canaux HDMI.

Le cœur AY utilisé est [JT49](https://github.com/jotego/jt49), distribué sous GPL-3.0.

### Trouver et préparer la ROM

La ROM QSound n'est pas redistribuée par NanoQL. Le dépôt du [clone matériel QSound/QPrint](https://github.com/alvaroalea/QL_QsoundQprint_clone/tree/main/ROM) propose plusieurs images de 8 192 octets pour tester le matériel. Son auteur indique avoir validé les versions 1.10, 1.31 et 1.40 ; la version 1.40 constitue le choix classique recommandé. La version 1.94 ajoute notamment des fonctions utilisées par le lecteur PT3, mais ne contient plus les routines QPrint. Vérifiez toujours que vous êtes autorisé à utiliser l'image choisie.

Dans `python tools/nanoql_setup.pyw`, sélectionnez **Optional 8 KiB QSound ROM** dans l'onglet de préparation de la microSD. La commande équivalente est :

```sh
python tools/prepare_sd_card.py path/to/QL.rom D:\ --qsound-rom path/to/QSound.rom
```

Remplacez `D:\` par la racine réelle de la microSD. Vous pouvez aussi copier manuellement la ROM à sa racine sous `QSound.rom`, puis la sélectionner dans **QSound ROM:** depuis l'overlay `F12`. La sélection est conservée dans `nanoql.ini` et provoque un reset QL. Une image montée avec une taille incorrecte affiche `QSOUND ROM LOAD FAILED`.

### Test rapide

Après le démarrage de QDOS, essayez `BELL`, `SHOOT` et `EXPLODE`. Selon la version de ROM, la commande programmable est nommée `SOUND` ou `SOUND_AY` afin d'éviter un conflit avec d'autres extensions sonores.

### Démonstration QSoundZ

[QSoundZ de SMFX](https://www.pouet.net/prod.php?which=96940) est un musicdisk freeware pour Sinclair QL conçu pour QSound. NanoQL ne redistribue pas cette production, mais fournit un outil reproductible qui la télécharge depuis le site de l'auteur, vérifie son SHA-256 et extrait son image Microdrive :

```sh
python tools/download_qsound_demo.py --sd-root D:\
```

Remplacez `D:\` par la racine réelle de la microSD. Dans l'overlay `F12`, montez ensuite `QSoundZ.mdv` comme **Microdrive 1**, puis entrez :

```text
LRUN mdv1_boot
```

L'interface parallèle QPrint n'est pas encore exposée sur des GPIO ou vers le BL616. Les lignes PB3/PB4 du PIA restent internes. Les interruptions CA1/CA2/CB1/CB2 du MC6821 ne sont pas modélisées car la liaison sonore documentée ne les utilise pas.

Références : le manuel QSound/QPrint, le [clone matériel](https://github.com/alvaroalea/QL_QsoundQprint_clone), [JT49](https://github.com/jotego/jt49) et [QSoundZ](https://www.pouet.net/prod.php?which=96940).

## English

NanoQL reproduces the sound section of the QSound/QPrint card as an optional QL hardware expansion. This implementation is physically validated on the Tang Nano 20K.

It includes:

- the 8 KiB ROM at QL address `$C0000-$C1FFF`;
- an MC6821 PIA from `$C2000`, with its four A0/A1-selected registers mirrored through the card window;
- the 8-bit PIA port A to AY-3-8910 data bus;
- `BC1` on PB0 and `BDIR` on PB2, matching the card schematic;
- a 0.75 MHz AY clock derived from the native QL clock and independent of CPU speed;
- all three AY channels, noise, and envelopes, mixed in mono with the native QL `BEEP` on both HDMI channels.

The AY implementation is [JT49](https://github.com/jotego/jt49), licensed under GPL-3.0.

### Obtaining and preparing the ROM

NanoQL does not redistribute the QSound ROM. The [QSound/QPrint hardware clone repository](https://github.com/alvaroalea/QL_QsoundQprint_clone/tree/main/ROM) provides several 8,192-byte images for hardware testing. Its author reports versions 1.10, 1.31, and 1.40 as tested; version 1.40 is the recommended classic choice. Version 1.94 adds features used by the PT3 player but omits QPrint routines. Always ensure that you are authorized to use the selected image.

Select **Optional 8 KiB QSound ROM** in `python tools/nanoql_setup.pyw`, or run:

```sh
python tools/prepare_sd_card.py path/to/QL.rom /media/sd --qsound-rom path/to/QSound.rom
```

The ROM can also be copied manually to the microSD root as `QSound.rom` and selected from **QSound ROM:** in the `F12` overlay. The selection is persisted in `nanoql.ini` and resets the QL. An incorrectly sized mounted image produces an explicit `QSOUND ROM LOAD FAILED` message.

### Quick test and QSoundZ

After QDOS starts, try `BELL`, `SHOOT`, and `EXPLODE`. Depending on the ROM revision, the programmable command is named either `SOUND` or `SOUND_AY` to avoid conflicts with other sound extensions.

[QSoundZ by SMFX](https://www.pouet.net/prod.php?which=96940) is a freeware Sinclair QL music disk designed for QSound. NanoQL does not redistribute it, but includes a reproducible downloader that checks the archive SHA-256 and extracts its Microdrive image:

```sh
python tools/download_qsound_demo.py --sd-root /media/sd
```

Mount `QSoundZ.mdv` as **Microdrive 1** in the `F12` overlay, then enter:

```text
LRUN mdv1_boot
```

The QPrint parallel interface is not yet exposed through GPIO or the BL616. MC6821 CA/CB interrupts are not modelled because the documented sound path does not use them.

References: the QSound/QPrint manual, the [hardware clone](https://github.com/alvaroalea/QL_QsoundQprint_clone), [JT49](https://github.com/jotego/jt49), and [QSoundZ](https://www.pouet.net/prod.php?which=96940).
