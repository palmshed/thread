# Troubleshooting Guide

This guide provides solutions to common issues encountered when building and testing the Thread project.

## Common Issues and Solutions

### 1. Test Failure: Missing cv2 Module

**Error:**
```
ModuleNotFoundError: No module named 'cv2'
Assertion failed: (file_count == 16), function main, file test_preprocess.c, line 67.
```

**Cause:** The Python OpenCV module (cv2) is not installed for the system Python that the tests are using.

**Solution:**
```bash
# Install OpenCV Python bindings for system Python
pip install --break-system-packages opencv-python numpy

# Verify installation
python3 -c "import cv2; print('cv2 works:', cv2.__version__)"
```

**Verification:**
```bash
# Test the specific failing test
ctest --test-dir build -R test_preprocess --output-on-failure

# Run all tests to ensure everything works
ctest --test-dir build --output-on-failure
```

### 2. OpenCV Version Compatibility Warnings

**Warning:**
```
ld: warning: building for macOS-11.0, but linking with dylib
'/opt/homebrew/opt/opencv/lib/libopencv_*.dylib' which was built for newer version 26.0
```

**Cause:** OpenCV libraries were built for a newer macOS version than the CMake target.

**Solutions:**

**Option A: Use Compatible OpenCV Version**
```bash
brew uninstall opencv
brew install opencv@4.8  # Use a specific compatible version
```

**Option B: Update CMake Target (Recommended)**
Add to your `CMakeLists.txt`:
```cmake
set(CMAKE_OSX_DEPLOYMENT_TARGET "14.0")
```

### 3. Missing Dependencies

**Issues:**
- `Could not find nvcc, please set CUDAToolkit_ROOT`
- `Could NOT find OpenMP_C`
- `Could NOT find OpenMP_CXX`

**Solutions:**

**For OpenMP Support (Performance Improvement):**
```bash
brew install libomp
```

**For CUDA Support (GPU Processing):**
```bash
# Only if you have an NVIDIA GPU
# Follow CUDA installation guide for macOS
# Set environment variable:
export CUDAToolkit_ROOT=/usr/local/cuda
```

### 4. Build Issues

**Problem:** Build fails or produces unexpected results.

**Solution: Clean Build**
```bash
rm -rf build
mkdir build
cd build
cmake ..
make -j$(sysctl -n hw.logicalcpu)
```

**Alternative: Out-of-source Build**
```bash
mkdir -p build-debug && cd build-debug
cmake .. -DCMAKE_BUILD_TYPE=Debug
make -j$(sysctl -n hw.logicalcpu)
```

### 5. Python Environment Issues

**Problem:** Multiple Python installations causing conflicts.

**Check Python Paths:**
```bash
which -a python3
python3 -c "import sys; print(sys.path)"
```

**Solutions:**

**Use Virtual Environment:**
```bash
python3 -m venv venv
source venv/bin/activate
pip install opencv-python numpy
```

**Use Homebrew Python:**
```bash
/opt/homebrew/opt/python@3.12/libexec/bin/python3 -c "import cv2"
```

## Quick Fix Recipe

For the most common issue (cv2 module missing):

```bash
# One-liner fix
pip install --break-system-packages opencv-python numpy && ctest --test-dir build --output-on-failure
```

## Verification Commands

After applying fixes, verify everything works:

```bash
# Check cv2 import
python3 -c "import cv2; print('cv2 works:', cv2.__version__)"

# Run specific test
ctest --test-dir build -R test_preprocess --output-on-failure

# Run all tests
ctest --test-dir build --output-on-failure

# Check build status
make -C build
```

## Expected Results

After successful fixes:
- ✅ All 79 tests pass (100% success rate)
- ✅ `test_preprocess` no longer fails
- ✅ cv2 module imports successfully
- ✅ Build completes without errors
- ⚠️ OpenCV version warnings may remain (non-critical)

## Getting Help

If you encounter issues not covered here:

1. Check the [DEVELOPMENT.md](DEVELOPMENT.md) guide
2. Review the [TESTING.md](TESTING.md) documentation
3. Ensure you've followed the setup instructions in [README.md](../README.md)
4. Check that all prerequisites are installed

## Platform-Specific Notes

### macOS
- Use Homebrew for package management
- Xcode Command Line Tools required
- Metal shaders compile automatically

### Linux
- Use apt/yum for system packages
- CUDA toolkit available for GPU support
- OpenMP typically available by default

### Windows
- Use Chocolatey for package management
- Visual Studio Build Tools required
- Google Benchmark disabled by default (linking issues)

## Contributing

If you find additional issues or solutions, please:
1. Update this troubleshooting guide
2. Follow the commit message format in [README.md](../README.md)
3. Test your changes across platforms when possible
