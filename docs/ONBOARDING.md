# Onboarding & Compatibility Policy

## Onboarding Guide

Welcome to the Thread project. This guide introduces the architecture, workflow, and platform requirements for contributors and users.

### For New Contributors

#### 1. Development Environment Setup

Follow the setup instructions in [README.md](../README.md) based on your platform (macOS, Linux, or Windows).

#### 2. Architecture Overview

Thread consists of:

* **Local CPU Processing**: Image tiling and stitching using C/C++ with OpenCV or stb_image
* **GPU Acceleration**: CUDA (Linux/Windows) or Metal (macOS) for upscaling operations
* **Python Orchestration**: Pipeline coordination and testing

#### 3. Development Workflow

1. Fork and clone the repository
2. Create a feature branch from `main`
3. Implement changes following the [commit standards](../README.md#git-commit-standards)
4. Run the full test suite (`./scripts/run.sh`)
5. Open a pull request with a clear description

#### 4. Important Files

* `CMakeLists.txt`: Build configuration
* `src/preprocess.c`: CPU image preprocessing
* `cloud_gpu/upscale.cu`: CUDA upscaling
* `src/metal/Upscale.metal`: Metal shader implementation
* `scripts/e2e.py`: End-to-end testing logic

#### 5. Testing Requirements

All changes must pass:

* Unit tests (`ctest`)
* Integration tests (`pytest`)
* Cross-platform builds (macOS, Linux, Windows)
* Docker-based isolation tests

### For Users

#### Quick Start

```bash
./scripts/setup.sh
./scripts/run.sh
```

#### Troubleshooting

* **Build issues**: Refer to [DEVELOPMENT.md](../DEVELOPMENT.md)
* **GPU issues**: Validate CUDA/Metal driver installation
* **Performance concerns**: Run benchmarks to verify acceleration

## Compatibility Policy

### Supported Platforms

| Platform      | Architecture  | GPU Support | Status |
| ------------- | ------------- | ----------- | ------ |
| macOS 11.0+   | x86_64, ARM64 | Metal       | Active |
| Ubuntu 20.04+ | x86_64        | CUDA 11.8+  | Active |
| Windows 10+   | x86_64        | CUDA 11.8+  | Active |

### Language Versions

* C/C++: C17 / C++20
* CUDA: 11.8+
* Metal: macOS 11.0+
* Python: 3.10+

### Dependencies

#### Required

* CMake 3.10+
* CUDA Toolkit 11.8+ (for GPU builds)
* OpenCV 4.x (optional; stb_image is the fallback)

#### Optional

* Google Benchmark (performance testing)
* OpenMP (parallel CPU processing)

### Compatibility Guarantees

#### API Stability

* **Major** (X.0.0): Breaking changes allowed
* **Minor** (x.Y.0): Backward-compatible feature additions
* **Patch** (x.y.Z): Bug fixes only

#### Platform Support Levels

* **Active**: Fully tested in CI
* **Deprecated**: Functional but untested
* **Removed**: No longer supported

#### GPU Compatibility

* CUDA: NVIDIA GPUs supporting CUDA 11.8+
* Metal: Apple Silicon and Intel-based macOS 11.0+ hardware

### Breaking Changes Policy

Breaking changes will:

1. Be documented in release notes
2. Include deprecation warnings when possible
3. Provide at least one minor version notice before removal

### Testing Compatibility

Compatibility is validated across:

* Multiple OS versions
* Diverse GPU configurations
* CPU fallback modes
* Containerized environments

### Support Timeline

* Bug fixes: 2 years after initial release
* Security updates: 3 years
* Platform support: Maintained as long as the vendor supports the platform

### Proposing Compatibility Changes

Contributors must:

1. Update this document
2. Adjust CI matrices
3. Update dependency constraints
4. Validate changes across all supported systems

For questions about onboarding or compatibility, open an issue or discussion on GitHub.
