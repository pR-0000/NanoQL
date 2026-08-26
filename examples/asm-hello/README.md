# NanoQL 68000 Hello World

## Français

Cet exemple illustre la boucle de développement la plus courte de NanoQL : assembler un programme 68000 brut, l'envoyer directement dans la RAM physique, le vérifier puis l'exécuter sans image disque ni ligne SuperBASIC.

1. Installez `vasmm68k_mot` et placez-le dans le `PATH`, ou indiquez son chemin avec `--assembler`.
2. Démarrez NanoQL normalement et appuyez une fois brièvement sur `S1` pour activer NanoQL Link.
3. Depuis la racine du dépôt, exécutez :

```sh
python examples/asm-hello/build_and_run.py --port COM20
```

Le script ci-dessus ne fait qu'enchaîner les deux commandes suivantes. Pour comprendre la procédure, employer un autre compilateur ou l'intégrer à votre propre projet, vous pouvez les lancer directement depuis la racine du dépôt :

```sh
vasmm68k_mot -m68000 -Fbin -quiet -o examples/asm-hello/hello.bin examples/asm-hello/hello.asm
python tools/nanoql_link.py --port COM20 load examples/asm-hello/hello.bin --address 0x30000 --pc 0x30000 --stack 0x3fff0
```

La première ligne peut être remplacée par n'importe quel assembleur ou compilateur capable de produire un binaire 68000 brut, big-endian et lié pour l'adresse `$30000`. La seconde ligne est toujours la commande NanoQL Link qui arrête le QL, transfère et vérifie le fichier, puis lance son premier opcode.

Sous macOS ou Linux, remplacez `COM20` par le port `/dev/cu.usbmodem...` ou `/dev/ttyACM...`. Si un seul port NanoQL Link est présent, `--port` peut être omis. Pour un assembleur qui n'est pas dans le `PATH` :

```sh
python examples/asm-hello/build_and_run.py --port COM20 --assembler /chemin/vers/vasmm68k_mot
```

Le programme est assemblé à `$30000`, chargé avec une pile initiale à `$3FFF0`, puis dessine `HELLO NANOQL` directement dans la VRAM MODE 4 à `$20000`. Il reste dans une boucle afin de faciliter l'inspection de la mémoire. Pour revenir à QDOS :

```sh
python tools/nanoql_link.py --port COM20 qdos
```

Le mode d'injection accepte un binaire **brut, big-endian et à adresse fixe**. Il ne charge pas les en-têtes exécutables QDOS et n'effectue aucune relocalisation.

## English

This example demonstrates NanoQL's shortest development loop: assemble a raw 68000 program, upload it directly to physical RAM, verify it, and execute it without a disk image or SuperBASIC loader.

1. Install `vasmm68k_mot` and add it to `PATH`, or pass its path with `--assembler`.
2. Start NanoQL normally and briefly press `S1` once to enable NanoQL Link.
3. From the repository root, run:

```sh
python examples/asm-hello/build_and_run.py --port COM20
```

The helper merely runs the following two commands. Run them directly to understand the process, use another compiler, or integrate NanoQL into your own build system:

```sh
vasmm68k_mot -m68000 -Fbin -quiet -o examples/asm-hello/hello.bin examples/asm-hello/hello.asm
python tools/nanoql_link.py --port COM20 load examples/asm-hello/hello.bin --address 0x30000 --pc 0x30000 --stack 0x3fff0
```

The first line can be replaced by any assembler or compiler that produces a raw, big-endian 68000 binary linked for address `$30000`. The second is the NanoQL Link command that stops the QL, uploads and verifies the file, then starts its first opcode.

On macOS or Linux, replace `COM20` with `/dev/cu.usbmodem...` or `/dev/ttyACM...`. Omit `--port` when only one NanoQL Link port is present. For an assembler outside `PATH`:

```sh
python examples/asm-hello/build_and_run.py --port COM20 --assembler /path/to/vasmm68k_mot
```

The program is assembled at `$30000`, starts with its stack at `$3FFF0`, and draws `HELLO NANOQL` directly into MODE 4 VRAM at `$20000`. It then loops to make memory inspection convenient. Return to QDOS with:

```sh
python tools/nanoql_link.py --port COM20 qdos
```

Direct injection accepts a **raw, big-endian, fixed-address** binary. It does not load QDOS executable headers or perform relocation.
