# Vintage Basic Benchmark for Sinclair QL

This example is the Sinclair QL version of Lawrence Woodman's Vintage Basic Benchmark. It is redistributed unchanged under the MIT License from:

https://github.com/lawrencewoodman/vintage_basic_benchmark

NanoQL Link can enter the source directly into QDOS and start it:

```sh
python tools/nanoql_link.py --port COM20 benchmark
```

Each of the seven tests lasts 20 seconds. Higher results are faster. Run it once with the NanoQL OSD CPU setting at `QL`, then again at `16 MHz`.
