import hashlib
import contextlib
import io
import json
import os
import sqlite3
import subprocess
import sys
import tempfile
import unittest
import urllib.error
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).parent))
import fetch_core_db


class FetchCoreDbTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.source = self.root / "source.db"
        db = sqlite3.connect(self.source)
        try:
            db.execute("CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
            db.executemany("INSERT INTO meta VALUES (?, ?)", [("built", "build-1"), ("blob_codec", "zstd")])
            db.commit()
        finally:
            db.close()
        self.database = self.source.read_bytes()
        digest = hashlib.sha256(self.database).hexdigest()
        self.manifest = {
            "schema_version": 1, "core_ref": "v0.9.11", "core_sha": "a" * 40,
            "blob_codec": "zstd", "db_built": "build-1",
            "db_size": len(self.database), "db_sha256": digest,
        }
        self.assets = {
            fetch_core_db.DB: self.database,
            fetch_core_db.MANIFEST: json.dumps(self.manifest).encode(),
            fetch_core_db.CHECKSUM: f"{digest}  haqor.db\n".encode(),
        }

    def tearDown(self):
        self.temp.cleanup()

    def api(self, assets=None):
        names = self.assets if assets is None else assets
        return lambda *_: {"assets": [
            {"name": name, "browser_download_url": "https://example/" + name}
            for name in names
        ]}

    def fetch(self, assets=None):
        values = self.assets if assets is None else assets
        return lambda url: values[url.rsplit("/", 1)[-1]]

    def install(self, destination=None, *, codec="zstd"):
        return fetch_core_db.install("v0.9.11", "a" * 40,
                                     destination or self.root / "installed.db", codec=codec)

    def test_valid_delivery_and_producer_shape_install_atomically(self):
        destination = self.root / "installed.db"
        with patch.object(fetch_core_db, "api_json", self.api()), patch.object(fetch_core_db, "download", self.fetch()):
            self.assertTrue(self.install(destination))
        self.assertEqual(destination.read_bytes(), self.database)

    def test_legacy_missing_release_or_api_404_falls_back(self):
        destination = self.root / "missing.db"
        with patch.object(fetch_core_db, "api_json", return_value={"assets": []}), patch.object(fetch_core_db, "download") as download:
            self.assertFalse(self.install(destination))
            download.assert_not_called()
        error = urllib.error.HTTPError("https://api.github.com", 404, "missing", {}, None)
        with patch.object(fetch_core_db.urllib.request, "urlopen", side_effect=error):
            with self.assertRaises(fetch_core_db.LegacyDatabase):
                fetch_core_db.api_json("https://example/api", None)

    def test_none_codec_skips_api(self):
        with patch.object(fetch_core_db, "api_json", side_effect=AssertionError("API called")):
            self.assertFalse(self.install(codec="none"))

    def test_partial_and_duplicate_assets_fail_closed(self):
        for names in ([fetch_core_db.DB, fetch_core_db.MANIFEST],
                      [fetch_core_db.DB, fetch_core_db.MANIFEST, fetch_core_db.CHECKSUM, fetch_core_db.DB]):
            with self.subTest(names=names), self.assertRaises(fetch_core_db.InvalidDatabaseRelease):
                fetch_core_db.assets({"assets": [
                    {"name": name, "browser_download_url": "https://example/" + name} for name in names
                ]})

    def test_matching_asset_with_missing_or_non_text_url_fails_closed(self):
        for bad_url in (None, "", 42):
            with self.subTest(bad_url=bad_url), self.assertRaises(fetch_core_db.InvalidDatabaseRelease):
                fetch_core_db.assets({"assets": [
                    {"name": fetch_core_db.DB, "browser_download_url": bad_url},
                    {"name": fetch_core_db.MANIFEST, "browser_download_url": "https://example/manifest"},
                    {"name": fetch_core_db.CHECKSUM, "browser_download_url": "https://example/checksum"},
                ]})

    def test_api_and_asset_http_errors_are_hard_failures(self):
        api_error = urllib.error.HTTPError("https://api.github.com", 403, "forbidden", {}, None)
        with patch.object(fetch_core_db.urllib.request, "urlopen", side_effect=api_error):
            with self.assertRaises(fetch_core_db.InvalidDatabaseRelease):
                fetch_core_db.api_json("https://example/api", "secret")
        for status in (403, 404):
            error = urllib.error.HTTPError("https://example/asset", status, "error", {}, None)
            with self.subTest(status=status), patch.object(fetch_core_db.urllib.request, "urlopen", side_effect=error):
                with self.assertRaises(fetch_core_db.InvalidDatabaseRelease):
                    fetch_core_db.download("https://example/asset")

    def test_auth_header_is_sent_only_to_api(self):
        requests = []

        class Response:
            def __enter__(self): return self
            def __exit__(self, *_): return False
            def read(self): return b'{"assets": []}'

        def open_request(request, **_):
            requests.append(request)
            return Response()

        with patch.object(fetch_core_db.urllib.request, "urlopen", side_effect=open_request):
            fetch_core_db.api_json("https://example/api", "secret")
            fetch_core_db.download("https://example/asset")
        self.assertEqual(requests[0].get_header("Authorization"), "Bearer secret")
        self.assertNotIn("Authorization", requests[1].headers)

    def test_manifest_identity_codec_built_size_schema_checksum_and_types(self):
        fields = {"core_ref": "v0.9.12", "core_sha": "b" * 40, "blob_codec": "none",
                  "db_built": "different", "db_size": 1, "db_sha256": "0" * 64, "schema_version": 2}
        for field, value in fields.items():
            with self.subTest(field=field):
                manifest = dict(self.manifest); manifest[field] = value
                assets = dict(self.assets); assets[fetch_core_db.MANIFEST] = json.dumps(manifest).encode()
                with patch.object(fetch_core_db, "api_json", self.api()), patch.object(fetch_core_db, "download", self.fetch(assets)), self.assertRaises(fetch_core_db.InvalidDatabaseRelease):
                    self.install()
        for field in ("schema_version", "db_size"):
            with self.subTest(field=field):
                manifest = dict(self.manifest); manifest[field] = True
                assets = dict(self.assets); assets[fetch_core_db.MANIFEST] = json.dumps(manifest).encode()
                with patch.object(fetch_core_db, "api_json", self.api()), patch.object(fetch_core_db, "download", self.fetch(assets)), self.assertRaises(fetch_core_db.InvalidDatabaseRelease):
                    self.install()

    def test_malformed_json_sqlite_mismatch_and_existing_destination_preservation(self):
        destination = self.root / "installed.db"; destination.write_bytes(b"old")
        for name, value in [(fetch_core_db.MANIFEST, b"not json"), (fetch_core_db.CHECKSUM, b"not a checksum\n"), (fetch_core_db.DB, b"not sqlite")]:
            with self.subTest(name=name):
                assets = dict(self.assets); assets[name] = value
                with patch.object(fetch_core_db, "api_json", self.api()), patch.object(fetch_core_db, "download", self.fetch(assets)), self.assertRaises(fetch_core_db.InvalidDatabaseRelease):
                    self.install(destination)
                self.assertEqual(destination.read_bytes(), b"old")

    def test_readonly_metadata_does_not_create_missing_database(self):
        missing = self.root / "missing" / "database.db"
        with self.assertRaises(fetch_core_db.InvalidDatabaseRelease):
            fetch_core_db.sqlite_meta(missing)
        self.assertFalse(missing.exists())

    def test_cli_uses_exit_three_for_fallback_and_two_for_invalid_release(self):
        destination = self.root / "cli.db"; argv = ["fetch_core_db.py", "v0.9.10", "b" * 40, str(destination)]
        with patch.object(sys, "argv", argv), patch.object(fetch_core_db, "install", return_value=False):
            self.assertEqual(fetch_core_db.main(), 3)
        with patch.object(sys, "argv", argv), patch.object(fetch_core_db, "install", side_effect=fetch_core_db.InvalidDatabaseRelease("bad")):
            with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as result: fetch_core_db.main()
            self.assertEqual(result.exception.code, 2)
        with patch.object(sys, "argv", [*argv, "--codec", "invalid"]), patch.object(fetch_core_db, "install", side_effect=AssertionError("install called")):
            with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as result: fetch_core_db.main()
            self.assertEqual(result.exception.code, 2)

    def test_producer_and_consumer_contract_with_special_path(self):
        special = self.root / "space # directory"; special.mkdir(); source = special / "source.db"
        db = sqlite3.connect(source)
        try:
            db.execute("CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
            db.executemany("INSERT INTO meta VALUES (?, ?)", [("built", "build-1"), ("blob_codec", "zstd")])
            db.commit()
        finally:
            db.close()
        output = special / "release assets"
        script = Path(__file__).resolve().parents[2] / "haqor-core" / "scripts" / "package_runtime_db.py"
        if not script.is_file():
            self.skipTest("paired haqor-core checkout is not present")
        subprocess.run([sys.executable, str(script), str(source), str(output), "--core-ref", "v0.9.11", "--core-sha", "a" * 40], check=True, env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"})
        manifest = json.loads((output / fetch_core_db.MANIFEST).read_text())
        self.assertEqual(manifest["db_sha256"], hashlib.sha256((output / fetch_core_db.DB).read_bytes()).hexdigest())
        generated = {name: (output / name).read_bytes() for name in (fetch_core_db.DB, fetch_core_db.MANIFEST, fetch_core_db.CHECKSUM)}
        destination = special / "installed # database.db"
        with patch.object(fetch_core_db, "api_json", self.api(generated)), patch.object(fetch_core_db, "download", self.fetch(generated)):
            self.assertTrue(fetch_core_db.install("v0.9.11", "a" * 40, destination))
        self.assertEqual(destination.read_bytes(), generated[fetch_core_db.DB])
        self.assertEqual(json.loads(generated[fetch_core_db.MANIFEST])["core_sha"], "a" * 40)


if __name__ == "__main__":
    unittest.main()
