#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause
# Copyright (c) 2026, bniladridas. All rights reserved.

# Quick script to create CUDA release for current version

set -euo pipefail

# Extract current CUDA version
CUDA_VERSION=$(grep "ARG CUDA_VERSION=" Dockerfile.cuda | cut -d= -f2)
BASE_VERSION=$(tr -d '[:space:]' < VERSION)
MIN_CUDA_VERSION="${MIN_CUDA_VERSION:-12.0.0}"
BRANCH_NAME="cuda-$CUDA_VERSION"
TAG_NAME="v${BASE_VERSION}-cuda-$CUDA_VERSION"

if [[ "$(printf '%s\n%s\n' "$MIN_CUDA_VERSION" "$CUDA_VERSION" | sort -V | tail -n 1)" != "$CUDA_VERSION" ]]; then
    echo "[ERROR] CUDA version $CUDA_VERSION is below minimum supported version $MIN_CUDA_VERSION" >&2
    exit 1
fi

echo "🚀 Creating release ${TAG_NAME}"

# Create and push branch
git checkout -b "$BRANCH_NAME" 2>/dev/null || git checkout "$BRANCH_NAME"
git push -u origin "$BRANCH_NAME"

# Create and push tag
git tag -a "$TAG_NAME" -m "Release v${BASE_VERSION} with CUDA $CUDA_VERSION support"
git push origin "$TAG_NAME"

# Create GitHub release
gh release create "$TAG_NAME" \
    --title "v${BASE_VERSION} - CUDA $CUDA_VERSION" \
    --notes "Release v${BASE_VERSION} with CUDA $CUDA_VERSION support

**CUDA Version:** $CUDA_VERSION
**Ubuntu Version:** 24.04

**Features:**
- Cross-platform GPU-accelerated image processing
- CUDA-to-Metal compatibility shim for macOS
- Dynamic Python version support in Docker
- Parameterized CUDA/Ubuntu versions

**Docker Usage:**
\`\`\`bash
docker build -f Dockerfile.cuda -t thread-cuda:$CUDA_VERSION .
\`\`\`"

git checkout main

echo "✅ Release created: https://github.com/$(gh repo view --json owner,name -q '.owner.login + "/" + .name')/releases/tag/$TAG_NAME"
