# NanoQL Roadmap

## Français

### Principes

NanoQL vise une reproduction matérielle fidèle du Sinclair QL, complétée par les fonctions pratiques du core QL MiSTer. Les fonctions destinées à l'utilisateur doivent être accessibles depuis le menu overlay ou l'outil Python NanoQL, avec des valeurs par défaut sûres et aussi peu d'étapes manuelles que possible.

Les ROM et firmwares dont la redistribution n'est pas clairement autorisée ne doivent pas être publiés. L'assistant de configuration doit les demander à l'utilisateur, les vérifier et générer localement les fichiers nécessaires.

### Contraintes actuelles

- FPGA : 11 119 / 20 736 cellules logiques utilisées (54 %).
- BSRAM : 13 / 46 blocs utilisés (29 %) après migration de la ROM dynamique en SDRAM.
- SDRAM : 8 Mo disponibles, avec 128, 640 ou 896 Kio présentés comme RAM QL selon le réglage OSD.
- Domaine système : 31,8 MHz, avec une Fmax mesurée de 65,549 MHz.
- HDMI : 720p50 avec audio PCM 48 kHz fonctionnel.

Le pourcentage de LUT restant ne suffit pas à garantir toutes les extensions. La migration de la ROM QL dynamique vers une zone réservée de la SDRAM a toutefois libéré 32 blocs BSRAM pour les ROM et tampons des fonctions suivantes. La fréquence du domaine système devient maintenant la contrainte principale pour les modes CPU rapides.

### Ordre de développement recommandé

#### 1. Fondation mémoire et configuration OSD

- Conserver la ROM QL chargée depuis la microSD dans sa zone SDRAM réservée.
- Réserver une carte SDRAM documentée pour la RAM QL, les ROM système, la ROM Gold Card et les futurs tampons.
- Étendre le canal de configuration Companion/FPGA pour transporter proprement les réglages RAM, CPU, OS, QL-SD et RTC.
- Proposer `128 Kio`, `640 Kio` et `896 Kio` dans le menu ; ajouter `4096 Kio` uniquement avec l'implémentation Gold Card.
- Reprendre le décodage mémoire et les masques d'adresses de QL_MiSTer.
- Appliquer les changements matériels au reset et les conserver dans `nanoql.ini`.

Premier objectif vérifiable : QDOS doit démarrer de façon répétable avec 128 Kio puis 896 Kio, détecter la bonne quantité de mémoire et réussir un test intégral de la RAM sans régression vidéo ou clavier.

#### 2. RTC

- Transmettre un timestamp au ZX8302 au démarrage, comme le fait QL_MiSTer.
- Conserver ensuite l'heure avec le compteur matériel du core.
- Permettre la synchronisation depuis NanoQL Link et, plus tard, éventuellement par NTP.
- Afficher clairement dans l'OSD si l'heure n'a pas encore été synchronisée.

La Tang Nano 20K ne possédant pas de pile RTC, une heure absolue correcte après une coupure complète nécessite une source externe telle que le PC, le réseau ou un module RTC optionnel.

#### 3. Vitesses CPU

- Proposer `QL`, `16 MHz`, `24 MHz` et `42 MHz` dans l'OSD.
- Conserver la contention vidéo originale uniquement en mode `QL`.
- Valider QDOS, les interruptions, le clavier, le son et la SDRAM à chaque vitesse.

Le mode 16 MHz est proche de la limite du domaine actuel. Le mode 24 MHz devrait nécessiter un domaine système plus rapide mais reste réaliste. Le mode 42 MHz requiert environ 84 MHz pour l'architecture MiSTer actuelle ; il est donc expérimental tant que les chemins critiques n'ont pas été optimisés au-delà de la Fmax actuelle de 63,261 MHz.

#### 4. Gold Card et SMSQ/E

- Activer automatiquement le mode Gold Card lorsque 4 Mo de RAM sont sélectionnés.
- Porter le ROM shadow, les fenêtres RAM supplémentaires, les registres Gold Card et le décodage d'adresses de QL_MiSTer.
- Charger une ROM de démarrage « MiSTer Gold Card » compatible TK2 depuis la microSD.
- Permettre la sélection de QDOS, Minerva ou SMSQ/E depuis l'OSD, avec validation de taille et reset automatique.

La ROM Gold Card ne sera incluse au dépôt que si sa licence de redistribution est explicitement compatible. Dans le cas contraire, l'outil de configuration la préparera localement à partir d'un fichier fourni par l'utilisateur.

#### 5. QL-SD et images QXL.WIN

- Porter fidèlement `qlromext` et l'interface QL-SD de QL_MiSTer.
- Exposer un fichier `QXL.WIN` de la microSD comme carte SD virtuelle bloc par bloc.
- Ajouter un sélecteur `QL-SD image` dans l'OSD.
- Gérer lecture, écriture, protection en écriture, démontage propre et changement dynamique d'image.
- Vérifier le fonctionnement avec le pilote QL-SD 1.08 ou ultérieur.
- Prévoir une récupération sûre après retrait ou erreur de fichier.

Le support d'une vraie seconde carte QL-SD nécessitera un connecteur microSD supplémentaire sur un PCB externe. La carte Tang Nano 20K seule permet en priorité les images QXL.WIN stockées sur sa microSD intégrée.

#### 6. Outils USB et installation

- Ajouter à NanoQL Link des commandes de liste, envoi, téléchargement, renommage et suppression de fichiers sur la microSD.
- Utiliser une écriture temporaire, une vérification CRC/SHA-256 puis un renommage atomique pour éviter les fichiers partiels.
- Intégrer le flash du firmware BL616 dans l'outil Python sous Windows, Linux et macOS.
- Détecter la révision 3921/3923 et vérifier le firmware après programmation.
- Garder une procédure de récupération explicite ; l'entrée dans le bootloader BL616 pourra toujours nécessiter le bouton `UPDATE`.

#### 7. Capture d'écran et vidéo

- Ajouter `Save screenshot` dans l'OSD.
- Capturer une image cohérente entre deux trames et l'enregistrer sur microSD avec un nom horodaté.
- Commencer par un format simple et robuste, puis proposer PNG si son coût côté BL616 reste raisonnable.
- Étudier ensuite un enregistrement vidéo palettisé à débit réduit.

La capture d'écran est réaliste. La vidéo est un objectif expérimental : elle dépend du débit FPGA/BL616/microSD, de la contention avec QL-SD et de la possibilité de conserver des trames cohérentes sans perturber le QL.

### Autres fonctions souhaitables

- Remplacer progressivement les modules `lite`, notamment le ZX8301, par les chemins fidèles de QL_MiSTer.
- Ajouter les images Microdrive pour la compatibilité historique.
- Ajouter les joysticks USB et les entrées GPIO du futur PCB.
- Exposer les ports série QL par USB CDC lorsque cela peut être fait fidèlement.
- Ajouter un écran de diagnostic OSD pour RAM, ROM, IPC, SDRAM, QL-SD et firmware Companion.
- Ajouter des profils de configuration exportables afin de partager facilement une combinaison ROM, RAM, CPU, vidéo et disque.

### Prochaine étape retenue

Le registre de configuration extensible et les choix de RAM 128/640/896 Kio sont implémentés. La prochaine validation physique doit confirmer le démarrage, la quantité de RAM détectée et la stabilité de QDOS dans les trois modes avant de poursuivre avec le RTC.

## English

### Principles

NanoQL aims to reproduce Sinclair QL hardware faithfully while adding the practical features available in the MiSTer QL core. User-facing features should be available through the overlay menu or the NanoQL Python tool, with safe defaults and as few manual steps as possible.

ROMs and firmware without explicit redistribution permission must not be published. The setup assistant should request them from the user, validate them, and generate the required local files.

### Current constraints

- FPGA: 11,119 / 20,736 logic cells used (54%).
- BSRAM: 13 / 46 blocks used (29%) after moving the dynamic ROM to SDRAM.
- SDRAM: 8 MiB available, exposing 128, 640, or 896 KiB as QL RAM according to the OSD setting.
- System domain: 31.8 MHz, with a measured Fmax of 65.549 MHz.
- HDMI: working 720p50 output with 48 kHz PCM audio.

The remaining LUT percentage alone does not guarantee that every extension will fit. Moving the dynamic QL ROM to a reserved SDRAM area has nevertheless freed 32 BSRAM blocks for future ROMs and buffers. System-domain timing is now the main constraint for faster CPU modes.

### Recommended development order

#### 1. Memory and OSD configuration foundation

- Keep the microSD-loaded QL ROM in its reserved SDRAM area.
- Define and document an SDRAM map for QL RAM, system ROMs, Gold Card ROM, and future buffers.
- Extend the Companion/FPGA configuration channel for RAM, CPU, OS, QL-SD, and RTC settings.
- Provide `128 KiB`, `640 KiB`, and `896 KiB` in the menu; add `4096 KiB` only with the Gold Card implementation.
- Port QL_MiSTer's memory decoding and address masks.
- Apply hardware changes on reset and persist them in `nanoql.ini`.

First acceptance target: QDOS must boot repeatedly with 128 KiB and then 896 KiB, report the correct memory size, and pass a complete RAM test without video or keyboard regressions.

#### 2. RTC

- Send a startup timestamp to the ZX8302 as QL_MiSTer does.
- Keep time with the core's hardware counter afterward.
- Support synchronization from NanoQL Link and optionally NTP later.
- Clearly show an unsynchronized clock state in the OSD.

The Tang Nano 20K has no battery-backed RTC. Correct absolute time after complete power loss therefore requires an external source such as the PC, network, or an optional RTC module.

#### 3. CPU speeds

- Provide `QL`, `16 MHz`, `24 MHz`, and `42 MHz` in the OSD.
- Keep original video contention only in `QL` mode.
- Validate QDOS, interrupts, keyboard, audio, and SDRAM at every speed.

16 MHz is close to the limit of the current domain. 24 MHz should require a faster system domain but remains realistic. 42 MHz needs about 84 MHz with the current MiSTer architecture and is therefore experimental until critical paths improve beyond the current 63.261 MHz Fmax.

#### 4. Gold Card and SMSQ/E

- Enable Gold Card mode automatically when 4 MiB RAM is selected.
- Port QL_MiSTer's ROM shadow, extra RAM windows, Gold Card registers, and address decoding.
- Load a TK2-compatible "MiSTer Gold Card" boot ROM from microSD.
- Select QDOS, Minerva, or SMSQ/E from the OSD with size validation and automatic reset.

The Gold Card ROM will only be committed if its redistribution license is explicitly compatible. Otherwise, the setup tool will prepare it locally from a user-supplied file.

#### 5. QL-SD and QXL.WIN images

- Faithfully port QL_MiSTer's `qlromext` and QL-SD interface.
- Expose a microSD `QXL.WIN` file as a sector-based virtual SD card.
- Add a `QL-SD image` selector to the OSD.
- Support reads, writes, write protection, clean unmount, and dynamic image changes.
- Validate operation with QL-SD driver 1.08 or newer.
- Recover safely from file removal and I/O errors.

A real secondary QL-SD card requires an additional microSD connector on an external PCB. The standalone Tang Nano 20K can primarily support QXL.WIN images stored on its integrated microSD.

#### 6. USB tools and installation

- Add microSD list, upload, download, rename, and delete commands to NanoQL Link.
- Use temporary files, CRC/SHA-256 verification, and atomic rename to prevent partial files.
- Integrate BL616 firmware flashing into the Python tool on Windows, Linux, and macOS.
- Detect revisions 3921/3923 and verify firmware after programming.
- Keep an explicit recovery path; entering the BL616 bootloader may still require the `UPDATE` button.

#### 7. Screenshot and video capture

- Add `Save screenshot` to the OSD.
- Capture a coherent image between frames and save it to microSD with a timestamped name.
- Start with a simple robust format, then add PNG if its BL616 cost is reasonable.
- Investigate reduced-rate paletted video recording afterward.

Screenshots are realistic. Video recording is experimental because it depends on FPGA/BL616/microSD throughput, contention with QL-SD, and coherent capture without disturbing the QL.

### Other useful features

- Progressively replace `lite` modules, especially ZX8301, with faithful QL_MiSTer paths.
- Add Microdrive images for historical compatibility.
- Add USB joysticks and GPIO inputs for the future carrier PCB.
- Expose QL serial ports over USB CDC where this can be implemented faithfully.
- Add an OSD diagnostics page for RAM, ROM, IPC, SDRAM, QL-SD, and Companion firmware.
- Add exportable profiles combining ROM, RAM, CPU, video, and disk settings.

### Selected next step

The extensible configuration register and 128/640/896 KiB RAM choices are implemented. The next physical validation must confirm boot, detected RAM size, and QDOS stability in all three modes before RTC work begins.
