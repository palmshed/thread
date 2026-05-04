#ifdef _WIN32
#define _CRT_SECURE_NO_WARNINGS
#include <direct.h>
#include <windows.h>
#else
#include <dirent.h>
#endif

#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"
#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#include <sys/stat.h>
#include <sys/types.h>

void splitImageIntoTiles(unsigned char *image, int width, int height,
                         int channels, int tile_size, const char *output_folder,
                         const char *base_name) {
  int tile_index = 0;
  for (int y = 0; y < height; y += tile_size) {
    for (int x = 0; x < width; x += tile_size) {
      int tile_w = (x + tile_size > width) ? width - x : tile_size;
      int tile_h = (y + tile_size > height) ? height - y : tile_size;
      if (tile_w <= 0 || tile_h <= 0 || channels <= 0) {
        fprintf(stderr, "Invalid tile dimensions or channel count\n");
        continue;
      }
      if ((size_t)tile_w > SIZE_MAX / (size_t)tile_h) {
        fprintf(stderr, "Tile size overflow during allocation\n");
        continue;
      }
      size_t tile_pixels = (size_t)tile_w * (size_t)tile_h;
      if (tile_pixels > SIZE_MAX / (size_t)channels) {
        fprintf(stderr, "Tile buffer overflow during allocation\n");
        continue;
      }
      size_t tile_bytes = tile_pixels * (size_t)channels;
      unsigned char *tile_data = (unsigned char *)malloc(tile_bytes);
      if (!tile_data) {
        fprintf(stderr, "Failed to allocate memory for tile\n");
        continue;
      }
      for (int ty = 0; ty < tile_h; ++ty) {
        for (int tx = 0; tx < tile_w; ++tx) {
          int src_x = x + tx;
          int src_y = y + ty;
          int src_idx = (src_y * width + src_x) * channels;
          int dst_idx = (ty * tile_w + tx) * channels;
          for (int c = 0; c < channels; ++c) {
            tile_data[dst_idx + c] = image[src_idx + c];
          }
        }
      }
      char path[1024];
      snprintf(path, sizeof(path), "%s/%s_tile_%d.jpg", output_folder,
               base_name, tile_index);
      if (!stbi_write_jpg(path, tile_w, tile_h, channels, tile_data, 90)) {
        fprintf(stderr, "Error saving tile %d to %s\n", tile_index, path);
      }
      free(tile_data);
      tile_index++;
    }
  }
}

int main(int argc, char **argv) {
  if (argc < 3 || argc > 4) {
    fprintf(
        stderr,
        "Usage: ./preprocess_c <input_folder> <output_folder> [tile_size]\n");
    return -1;
  }

  const char *input_folder = argv[1];
  const char *output_folder = argv[2];
  int tile_size = 64;
  if (argc == 4) {
    tile_size = atoi(argv[3]);
    if (tile_size <= 0) {
      fprintf(stderr, "Error: tile_size must be positive\n");
      return -1;
    }
  }

  // Create output folder if it does not exist
  struct stat st = {0};
  if (stat(output_folder, &st) == -1) {
#ifdef _WIN32
    _mkdir(output_folder);
#else
    mkdir(output_folder, 0700);
#endif
  }

#ifdef _WIN32
  // Windows directory iteration
  char search_path[1024];
  snprintf(search_path, sizeof(search_path), "%s\\*", input_folder);
  WIN32_FIND_DATA find_data;
  HANDLE hFind = FindFirstFile(search_path, &find_data);
  if (hFind == INVALID_HANDLE_VALUE) {
    fprintf(stderr, "Error opening input folder: %s\n", input_folder);
    return -1;
  }
  do {
    if (!(find_data.dwFileAttributes &
          FILE_ATTRIBUTE_DIRECTORY)) { // Regular file
      char input_path[1024];
      snprintf(input_path, sizeof(input_path), "%s\\%s", input_folder,
               find_data.cFileName);

      int width, height, channels;
      unsigned char *image =
          stbi_load(input_path, &width, &height, &channels, 0);
      if (!image) {
        fprintf(stderr, "Error loading image: %s\n", input_path);
        continue;
      }

      // Extract base name without extension
      char base_name[256];
      strncpy(base_name, find_data.cFileName, sizeof(base_name) - 1);
      base_name[sizeof(base_name) - 1] = '\0';
      char *dot = strrchr(base_name, '.');
      if (dot)
        *dot = '\0';

      splitImageIntoTiles(image, width, height, channels, tile_size,
                          output_folder, base_name);

      stbi_image_free(image);

      printf("Processed %s and saved tiles!\n", input_path);
    }
  } while (FindNextFile(hFind, &find_data));
  FindClose(hFind);
#else
  // POSIX directory iteration
  DIR *dir = opendir(input_folder);
  if (!dir) {
    fprintf(stderr, "Error opening input folder: %s\n", input_folder);
    return -1;
  }

  struct dirent *entry;
  while ((entry = readdir(dir)) != NULL) {
    if (entry->d_type == DT_REG) { // Regular file
      char input_path[1024];
      snprintf(input_path, sizeof(input_path), "%s/%s", input_folder,
               entry->d_name);

      int width, height, channels;
      unsigned char *image =
          stbi_load(input_path, &width, &height, &channels, 0);
      if (!image) {
        fprintf(stderr, "Error loading image: %s\n", input_path);
        continue;
      }

      // Extract base name without extension
      char base_name[256];
      strncpy(base_name, entry->d_name, sizeof(base_name) - 1);
      base_name[sizeof(base_name) - 1] = '\0';
      char *dot = strrchr(base_name, '.');
      if (dot)
        *dot = '\0';

      splitImageIntoTiles(image, width, height, channels, tile_size,
                          output_folder, base_name);

      stbi_image_free(image);

      printf("Processed %s and saved tiles!\n", input_path);
    }
  }

  closedir(dir);
#endif
  return 0;
}
