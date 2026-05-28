#!/bin/bash

# Configuration - update these values for your setup
CLOUD_IP="${CLOUD_IP:-YOUR_CLOUD_IP}"
CLOUD_USER="${CLOUD_USER:-ubuntu}"
CLOUD_PROJECT_PATH="${CLOUD_PROJECT_PATH:-/home/ubuntu/Thread}"
LOCAL_TILES_DIR="${LOCAL_TILES_DIR:-./test_images/tiles}"
REMOTE_TILES_DIR="${REMOTE_TILES_DIR:-tiles}"
UPSCALER_NAME="${UPSCALER_NAME:-upscaler}"

# Validate inputs to prevent injection attacks
validate_input() {
    local input="$1"
    local name="$2"

    # Check for dangerous characters (including spaces and quotes)
    if [[ "$input" =~ [[:space:];\|\&\$\`\(\)\"\'\<\>\{\}\[\]] ]]; then
        echo "Error: $name contains dangerous characters"
        exit 1
    fi

    # Check for option injection (starting with -)
    if [[ "$input" =~ ^- ]]; then
        echo "Error: $name cannot start with '-'"
        exit 1
    fi
}

# Validate all user inputs
validate_input "$CLOUD_IP" "CLOUD_IP"
validate_input "$CLOUD_USER" "CLOUD_USER"
validate_input "$CLOUD_PROJECT_PATH" "CLOUD_PROJECT_PATH"
validate_input "$LOCAL_TILES_DIR" "LOCAL_TILES_DIR"
validate_input "$REMOTE_TILES_DIR" "REMOTE_TILES_DIR"
validate_input "$UPSCALER_NAME" "UPSCALER_NAME"

if [ "$CLOUD_IP" = "YOUR_CLOUD_IP" ]; then
    echo "Error: Please set CLOUD_IP environment variable or update the script"
    echo "Usage: CLOUD_IP=x.x.x.x $0"
    exit 1
fi

if [ ! -d "$LOCAL_TILES_DIR" ]; then
    echo "Error: Local tiles directory '$LOCAL_TILES_DIR' does not exist"
    echo "Please create the directory or set LOCAL_TILES_DIR environment variable"
    exit 1
fi

echo "Transferring tiles from $LOCAL_TILES_DIR to $CLOUD_USER@$CLOUD_IP:$CLOUD_PROJECT_PATH/$REMOTE_TILES_DIR"

# Transfer tiles to cloud with proper quoting
scp -r "$LOCAL_TILES_DIR" "$CLOUD_USER@$CLOUD_IP:$CLOUD_PROJECT_PATH/$REMOTE_TILES_DIR"

echo "Building CUDA upscaler on cloud..."
# Build CUDA upscaler on cloud with proper variable passing
ssh "$CLOUD_USER@$CLOUD_IP" "PROJECT_PATH=$(printf '%q' "$CLOUD_PROJECT_PATH") UPSCALER=$(printf '%q' "$UPSCALER_NAME") bash -c 'cd \"\$PROJECT_PATH\" && nvcc cloud_gpu/upscale.cu -o \"\$UPSCALER\" -I/usr/local/include/opencv4 -L/usr/local/lib -lopencv_core -lopencv_imgcodecs -lopencv_imgproc -lopencv_highgui -std=c++17'"

echo "Processing complete. Transfer results back with:"
echo "scp -r $(printf '%q' "$CLOUD_USER@$CLOUD_IP:$CLOUD_PROJECT_PATH/upscaled") ./test_images/"
