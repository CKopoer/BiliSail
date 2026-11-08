"""Fetch the locked SQLite binary with HTTP checks before its native asset hook."""

import argparse
import hashlib
import http.client
import json
import os
from pathlib import Path
import platform
import re
import tempfile
import time
from urllib.error import HTTPError, URLError
from urllib.parse import urljoin, urlparse
from urllib.request import Request, url2pathname, urlopen


TARGETS = {
    "windows-x64": ("sqlite3.x64.windows.dll", "sqlite3.dll"),
    "windows-arm64": ("sqlite3.arm64.windows.dll", "sqlite3.dll"),
    "linux-x64": ("libsqlite3.x64.linux.so", "libsqlite3.so"),
    "macos-x64": ("libsqlite3.x64.macos.dylib", "libsqlite3.dylib"),
    "macos-arm64": ("libsqlite3.arm64.macos.dylib", "libsqlite3.dylib"),
    "ios-arm64": ("libsqlite3.arm64.ios.dylib", "libsqlite3.dylib"),
    "android-arm64": ("libsqlite3.arm64.android.so", "libsqlite3.so"),
}
API_ROOT = "https://api.github.com/repos/simolus3/sqlite3.dart/releases"
MAX_BYTES = 16 * 1024 * 1024
MAX_ATTEMPTS = 3


def host_target() -> str:
    system = {"Windows": "windows", "Darwin": "macos", "Linux": "linux"}[platform.system()]
    arch = {"arm64": "arm64", "aarch64": "arm64", "amd64": "x64", "x86_64": "x64"}.get(platform.machine().lower())
    target = f"{system}-{arch}"
    if target not in TARGETS:
        raise RuntimeError(f"Unsupported SQLite host: {target}")
    return target


def asset_spec(repo: Path, target: str) -> tuple[str, str, Path]:
    config = repo / ".dart_tool/package_config.json"
    packages = json.loads(config.read_text(encoding="utf-8"))["packages"]
    package = next(item for item in packages if item["name"] == "sqlite3")
    root = Path(url2pathname(urlparse(urljoin(config.as_uri(), package["rootUri"])).path))
    manifest = (root / "lib/src/hook/asset_hashes.dart").read_text(encoding="utf-8")
    tag = re.search(r"releaseTag\s*=\s*'(sqlite3-[\d.]+)'", manifest)
    filename, local_name = TARGETS[target]
    checksum = re.search(r"'" + re.escape(filename) + r"':\s*'([0-9a-f]{64})'", manifest)
    if not tag or not checksum:
        raise RuntimeError("Review the changed SQLite native asset manifest")
    digest = checksum[1]
    cache = repo / ".dart_tool/hooks_runner/shared/sqlite3/build" / f"download-{digest[:8]}"
    return tag[1], digest, cache / local_name


def request(url: str, deadline: float, accept: str):
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        raise TimeoutError("SQLite preparation exceeded its 120 second deadline")
    outgoing = Request(url, headers={
        "User-Agent": "BiliSail-SQLite-Preparation",
        "Accept": accept,
    })
    token = os.environ.get("BILISAIL_GITHUB_TOKEN")
    if token and url.startswith(f"{API_ROOT}/"):
        # urllib omits unredirected headers from the CDN request. The CI token
        # belongs only on the official API, never github.com or an asset URL.
        outgoing.add_unredirected_header("Authorization", f"Bearer {token}")
    return urlopen(outgoing, timeout=min(20, remaining))


def api_asset(tag: str, filename: str, digest: str, deadline: float) -> str:
    with request(f"{API_ROOT}/tags/{tag}", deadline, "application/vnd.github+json") as response:
        raw = b"".join(read_chunks(response, deadline, 1024 * 1024))
    release = json.loads(raw)
    if release.get("tag_name") != tag:
        raise RuntimeError("SQLite Release tag does not match the locked package")
    asset = next((item for item in release["assets"] if item["name"] == filename), None)
    if asset is None or asset.get("state") != "uploaded":
        raise RuntimeError(f"SQLite Release asset is missing: {filename}")
    if asset.get("digest") not in (None, f"sha256:{digest}"):
        raise RuntimeError("SQLite Release digest does not match the locked package")
    asset_id = asset["id"]
    if not isinstance(asset_id, int) or asset_id <= 0:
        raise RuntimeError("Invalid SQLite Release asset ID")
    return f"{API_ROOT}/assets/{asset_id}"


def read_chunks(response, deadline: float, limit: int):
    size = 0
    # read1 returns available data after one underlying read, so a slow trickle
    # cannot postpone the deadline check until a whole 64 KiB block arrives.
    while chunk := response.read1(64 * 1024):
        size += len(chunk)
        if size > limit:
            raise RuntimeError("SQLite response exceeded its size limit")
        if time.monotonic() >= deadline:
            raise TimeoutError("SQLite preparation exceeded its deadline")
        yield chunk
    if time.monotonic() >= deadline:
        raise TimeoutError("SQLite preparation exceeded its deadline")


def download(url: str, destination: Path, digest: str, deadline: float) -> None:
    # urllib rejects non-success HTTP statuses before their error bodies can be
    # mistaken for native code. TLS uses the platform's normal verification.
    with request(url, deadline, "application/octet-stream") as response:
        with tempfile.NamedTemporaryFile(dir=destination.parent, suffix=".part", delete=False) as output:
            temporary = Path(output.name)
            try:
                hasher = hashlib.sha256()
                for chunk in read_chunks(response, deadline, MAX_BYTES):
                    hasher.update(chunk)
                    output.write(chunk)
                if hasher.hexdigest() != digest:
                    raise RuntimeError("SQLite SHA-256 mismatch; refusing the downloaded binary")
                output.close()
                os.replace(temporary, destination)
            finally:
                output.close()
                temporary.unlink(missing_ok=True)


def prepare(repo: Path, target: str) -> Path:
    repo = repo.resolve()
    tag, digest, destination = asset_spec(repo, target)
    if destination.is_file() and hashlib.sha256(destination.read_bytes()).hexdigest() == digest:
        print(f"Verified cached SQLite for {target}: {digest}", flush=True)
        return destination
    destination.parent.mkdir(parents=True, exist_ok=True)
    filename = TARGETS[target][0]
    release_url = f"https://github.com/simolus3/sqlite3.dart/releases/download/{tag}/{filename}"
    asset_url = None
    api_first = bool(os.environ.get("BILISAIL_GITHUB_TOKEN"))
    deadline = time.monotonic() + 120
    for attempt in range(MAX_ATTEMPTS):
        phase = "Release download"
        try:
            # Either official gateway can fail independently. Do not stay on
            # an unavailable API after the first Release download failure.
            url = release_url
            use_api = (attempt % 2 == 0) == api_first
            if use_api:
                if asset_url is None:
                    phase = "Release API metadata"
                    asset_url = api_asset(tag, filename, digest, deadline)
                phase = "Release API asset"
                url = asset_url
            download(url, destination, digest, deadline)
            print(f"Verified SQLite for {target}: {digest}", flush=True)
            return destination
        except HTTPError as error:
            error.close()
            if (error.code not in (408, 429, 500, 502, 503, 504)
                    or attempt == MAX_ATTEMPTS - 1 or time.monotonic() >= deadline):
                raise RuntimeError(f"SQLite {phase} failed after {attempt + 1} attempts (HTTP {error.code})") from None
            failure = f"HTTP {error.code}"
        except (URLError, TimeoutError, ConnectionError, http.client.IncompleteRead) as error:
            if attempt == MAX_ATTEMPTS - 1 or time.monotonic() >= deadline:
                raise RuntimeError(f"SQLite {phase} failed after {attempt + 1} attempts ({type(error).__name__})") from None
            failure = type(error).__name__
        next_route = "Release download" if use_api else "Release API"
        print(f"SQLite {phase} attempt {attempt + 1}/{MAX_ATTEMPTS}: {failure}; retrying via {next_route}", flush=True)
        time.sleep(min(2 ** attempt, max(0, deadline - time.monotonic())))
    raise RuntimeError("SQLite preparation did not complete")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument("--target", choices=TARGETS)
    args = parser.parse_args()
    prepare(args.repo, args.target or host_target())
