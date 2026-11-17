"""Builds releases/boxstream-setup.sh: the one-file Oracle Cloud Shell setup.

Packs helper/boxstream_helper.py and helper/install.sh into the template
(helper/cloudshell_setup.template.sh) so users download a single file.
"""
import base64
import io
import os
import tarfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HELPER = os.path.join(ROOT, "helper")
OUT = os.path.join(ROOT, "releases", "boxstream-setup.sh")

buf = io.BytesIO()
with tarfile.open(fileobj=buf, mode="w:gz") as tar:
    for name in ("boxstream_helper.py", "install.sh"):
        data = open(os.path.join(HELPER, name), "rb").read().replace(b"\r\n", b"\n")
        info = tarfile.TarInfo(name)
        info.size = len(data)
        info.mode = 0o755
        tar.addfile(info, io.BytesIO(data))
payload = base64.b64encode(buf.getvalue()).decode()
lines = "\n".join(payload[i:i + 76] for i in range(0, len(payload), 76))

template = open(os.path.join(HELPER, "cloudshell_setup.template.sh"), encoding="utf-8").read()
assert template.count("__PAYLOAD__") == 1
script = template.replace("__PAYLOAD__", lines).replace("\r\n", "\n")
os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, "w", encoding="utf-8", newline="\n") as f:
    f.write(script)
print(OUT, len(script), "bytes; payload", len(payload), "bytes")
