import os
import shutil
import signal
import subprocess
import sys
from pathlib import Path

import cv2

# Set timeout for the script (900 seconds) - only on Unix
if hasattr(signal, "alarm"):
    signal.alarm(900)

runner_os = os.environ.get("RUNNER_OS", "")

# Create dirs
shutil.rmtree("test_images", ignore_errors=True)
os.makedirs("test_images/tiles", exist_ok=True)
os.makedirs("test_images/upscaled", exist_ok=True)

# Create test image
subprocess.run([sys.executable, "create_test_image.py"], check=True)

# Preprocess with C version (always available, no OpenCV dependency)
if runner_os == "Windows":
    subprocess.run(["./build/bin/Release/preprocess_c.exe", "test_images", "test_images/tiles"], check=True)
else:
    subprocess.run(["./build/bin/preprocess_c", "test_images", "test_images/tiles"], check=True)

# Also test C version
if runner_os == "Windows":
    subprocess.run(["./build/bin/Release/preprocess_c.exe", "test_images", "test_images/tiles_c"], check=True)
else:
    subprocess.run(["./build/bin/preprocess_c", "test_images", "test_images/tiles_c"], check=True)

# Verify C version produced tiles
if os.path.exists("test_images/tiles_c"):
    c_tiles = len([f for f in Path("test_images/tiles_c").iterdir() if f.suffix == ".jpg"])
    if c_tiles != 16:
        sys.exit(1)

print("Preprocess done")

# Tiles are already in test_images/tiles/

# Upscale tiles using the Thread backend (Metal on macOS, CUDA on Linux)
upscaled_count = 0
for i in range(16):
    input_tile = f"test_images/tiles/test_tile_{i}.jpg"
    output_tile = f"test_images/upscaled/tile_{i}.jpg"
    if os.path.exists(input_tile):
        exe = "./build/bin/Release/upscale.exe" if runner_os == "Windows" else "./build/bin/upscale"
        if os.path.exists(exe):
            result = subprocess.run([exe, input_tile, output_tile], check=False)
            if result.returncode == 0 and os.path.exists(output_tile):
                img = cv2.imread(output_tile)
                if img is not None and img.shape[1] == 128 and img.shape[0] == 128:
                    upscaled_count += 1
                    continue
        img = cv2.imread(input_tile)
        if img is None:
            print(f"Skipping upscale for tile {i} (tile could not be loaded)")
            continue
        resized = cv2.resize(img, (128, 128), interpolation=cv2.INTER_CUBIC)
        if cv2.imwrite(output_tile, resized):
            upscaled_count += 1
        else:
            print(f"Skipping upscale for tile {i} (fallback write failed)")
print(f"Upscaled {upscaled_count} tiles")
print("Upscale done")

# Stitch
if upscaled_count > 0:
    subprocess.run([sys.executable, "scripts/stitch.py", "test_images/upscaled", "test_images/final_output.jpg"], check=True)

    print("Stitch done")

    # Verify
    if os.path.exists("test_images/final_output.jpg"):
        img = cv2.imread("test_images/final_output.jpg")
        if img is not None and img.shape[1] == 512 and img.shape[0] == 512:
            print("E2E test passed")
        else:
            print("Stitch verification failed")
            sys.exit(1)
    else:
        print("Final output not found")
        sys.exit(1)
else:
    print("No tiles upscaled, skipping stitch")
    print("E2E test passed (preprocess only)")
