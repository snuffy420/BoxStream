"""Box://Stream Helper Setup: installs the helper on your own server in one click.

Enter the server's public IP, choose the SSH key file your cloud provider gave
you (Oracle Cloud: the .key file saved when the server was created), and press
Install. Everything needed is uploaded and set up over SSH; at the end you get
the address and pairing code to enter in Box://Stream (Settings > Helper).

Needs Python 3 and Windows' built-in OpenSSH (ssh.exe / scp.exe).
"""
import json
import os
import re
import shutil
import subprocess
import tempfile
import threading
import tkinter as tk
import urllib.request
from tkinter import filedialog, messagebox, ttk

HERE = os.path.dirname(os.path.abspath(__file__))
FILES = ["install.sh", "boxstream_helper.py"]
NOWINDOW = getattr(subprocess, "CREATE_NO_WINDOW", 0)


def private_key_copy(path):
    """OpenSSH refuses keys other users can read: use a private copy."""
    folder = os.path.join(os.path.expanduser("~"), ".ssh")
    os.makedirs(folder, exist_ok=True)
    dest = os.path.join(folder, "boxstream-helper.key")
    shutil.copyfile(path, dest)
    if os.name == "nt":
        user = os.environ.get("USERNAME", "")
        subprocess.run(["icacls", dest, "/inheritance:r", "/grant:r", "%s:F" % user],
                       capture_output=True, creationflags=NOWINDOW)
    else:
        os.chmod(dest, 0o600)
    return dest


class Setup(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("Box://Stream Helper Setup")
        self.geometry("680x560")
        pad = {"padx": 8, "pady": 4}
        intro = ("Installs the Box://Stream Helper on your own server (for example a free Oracle Cloud "
                 "server). It converts only the audio your Roku can't play: DTS/TrueHD and hi-res FLAC.")
        ttk.Label(self, text=intro, wraplength=640, justify="left").pack(anchor="w", **pad)
        form = ttk.Frame(self)
        form.pack(fill="x", **pad)
        self.ip = tk.StringVar()
        self.user = tk.StringVar(value="ubuntu")
        self.key = tk.StringVar()
        ttk.Label(form, text="Server public IP").grid(row=0, column=0, sticky="w")
        ttk.Entry(form, textvariable=self.ip, width=30).grid(row=0, column=1, sticky="w", **pad)
        ttk.Label(form, text="Username").grid(row=1, column=0, sticky="w")
        ttk.Entry(form, textvariable=self.user, width=30).grid(row=1, column=1, sticky="w", **pad)
        ttk.Label(form, text="SSH key file").grid(row=2, column=0, sticky="w")
        ttk.Entry(form, textvariable=self.key, width=50).grid(row=2, column=1, sticky="w", **pad)
        ttk.Button(form, text="Browse…", command=self.pick_key).grid(row=2, column=2, **pad)
        self.go = ttk.Button(self, text="Install", command=self.start)
        self.go.pack(anchor="w", **pad)
        self.log = tk.Text(self, height=14, wrap="word", state="disabled", background="#f6f6f6")
        self.log.pack(fill="both", expand=True, **pad)
        result = ttk.LabelFrame(self, text="Enter these in Box://Stream: Settings > Helper")
        result.pack(fill="x", **pad)
        self.addr = tk.StringVar()
        self.code = tk.StringVar()
        for row, (label, var) in enumerate((("Address", self.addr), ("Pairing code", self.code))):
            ttk.Label(result, text=label).grid(row=row, column=0, sticky="w", **pad)
            ttk.Entry(result, textvariable=var, width=40, font=("Segoe UI", 12, "bold")).grid(row=row, column=1, **pad)
            ttk.Button(result, text="Copy", command=lambda v=var: (self.clipboard_clear(), self.clipboard_append(v.get()))).grid(row=row, column=2, **pad)

    def pick_key(self):
        path = filedialog.askopenfilename(title="SSH private key", filetypes=[("Key files", "*.key *.pem *"), ("All files", "*")])
        if path:
            self.key.set(path)

    def say(self, text):
        def put():
            self.log.configure(state="normal")
            self.log.insert("end", text + "\n")
            self.log.see("end")
            self.log.configure(state="disabled")
        self.after(0, put)

    def start(self):
        ip, user, key = self.ip.get().strip(), self.user.get().strip() or "ubuntu", self.key.get().strip()
        if not re.match(r"^\d{1,3}(\.\d{1,3}){3}$", ip):
            return messagebox.showinfo("Helper Setup", "Enter the server's public IP address (four numbers with dots).")
        if not os.path.isfile(key):
            return messagebox.showinfo("Helper Setup", "Choose the SSH key file for the server.")
        missing = [f for f in FILES if not os.path.isfile(os.path.join(HERE, f))]
        if missing:
            return messagebox.showerror("Helper Setup", "Missing next to this program: " + ", ".join(missing))
        self.go.configure(state="disabled")
        threading.Thread(target=self.install, args=(ip, user, key), daemon=True).start()

    def run(self, args, timeout=900):
        proc = subprocess.run(args, capture_output=True, text=True, timeout=timeout, creationflags=NOWINDOW)
        return proc.returncode, (proc.stdout or "") + (proc.stderr or "")

    def install(self, ip, user, key):
        try:
            keyfile = private_key_copy(key)
            ssh = ["ssh", "-i", keyfile, "-o", "StrictHostKeyChecking=accept-new", "-o", "ConnectTimeout=20", "%s@%s" % (user, ip)]
            self.say("Connecting to %s…" % ip)
            code, out = self.run(ssh + ["echo connected"], 60)
            if code != 0:
                self.say("Couldn't connect: " + out.strip()[-300:])
                self.say("Check the IP, the username (Oracle Ubuntu: ubuntu) and that this is the right key file.")
                return
            self.say("Uploading the helper…")
            # Plain LF line endings for Linux.
            tmp = tempfile.mkdtemp()
            for f in FILES:
                data = open(os.path.join(HERE, f), "rb").read().replace(b"\r\n", b"\n")
                open(os.path.join(tmp, f), "wb").write(data)
            code, out = self.run(["scp", "-i", keyfile, "-o", "StrictHostKeyChecking=accept-new"] +
                                 [os.path.join(tmp, f) for f in FILES] + ["%s@%s:/home/%s/" % (user, ip, user)], 120)
            if code != 0:
                self.say("Upload failed: " + out.strip()[-300:])
                return
            self.say("Installing (ffmpeg, the helper and HTTPS). This takes a few minutes…")
            code, out = self.run(ssh + ["bash ~/install.sh"], 1200)
            for line in out.splitlines():
                if line.startswith("==") or "Address" in line or "Pairing" in line:
                    self.say(line.strip())
            addr = re.search(r"Address:\s+(\S+)", out)
            token = re.search(r"Pairing code:\s+(\S+)", out)
            if code != 0 or not addr or not token:
                self.say("The install didn't finish: " + out.strip()[-400:])
                return
            self.after(0, lambda: (self.addr.set(addr.group(1)), self.code.set(token.group(1))))
            self.say("Checking the helper can be reached from the internet…")
            ok = False
            for _ in range(8):
                try:
                    req = urllib.request.Request(addr.group(1) + "/ping", headers={"X-Helper-Token": token.group(1)})
                    with urllib.request.urlopen(req, timeout=20) as r:
                        ok = json.loads(r.read().decode()).get("ok") is True
                    if ok:
                        break
                except Exception:
                    pass
                threading.Event().wait(15)
            if ok:
                self.say("Done! The helper is running. Enter the address and pairing code below in Box://Stream.")
            else:
                self.say("Installed, but it can't be reached from the internet yet. In the Oracle console open: "
                         "your server > Subnet > Default Security List > Add Ingress Rules, and add TCP port 80 "
                         "and TCP port 443 from 0.0.0.0/0. Then press Install again (it's safe to repeat).")
        except Exception as e:
            self.say("Error: %s" % e)
        finally:
            self.after(0, lambda: self.go.configure(state="normal"))


if __name__ == "__main__":
    Setup().mainloop()
