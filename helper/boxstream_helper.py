#!/usr/bin/env python3
"""Box://Stream Helper: converts only the audio Box://Stream's Roku can't play.

Runs on the user's own server (e.g. a free Oracle Cloud VM) behind Caddy (HTTPS).
Video never passes through here: the Roku gets only converted audio.

  GET /ping                                       {"ok": true, "version": ...}
  GET /flac?src=URL[&start=SECONDS]               hi-res FLAC as 48 kHz / 24-bit FLAC (streamed)
  GET /ac3/start?src=URL&track=N[&ch=C&kbps=K&start=SECONDS]
                                                  begin converting audio track N to Dolby
                                                  Digital, 48 kHz, C channels (1-6; more are
                                                  folded down to 5.1) at K kb/s; {"id": ...}
  GET /ac3/read?id=ID&from=BYTE[&max=BYTES]       the converted bytes from BYTE on (what is
                                                  ready so far); headers X-Done, X-Total
  GET /ac3/status?id=ID                           {"bytes", "seconds", "done", "speed"}
  GET /ac3/stop?id=ID

Every request needs the pairing token (header X-Helper-Token, or ?token=).
The seedbox login, if any, comes in header X-Source-Auth (an Authorization value).
It is kept in memory for that conversion only and added by a private proxy on
127.0.0.1, so it never appears on a command line, and ffmpeg can still jump to
any point in the file. One conversion runs at a time.
"""
import json
import os
import secrets
import subprocess
import threading
import time
import urllib.parse
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

VERSION = "1.2.0"
CONFIG = os.environ.get("BOXSTREAM_HELPER_CONFIG", "/etc/boxstream-helper.json")
CFG = json.load(open(CONFIG))
TOKEN = CFG["token"]
AC3_RATES = (96, 128, 192, 224, 256, 320, 384, 448, 512, 576, 640)
PORT = int(CFG.get("port", 8090))
PROXY_PORT = PORT + 1
WORK = "/tmp/boxstream-helper"
os.makedirs(WORK, exist_ok=True)

LOCK = threading.Lock()
SOURCES = {}     # proxy id -> {"url", "auth"}
SESSION = {}     # the one running conversion
CURRENT = {"proc": None}


# ---- Private proxy: ffmpeg reads the source through here (login added here) ----

class Proxy(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        pass

    def do_GET(self):
        sid = self.path.strip("/").split("/")[-1]
        src = SOURCES.get(sid)
        if not src:
            self.send_response(404)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        req = urllib.request.Request(src["url"])
        if src["auth"]:
            req.add_header("Authorization", src["auth"])
        if self.headers.get("Range"):
            req.add_header("Range", self.headers["Range"])
        try:
            r = urllib.request.urlopen(req, timeout=30)
        except urllib.error.HTTPError as e:
            r = e
        self.send_response(r.status if hasattr(r, "status") else r.code)
        for h in ("Content-Type", "Content-Length", "Content-Range", "Accept-Ranges"):
            if r.headers.get(h):
                self.send_header(h, r.headers[h])
        self.end_headers()
        try:
            while True:
                chunk = r.read(262144)
                if not chunk:
                    break
                self.wfile.write(chunk)
        except (BrokenPipeError, ConnectionResetError):
            pass


def proxy_url(src, auth):
    sid = secrets.token_hex(8)
    SOURCES.clear()  # one conversion at a time
    SOURCES[sid] = {"url": src, "auth": auth}
    return "http://127.0.0.1:%d/p/%s" % (PROXY_PORT, sid)


def stop_current():
    proc = CURRENT["proc"]
    if proc and proc.poll() is None:
        proc.kill()
    CURRENT["proc"] = None


def ffmpeg_base(start, url):
    args = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-nostdin", "-threads", "1"]
    if start:
        args += ["-ss", str(float(start))]
    return args + ["-i", url]


# ---- Public API ------------------------------------------------------------------

class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):  # no URLs (with seedbox paths) in logs
        pass

    def reply(self, code, body, ctype="application/json", extra=None):
        data = body.encode() if isinstance(body, str) else body
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        url = urllib.parse.urlparse(self.path)
        q = {k: v[-1] for k, v in urllib.parse.parse_qs(url.query).items()}
        token = self.headers.get("X-Helper-Token") or q.get("token", "")
        if token != TOKEN:
            return self.reply(403, '{"ok":false,"error":"wrong pairing code"}')
        path = url.path
        if path == "/ping":
            return self.reply(200, json.dumps({"ok": True, "version": VERSION}))
        if path in ("/flac", "/ac3/start"):
            src = q.get("src", "")
            if not src.startswith(("http://", "https://")):
                return self.reply(400, '{"ok":false,"error":"src must be an http(s) URL"}')
            auth = self.headers.get("X-Source-Auth", "")
            with LOCK:
                stop_current()
                source = proxy_url(src, auth)
            if path == "/flac":
                return self.stream_flac(source, q.get("start", ""))
            return self.start_ac3(source, int(q.get("track", "0")), q.get("start", ""),
                                  q.get("ch", "6"), q.get("kbps", "640"))
        if path == "/ac3/read":
            return self.read_ac3(q)
        if path == "/ac3/status":
            s = SESSION
            if s.get("id") != q.get("id"):
                return self.reply(404, '{"ok":false}')
            return self.reply(200, json.dumps(status()))
        if path == "/ac3/stop":
            with LOCK:
                stop_current()
            return self.reply(200, '{"ok":true}')
        return self.reply(404, '{"ok":false,"error":"unknown path"}')

    def stream_flac(self, source, start):
        args = ffmpeg_base(start, source) + [
            "-map", "0:a:0", "-af", "aresample=48000:resampler=soxr:precision=28", "-sample_fmt", "s32",
            "-c:a", "flac", "-compression_level", "0", "-frame_size", "4096", "-f", "flac", "pipe:1"]
        proc = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        CURRENT["proc"] = proc
        self.send_response(200)
        self.send_header("Content-Type", "audio/flac")
        self.send_header("Transfer-Encoding", "chunked")
        self.end_headers()
        try:
            while True:
                chunk = proc.stdout.read(65536)
                if not chunk:
                    break
                self.wfile.write(b"%x\r\n%s\r\n" % (len(chunk), chunk))
            self.wfile.write(b"0\r\n\r\n")
        except (BrokenPipeError, ConnectionResetError):
            pass
        finally:
            if proc.poll() is None:
                proc.kill()

    def start_ac3(self, source, track, start, ch="6", kbps="640"):
        sid = secrets.token_hex(6)
        out = os.path.join(WORK, "session.ac3")
        try:
            channels = min(max(int(ch), 1), 6)   # 7.1 and up: folded down to 5.1
        except ValueError:
            channels = 6
        try:
            rate = int(kbps)
        except ValueError:
            rate = 640
        if rate not in AC3_RATES:
            rate = 640
        try:
            os.remove(out)
        except OSError:
            pass
        args = ffmpeg_base(start, source) + [
            "-map", "0:a:%d" % track, "-c:a", "ac3", "-ar", "48000",
            "-ac", str(channels), "-b:a", "%dk" % rate, "-f", "ac3", out]
        proc = subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        CURRENT["proc"] = proc
        SESSION.clear()
        SESSION.update({"id": sid, "file": out, "proc": proc, "began": time.time(), "start": float(start or 0),
                        "kbps": rate})
        return self.reply(200, json.dumps({"ok": True, "id": sid}))

    def read_ac3(self, q):
        s = SESSION
        if not s or s.get("id") != q.get("id"):
            return self.reply(404, '{"ok":false,"error":"no such conversion"}')
        frm = int(q.get("from", "0"))
        most = min(int(q.get("max", "1048576")), 4194304)
        data = b""
        try:
            with open(s["file"], "rb") as f:
                f.seek(frm)
                data = f.read(most)
        except OSError:
            pass
        done = s["proc"].poll() is not None
        size = os.path.getsize(s["file"]) if os.path.exists(s["file"]) else 0
        return self.reply(200, data, "application/octet-stream",
                          {"X-Done": "1" if done else "0", "X-Total": str(size)})


def status():
    s = SESSION
    size = os.path.getsize(s["file"]) if os.path.exists(s["file"]) else 0
    elapsed = max(time.time() - s["began"], 0.001)
    seconds = size / (s.get("kbps", 640) * 125.0)  # bytes of Dolby Digital per second
    return {"ok": True, "bytes": size, "seconds": round(seconds, 1), "elapsed": round(elapsed, 1),
            "speed": round(seconds / elapsed, 2), "done": s["proc"].poll() is not None}


if __name__ == "__main__":
    threading.Thread(target=lambda: ThreadingHTTPServer(("127.0.0.1", PROXY_PORT), Proxy).serve_forever(),
                     daemon=True).start()
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
