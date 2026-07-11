# NanoQL BL616 firmware package

## Francais

Ce dossier contient les configurations reproductibles du BL616 embarque des
Tang Nano 20K revisions 3921 et 3923. Les binaires tiers ne sont pas recopies
dans Git. L'assistant recommande automatiquement les bons fichiers pour la
revision selectionnee :

```text
python tools/nanoql_setup.py
```

Il telecharge la release officielle epinglee, verifie les empreintes SHA-256
et ouvre BouffaloLabFlashCube sous Windows. Il utilise uniquement Python 3 et
Tkinter, sans package `pip`.

Depuis la racine du depot :

```powershell
.\tools\prepare_bl616_firmware.ps1 -Revision 3923 -Launch
```

Equivalent Python sous Windows :

```text
python tools/prepare_bl616_firmware.py --revision 3923 --launch
```

Maintenir le bouton `UPDATE`, connecter l'USB-C au PC, relacher le bouton,
rafraichir les ports dans FlashCube, choisir le port COM puis cliquer sur
`Download`. Le fichier a selectionner est affiche par le script.

## English

This directory contains reproducible on-board BL616 configurations for Tang
Nano 20K revisions 3921 and 3923. Third-party binaries are not copied into
Git. The graphical assistant selects the matching files:

```text
python tools/nanoql_setup.py
```

It downloads the pinned official release, verifies SHA-256 hashes, and opens
BouffaloLabFlashCube on Windows. It uses only Python 3 and Tkinter, with no
`pip` package dependency.

From the repository root:

```powershell
.\tools\prepare_bl616_firmware.ps1 -Revision 3923 -Launch
```

Cross-platform preparation with Python 3:

```sh
python3 tools/prepare_bl616_firmware.py --revision 3923
```

On Windows, append `--launch` to open FlashCube. FlashCube itself is a Windows
application. On macOS and Linux the Python script still prepares and verifies
the complete two-image package. Native command-line flashing is being kept
separate until the two-segment BL616 operation has been validated on hardware;
do not feed the encrypted FPGA Partner image to a generic single-image flasher.

Hold `UPDATE`, connect USB-C to the PC, release the button, refresh ports in
FlashCube, select the COM port, then click `Download`. The script displays the
configuration file to select.

The generated package uses revision-specific explicit names such as
`1_NORMAL_3923_partner_auto.ini` and `2_TEST_3923_companion_only.ini`.
Normal mode keeps the Gowin programmer while USB data is connected; test mode
forces Companion to run even with a PC attached. Holding `UPDATE` always
remains available; flash the matching `1_NORMAL` configuration to restore the
standard Partner setup.

## Provenance

- FPGA Companion release: `v1.4.22`
- Release URL: https://github.com/MiSTle-Dev/FPGA-Companion/releases/tag/v1.4.22
- Board targets: generic `nano20k` for revision 3921 and `nano20k_v3923` for
  revision 3923. The FPGA bitstream itself is common to both revisions.
- Installation guide: https://github.com/MiSTle-Dev/.github/wiki/Firmware-Installation-BL616-%C2%B5C
- The `flash_nano20k_3921*.ini` and `flash_nano20k_3923*.ini` files are based
  on the configurations distributed with that release.
- FPGA Companion is distributed under the Apache License 2.0.
- The encrypted FPGA Partner firmware is distributed by the upstream release
  with Sipeed provenance; it is downloaded from upstream rather than
  redistributed by NanoQL.
