# NanoQL QL-SD

## Français

NanoQL présente une image `QXL.WIN` de la microSD comme une carte SDHC virtuelle connectée à une interface QLROMEXT. QDOS la voit comme `win1_` avec une ROM contenant le pilote QL-SD 1.08 ou ultérieur.

### Premier test

1. Programmez le bitstream NanoQL principal le plus récent.
2. Téléchargez la [ROM QL-SD 1.09 pour MiSTer](https://www.kilgus.net/soft/MiSTer_QL_OS_qlsd109.zip) et extrayez `js_qlsd109.rom` à la racine de la microSD.
3. Téléchargez l'[image de démonstration QL-SD](https://www.kilgus.net/soft/qlsd_win_demo.zip) et extrayez son `QXL.WIN` à la racine de la microSD.
4. Ouvrez l'overlay avec `F12`. Dans `QL ROM`, sélectionnez `js_qlsd109.rom`. Dans `QL-SD image`, sélectionnez l'image `.WIN`.
5. Choisissez `Reset QL`, puis démarrez QDOS avec `F1` ou `F2`.
6. Saisissez `DIR win1_` pour vérifier la lecture, puis `LRUN win1_boot` pour lancer le système de démonstration.

Pour un premier essai d'écriture, créez un court programme, utilisez `SAVE win1_nanoql_test`, puis vérifiez-le avec `DIR win1_`. Éteignez proprement NanoQL avant de retirer physiquement la microSD.

L'image de démonstration officielle contient un fichier de démarrage, des utilitaires et plusieurs jeux prêts à exécuter. La ROM QL habituelle peut rester sur la carte : le menu sélectionne celle utilisée au prochain reset.

## English

NanoQL presents a microSD `QXL.WIN` image as a virtual SDHC card connected through a QLROMEXT-compatible interface. QDOS exposes it as `win1_` when the selected ROM contains QL-SD driver 1.08 or newer.

### First test

1. Program the latest main NanoQL bitstream.
2. Download the [MiSTer QL-SD 1.09 ROM package](https://www.kilgus.net/soft/MiSTer_QL_OS_qlsd109.zip) and extract `js_qlsd109.rom` to the microSD root.
3. Download the [QL-SD demonstration image](https://www.kilgus.net/soft/qlsd_win_demo.zip) and extract its `QXL.WIN` to the microSD root.
4. Open the overlay with `F12`. Select `js_qlsd109.rom` under `QL ROM` and the `.WIN` image under `QL-SD image`.
5. Select `Reset QL`, then start QDOS with `F1` or `F2`.
6. Enter `DIR win1_` to verify reads, then `LRUN win1_boot` to start the demonstration system.

For an initial write test, create a short program, use `SAVE win1_nanoql_test`, and verify it with `DIR win1_`. Power NanoQL down cleanly before physically removing the microSD card.

The official demonstration image contains a boot file, utilities, and several ready-to-run games. The usual QL ROM can remain on the card because the menu selects which ROM is used at the next reset.
