#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause
# Copyright (c) 2026, bniladridas. All rights reserved.

set -euo pipefail

echo "[INFO] Starting automated CUDA release creation..."
BASE_VERSION=$(tr -d '[:space:]' < VERSION)
DRY_RUN="${DRY_RUN:-false}"
MIN_CUDA_VERSION="${MIN_CUDA_VERSION:-12.0.0}"

if [[ ! "$BASE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "[ERROR] VERSION must contain a single semantic version, found: ${BASE_VERSION}" >&2
    exit 1
fi

echo "[INFO] Dry run: ${DRY_RUN}"
echo "[INFO] Minimum CUDA release version: ${MIN_CUDA_VERSION}"

version_gte() {
    local left=$1
    local right=$2
    [[ "$(printf '%s\n%s\n' "$right" "$left" | sort -V | tail -n 1)" == "$left" ]]
}

# Function to extract CUDA version from Dockerfile
get_cuda_version() {
    local commit=$1
    git show "$commit:Dockerfile.cuda" 2>/dev/null | grep -o 'nvidia/cuda:[0-9]\+\.[0-9]\+\.[0-9]\+' | head -1 | cut -d: -f2 || echo ""
}

# Function to create branch, tag, and release
create_cuda_release() {
    local commit=$1
    local cuda_version=$2
    local branch_name="cuda-$cuda_version"
    local tag_name="v${BASE_VERSION}-cuda-$cuda_version"

    echo "[INFO] Processing CUDA $cuda_version from commit $commit"

    if ! version_gte "$cuda_version" "$MIN_CUDA_VERSION"; then
        echo "[SKIP] CUDA $cuda_version is below minimum supported version $MIN_CUDA_VERSION"
        return 0
    fi

    # Check if branch already exists
    if git show-ref --verify --quiet "refs/heads/$branch_name" 2>/dev/null; then
        echo "[SKIP] Branch $branch_name already exists"
        return 0
    fi

    # Check if remote branch exists
    if [[ "$DRY_RUN" != "true" ]] && git ls-remote --heads origin "$branch_name" | grep -q "$branch_name"; then
        echo "[SKIP] Remote branch $branch_name already exists"
        return 0
    fi

    # Create branch from commit
    echo "[INFO] Creating branch $branch_name from commit $commit"
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY RUN] Would create branch $branch_name from commit $commit"
    else
        git checkout "$commit" -b "$branch_name" 2>/dev/null || {
            echo "[WARN] Could not create branch, may already exist locally"
            git checkout "$branch_name" 2>/dev/null || return 1
        }
    fi

    # Push branch
    echo "[INFO] Pushing branch $branch_name"
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY RUN] Would push branch $branch_name"
    else
        git push -u origin "$branch_name" || echo "[WARN] Branch push failed or already exists"
    fi

    # Check if tag already exists
    if git tag -l | grep -q "^$tag_name$"; then
        echo "[SKIP] Tag $tag_name already exists"
    else
        # Create tag
        echo "[INFO] Creating tag $tag_name"
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "[DRY RUN] Would create tag $tag_name"
        else
            git tag -a "$tag_name" -m "Release v${BASE_VERSION} with CUDA $cuda_version support" || echo "[WARN] Tag creation failed"
        fi

        # Push tag
        echo "[INFO] Pushing tag $tag_name"
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "[DRY RUN] Would push tag $tag_name"
        else
            git push origin "$tag_name" || echo "[WARN] Tag push failed or already exists"
        fi
    fi

    # Check if release already exists
    if gh release view "$tag_name" >/dev/null 2>&1; then
        echo "[SKIP] Release $tag_name already exists"
    else
        # Create GitHub release
        echo "[INFO] Creating GitHub release $tag_name"
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "[DRY RUN] Would create GitHub release $tag_name"
        else
            gh release create "$tag_name" \
                --title "v${BASE_VERSION} - CUDA $cuda_version" \
                --notes "Release v${BASE_VERSION} with CUDA $cuda_version support

**CUDA Version:** $cuda_version
**Ubuntu Version:** 24.04

**Docker Usage:**
\`\`\`bash
docker build -f Dockerfile.cuda -t thread-cuda:$cuda_version .
\`\`\`" || echo "[WARN] Release creation failed or already exists"
        fi
    fi

    echo "[PASS] Completed processing CUDA $cuda_version"
}

# Main script
echo "[INFO] Scanning git history for CUDA versions..."

# Get commits that modified Dockerfile.cuda
commits=$(git log --oneline --follow Dockerfile.cuda | awk '{print $1}')

seen_versions=""
processed_versions=""
processed_count=0
skipped_versions=""

for commit in $commits; do
    cuda_version=$(get_cuda_version "$commit")

    if [[ -n "$cuda_version" && ",$seen_versions," != *",$cuda_version,"* ]]; then
        if [[ -z "$seen_versions" ]]; then
            seen_versions="$cuda_version"
        else
            seen_versions="$seen_versions,$cuda_version"
        fi
        if version_gte "$cuda_version" "$MIN_CUDA_VERSION"; then
            create_cuda_release "$commit" "$cuda_version"
            if [[ -z "$processed_versions" ]]; then
                processed_versions="$cuda_version"
            else
                processed_versions="$processed_versions,$cuda_version"
            fi
            processed_count=$((processed_count + 1))
        else
            echo "[SKIP] Ignoring historical CUDA version $cuda_version below minimum $MIN_CUDA_VERSION"
            if [[ -z "$skipped_versions" ]]; then
                skipped_versions="$cuda_version"
            else
                skipped_versions="$skipped_versions,$cuda_version"
            fi
        fi
    fi
done

# Return to main branch
if [[ "$DRY_RUN" != "true" ]]; then
    git checkout main >/dev/null 2>&1 || true
fi

echo "[PASS] CUDA release automation complete!"
echo "[INFO] Processed $processed_count unique CUDA versions: ${processed_versions}"
if [[ -n "$skipped_versions" ]]; then
    echo "[INFO] Skipped unsupported CUDA versions: ${skipped_versions}"
fi
