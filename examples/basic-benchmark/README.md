# Vintage Basic Benchmark for Sinclair QL

This example is the Sinclair QL version of Lawrence Woodman's Vintage Basic Benchmark. It is redistributed unchanged under the MIT License from:

https://github.com/lawrencewoodman/vintage_basic_benchmark

NanoQL Link can enter the source directly into QDOS and start it:

```sh
python tools/nanoql_link.py --port COMx benchmark
```

Each of the seven tests lasts 20 seconds. Higher results are faster. Run it once with the NanoQL OSD CPU setting at `QL`, then again at `16 MHz`.

The Microdrive path avoids remote keyboard entry and does not require development mode. Copy `bench_ql_bas` to this folder on the microSD:

```text
NanoQL/Microdrives/Benchmark/bench_ql_bas
```

Open the `F12` overlay, select **Build MDV1 from:** and then `Benchmark`. NanoQL builds and mounts the cartridge for the current session, then restarts the QL. At the SuperBASIC prompt, enter:

```text
DIR mdv1_
LRUN mdv1_bench_ql_bas
```

`DIR` verifies the physical Microdrive stream and directory. `LRUN` loads and starts the benchmark through the unmodified QDOS Microdrive driver.

Developers can alternatively run `python tools/nanoql_link.py --port COMx mdv-sync examples/basic-benchmark` while NanoQL Link is active.
