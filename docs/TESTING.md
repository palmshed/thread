# Testing and Benchmarking Guide

This document provides information on how to run tests and benchmarks for the Metal shim implementation.

## Prerequisites

- Xcode command line tools
- CMake 3.10+
- C++17 compatible compiler
- Metal-capable macOS device

## Code Quality

Before running tests, ensure code quality standards are met using pre-commit hooks:

```bash
pre-commit run --all-files
```

### Quality Checks Overview

| Check | GitHub Actions | CircleCI | Tools |
|-------|----------------|----------|-------|
| Code Formatting | ✓ | ✓ | Black, isort |
| Linting | ✓ | ✓ | Ruff |
| YAML Validation | ✓ | ✓ | yamllint |
| File Checks | ✓ | ✓ | pre-commit-hooks |
| Security Analysis | ✓ | ✓ | CodeQL |
| Container Scanning | ✓ | ✓ | Trivy |
| Commit Messages | ✓ | ✓ | commit-msg hook |

## Running Tests

### Unit Tests

To build and run the unit tests:

```bash
mkdir -p build && cd build
cmake .. -DBUILD_TESTS=ON
make
ctest --output-on-failure
```

### Performance Benchmarks

To run the performance benchmarks:

```bash
cd build
./bin/benchmark_metal_shim --benchmark_min_time=1s
```

#### Running Individual Benchmarks Locally

For manual testing or debugging:

```bash
# Build first
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
# On Linux:
make -j$(nproc)
# On macOS:
make -j$(sysctl -n hw.ncpu)

# Run benchmark library tests (e.g., user counters)
./bin/user_counters_tabular_test --benchmark_min_time=1s --benchmark_repetitions=3

# Run project performance benchmarks (Metal shim)
./bin/benchmark_metal_shim
```

### Test Coverage

To generate a test coverage report (requires `gcov` and `lcov`):

```bash
mkdir -p build_coverage && cd build_coverage
cmake .. -DCMAKE_BUILD_TYPE=Debug -DENABLE_COVERAGE=ON
make
test_metal_shim
lcov --capture --directory . --output-file coverage.info
genhtml coverage.info --output-directory coverage
open coverage/index.html
```

## Writing Tests

### Unit Tests

- Place unit tests in `tests/unit/`
- Use Google Test framework
- Test files should be named `test_*.cpp`
- Test cases should be small and focused

### Benchmark Tests

- Place benchmark tests in `tests/performance/`
- Use Google Benchmark framework
- Test files should be named `benchmark_*.cpp`
- Include a range of input sizes

## CI/CD Integration

Tests run on pull requests and pushes to the main branch. The main checks are:

### CI Pipeline Components

- Build verification across platforms (Linux, macOS, Windows)
- Unit tests with multiple Python versions
- Code style checks and formatting validation
- Security vulnerability scanning
- Performance benchmarking
- Docker container builds and testing
- Documentation build

## Performance Profiling

To profile the Metal shim:

1. Use Xcode's Instruments
2. Select the Time Profiler
3. Run your benchmark or test
4. Analyze the results

## Memory Management

Use the following tools to check for memory issues:

- Xcode's Memory Graph Debugger
- Address Sanitizer (add `-fsanitize=address` to compiler flags)
- Leak Sanitizer (add `-fsanitize=leak` to compiler flags)

## Troubleshooting

### Test Executable Not Found

If `ctest` reports "Could not find executable", build first:

```bash
cmake --build build
cd build && ctest -R user_counters_tabular_test -V
```

## Best Practices

- Write tests for all new features
- Update tests when modifying existing code
- Keep tests independent and isolated
- Use meaningful test names
- Include assertions for expected behavior
- Test edge cases and error conditions
- Document test assumptions and requirements
