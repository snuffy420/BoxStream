"""Builds the sideload zip: releases/boxstream-v<version>-roku.zip"""
import hashlib
import os
import re
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def version():
    manifest = open(os.path.join(ROOT, "manifest"), encoding="utf-8").read()
    parts = [re.search(rf"{k}_version=(\d+)", manifest).group(1) for k in ("major", "minor", "build")]
    return ".".join(parts)


def package_files():
    yield "manifest"
    for folder in ("source", "components", "images", "fonts"):
        for directory, _, names in sorted(os.walk(os.path.join(ROOT, folder))):
            for name in sorted(names):
                if not name.lower().endswith((".svg", ".gif")):
                    yield os.path.relpath(os.path.join(directory, name), ROOT).replace(os.sep, "/")


def bump():
    """Every build is a new revision: 0.1.4 -> 0.1.5 (pass --same to keep it)."""
    path = os.path.join(ROOT, "manifest")
    text = open(path, encoding="utf-8").read()
    build = int(re.search(r"build_version=(\d+)", text).group(1)) + 1
    minor = int(re.search(r"minor_version=(\d+)", text).group(1))
    major = int(re.search(r"major_version=(\d+)", text).group(1))
    # 0.1.9 is followed by 0.2.0, and 0.9.9 by 1.0.0: each part stays a single digit.
    if build > 9:
        build = 0
        minor += 1
    if minor > 9:
        minor = 0
        major += 1
    text = re.sub(r"build_version=\d+", f"build_version={build}", text)
    text = re.sub(r"minor_version=\d+", f"minor_version={minor}", text)
    text = re.sub(r"major_version=\d+", f"major_version={major}", text)
    open(path, "w", encoding="utf-8", newline=chr(10)).write(text)


def main():
    import subprocess, sys
    if "--same" not in sys.argv:
        bump()
    # About page: QR codes and links from tools/about.json.
    subprocess.run([sys.executable, os.path.join(ROOT, "tools", "build_about.py")], check=True)
    # The splash shows the version.
    subprocess.run([sys.executable, os.path.join(ROOT, "tools", "build_assets.py"), "--splash"], check=True, stdout=subprocess.DEVNULL)
    os.makedirs(os.path.join(ROOT, "releases"), exist_ok=True)
    output = os.path.join(ROOT, "releases", f"boxstream-v{version()}-roku.zip")
    # Only the newest build is kept.
    for name in os.listdir(os.path.join(ROOT, "releases")):
        if name.startswith("boxstream-v") and not name.startswith(os.path.basename(output)):
            os.remove(os.path.join(ROOT, "releases", name))
    with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as archive:
        for path in package_files():
            archive.write(os.path.join(ROOT, path), path)
    digest = hashlib.sha256(open(output, "rb").read()).hexdigest()
    with open(output + ".sha256", "w", encoding="ascii", newline="\n") as f:
        f.write(f"{digest}  {os.path.basename(output)}\n")
    print(output, os.path.getsize(output), "bytes")
    return output


if __name__ == "__main__":
    main()
