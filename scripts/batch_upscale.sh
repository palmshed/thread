#!/bin/bash

# Batch upscaler script for processing multiple tiles
# Usage: ./batch_upscale.sh <input_dir> <output_dir> [scale] [pattern]

set -e

INPUT_DIR="${1:-tiles}"
OUTPUT_DIR="${2:-upscaled}"
SCALE="${3:-2}"
PATTERN="${4:-*.jpg}"
UPSCALER="${UPSCALER:-./upscaler}"

if [ ! -d "$INPUT_DIR" ]; then
    echo "Error: Input directory '$INPUT_DIR' does not exist"
    exit 1
fi

# Validate INPUT_DIR doesn't start with hyphen to prevent command injection
if [[ "$INPUT_DIR" =~ ^- ]]; then
    echo "Error: Input directory cannot start with '-'"
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

if [ ! -f "$UPSCALER" ]; then
    echo "Error: Upscaler binary '$UPSCALER' not found"
    echo "Build it first with: nvcc cloud_gpu/upscale.cu -o upscaler -I/usr/local/include/opencv4 -L/usr/local/lib -lopencv_core -lopencv_imgcodecs -lopencv_imgproc -lopencv_highgui -std=c++17"
    exit 1
fi

echo "Processing tiles from $INPUT_DIR to $OUTPUT_DIR with scale $SCALE"
echo "Pattern: $PATTERN"

# Use find to get file list and check if any files exist (prevent command injection)
files=$(find "$INPUT_DIR" -maxdepth 1 -name "$PATTERN" -type f)

if [ -z "$files" ]; then
    echo "Error: No files found matching pattern '$PATTERN' in $INPUT_DIR"
    exit 1
fi

count=0
while IFS= read -r file; do
    if [ -f "$file" ]; then
        basename=$(basename "$file")
        output_file="$OUTPUT_DIR/$basename"
        echo "Processing: $basename"
        "$UPSCALER" "$file" "$output_file" "$SCALE"
        ((count += 1))
    fi
done <<< "$files"

echo "Processed $count files"
