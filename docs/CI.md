# Checks

This page explains the checks used by Thread.

## Overview

The main checks build the code, run tests, and validate release files. Docs deploy when the static site changes. Other workflows are manual.

## Workflows

### CI

Runs on pushes and pull requests to `main`.

It checks Python, C/C++ build paths, tests, and packaging.

### Release Check

Runs when release files change. It keeps `VERSION`, Python metadata, and vcpkg metadata in sync.

## Supported Platforms

- **Linux**: CPU and CUDA paths
- **macOS**: CPU and Metal paths
- **Windows**: CPU path
- **Docker**: CPU and CUDA images

## Key Features

- CI runs only where it is useful.
- Manual workflows stay manual.
- Release checks fail on version drift.
- Docs deploy from `docs/web`.

## Configuration

GitHub Actions lives in `.github/workflows`.

CircleCI lives in `.circleci/config.yml`.

## Getting Started

To run the pipeline locally or contribute changes:

Push a branch and open a pull request.

Fix failing checks before merging.
