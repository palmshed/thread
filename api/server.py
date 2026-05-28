from __future__ import annotations

import math
import os
import re
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import cv2
from flask import Flask, jsonify, request, send_file
from werkzeug.utils import secure_filename

app = Flask(__name__)

API_VERSION = os.getenv("API_VERSION", "v1")
UPLOAD_FOLDER = Path(os.getenv("UPLOAD_FOLDER", "/tmp/thread/uploads"))
OUTPUT_FOLDER = Path(os.getenv("OUTPUT_FOLDER", "/tmp/thread/output"))
ALLOWED_EXTENSIONS = {"png", "jpg", "jpeg", "bmp", "tiff"}
DEFAULT_TILE_SIZE = 512
MAX_PAGE_LIMIT = 100

JOBS: dict[str, dict[str, Any]] = {}


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def mtime_iso(path: Path) -> str:
    return datetime.fromtimestamp(path.stat().st_mtime, timezone.utc).isoformat().replace("+00:00", "Z")


def is_safe_id(resource_id: str) -> bool:
    """Return true when a URL resource ID is safe to use in local paths."""
    return isinstance(resource_id, str) and re.fullmatch(r"[A-Za-z0-9_-]+", resource_id) is not None


UPLOAD_FOLDER.mkdir(parents=True, exist_ok=True)
OUTPUT_FOLDER.mkdir(parents=True, exist_ok=True)


def generate_squuid() -> str:
    """Generate a lower-case resource ID compatible with SQUUID-shaped URLs."""
    return str(uuid.uuid4())


def allowed_file(filename: str) -> bool:
    return "." in filename and filename.rsplit(".", 1)[1].lower() in ALLOWED_EXTENSIONS


def parse_positive_int(name: str, default: int, *, maximum: int | None = None) -> tuple[int | None, tuple[Any, int] | None]:
    raw_value = request.args.get(name)
    if raw_value is None:
        data = request.get_json(silent=True) or {}
        raw_value = data.get(name, default)

    try:
        value = int(raw_value)
    except (TypeError, ValueError):
        return None, error_response("invalid_parameter", "Invalid parameter", f"{name} must be an integer", 400)

    if value < 0:
        return None, error_response("invalid_parameter", "Invalid parameter", f"{name} must be non-negative", 400)
    if maximum is not None and value > maximum:
        return None, error_response("invalid_parameter", "Invalid parameter", f"{name} must be <= {maximum}", 400)
    return value, None


def parse_optional_grid_dimension(data: dict[str, Any], name: str) -> tuple[int | None, tuple[Any, int] | None]:
    raw_value = data.get(name)
    if raw_value is None:
        return None, None

    try:
        value = int(raw_value)
    except (TypeError, ValueError):
        return None, error_response("invalid_parameter", "Invalid parameter", f"{name} must be an integer", 400)

    if value <= 0:
        return None, error_response("invalid_parameter", "Invalid parameter", f"{name} must be positive", 400)
    return value, None


def parse_stitch_request() -> tuple[list[str], int | None, int | None, str, tuple[Any, int] | None]:
    data = request.get_json(silent=True) or {}
    tile_ids = data.get("tile_ids", [])
    if not isinstance(tile_ids, list) or not tile_ids:
        return [], None, None, "", error_response("no_tiles", "No tiles provided", "Please provide tile IDs to stitch", 400)
    if any(not isinstance(tile_id, str) or not is_safe_id(tile_id) for tile_id in tile_ids):
        return (
            [],
            None,
            None,
            "",
            error_response(
                "invalid_id",
                "Invalid tile ID",
                "All tile IDs must contain only safe characters.",
                400,
            ),
        )

    rows, error = parse_optional_grid_dimension(data, "rows")
    if error:
        return [], None, None, "", error
    cols, error = parse_optional_grid_dimension(data, "cols")
    if error:
        return [], None, None, "", error

    output_name = secure_filename(data.get("output", "stitched.png"))
    if not output_name or not allowed_file(output_name):
        return (
            [],
            None,
            None,
            "",
            error_response("invalid_output", "Invalid output name", "Output must be an image filename.", 400),
        )

    return tile_ids, rows, cols, output_name, None


def hal_response(
    data: dict[str, Any], links: dict[str, Any] | None = None, embedded: dict[str, Any] | None = None
) -> dict[str, Any]:
    response = {"_links": {"self": {"href": request.path}}}
    if links:
        response["_links"].update(links)
    if embedded:
        response["_embedded"] = embedded
    response.update(data)
    return response


def error_response(code: str, title: str, details: str, status_code: int) -> tuple[Any, int]:
    return jsonify({"errors": [{"code": code, "title": title, "details": details}]}), status_code


def image_record(path: Path) -> dict[str, Any]:
    image_id, filename = path.name.split("_", 1)
    return {
        "id": image_id,
        "filename": filename,
        "format": filename.rsplit(".", 1)[1].lower(),
        "size": path.stat().st_size,
        "created_at": mtime_iso(path),
    }


def find_uploaded_image(image_id: str) -> Path | None:
    if not is_safe_id(image_id):
        return None
    for path in UPLOAD_FOLDER.iterdir():
        if path.is_file() and path.name.startswith(f"{image_id}_") and allowed_file(path.name):
            return path
    return None


def tile_record(path: Path) -> dict[str, Any]:
    tile_id = path.stem
    return {"id": tile_id, "filename": path.name, "size": path.stat().st_size, "href": f"/{API_VERSION}/tiles/{tile_id}"}


def find_tile(tile_id: str) -> Path | None:
    if not is_safe_id(tile_id):
        return None
    for path in OUTPUT_FOLDER.glob("tiles_*/*"):
        if path.is_file() and path.stem == tile_id and allowed_file(path.name):
            return path
    return None


def determine_grid(tile_count: int, rows: int | None, cols: int | None) -> tuple[int, int]:
    if tile_count <= 0:
        raise ValueError("No tiles provided")
    if rows and cols:
        if rows * cols != tile_count:
            raise ValueError(f"Grid {rows}x{cols} does not match {tile_count} tiles")
        return rows, cols
    if rows:
        cols = tile_count // rows
        if rows * cols != tile_count:
            raise ValueError(f"Cannot arrange {tile_count} tiles in {rows} rows")
        return rows, cols
    if cols:
        rows = tile_count // cols
        if rows * cols != tile_count:
            raise ValueError(f"Cannot arrange {tile_count} tiles in {cols} columns")
        return rows, cols

    grid_size = math.isqrt(tile_count)
    if grid_size * grid_size != tile_count:
        raise ValueError("Tile count is not a perfect square; provide rows or cols")
    return grid_size, grid_size


def resize_image(source_file: Path, output_file: Path, scale: int) -> None:
    image = cv2.imread(str(source_file), cv2.IMREAD_UNCHANGED)
    if image is None:
        raise ValueError(f"Could not load image: {source_file}")
    height, width = image.shape[:2]
    output_file.parent.mkdir(parents=True, exist_ok=True)
    resized = cv2.resize(image, (width * scale, height * scale), interpolation=cv2.INTER_CUBIC)
    if not cv2.imwrite(str(output_file), resized):
        raise ValueError(f"Could not write image: {output_file}")


def split_image(source_file: Path, image_id: str, tile_size: int) -> list[Path]:
    image = cv2.imread(str(source_file), cv2.IMREAD_UNCHANGED)
    if image is None:
        raise ValueError(f"Could not load image: {source_file}")

    tiles_dir = OUTPUT_FOLDER / f"tiles_{image_id}"
    tiles_dir.mkdir(parents=True, exist_ok=True)
    for old_tile in tiles_dir.glob("*"):
        if old_tile.is_file():
            old_tile.unlink()

    height, width = image.shape[:2]
    tile_paths = []
    tile_index = 0
    for y in range(0, height, tile_size):
        for x in range(0, width, tile_size):
            tile = image[y : min(y + tile_size, height), x : min(x + tile_size, width)]
            tile_path = tiles_dir / f"{image_id}_tile_{tile_index}.jpg"
            if not cv2.imwrite(str(tile_path), tile):
                raise ValueError(f"Could not write tile: {tile_path}")
            tile_paths.append(tile_path)
            tile_index += 1
    return tile_paths


def stitch_image(tile_paths: list[Path], output_path: Path, rows: int | None, cols: int | None) -> tuple[int, int]:
    grid_rows, grid_cols = determine_grid(len(tile_paths), rows, cols)
    images = []
    for tile_path in tile_paths:
        image = cv2.imread(str(tile_path), cv2.IMREAD_UNCHANGED)
        if image is None:
            raise ValueError(f"Could not load tile: {tile_path}")
        images.append(image)

    first_height, first_width = images[0].shape[:2]
    normalized = [
        image if image.shape[:2] == (first_height, first_width) else cv2.resize(image, (first_width, first_height))
        for image in images
    ]
    rows_joined = [
        cv2.hconcat(normalized[row_start : row_start + grid_cols]) for row_start in range(0, len(normalized), grid_cols)
    ]
    stitched = cv2.vconcat(rows_joined)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    if not cv2.imwrite(str(output_path), stitched):
        raise ValueError(f"Could not write stitched image: {output_path}")
    return grid_rows, grid_cols


@app.route(f"/{API_VERSION}/images", methods=["POST"])
def upload_image() -> tuple[Any, int]:
    if "file" not in request.files:
        return error_response("no_file", "No file provided", "Please provide an image file", 400)

    file = request.files["file"]
    if file.filename == "":
        return error_response("empty_filename", "Empty filename", "Please provide a valid filename", 400)
    if not allowed_file(file.filename or ""):
        return error_response(
            "invalid_format", "Invalid file format", f"Allowed formats: {', '.join(ALLOWED_EXTENSIONS)}", 400
        )

    image_id = generate_squuid()
    filename = secure_filename(file.filename or "")
    filepath = UPLOAD_FOLDER / f"{image_id}_{filename}"
    file.save(filepath)

    return (
        jsonify(
            hal_response(
                {**image_record(filepath), "created_at": utc_now_iso()},
                {
                    "self": {"href": f"/{API_VERSION}/images/{image_id}"},
                    "tiles": {"href": f"/{API_VERSION}/images/{image_id}/tiles"},
                    "upscale": {"href": f"/{API_VERSION}/images/{image_id}/upscale"},
                },
            )
        ),
        201,
    )


@app.route(f"/{API_VERSION}/images", methods=["GET"])
def list_images() -> Any:
    offset, error = parse_positive_int("offset", 0)
    if error:
        return error
    limit, error = parse_positive_int("limit", 25, maximum=MAX_PAGE_LIMIT)
    if error:
        return error

    images = sorted(
        (image_record(path) for path in UPLOAD_FOLDER.iterdir() if path.is_file() and allowed_file(path.name)),
        key=lambda item: item["created_at"],
    )
    paginated = images[offset : offset + limit]
    links = {"self": {"href": f"/{API_VERSION}/images?offset={offset}&limit={limit}"}}
    if offset + limit < len(images):
        links["next"] = {"href": f"/{API_VERSION}/images?offset={offset + limit}&limit={limit}"}
    if offset > 0:
        links["prev"] = {"href": f"/{API_VERSION}/images?offset={max(0, offset - limit)}&limit={limit}"}

    return jsonify(hal_response({"count": len(paginated), "total": len(images)}, links=links, embedded={"images": paginated}))


@app.route(f"/{API_VERSION}/images/<image_id>", methods=["GET"])
def get_image(image_id: str) -> Any:
    filepath = find_uploaded_image(image_id)
    if not filepath:
        return error_response("not_found", "Image not found", f"No image found with ID: {image_id}", 404)

    return jsonify(
        hal_response(
            image_record(filepath),
            {
                "self": {"href": f"/{API_VERSION}/images/{image_id}"},
                "tiles": {"href": f"/{API_VERSION}/images/{image_id}/tiles"},
                "upscale": {"href": f"/{API_VERSION}/images/{image_id}/upscale"},
                "download": {"href": f"/{API_VERSION}/images/{image_id}/file"},
            },
        )
    )


@app.route(f"/{API_VERSION}/images/<image_id>/file", methods=["GET"])
def download_image(image_id: str) -> Any:
    filepath = find_uploaded_image(image_id)
    if filepath:
        return send_file(filepath)
    return error_response("not_found", "Image not found", f"No image found with ID: {image_id}", 404)


@app.route(f"/{API_VERSION}/images/<image_id>/tiles", methods=["POST"])
def create_tiles(image_id: str) -> Any:
    if not is_safe_id(image_id):
        return error_response("invalid_id", "Invalid image ID", "The provided image ID contains invalid characters.", 400)

    source_file = find_uploaded_image(image_id)
    if not source_file:
        return error_response("not_found", "Image not found", f"No image found with ID: {image_id}", 404)

    tile_size, error = parse_positive_int("tile_size", DEFAULT_TILE_SIZE)
    if error:
        return error
    if tile_size == 0:
        return error_response("invalid_parameter", "Invalid parameter", "tile_size must be positive", 400)

    try:
        tile_paths = split_image(source_file, image_id, tile_size)
    except ValueError as exc:
        return error_response("processing_failed", "Processing failed", str(exc), 422)

    tiles = [tile_record(path) for path in tile_paths]
    return (
        jsonify(
            hal_response(
                {"image_id": image_id, "tile_count": len(tiles), "tile_size": tile_size},
                links={
                    "self": {"href": f"/{API_VERSION}/images/{image_id}/tiles"},
                    "image": {"href": f"/{API_VERSION}/images/{image_id}"},
                },
                embedded={"tiles": tiles},
            )
        ),
        202,
    )


@app.route(f"/{API_VERSION}/images/<image_id>/upscale", methods=["POST"])
def upscale_image(image_id: str) -> Any:
    source_file = find_uploaded_image(image_id)
    if not source_file:
        return error_response("not_found", "Image not found", f"No image found with ID: {image_id}", 404)

    scale, error = parse_positive_int("scale", 2, maximum=8)
    if error:
        return error
    if scale == 0:
        return error_response("invalid_parameter", "Invalid parameter", "scale must be positive", 400)

    output_file = OUTPUT_FOLDER / f"upscaled_{image_id}.png"
    try:
        resize_image(source_file, output_file, scale)
    except ValueError as exc:
        return error_response("processing_failed", "Processing failed", str(exc), 422)

    return (
        jsonify(
            hal_response(
                {"id": image_id, "scale": scale, "output_file": output_file.name},
                {
                    "self": {"href": f"/{API_VERSION}/images/{image_id}/upscale"},
                    "image": {"href": f"/{API_VERSION}/images/{image_id}"},
                    "download": {"href": f"/{API_VERSION}/outputs/{output_file.name}"},
                },
            )
        ),
        202,
    )


@app.route(f"/{API_VERSION}/tiles", methods=["GET"])
def list_tiles() -> Any:
    offset, error = parse_positive_int("offset", 0)
    if error:
        return error
    limit, error = parse_positive_int("limit", 25, maximum=MAX_PAGE_LIMIT)
    if error:
        return error

    tiles = sorted(
        (tile_record(path) for path in OUTPUT_FOLDER.glob("tiles_*/*") if path.is_file() and allowed_file(path.name)),
        key=lambda item: item["id"],
    )
    paginated = tiles[offset : offset + limit]
    links = {"self": {"href": f"/{API_VERSION}/tiles?offset={offset}&limit={limit}"}}
    if offset + limit < len(tiles):
        links["next"] = {"href": f"/{API_VERSION}/tiles?offset={offset + limit}&limit={limit}"}
    if offset > 0:
        links["prev"] = {"href": f"/{API_VERSION}/tiles?offset={max(0, offset - limit)}&limit={limit}"}

    return jsonify(hal_response({"count": len(paginated), "total": len(tiles)}, links=links, embedded={"tiles": paginated}))


@app.route(f"/{API_VERSION}/tiles/<tile_id>", methods=["GET"])
def get_tile(tile_id: str) -> Any:
    filepath = find_tile(tile_id)
    if not filepath:
        return error_response("not_found", "Tile not found", f"No tile found with ID: {tile_id}", 404)

    return jsonify(
        hal_response(
            tile_record(filepath),
            {
                "self": {"href": f"/{API_VERSION}/tiles/{tile_id}"},
                "upscale": {"href": f"/{API_VERSION}/tiles/{tile_id}/upscale"},
            },
        )
    )


@app.route(f"/{API_VERSION}/tiles/<tile_id>/upscale", methods=["POST"])
def upscale_tile(tile_id: str) -> Any:
    source_file = find_tile(tile_id)
    if not source_file:
        return error_response("not_found", "Tile not found", f"No tile found with ID: {tile_id}", 404)

    scale, error = parse_positive_int("scale", 2, maximum=8)
    if error:
        return error
    if scale == 0:
        return error_response("invalid_parameter", "Invalid parameter", "scale must be positive", 400)

    output_file = OUTPUT_FOLDER / f"upscaled_{tile_id}.png"
    try:
        resize_image(source_file, output_file, scale)
    except ValueError as exc:
        return error_response("processing_failed", "Processing failed", str(exc), 422)

    return (
        jsonify(
            hal_response(
                {"id": tile_id, "scale": scale, "output_file": output_file.name},
                {
                    "self": {"href": f"/{API_VERSION}/tiles/{tile_id}/upscale"},
                    "tile": {"href": f"/{API_VERSION}/tiles/{tile_id}"},
                    "download": {"href": f"/{API_VERSION}/outputs/{output_file.name}"},
                },
            )
        ),
        202,
    )


@app.route(f"/{API_VERSION}/tiles/<tile_id>/upscaled", methods=["GET"])
def download_upscaled(tile_id: str) -> Any:
    if not is_safe_id(tile_id):
        return error_response("invalid_id", "Invalid tile ID", "The provided tile ID contains invalid characters.", 400)
    upscaled_file = OUTPUT_FOLDER / f"upscaled_{tile_id}.png"
    if upscaled_file.exists():
        return send_file(upscaled_file)
    return error_response("not_found", "Upscaled tile not found", f"No upscaled tile found for ID: {tile_id}", 404)


@app.route(f"/{API_VERSION}/stitch", methods=["POST"])
def stitch_tiles() -> Any:
    tile_ids, rows, cols, output_name, error = parse_stitch_request()
    if error:
        return error

    tile_paths = []
    for tile_id in tile_ids:
        upscaled_path = OUTPUT_FOLDER / f"upscaled_{tile_id}.png"
        tile_path = upscaled_path if upscaled_path.exists() else find_tile(tile_id)
        if not tile_path:
            return error_response("not_found", "Tile not found", f"No tile found with ID: {tile_id}", 404)
        tile_paths.append(tile_path)

    job_id = generate_squuid()
    output_path = OUTPUT_FOLDER / "stitched" / f"{job_id}_{output_name}"
    try:
        grid_rows, grid_cols = stitch_image(tile_paths, output_path, rows, cols)
    except ValueError as exc:
        return error_response("processing_failed", "Processing failed", str(exc), 422)

    JOBS[job_id] = {
        "id": job_id,
        "status": "completed",
        "result": f"/{API_VERSION}/outputs/{output_path.name}",
        "tile_count": len(tile_paths),
        "rows": grid_rows,
        "cols": grid_cols,
    }
    return (
        jsonify(
            hal_response(
                JOBS[job_id],
                {
                    "self": {"href": f"/{API_VERSION}/stitch/{job_id}"},
                    "status": {"href": f"/{API_VERSION}/jobs/{job_id}"},
                    "download": {"href": f"/{API_VERSION}/outputs/{output_path.name}"},
                },
            )
        ),
        202,
    )


@app.route(f"/{API_VERSION}/jobs/<job_id>", methods=["GET"])
def get_job_status(job_id: str) -> Any:
    job = JOBS.get(job_id)
    if not job:
        return error_response("not_found", "Job not found", f"No job found with ID: {job_id}", 404)
    return jsonify(hal_response(job, {"self": {"href": f"/{API_VERSION}/jobs/{job_id}"}}))


@app.route(f"/{API_VERSION}/outputs/<filename>", methods=["GET"])
def download_output(filename: str) -> Any:
    safe_name = secure_filename(filename)
    if safe_name != filename:
        return error_response("invalid_filename", "Invalid filename", "The requested filename is not valid.", 400)
    for path in (OUTPUT_FOLDER / safe_name, OUTPUT_FOLDER / "stitched" / safe_name):
        if path.exists() and path.is_file():
            return send_file(path)
    return error_response("not_found", "Output not found", f"No output found with filename: {filename}", 404)


@app.route("/", methods=["GET"])
def api_root() -> Any:
    return jsonify(
        {
            "message": f"Thread API {API_VERSION}",
            "endpoints": {
                "health": f"/{API_VERSION}/health",
                "images": f"/{API_VERSION}/images",
                "tiles": f"/{API_VERSION}/tiles",
                "stitch": f"/{API_VERSION}/stitch",
            },
        }
    )


@app.route("/health", methods=["GET"])
@app.route(f"/{API_VERSION}/health", methods=["GET"])
def health_check() -> Any:
    return jsonify({"status": "healthy", "version": API_VERSION})


@app.errorhandler(400)
def bad_request(error: Any) -> tuple[Any, int]:
    return error_response("bad_request", "Bad Request", str(error.description), 400)


@app.errorhandler(404)
def not_found(error: Any) -> tuple[Any, int]:
    return error_response("not_found", "Not Found", "The requested resource was not found", 404)


@app.errorhandler(500)
def internal_error(error: Any) -> tuple[Any, int]:
    return error_response("internal_error", "Internal Server Error", "An unexpected error occurred", 500)


if __name__ == "__main__":
    debug_mode = os.getenv("FLASK_DEBUG", "").lower() in ("1", "true", "yes")
    port = int(os.getenv("PORT", "5001"))
    app.run(host="0.0.0.0", port=port, debug=debug_mode)
