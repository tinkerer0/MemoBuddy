#!/usr/bin/env python3
"""Regenerates THIRD_PARTY_LICENSES.md from the license files of everything
that ships inside the app: the Rust crates it depends on for macOS and Windows
(a conservative list from the normal dependency graph, without build scripts
and proc macros, so a few crates used only while building may also appear)
and the npm code bundled into its pages.

    python3 scripts/third-party-licenses.py

Each crate's own license files are copied word for word, so the notices keep
their real copyright lines. A crate published without license files uses the
copies in src-tauri/licenses/ (see the README there); a crate with neither
stops the script, so a new dependency is reviewed before release. The file is
written only when everything was found. It is bundled into the app
(tauri.conf.json resources, and the MSIX by scripts/pack-msix.ps1).
Needs cargo and node_modules (npm ci).
"""
import json
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MANIFEST = os.path.join(ROOT, "src-tauri", "Cargo.toml")
OVERRIDES = os.path.join(ROOT, "src-tauri", "licenses")
OUTPUT = os.path.join(ROOT, "THIRD_PARTY_LICENSES.md")
TARGETS = ["aarch64-apple-darwin", "x86_64-apple-darwin", "x86_64-pc-windows-msvc"]
LICENSE_FILE = re.compile(r"^(licen[cs]e|copying|notice|copyright)", re.I)
NPM_PACKAGES = ["@tauri-apps/api", "vite"]

INTRO = """# Third-party licenses

MemoBuddy includes the open-source software listed below, each used under the
license shown. The texts are the license files published with each component.
None of them is modified except wry and tao, whose sources (with MemoBuddy's
small changes, marked "MemoPet patch") are in the MemoBuddy repository under
vendor/. The source code of every Rust crate, including those under the
Mozilla Public License 2.0, is available from crates.io
(https://crates.io/crates/<name>).
"""


def shipped_crates():
    """Packages linked into the app for any of the desktop targets."""
    shipped = {}
    for target in TARGETS:
        output = subprocess.run(
            ["cargo", "metadata", "--format-version", "1", "--locked", "--manifest-path", MANIFEST, "--filter-platform", target],
            capture_output=True, text=True, check=True).stdout
        meta = json.loads(output)
        packages = {package["id"]: package for package in meta["packages"]}
        nodes = {node["id"]: node for node in meta["resolve"]["nodes"]}
        root = meta["resolve"]["root"]
        seen, stack = set(), [root]
        while stack:
            current = stack.pop()
            if current in seen:
                continue
            seen.add(current)
            for dep in nodes[current]["deps"]:
                if not any(kind["kind"] is None for kind in dep["dep_kinds"]):
                    continue  # build or dev dependency
                package = packages[dep["pkg"]]
                if any("proc-macro" in built["kind"] for built in package["targets"]):
                    continue  # runs at compile time only
                stack.append(dep["pkg"])
        for package_id in seen - {root}:
            shipped[package_id] = packages[package_id]
    return sorted(shipped.values(), key=lambda package: (package["name"], package["version"]))


def files_in(folder):
    found = []
    for name in sorted(os.listdir(folder)):
        path = os.path.join(folder, name)
        if os.path.isfile(path) and LICENSE_FILE.match(name) and not name.endswith(".spdx"):
            found.append(path)
        elif os.path.isdir(path) and name.upper() == "LICENSES":
            found += [os.path.join(path, inner) for inner in sorted(os.listdir(path)) if os.path.isfile(os.path.join(path, inner))]
    return found


def license_files(package):
    found = files_in(os.path.dirname(package["manifest_path"]))
    if found:
        return found
    repository = (package.get("repository") or "").rstrip("/")
    match = re.match(r"https://github\.com/([^/]+)/([^/]+?)(?:\.git)?$", repository)
    if match:
        folder = os.path.join(OVERRIDES, f"{match.group(1)}__{match.group(2)}")
        if os.path.isdir(folder):
            return [os.path.join(folder, name) for name in sorted(os.listdir(folder)) if name != "README.md"]
    return []


def read(path):
    with open(path, encoding="utf-8", errors="replace") as handle:
        lines = handle.read().replace("\r\n", "\n").replace("\r", "\n").split("\n")
    return "\n".join(line.rstrip() for line in lines).strip("\n")


def title(text):
    head = text[:600].lower()
    for needle, name in [
        ("apache license", "Apache License 2.0"),
        ("cc0 1.0 universal", "CC0 1.0 Universal"),
        ("creativecommons.org/licenses/by/3.0", "Creative Commons Attribution 3.0"),
        ("mozilla public license", "Mozilla Public License 2.0"),
        ("permission is hereby granted, free of charge", "MIT License"),
        ("this is free and unencumbered software", "The Unlicense"),
        ("unicode", "Unicode License"),
        ("redistribution and use in source and binary forms", "BSD License"),
        ("provided 'as-is'", "zlib License"),
        ("provided \"as-is\"", "zlib License"),
    ]:
        if needle in head:
            return name
    first = next((line.strip("# ") for line in text.split("\n") if line.strip()), "License")
    return first[:80]


def npm_section():
    parts = ["## npm packages bundled into the app's pages", ""]
    for name in NPM_PACKAGES:
        folder = os.path.join(ROOT, "node_modules", name)
        with open(os.path.join(folder, "package.json"), encoding="utf-8") as handle:
            version = json.load(handle)["version"]
        files = files_in(folder)
        if not files:
            sys.exit(f"no license file in node_modules/{name}")
        parts += [f"### {name} {version}", ""]
        for path in files:
            text = read(path)
            if name == "vite":
                # Vite's file also lists the packages bundled into Vite itself;
                # only Vite's own license applies to the helper in our pages.
                text = text.split("# Licenses of bundled dependencies")[0].strip("\n")
            parts += ["```", text, "```", ""]
    return parts


def main():
    groups = {}
    missing = []
    for package in shipped_crates():
        files = license_files(package)
        if not files:
            missing.append(f"{package['name']} {package['version']} ({package.get('license')})")
            continue
        for path in files:
            groups.setdefault(read(path), []).append(f"{package['name']} {package['version']}")
    if missing:
        sys.exit("no license text for: " + ", ".join(missing) + " (add a copy under src-tauri/licenses/)")
    lines = [INTRO, "## Rust crates", ""]
    for text, users in sorted(groups.items(), key=lambda item: (title(item[0]), sorted(item[1])[0])):
        crates = ", ".join(sorted(set(users)))
        lines += [f"### {title(text)}", "", f"Used by: {crates}", "", "```", text, "```", ""]
    lines += npm_section()
    content = "\n".join(lines).rstrip("\n") + "\n"
    handle, temporary = tempfile.mkstemp(dir=ROOT, prefix=".THIRD_PARTY_LICENSES.", suffix=".tmp")
    with os.fdopen(handle, "w", encoding="utf-8") as out:
        out.write(content)
    os.chmod(temporary, 0o644)  # mkstemp makes it owner-only; the notices are public
    os.replace(temporary, OUTPUT)
    crates = len({user for users in groups.values() for user in users})
    print(f"wrote THIRD_PARTY_LICENSES.md: {crates} crates, {len(groups)} license texts, {len(content.encode())} bytes")


if __name__ == "__main__":
    main()
