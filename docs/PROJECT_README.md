Thread is a small image processing project.

It splits images into tiles, upscales them, and stitches them back together. The CPU path is the default path. CUDA and Metal are optional.

The repo also has a small HTTP API for the same flow.

**Workflow**

Split an image locally.

Upscale the tiles.

Stitch the output.

**Prerequisites**

- macOS with Homebrew, Linux (Ubuntu) with apt, or Windows with Chocolatey
- CMake
- OpenCV is optional for native builds
- NumPy
- Python 3.10+ with pip
- Cloud instance with NVIDIA GPU and CUDA toolkit (for GPU upscaling)

The default local path uses CPU tools and Python packages.

**Setup**

**Quick Setup**
Run the setup script to install all dependencies:

```bash
./scripts/setup.sh
```

**Docker Setup**
For containerized environments:

- **Local CPU components**:
  ```bash
  docker build -t thread .
  docker run --rm thread
  ```
- **CUDA GPU components** (requires NVIDIA GPU):
  ```bash
  docker build -f Dockerfile.cuda -t thread-cuda .
  docker run --rm --gpus all -v /path/to/tiles:/app/tiles thread-cuda ./cloud_gpu/upscaler tiles/input_tile.jpg tiles/output_tile.jpg
  ```

**Manual Setup**

**macOS**

```bash
brew install cmake ninja
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

**Ubuntu**

```bash
sudo apt-get update
sudo apt-get install -y build-essential cmake ninja-build git python3 python3-pip python3-venv
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

**Windows**

```bash
choco install -y cmake ninja python3 git
python -m venv venv
.\venv\Scripts\activate
pip install -r requirements.txt
```

**Cloud GPU**

```bash
# On cloud instance with CUDA
cd cloud_gpu
nvcc upscale.cu -o upscaler -I/usr/include/opencv4 -lopencv_core -lopencv_imgcodecs
```

**Usage**

**Quick Run**
To build, test, and run e2e locally:

```bash
./scripts/run.sh
```

**Testing**
For detailed testing instructions, see TESTING.md[^1].

To run unit tests (parallel execution enabled for faster runs):

```bash
# Python tests (parallel with pytest-xdist)
python3 -m pytest tests/
# C/C++ tests (parallel with ctest)
cd build && ctest -j$(nproc)
# Run benchmark test specifically (verbose output, tests Metal shim performance)
cd build && ctest -R user_counters_tabular_test -V
# End-to-end tests
python3 scripts/e2e.py
```

**Manual Usage**

1. **Split images into tiles** (C++ version with OpenCV):
   ```bash
   ./preprocess path/to/input_images/ path/to/tiles/
   ```
   Or (C version with stb_image, no OpenCV required):
   ```bash
   ./preprocess_c path/to/input_images/ path/to/tiles/
   ```
2. **Transfer tiles to cloud** (configurable via environment variables):
   ```bash
   # Set your cloud configuration
   export CLOUD_IP="your.cloud.ip"
   export CLOUD_USER="ubuntu"
   export CLOUD_PROJECT_PATH="/home/ubuntu/Thread"
   ./scripts/transfer_tiles.sh
   ```
3. **Upscale tiles on cloud**:
   ```bash
   # Single tile
   cd cloud_gpu && ./upscaler input_tile.jpg output_tile.jpg 2

   # Batch process all tiles
   ./scripts/batch_upscale.sh tiles upscaled 2 "*.jpg"
   ```
4. **Stitch upscaled tiles** with flexible grid dimensions:
   ```bash
   # Auto-detect square grid
   python3 scripts/stitch.py path/to/upscaled_tiles/ output_image.jpg

   # Specify custom grid dimensions
   python3 scripts/stitch.py path/to/upscaled_tiles/ output_image.jpg --rows 2 --cols 8

   # Use custom file pattern
   python3 scripts/stitch.py path/to/upscaled_tiles/ output_image.jpg --pattern "upscaled_*.png"
   ```

**Verification**
To ensure the project components work correctly:

- **CUDA Build Check**: Run `scripts/check_cuda_build.sh` on a CUDA-enabled system to verify `upscale.cu` compiles without errors.
- **Local E2E Testing**: The `scripts/run.sh` script simulates the full pipeline (tiling -> copy tiles -> stitching) without actual upscaling or GPU hardware. `scripts/e2e.py` provides additional end-to-end validation.
- **Code Review**: Manually inspect `cloud_gpu/upscale.cu` for CUDA best practices and logic correctness.
- **Troubleshooting**: If you encounter build or test issues, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md)[^4] for common problems and solutions.

**Git Commit Standards**
This project enforces conventional commit standards for clean history:

### Commit Message Format
```
type(scope): short description (<=60 chars)
- optional bullet point 1 (<=72 chars)
- optional bullet point 2
```

### Rules
- **Type**: Must be one of:
  - `feat`: New feature
  - `fix`: Bug fix
  - `docs`: Documentation changes
  - `style`: Code style/formatting
  - `refactor`: Code change that neither fixes a bug nor adds a feature
  - `perf`: Performance improvements
  - `test`: Adding or modifying tests
  - `chore`: Maintenance tasks
  - `ci`: CI/CD related changes
  - `build`: Build system changes
  - `revert`: Revert a previous commit
- **Scope**: Lowercase with hyphens (e.g., `ci`, `api`, `ui`)
- **Description**: Short summary in lowercase (no period at the end)
- **Bullet Points**: Optional, each starting with `- ` and <=72 characters
- **All text must be in lowercase**

### Examples
```
feat(api): add user authentication
- implement jwt token generation
- add login endpoint
fix(ci): resolve build failures
- update cmake minimum version
- fix opencv linking

docs(readme): update contribution guidelines
- add commit message format
- include code style requirements
```

To enable enforcement, copy the hook:

```bash
cp scripts/commit-msg .git/hooks/commit-msg
chmod +x .git/hooks/commit-msg
```
To clean up existing commit messages in history:

```bash
git filter-branch --msg-filter 'bash scripts/rewrite_msg.sh' -- --all
git push --force origin main  # if needed
```

**License**
Copyright (c) 2026, bniladridas. All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions
are met:
  * Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
  * Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in
    the documentation and/or other materials provided with the distribution.
  * Neither the name of bniladridas nor the names of its contributors may be used to endorse or promote products derived
    from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY,
OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

---

This software links to the following components which are not licensed under the above license text.
For details on the specific licenses please refer to the provided links.

- OpenCV: https://opencv.org/license/
- stb_image: https://github.com/nothings/stb/blob/master/LICENSE

[^1]: [TESTING.md](TESTING.md) - Comprehensive testing procedures and guidelines.

[^2]: [DEVELOPMENT.md](../DEVELOPMENT.md) - Development setup, architecture, and contribution guidelines.

[^3]: [ONBOARDING.md](ONBOARDING.md) - Contributor onboarding and compatibility policy.

[^4]: [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Common issues and solutions for build and test problems.

[^5]: [README.md](../README.md) - API design standards and REST best practices.
