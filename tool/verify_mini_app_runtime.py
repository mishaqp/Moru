#!/usr/bin/env python3
"""Check bundled mini-app assets and report deterministic ZIP/APK payload sizes.

No downloads or third-party Python dependencies. Optional npm tarballs verify
the original sources and the recorded, bounded JS transformations as well.
"""

import argparse
import base64
import hashlib
import io
import json
from pathlib import Path
import sys
import tarfile
import zipfile


APK_PREFIX = "assets/flutter_assets/assets/mini_apps/runtime/"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def transform_source(data, transforms):
    for transform in transforms:
        if transform["op"] == "replace-once":
            before = transform["before"].encode()
            require(data.count(before) == 1, "replacement source changed")
            data = data.replace(before, transform["after"].encode())
        elif transform["op"] == "empty-webpack-module":
            start, end = transform["start"].encode(), transform["end"].encode()
            require(data.count(start) == 1 and data.count(end) == 1,
                    "webpack module boundary changed")
            begin = data.index(start)
            finish = data.index(end, begin)
            require(digest(data[begin:finish]) == transform["moduleSha256"],
                    "webpack module content changed")
            data = data[:begin] + transform["replacement"].encode() + data[finish:]
        else:
            raise ValueError(f"unknown transform: {transform['op']}")
    return data


def verify_tarballs(manifest, directory, files):
    for package in manifest["packages"]:
        tarball = directory / package["tarballFile"]
        data = tarball.read_bytes()
        require(digest(data) == package["sha256"], f"source SHA-256: {tarball.name}")
        integrity = "sha512-" + base64.b64encode(hashlib.sha512(data).digest()).decode()
        require(integrity == package["integrity"], f"npm integrity: {tarball.name}")
        with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as archive:
            for asset in package["assets"]:
                member = archive.extractfile("package/" + asset["source"])
                require(member is not None, f"missing source: {asset['source']}")
                original = member.read()
                require(digest(original) == asset["sourceSha256"],
                        f"original file SHA-256: {asset['source']}")
                expected = transform_source(original, asset.get("transforms", []))
                require(expected == files[asset["file"]],
                        f"source reproduction: {asset['file']}")


def deterministic_zip(files):
    stream = io.BytesIO()
    with zipfile.ZipFile(stream, "w", compression=zipfile.ZIP_DEFLATED,
                         compresslevel=9) as archive:
        for name, data in sorted(files.items()):
            info = zipfile.ZipInfo(APK_PREFIX + name, (1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.create_system = 3
            info.external_attr = 0o100644 << 16
            archive.writestr(info, data, compresslevel=9)
    return stream.getvalue()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime", type=Path,
                        default=Path(__file__).resolve().parents[1] /
                        "assets/mini_apps/runtime")
    parser.add_argument("--tarballs", type=Path,
                        help="directory containing the five pinned npm source tarballs")
    parser.add_argument("--write-zip", type=Path,
                        help="write a reproducible ZIP containing the APK asset paths")
    parser.add_argument("--apk", type=Path,
                        help="also inspect actual runtime entries in a built APK")
    args = parser.parse_args()
    manifest_file = args.runtime / "vendor-manifest.json"
    manifest_bytes = manifest_file.read_bytes()
    manifest = json.loads(manifest_bytes)
    require(manifest["format"] == 1, "unsupported manifest format")
    expected = set(manifest["files"]) | {manifest_file.name}
    actual = {file.name for file in args.runtime.iterdir()}
    require(expected == actual, "runtime directory differs from manifest")
    files = {manifest_file.name: manifest_bytes}
    for name, metadata in manifest["files"].items():
        require(Path(name).name == name and name not in (".", ".."),
                f"non-flat filename: {name}")
        path = args.runtime / name
        require(path.is_file() and not path.is_symlink(), f"not a regular file: {name}")
        data = path.read_bytes()
        require(len(data) == metadata["bytes"], f"size changed: {name}")
        require(digest(data) == metadata["sha256"], f"SHA-256 changed: {name}")
        if name.endswith(".wasm"):
            require(data[:8] == b"\0asm\x01\0\0\0", f"invalid WASM header: {name}")
        files[name] = data
    raw_bytes = sum(map(len, files.values()))
    require(raw_bytes < manifest["sizeBudgetBytes"], "runtime exceeds 8 MiB budget")
    if args.tarballs:
        verify_tarballs(manifest, args.tarballs, files)
    zipped = deterministic_zip(files)
    if args.write_zip:
        args.write_zip.write_bytes(zipped)
    # Conservative upper bound: store every file uncompressed, with a local and
    # central ZIP header plus up to 4095 bytes of entry alignment padding.
    overhead = 22 + sum(30 + 46 + 2 * len((APK_PREFIX + name).encode()) + 4095
                        for name in files)
    report = {"files": len(files), "raw_bytes": raw_bytes,
              "zip_bytes": len(zipped), "zip_sha256": digest(zipped),
              "raw_apk_payload_bytes": raw_bytes,
              "uncompressed_apk_bound_bytes": raw_bytes + overhead}
    if args.apk:
        with zipfile.ZipFile(args.apk) as archive:
            entries = [archive.getinfo(APK_PREFIX + name) for name in files]
            for name, data in files.items():
                require(archive.read(APK_PREFIX + name) == data,
                        f"APK bytes differ: {name}")
            report["actual_apk_raw_bytes"] = sum(entry.file_size for entry in entries)
            report["actual_apk_compressed_bytes"] = sum(entry.compress_size for entry in entries)
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, KeyError, tarfile.TarError, zipfile.BadZipFile) as error:
        print(f"Mini-app runtime verification failed: {error}", file=sys.stderr)
        sys.exit(1)
