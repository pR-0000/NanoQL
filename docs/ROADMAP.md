# NanoQL Roadmap

## Français

### Principes

NanoQL vise une reproduction matérielle fidèle du Sinclair QL, complétée par les fonctions pratiques du core QL MiSTer. Les fonctions destinées à l'utilisateur doivent être accessibles depuis le menu overlay ou l'outil Python NanoQL, avec des valeurs par défaut sûres et aussi peu d'étapes manuelles que possible.

Les ROM et firmwares dont la redistribution n'est pas clairement autorisée ne doivent pas être publiés. L'assistant de configuration doit les demander à l'utilisateur, les vérifier et générer localement les fichiers nécessaires.

### Contraintes actuelles

- FPGA : 13 114 / 20 736 cellules logiques utilisées (64 %).
- BSRAM : 17 / 46 blocs utilisés (37 %), dont les tampons sectoriels QL-SD et Microdrive.
- SDRAM : 8 Mo disponibles, avec 128, 640 ou 896 Kio présentés comme RAM QL selon le réglage OSD.
- Domaine système : 31,8 MHz, avec une Fmax mesurée de 52,238 MHz.
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

- `QL` et `16 MHz` sont disponibles et commutables à chaud dans l'OSD.
- Ajouter `24 MHz` et `42 MHz` après augmentation et validation du domaine système.
- Conserver la contention vidéo originale uniquement en mode `QL`.
- Valider QDOS, les interruptions, le clavier, le son et la SDRAM à chaque vitesse.

Le mode 16 MHz fonctionne à 15,9 MHz avec le domaine actuel. Le mode 24 MHz nécessite un domaine système plus rapide mais reste réaliste. Le mode 42 MHz requiert environ 84 MHz pour l'architecture MiSTer actuelle ; il est donc expérimental tant que les chemins critiques n'ont pas été optimisés au-delà de la Fmax actuelle de 52,238 MHz.

#### 4. Gold Card et SMSQ/E

- Activer automatiquement le mode Gold Card lorsque 4 Mo de RAM sont sélectionnés.
- Porter le ROM shadow, les fenêtres RAM supplémentaires, les registres Gold Card et le décodage d'adresses de QL_MiSTer.
- Charger une ROM de démarrage « MiSTer Gold Card » compatible TK2 depuis la microSD.
- Permettre la sélection de QDOS, Minerva ou SMSQ/E depuis l'OSD, avec validation de taille et reset automatique.

La ROM Gold Card ne sera incluse au dépôt que si sa licence de redistribution est explicitement compatible. Dans le cas contraire, l'outil de configuration la préparera localement à partir d'un fichier fourni par l'utilisateur.

#### 5. QL-SD et images QXL.WIN

- `qlromext`, la carte SD virtuelle et le transport sectoriel de QL_MiSTer sont portés.
- Un fichier `QXL.WIN` de la microSD peut être monté depuis le sélecteur `QL-SD image` de l'OSD.
- La lecture d'une image `QXL.WIN` avec le pilote QL-SD 1.09 est validée physiquement.
- Valider l'écriture, la protection en écriture, le démontage propre et le changement dynamique d'image.
- Prévoir une récupération sûre après retrait ou erreur de fichier.

Le support d'une vraie seconde carte QL-SD nécessitera un connecteur microSD supplémentaire sur un PCB externe. La carte Tang Nano 20K seule permet en priorité les images QXL.WIN stockées sur sa microSD intégrée.

#### 6. Outils USB et installation

- Le chargement de sources SuperBASIC par clavier distant est disponible comme outil expérimental ; QL-SD est le chemin fiable pour les programmes.
- Les commandes NanoQL Link de liste, envoi, téléchargement, création de dossier et suppression sont disponibles pour `NanoQL/Drive1`.
- Les uploads utilisent un fichier temporaire, une vérification de taille et CRC32, puis un renommage final ; le transport a été validé physiquement sans reconnexion USB.
- Le chemin matériel `MDV1_`, `DIR`, `LOAD` et `LRUN` est validé physiquement en lecture.
- Le BL616 convertit de façon autonome un dossier de `NanoQL/Microdrives` en image QLAY depuis l'overlay, sans mode développeur. La conversion, le montage, `DIR`, `LOAD` et `LRUN` sont validés physiquement dans les modes CPU QL et 16 MHz.
- Les commandes `WRITE` et `ERASE` du ZX8302, les tampons modifiables, la normalisation QLAY et la persistance dans `MDV1.mdv` sont validés physiquement, y compris après reset et aux deux vitesses CPU actuelles.
- Ajouter ensuite une resynchronisation sûre des modifications de l'image vers le dossier source.
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
- Resynchroniser de façon optionnelle les modifications d'une image Microdrive vers son dossier source.
- Ajouter les joysticks USB et les entrées GPIO du futur PCB.
- Exposer les ports série QL par USB CDC lorsque cela peut être fait fidèlement.
- Ajouter un écran de diagnostic OSD pour RAM, ROM, IPC, SDRAM, QL-SD et firmware Companion.
- Ajouter des profils de configuration exportables afin de partager facilement une combinaison ROM, RAM, CPU, vidéo et disque.
- Étudier une extension QSound optionnelle fidèle à l'AY-3-8910 à 0,75 MHz, avec mixage sur HDMI et compatibilité avec les logiciels existants.
- Étudier un mode vidéo Q60 optionnel en SDRAM, sans modifier le mode QL fidèle par défaut ; valider d'abord la carte mémoire, les registres et la bande passante du framebuffer 16 bits.

### Parité matérielle étendue

Les fonctions de Q-emuLator constituent une cible de compatibilité utile, mais NanoQL doit conserver comme priorité un chemin QL déterministe et mesurable. Les extensions seront optionnelles et ne remplaceront jamais le profil matériel original.

- Priorité haute : QIMI/souris USB, joysticks, resynchronisation Microdrive, accès aux fichiers hôte via le BL616, RAM disk, débogueur 68000 matériel et ports série USB CDC.
- Priorité moyenne : QSound, QL Sampled Sound System, imprimante parallèle virtuelle et extraction contrôlée des paquets ZIP/QLPAK vers une image QDOS.
- Priorité avancée : Gold Card/SMSQ/E, Aurora et modes vidéo Q40/Q60. Les framebuffers tiennent dans 8 Mio, mais les modes 1024 pixels 16 bits exigent une hausse importante de la bande passante SDRAM.
- Priorité expérimentale : TCP/IP par le BL616, de préférence derrière une interface QL documentée ou un lien série/SLIP afin de ne pas contourner QDOS de manière opaque.

### Prochaine étape retenue

Valider l'écriture QL-SD, puis sécuriser la resynchronisation optionnelle d'une image Microdrive vers son dossier source.

## English

### Principles

NanoQL aims to reproduce Sinclair QL hardware faithfully while adding the practical features available in the MiSTer QL core. User-facing features should be available through the overlay menu or the NanoQL Python tool, with safe defaults and as few manual steps as possible.

ROMs and firmware without explicit redistribution permission must not be published. The setup assistant should request them from the user, validate them, and generate the required local files.

### Current constraints

- FPGA: 13,114 / 20,736 logic cells used (64%).
- BSRAM: 17 / 46 blocks used (37%), including QL-SD and Microdrive sector buffers.
- SDRAM: 8 MiB available, exposing 128, 640, or 896 KiB as QL RAM according to the OSD setting.
- System domain: 31.8 MHz, with a measured Fmax of 52.238 MHz.
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

- `QL` and `16 MHz` are available and live-switchable in the OSD.
- Add `24 MHz` and `42 MHz` after increasing and validating the system domain.
- Keep original video contention only in `QL` mode.
- Validate QDOS, interrupts, keyboard, audio, and SDRAM at every speed.

The 16 MHz mode runs at 15.9 MHz with the current domain. 24 MHz requires a faster system domain but remains realistic. 42 MHz needs about 84 MHz with the current MiSTer architecture and is therefore experimental until critical paths improve beyond the current 52.238 MHz Fmax.

#### 4. Gold Card and SMSQ/E

- Enable Gold Card mode automatically when 4 MiB RAM is selected.
- Port QL_MiSTer's ROM shadow, extra RAM windows, Gold Card registers, and address decoding.
- Load a TK2-compatible "MiSTer Gold Card" boot ROM from microSD.
- Select QDOS, Minerva, or SMSQ/E from the OSD with size validation and automatic reset.

The Gold Card ROM will only be committed if its redistribution license is explicitly compatible. Otherwise, the setup tool will prepare it locally from a user-supplied file.

#### 5. QL-SD and QXL.WIN images

- QL_MiSTer's `qlromext`, virtual SD card, and sector transport are ported.
- A microSD `QXL.WIN` file can be mounted from the OSD `QL-SD image` selector.
- Reading a `QXL.WIN` image with QL-SD driver 1.09 is physically validated.
- Validate writes, write protection, clean unmount, and dynamic image changes.
- Recover safely from file removal and I/O errors.

A real secondary QL-SD card requires an additional microSD connector on an external PCB. The standalone Tang Nano 20K can primarily support QXL.WIN images stored on its integrated microSD.

#### 6. USB tools and installation

- Remote-keyboard SuperBASIC loading is available as an experimental tool; QL-SD is the reliable program path.
- NanoQL Link list, upload, download, directory creation, and delete commands are available for `NanoQL/Drive1`.
- Uploads use a temporary file, size and CRC32 verification, then a final rename; the transport has been physically validated without USB reconnections.
- The hardware `MDV1_` path, `DIR`, `LOAD`, and `LRUN` are physically validated for reads.
- The BL616 autonomously converts a folder under `NanoQL/Microdrives` to a QLAY image from the overlay without development mode. Conversion, mounting, `DIR`, `LOAD`, and `LRUN` are physically validated in both QL and 16 MHz CPU modes.
- ZX8302 `WRITE` and `ERASE`, writable buffers, QLAY normalization, and persistence to `MDV1.mdv` are physically validated across reset and at both current CPU speeds.
- Add safe synchronization of image changes back to the source folder afterward.
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
- Optionally synchronize changes from a Microdrive image back to its source folder.
- Add USB joysticks and GPIO inputs for the future carrier PCB.
- Expose QL serial ports over USB CDC where this can be implemented faithfully.
- Add an OSD diagnostics page for RAM, ROM, IPC, SDRAM, QL-SD, and Companion firmware.
- Add exportable profiles combining ROM, RAM, CPU, video, and disk settings.
- Investigate a faithful optional QSound expansion using the 0.75 MHz AY-3-8910, mixed into HDMI audio and compatible with existing software.
- Investigate an optional SDRAM-backed Q60 video mode without changing the faithful default QL mode; validate its memory map, registers, and 16-bit framebuffer bandwidth first.

### Extended hardware parity

Q-emuLator's feature set is a useful compatibility target, but NanoQL must prioritize a deterministic, measurable QL hardware path. Every extension remains optional and never replaces the original-machine profile.

- High priority: QIMI/USB mouse, joysticks, Microdrive resynchronization, BL616 host-file access, RAM disk, hardware 68000 debugger, and USB CDC serial ports.
- Medium priority: QSound, QL Sampled Sound System, virtual parallel printer, and controlled ZIP/QLPAK extraction into a QDOS image.
- Advanced priority: Gold Card/SMSQ/E, Aurora, and Q40/Q60 video modes. Their framebuffers fit in 8 MiB, but 1024-pixel 16-bit modes require substantially more SDRAM bandwidth.
- Experimental priority: TCP/IP through the BL616, preferably behind a documented QL device or serial/SLIP link rather than an opaque QDOS bypass.

### Selected next step

Validate QL-SD writes, then safely synchronize a Microdrive image back to its source folder as an optional operation.
