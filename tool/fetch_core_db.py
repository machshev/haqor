#!/usr/bin/env python3
"""Fetch and atomically install a verified haqor-core release database."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import sqlite3
import tempfile
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

DB = "haqor.db"
MANIFEST = "haqor.db.manifest.json"
CHECKSUM = "haqor.db.sha256"


class LegacyDatabase(Exception):
    pass


class InvalidDatabaseRelease(ValueError):
    pass


def api_json(url: str, token: str | None) -> dict:
    request = urllib.request.Request(url, headers={"Accept": "application/vnd.github+json"})
    if token:
        request.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            value = json.loads(response.read())
    except urllib.error.HTTPError as error:
        if error.code == 404:
            raise LegacyDatabase from error
        raise InvalidDatabaseRelease(f"release API returned HTTP {error.code}") from error
    except (OSError, json.JSONDecodeError) as error:
        raise InvalidDatabaseRelease(f"release API request failed: {error}") from error
    if not isinstance(value, dict):
        raise InvalidDatabaseRelease("release API response is not an object")
    return value


def assets(release: dict) -> dict[str, str]:
    found: dict[str, str] = {}
    raw = release.get("assets")
    if not isinstance(raw, list):
        raise InvalidDatabaseRelease("release API response lacks assets")
    for item in raw:
        if not isinstance(item, dict):
            continue
        name, url = item.get("name"), item.get("browser_download_url")
        if not isinstance(name, str) or name not in {DB, MANIFEST, CHECKSUM}:
            continue
        if not isinstance(url, str) or not url:
            raise InvalidDatabaseRelease(f"release asset {name} lacks a download URL")
        if name in found:
            raise InvalidDatabaseRelease(f"duplicate release asset: {name}")
        found[name] = url
    if not found:
        raise LegacyDatabase
    if set(found) != {DB, MANIFEST, CHECKSUM}:
        raise InvalidDatabaseRelease(f"partial database asset set: {sorted(found)}")
    return found


def download(url: str) -> bytes:
    # Never forward GH_TOKEN through a GitHub asset redirect.
    try:
        with urllib.request.urlopen(urllib.request.Request(url), timeout=120) as response:
            return response.read()
    except OSError as error:
        raise InvalidDatabaseRelease(f"database asset download failed: {error}") from error


def sqlite_meta(path: Path) -> dict[str, str]:
    uri = f"file:{urllib.parse.quote(str(path.resolve()), safe='/')}?mode=ro"
    try:
        connection = sqlite3.connect(uri, uri=True)
        try:
            values = dict(connection.execute(
                "SELECT key, value FROM meta WHERE key IN ('built', 'blob_codec')"
            ).fetchall())
        finally:
            connection.close()
    except (OSError, sqlite3.Error) as error:
        raise InvalidDatabaseRelease(f"database is not readable SQLite: {error}") from error
    if set(values) != {"built", "blob_codec"} or any(
        not isinstance(value, str) or not value for value in values.values()
    ):
        raise InvalidDatabaseRelease("database meta built/blob_codec must be non-empty text")
    return values


def install(core_ref: str, core_sha: str, destination: Path, *, codec: str = "zstd") -> bool:
    if codec != "zstd":
        return False
    try:
        release = api_json(
            "https://api.github.com/repos/machshev/haqor-core/releases/tags/"
            + urllib.parse.quote(core_ref, safe=""),
            os.environ.get("GH_TOKEN"),
        )
        urls = assets(release)
    except LegacyDatabase:
        return False
    manifest_bytes, checksum_bytes, database_bytes = (
        download(urls[MANIFEST]), download(urls[CHECKSUM]), download(urls[DB])
    )
    try:
        manifest = json.loads(manifest_bytes)
        required = {"schema_version", "core_ref", "core_sha", "blob_codec", "db_built", "db_size", "db_sha256"}
        if not isinstance(manifest, dict) or set(manifest) != required:
            raise ValueError("manifest fields do not match schema")
        if type(manifest["schema_version"]) is not int or manifest["schema_version"] != 1:
            raise ValueError("unsupported manifest schema")
        for field in ("core_ref", "core_sha", "blob_codec", "db_built", "db_sha256"):
            if not isinstance(manifest[field], str) or not manifest[field]:
                raise ValueError(f"manifest {field} must be non-empty text")
        if manifest["core_ref"] != core_ref or manifest["core_sha"] != core_sha:
            raise ValueError("manifest core identity does not match checkout")
        if manifest["blob_codec"] != codec:
            raise ValueError("manifest codec does not match requested codec")
        if type(manifest["db_size"]) is not int or manifest["db_size"] < 1:
            raise ValueError("manifest db_size must be a positive integer")
        digest = hashlib.sha256(database_bytes).hexdigest()
        if manifest["db_sha256"] != digest or manifest["db_size"] != len(database_bytes):
            raise ValueError("manifest database bytes do not match")
        if checksum_bytes.decode("ascii").strip() != f"{digest}  {DB}":
            raise ValueError("database checksum file mismatch")
    except (UnicodeDecodeError, json.JSONDecodeError, TypeError, ValueError) as error:
        raise InvalidDatabaseRelease(str(error)) from error
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=destination.parent, prefix=f".{destination.name}.", delete=False) as temporary:
        temporary.write(database_bytes)
        temporary.flush()
        os.fsync(temporary.fileno())
        temporary_path = Path(temporary.name)
    try:
        metadata = sqlite_meta(temporary_path)
        if metadata["blob_codec"] != codec or metadata["built"] != manifest["db_built"]:
            raise InvalidDatabaseRelease("SQLite metadata does not match manifest")
        os.replace(temporary_path, destination)
    finally:
        temporary_path.unlink(missing_ok=True)
    return True


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("core_ref")
    parser.add_argument("core_sha")
    parser.add_argument("destination", type=Path)
    parser.add_argument("--codec", choices=("none", "zstd"), default="zstd")
    args = parser.parse_args()
    try:
        found = install(args.core_ref, args.core_sha, args.destination, codec=args.codec)
    except InvalidDatabaseRelease as error:
        parser.error(str(error))
    if not found:
        return 3
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
