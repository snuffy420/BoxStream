"""Builds everything for a GitHub release in releases/github/:

  BoxStream-v<ver>.zip (+ .sha256)          the bundle: Roku app zip, helper setup
                                            script and INSTALL.txt
  boxstream-v<ver>-roku.zip (+ .sha256)     the Roku app on its own
  boxstream-setup.sh (+ .sha256)            the helper's Oracle Cloud Shell setup on its own
  boxstream-v<ver>-source.7z (+ .sha256)    the source (the repo files), like the other projects
  repo/                                     the project files to upload to the repository
  UPLOAD.txt                                what goes where

Run:  python tools/release.py          (a new version: bumps the manifest, like package.py)
      python tools/release.py --same   (the manifest's version as it is)
"""
import hashlib
import os
import shutil
import subprocess
import sys
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import package  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "releases", "github")
# Never part of the public repository.
PRIVATE = {"releases", "testfiles", "data", "__pycache__", ".git", "node_modules"}


def sha256_file(path):
    digest = hashlib.sha256(open(path, "rb").read()).hexdigest()
    with open(path + ".sha256", "w", encoding="ascii", newline="\n") as f:
        f.write(f"{digest}  {os.path.basename(path)}\n")
    return digest


def find_7z():
    tool = shutil.which("7z") or shutil.which("7zz")
    if not tool and os.path.isfile("C:/Program Files/7-Zip/7z.exe"):
        tool = "C:/Program Files/7-Zip/7z.exe"
    if not tool:
        raise SystemExit("Install 7-Zip (7z on PATH) to build the source archive.")
    return tool


def source_7z(repo, version):
    """A genuine 7z of the repository files, tested, with its checksum."""
    tool = find_7z()
    out = os.path.join(OUT, f"boxstream-v{version}-source.7z")
    if os.path.exists(out):
        os.remove(out)
    subprocess.run([tool, "a", "-t7z", "-mx=7", "-scsUTF-8", out, "."], cwd=repo, check=True,
                   stdout=subprocess.DEVNULL)
    subprocess.run([tool, "t", out], check=True, stdout=subprocess.DEVNULL)
    assert open(out, "rb").read(6) == bytes([0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C])  # 7z signature
    sha256_file(out)
    return out


def main():
    roku_zip = package.main()
    version = package.version()
    subprocess.run([sys.executable, os.path.join(ROOT, "tools", "build_setup.py")], check=True)
    setup = os.path.join(ROOT, "releases", "boxstream-setup.sh")

    if os.path.isdir(OUT):
        shutil.rmtree(OUT)
    os.makedirs(OUT)

    # The two files on their own, each with its checksum.
    app = os.path.join(OUT, os.path.basename(roku_zip))
    shutil.copyfile(roku_zip, app)
    sha256_file(app)
    script = os.path.join(OUT, "boxstream-setup.sh")
    shutil.copyfile(setup, script)
    sha256_file(script)

    # The bundle: app, script and the install guide (with this version in it).
    guide = open(os.path.join(ROOT, "INSTALL.txt"), encoding="utf-8").read().replace("{VERSION}", version)
    bundle = os.path.join(OUT, f"BoxStream-v{version}.zip")
    with zipfile.ZipFile(bundle, "w", zipfile.ZIP_DEFLATED) as z:
        z.write(app, os.path.basename(app))
        z.write(script, "boxstream-setup.sh")
        z.writestr("INSTALL.txt", guide.replace("\n", "\r\n"))  # Notepad-friendly
    sha256_file(bundle)

    # The repository's files.
    repo = os.path.join(OUT, "repo")
    for directory, folders, names in os.walk(ROOT):
        rel = os.path.relpath(directory, ROOT)
        parts = set(rel.split(os.sep))
        if parts & PRIVATE:
            folders[:] = []
            continue
        folders[:] = [f for f in folders if f not in PRIVATE]
        for name in names:
            if name.endswith((".pyc", ".log")):
                continue
            target = os.path.join(repo, rel, name)
            os.makedirs(os.path.dirname(target), exist_ok=True)
            shutil.copyfile(os.path.join(directory, name), target)

    source_7z(repo, version)

    files = sorted(n for n in os.listdir(OUT) if n != "repo")
    with open(os.path.join(OUT, "UPLOAD.txt"), "w", encoding="utf-8", newline="\r\n") as f:
        f.write(f"Box://Stream {version} - GitHub upload\n\n")
        f.write("REPOSITORY\n  Upload the CONTENTS of the repo folder to the repository's root,\n"
                "  keeping the folders and replacing existing files.\n\n")
        f.write(f"RELEASE\n  Create a release tagged v{version} and attach:\n")
        for n in files:
            if n != "UPLOAD.txt":
                f.write(f"    {n}\n")
        f.write(f"  Description: the {version} section of CHANGELOG.md.\n")
        f.write("\nCONTACT FORM\n  Settings > Pages: deploy from the main branch, / (root), so\n"
                "  https://snuffy420.github.io/BoxStream/docs/contact.html works.\n")
    for n in files + ["UPLOAD.txt"]:
        if n != "repo":
            print(os.path.join(OUT, n))


if __name__ == "__main__":
    main()
