<p align="center">
  <img src="https://raw.githubusercontent.com/bniladridas/thread/main/.github/thread-flow.png" alt="Thread image flow" width="480">
</p>

# Thread

Thread is an image pipeline.

It takes one image.

It makes tiles.

It can upscale tiles.

It can stitch tiles back into one image.

It has a local API.

<br>

## Stack

`hautofix → vortai → thread → mlapi`

Depends on: vortai, mlapi.

<br>

# What Works Now

| Part | State |
| --- | --- |
| Python API | Active |
| Upload image | Active |
| Make tiles | Active |
| CPU upscale fallback | Active |
| Stitch output | Active |
| C preprocessor | Active |
| CUDA | Optional |
| Metal | Optional |

The default path is CPU.

CUDA and Metal are not needed for the local flow.

<br>

# Run It

Install tools.

```bash
bash scripts/setup.sh
```

What the setup script does:

| Area | Default |
| --- | --- |
| macOS | Homebrew, CMake, Ninja, Xcode command line tools |
| Linux | apt packages for CMake, Ninja, Python, Git |
| Windows | Chocolatey packages for CMake, Ninja, Python, Git |
| Python | `venv`, requirements, test and lint tools |
| Native OpenCV | Off |
| Metal tools | Off |
| CUDA install | Off |

Optional setup:

| Need | Command |
| --- | --- |
| Native OpenCV packages | `INSTALL_NATIVE_OPENCV=true bash scripts/setup.sh` |
| Apple Metal tools | `WITH_METAL=ON bash scripts/setup.sh` |
| CUDA toolkit on Linux | `INSTALL_CUDA=true bash scripts/setup.sh` |

Build CPU path.

```bash
cmake -S . -B build -DUSE_CUDA=OFF -DWITH_OPENCV=OFF -DWITH_METAL=OFF -DENABLE_BENCHMARK=OFF
cmake --build build --parallel
ctest --test-dir build --output-on-failure
```

Run Python tests.

```bash
python -m pytest
```

Run full image flow.

```bash
python scripts/e2e.py
```

Start API.

```bash
python api/server.py
```

API: `http://localhost:5001`.

<br>

# API

Version: `v1`.

Upload an image:

```bash
curl -X POST http://localhost:5001/v1/images \
  -F "file=@image.jpg"
```

Create tiles:

```bash
curl -X POST http://localhost:5001/v1/images/<image_id>/tiles \
  -H "Content-Type: application/json" \
  -d '{"tile_size": 512}'
```

Upscale a tile:

```bash
curl -X POST http://localhost:5001/v1/tiles/<tile_id>/upscale \
  -H "Content-Type: application/json" \
  -d '{"scale": 2}'
```

Stitch tiles:

```bash
curl -X POST http://localhost:5001/v1/stitch \
  -H "Content-Type: application/json" \
  -d '{"tile_ids": ["tile_0", "tile_1", "tile_2", "tile_3"], "rows": 2, "cols": 2}'
```

<br>

# Build Notes

Use `WITH_METAL=ON` only with Apple Metal tools.

Use `USE_CUDA=ON` only with CUDA.

The default build keeps both off.

<br>

# Project Layout

| Path | Use |
| --- | --- |
| `api/` | Flask API |
| `src/` | Local preprocess and Metal code |
| `cloud_gpu/` | CUDA code |
| `scripts/` | Setup, tests, image flow |
| `tests/` | C and Python tests |
| `docs/` | Notes and small site |

<br>

# Checks

| Check | State |
| --- | --- |
| Build | Active |
| Tests | Active |
| Release check | Active |
| Docs deploy | Active |
| Extra workflows | Manual or slash command |

<br>

# License

BSD 3-Clause. See [LICENSE](LICENSE).
