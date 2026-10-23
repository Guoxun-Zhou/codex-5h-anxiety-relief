#!/usr/bin/env python3
"""Build a source release from the explicit publication manifest."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def listed_files(root: Path) -> list[tuple[str, Path]]:
    root = root.resolve()
    lines = (root / "publish-manifest.txt").read_text(encoding="utf-8-sig").splitlines()
    files = []
    seen = set()
    for line in lines:
        if not line or line.startswith("#"):
            continue
        relative = PurePosixPath(line)
        if relative.is_absolute() or ".." in relative.parts or "\\" in line or ":" in line:
            raise ValueError("Unsafe manifest path: " + line)
        if line.lower() in seen:
            raise ValueError("Duplicate manifest path: " + line)
        seen.add(line.lower())
        if any(part.lower() in (".git", ".codex", "auth.json", "settings.json", "running.lock") or part.lower().startswith(".env") for part in relative.parts):
            raise ValueError("Runtime or credential file in manifest: " + line)
        if re.search(r"(^|/)state-[^/]+\.json$|\.log(?:\.[^/]+)?$|\.(zip|exe|key|pem|pfx)$", line, re.IGNORECASE):
            raise ValueError("Runtime or binary file in manifest: " + line)
        original = root.joinpath(*relative.parts)
        resolved = original.resolve()
        if root not in resolved.parents or not resolved.is_file():
            raise ValueError("Missing or escaping manifest file: " + line)
        if any(path.is_symlink() for path in (original, *original.parents) if path != root and root in path.parents):
            raise ValueError("Linked manifest file: " + line)
        files.append((line, resolved))
    if not files:
        raise ValueError("Empty publication manifest")
    return files


def build(root: Path, output: Path) -> tuple[Path, int]:
    project = json.loads((root / "project.json").read_text(encoding="utf-8-sig"))
    version = project["version"]
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError("Invalid release version")
    name = f"codex-5h-anxiety-relief-v{version}"
    files = listed_files(root)
    output.mkdir(parents=True, exist_ok=True)
    archive = output / (name + "-github.zip")
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as bundle:
        for relative, path in files:
            entry = zipfile.ZipInfo(name + "/" + relative, date_time=(2026, 10, 23, 0, 0, 0))
            entry.create_system = 3
            entry.external_attr = ((0o100755 if path.suffix == ".sh" else 0o100644) << 16)
            entry.compress_type = zipfile.ZIP_DEFLATED
            bundle.writestr(entry, path.read_bytes())
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    (output / "SHA256SUMS.txt").write_text(f"{digest}  {archive.name}\n", encoding="ascii")
    return archive, len(files)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "dist")
    args = parser.parse_args()
    archive, count = build(ROOT, args.output.resolve())
    print(f"Built {archive.name}: {count} manifest-listed files")
