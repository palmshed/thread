from __future__ import annotations

import importlib
import io
import os
import sys
from pathlib import Path

import cv2
import numpy as np


def import_test_app(tmp_path: Path, monkeypatch):
    monkeypatch.setenv("UPLOAD_FOLDER", str(tmp_path / "uploads"))
    monkeypatch.setenv("OUTPUT_FOLDER", str(tmp_path / "output"))

    sys.modules.pop("api.server", None)
    server = importlib.import_module("api.server")
    server.app.config.update(TESTING=True)
    return server.app


def make_image_bytes() -> bytes:
    image = np.full((32, 32, 3), (0, 0, 255), dtype=np.uint8)
    ok, encoded = cv2.imencode(".jpg", image)
    assert ok
    return encoded.tobytes()


def test_upload_tile_upscale_stitch_download(tmp_path: Path, monkeypatch) -> None:
    app = import_test_app(tmp_path, monkeypatch)
    client = app.test_client()

    upload = client.post(
        "/v1/images",
        data={"file": (io.BytesIO(make_image_bytes()), "sample.jpg")},
        content_type="multipart/form-data",
    )
    assert upload.status_code == 201
    image_id = upload.get_json()["id"]

    tiles = client.post(f"/v1/images/{image_id}/tiles", json={"tile_size": 16})
    assert tiles.status_code == 202
    tile_payload = tiles.get_json()
    assert tile_payload["tile_count"] == 4
    tile_ids = [tile["id"] for tile in tile_payload["_embedded"]["tiles"]]

    upscale = client.post(f"/v1/tiles/{tile_ids[0]}/upscale", json={"scale": 2})
    assert upscale.status_code == 202

    stitched = client.post("/v1/stitch", json={"tile_ids": tile_ids, "rows": 2, "cols": 2, "output": "result.png"})
    assert stitched.status_code == 202
    stitched_payload = stitched.get_json()
    assert stitched_payload["status"] == "completed"

    job = client.get(stitched_payload["_links"]["status"]["href"])
    assert job.status_code == 200
    assert job.get_json()["result"].endswith(".png")

    download = client.get(stitched_payload["_links"]["download"]["href"])
    assert download.status_code == 200
    assert download.data


def test_rejects_invalid_pagination(tmp_path: Path, monkeypatch) -> None:
    app = import_test_app(tmp_path, monkeypatch)
    response = app.test_client().get("/v1/images?offset=-1")
    assert response.status_code == 400


def test_stitch_rejects_invalid_grid_dimensions(tmp_path: Path, monkeypatch) -> None:
    app = import_test_app(tmp_path, monkeypatch)
    client = app.test_client()

    for payload in (
        {"tile_ids": ["tile_0"], "rows": "two", "cols": 1},
        {"tile_ids": ["tile_0"], "rows": 0, "cols": 1},
        {"tile_ids": ["tile_0"], "rows": 1, "cols": -1},
    ):
        response = client.post("/v1/stitch", json=payload)
        assert response.status_code == 400
        assert response.get_json()["errors"][0]["code"] == "invalid_parameter"


def test_download_rejects_path_traversal(tmp_path: Path, monkeypatch) -> None:
    app = import_test_app(tmp_path, monkeypatch)
    response = app.test_client().get("/v1/outputs/../secret.png")
    assert response.status_code == 404


def test_environment_isolated(tmp_path: Path, monkeypatch) -> None:
    app = import_test_app(tmp_path, monkeypatch)
    assert Path(os.environ["UPLOAD_FOLDER"]).is_relative_to(tmp_path)
    assert app.config["TESTING"] is True
