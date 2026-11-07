"""Check staged Linux dependencies and retain their distro license metadata."""

import json
import hashlib
import os
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import sys


def run(*arguments: str, env: dict[str, str] | None = None) -> str:
    result = subprocess.run(
        arguments, check=True, capture_output=True, text=True, env=env, timeout=120
    )
    return result.stdout


def find_distro_packages(libraries: list[Path]) -> list[str]:
    # Ubuntu x64 libraries and GTK modules come from these multiarch trees.
    # A basename-only glob also matches Chrome's private /opt copies on CI.
    roots = (
        PurePosixPath("/usr/lib/x86_64-linux-gnu"),
        PurePosixPath("/lib/x86_64-linux-gnu"),
    )
    names = {path.name for path in libraries}
    ownership = subprocess.run(
        ["dpkg-query", "--search", *(f"{root}/*" for root in roots)],
        capture_output=True, text=True, check=False, timeout=120,
        env=dict(os.environ, LC_ALL="C"),
    )
    if ownership.returncode not in (0, 1):
        raise RuntimeError(ownership.stderr)
    packages = set()
    for line in ownership.stdout.splitlines():
        owners, separator, filename = line.partition(": ")
        if not separator or line.startswith(("diversion ", "local diversion ")):
            continue
        path = PurePosixPath(filename)
        if path.name in names and any(path.is_relative_to(root) for root in roots):
            packages.update(owners.split(", "))
    if not packages:
        raise RuntimeError("No distro dependency license metadata found")
    return sorted(packages)


def write_distro_notices(
    packages: list[str], notices: Path, doc_root: Path = Path("/usr/share/doc")
) -> None:
    records = run(
        "dpkg-query", "--show",
        "--showformat=${binary:Package}\t${Version}\t${source:Package}\t${source:Version}\n",
        *packages,
    )
    notices.mkdir(parents=True, exist_ok=True)
    for package in packages:
        copyright_file = doc_root / package.split(":")[0] / "copyright"
        if not copyright_file.is_file():
            raise RuntimeError(f"Distro license text missing: {package}")
        filename = package.replace(":", "_") + ".copyright"
        shutil.copyfile(copyright_file, notices / filename)
    (notices / "packages.tsv").write_text(
        "binary\tversion\tsource\tsource-version\n" + records, encoding="utf-8"
    )
    (notices / "README.txt").write_text(
        "Ubuntu 24.04 dependency binaries. License texts are in *.copyright.\n"
        "packages.tsv records exact binary and source versions. Enable Ubuntu\n"
        "deb-src repositories, then fetch with: apt-get source SOURCE=VERSION\n"
        "Flutter, media-kit and the isolated bili_mux have separate notices.\n",
        encoding="utf-8",
    )


def main() -> None:
    appdir = Path(sys.argv[1]).resolve()
    version = sys.argv[2]
    libraries = sorted(path for path in appdir.rglob("*.so*") if path.is_file())
    if not any(path.name == "libmpv.so.2" for path in libraries):
        raise RuntimeError("The package must include dlopen'ed libmpv.so.2")
    env = dict(os.environ, LC_ALL="C")
    env["LD_LIBRARY_PATH"] = f"{appdir}/usr/bin/lib:{appdir}/usr/lib"
    for binary in [appdir / "usr/bin/bilisail", *libraries]:
        with binary.open("rb") as stream:
            magic = stream.read(4)
        if magic != b"\x7fELF":
            continue
        dependencies = run("ldd", str(binary), env=env)
        if "not found" in dependencies:
            raise RuntimeError(f"Unresolved dependencies: {binary}\n{dependencies}")

    mpv_source = appdir / "usr/bin/data/licenses/mpv/SOURCE.json"
    if not mpv_source.is_file():
        raise RuntimeError("Missing personal libmpv source provenance")
    source = json.loads(mpv_source.read_text(encoding="utf-8"))
    if source.get("repository") != "https://github.com/CKopoer/mpv":
        raise RuntimeError("Linux libmpv must come from the maintained personal fork")
    native_libraries = [
        path for path in libraries if path.name.startswith("libmpv.so")
    ]
    native_records = [
        {
            "path": str(path.relative_to(appdir)),
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        }
        for path in native_libraries
    ]
    native_notice = appdir / "usr/share/doc/bilisail/native-mpv.json"
    native_notice.parent.mkdir(parents=True, exist_ok=True)
    native_notice.write_text(
        json.dumps({"source": source, "libraries": native_records}, indent=2) + "\n",
        encoding="utf-8",
    )
    packages = find_distro_packages(
        [path for path in libraries if not path.name.startswith("libmpv.so")]
    )
    write_distro_notices(packages, appdir / "usr/share/doc/bilisail/dependencies")
    # Flutter/Linux stores application version data here; reject stale bundles.
    version_file = appdir / "usr/bin/data/flutter_assets/version.json"
    metadata = json.loads(version_file.read_text(encoding="utf-8"))
    name, number = version.split("+")
    if metadata["version"] != name or metadata["build_number"] != number:
        raise RuntimeError(f"Linux version metadata mismatch: {metadata}")


if __name__ == "__main__":
    main()
