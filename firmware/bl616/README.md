# NanoQL BL616 firmware package

## Français

Ce dossier contient les configurations reproductibles du BL616 embarqué des Tang Nano 20K révisions 3921 et 3923. L'assistant recommande automatiquement les bons fichiers pour la révision sélectionnée :

```text
python tools/nanoql_setup.py
```

Il télécharge la version officielle épinglée, vérifie les empreintes SHA-256 et ouvre BouffaloLabFlashCube sous Windows. Il utilise uniquement Python 3 et Tkinter, sans package `pip`.

Depuis la racine du dépôt :

```powershell
.\tools\prepare_bl616_firmware.ps1 -Revision 3923 -Launch
```

Équivalent Python sous Windows :

```text
python tools/prepare_bl616_firmware.py --revision 3923 --launch
```

Le paquet ne contient que deux profils par révision : `ORIGINAL` restaure FPGA Partner et Companion de Sipeed, tandis que `NANOQL` installe le firmware unifié nécessaire au clavier USB, à la microSD et à NanoQL Link.

Maintenez le bouton `UPDATE`, connectez l'USB-C au PC, relâchez le bouton, rafraîchissez les ports dans FlashCube, choisissez le port COM puis cliquez sur `Download`. Le fichier à sélectionner est affiché par le script.

Lors de la première installation, installez d'abord `NANOQL` avec `UPDATE`, puis programmez le bitstream FPGA par NanoQL Link. Si aucun core NanoQL valide n'est présent, le firmware ouvre automatiquement son port de récupération. Les mises à jour suivantes utilisent le même ordre : BL616 NanoQL, puis FPGA après un appui bref sur `S1`. Le profil `ORIGINAL` reste disponible pour la récupération et les programmateurs JTAG externes.

## English

This directory contains reproducible on-board BL616 configurations for Tang Nano 20K revisions 3921 and 3923. The graphical assistant selects the matching files:

```text
python tools/nanoql_setup.py
```

It downloads the pinned official release, verifies SHA-256 hashes, and opens BouffaloLabFlashCube on Windows. It uses only Python 3 and Tkinter, with no `pip` package dependency.

From the repository root:

```powershell
.\tools\prepare_bl616_firmware.ps1 -Revision 3923 -Launch
```

Cross-platform preparation with Python 3:

```sh
python3 tools/prepare_bl616_firmware.py --revision 3923
```

On Windows, append `--launch` to open FlashCube. FlashCube itself is a Windows application. On macOS and Linux the Python script still prepares and verifies the complete two-image package. Native command-line flashing is being kept separate until the two-segment BL616 operation has been validated on hardware; do not feed the encrypted FPGA Partner image to a generic single-image flasher.

The package contains only two profiles per revision: `ORIGINAL` restores Sipeed FPGA Partner and Companion, while `NANOQL` installs the unified firmware required for the USB keyboard, microSD, and NanoQL Link.

Hold `UPDATE`, connect USB-C to the PC, release the button, refresh ports in FlashCube, select the COM port, then click `Download`. The script displays the configuration file to select.

For first installation, install `NANOQL` first with `UPDATE`, then program the FPGA bitstream through NanoQL Link. If no valid NanoQL core is present, firmware automatically exposes its recovery port. Later updates use the same order: NanoQL BL616 first, then FPGA after briefly pressing `S1`. The `ORIGINAL` profile remains available for recovery and external JTAG programmers.

## Provenance

- FPGA Companion release: `v1.4.22`
- Release URL: https://github.com/MiSTle-Dev/FPGA-Companion/releases/tag/v1.4.22
- Board targets: generic `nano20k` for revision 3921 and `nano20k_v3923` for revision 3923. The FPGA bitstream itself is common to both revisions.
- Installation guide: https://github.com/MiSTle-Dev/.github/wiki/Firmware-Installation-BL616-%C2%B5C
- The `flash_nano20k_3921*.ini` and `flash_nano20k_3923*.ini` files are based on the configurations distributed with that release.
- FPGA Companion and the two derived NanoQL firmware images are distributed under the Apache License 2.0; see `LICENSE-FPGA-COMPANION`.
- The encrypted FPGA Partner firmware is distributed by the upstream release with Sipeed provenance; it is downloaded from upstream rather than redistributed by NanoQL.
