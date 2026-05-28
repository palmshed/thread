# Compatibility Matrix

## Language Versions
- Python: 3.10+ (tested: 3.10, 3.11, 3.12, 3.13, 3.14)
- C++: 20 required
- CUDA: 12.0+ optional (tested: 12.6.1, 13.0.1, 13.0.2, 13.1.0, 13.1.1)
- Objective-C++: 17 for macOS Metal support
- Metal: 3.0+ for macOS Metal acceleration

## Build Tools
- CMake: 3.10+ required, 3.21+ recommended for CUDA and Metal support
- CUDA Toolkit: 12.0+ optional
- Xcode: 14.0+ for macOS Metal development
- Ninja: 1.10+ recommended
- Make: 4.3+ supported

## Core Dependencies
- OpenCV: 4.0+ required, 4.5.0+ recommended, CUDA support optional
- Eigen: 3.4.0+ required
- GTest: 1.12.0+ for unit testing
- pybind11: 2.10.0+ for Python bindings
- NumPy: 1.21.0+ required for the Python interface

## Platform-Specific

### Linux
#### Ubuntu
- Ubuntu 22.04+ LTS tested on 22.04 and 24.04
- GCC: 11.0+ or Clang: 14.0+
- `libtbb12` (TBB 2021.0+)
- CUDA: 12.0+ for GPU support
- OpenCV: 4.0+ with 4.5.0+ recommended

#### Other Linux Distributions
- GCC: 11.0+ or Clang: 14.0+
- `libtbb12` (TBB 2021.0+)

### Windows
- Visual Studio 2022 (17.0+) with C++ CMake tools
- Windows SDK 10.0.19041.0+

### macOS
- Xcode 14.0+
- macOS 12.0+ (Monterey)
- Metal Shading Language 2.4+

## Optional Dependencies
- TensorRT: 8.5+ for TensorRT acceleration
- ONNX Runtime: 1.13.0+ for ONNX model support
- TensorFlow: 2.12.0+ optional
- PyTorch: 2.0.0+ optional
