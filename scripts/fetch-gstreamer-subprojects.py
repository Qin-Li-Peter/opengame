#!/usr/bin/env python3
"""Download and verify source archives named by a GStreamer release's wrap files."""
from __future__ import annotations

import configparser
import hashlib
import json
from pathlib import Path
import sys
import tarfile
import tempfile
import time
import urllib.request

archive = Path(sys.argv[1])
destination = Path(sys.argv[2])
destination.mkdir(parents=True, exist_ok=True)

items: dict[str, dict[str, str]] = {}
with tarfile.open(archive, "r:gz") as bundle:
    for member in bundle.getmembers():
        if not member.isfile() or "/subprojects/" not in member.name or not member.name.endswith(".wrap"):
            continue
        stream = bundle.extractfile(member)
        if stream is None:
            continue
        parser = configparser.ConfigParser(interpolation=None)
        parser.read_string(stream.read().decode("utf-8"))
        if not parser.has_section("wrap-file"):
            continue
        section = parser["wrap-file"]
        if "source_url" not in section or "source_hash" not in section:
            continue
        filename = section.get("source_filename", Path(section["source_url"]).name)
        record = {
            "file": filename,
            "sha256": section["source_hash"],
            "url": section["source_url"],
        }
        if section.get("source_fallback_url"):
            record["fallback_url"] = section["source_fallback_url"]
        previous = items.get(filename)
        if previous and previous["sha256"] != record["sha256"]:
            raise SystemExit(f"conflicting GStreamer wrap source: {filename}")
        items[filename] = record

opener = urllib.request.build_opener()
opener.addheaders = [("User-Agent", "OpenGame-source-fetch/1")]
for filename, item in sorted(items.items()):
    target = destination / filename
    expected = item["sha256"]
    if target.exists() and hashlib.sha256(target.read_bytes()).hexdigest() == expected:
        print(expected, target)
        continue
    errors = []
    urls = [url for url in (item["url"], item.get("fallback_url")) if url]
    for attempt in range(3):
        url = urls[attempt % len(urls)]
        if not url:
            continue
        partial = destination / (filename + ".partial")
        try:
            with opener.open(url, timeout=90) as response, partial.open("wb") as output:
                while chunk := response.read(1024 * 1024):
                    output.write(chunk)
            actual = hashlib.sha256(partial.read_bytes()).hexdigest()
            if actual != expected:
                raise ValueError(f"hash {actual}")
            partial.replace(target)
            print(expected, target)
            break
        except Exception as error:
            errors.append(f"{url}: {error}")
            partial.unlink(missing_ok=True)
            time.sleep(attempt + 1)
    else:
        raise SystemExit("unable to fetch %s\n%s" % (filename, "\n".join(errors)))

(destination / "wrap-sources.json").write_text(json.dumps(sorted(items.values(), key=lambda item: item["file"]), indent=2) + "\n")
print(f"Verified {len(items)} GStreamer wrap source archives")
