"""Copy Erik's Firefox logins into the agent Chromium.

Firefox is the source of truth. Its cookies (persistent ones from
cookies.sqlite, session ones from the session store) are written into the
running agent Chromium over its loopback DevTools port, so agents are logged in
wherever Erik is, without a new sign-in or a phone prompt.

Rules, per site (registrable domain):
- a site is pushed when its Firefox cookies changed since the last sync, or
  when the agent lacks one of them (fresh profile, browser restart, logout);
- a push writes all of the site's Firefox cookies, so a login stays coherent;
- nothing is ever deleted from the agent, so its own logins on sites Firefox
  has no cookies for stay;
- only sites Erik used in Firefox in the last --days (30) are synced: Firefox
  keeps thousands of stale session cookies, and Chromium holds ~3300 cookies in
  total, evicting non-secure ones first when it is over;
- partitioned (third-party) and container cookies are skipped, as are the
  excluded sites (the agent's own LastPass session).

Firefox stores cookies unencrypted, and the agent Chromium encrypts its store
itself (CDP takes plain values), so no keyring is involved. The working copy of
Firefox's database lives in $XDG_RUNTIME_DIR (tmpfs, 0700) and is deleted at
the end. The state file only holds hashes.
"""

import argparse
import configparser
import hashlib
import json
import os
import shutil
import sqlite3
import sys
import tempfile
import time
import urllib.request

import lz4.block
import websocket

SECOND_LEVEL = {"ac", "co", "com", "edu", "gov", "net", "org"}


def site_of(host):
    labels = host.lstrip(".").split(".")
    n = 3 if len(labels) >= 3 and labels[-2] in SECOND_LEVEL and len(labels[-1]) == 2 else 2
    return ".".join(labels[-n:])


def firefox_profile(root):
    ini = configparser.RawConfigParser()
    if not ini.read(os.path.join(root, "profiles.ini")):
        return None
    paths = [ini[s]["Default"] for s in ini.sections() if s.startswith("Install") and "Default" in ini[s]]
    paths += [ini[s]["Path"] for s in ini.sections() if ini[s].get("Default") == "1" and "Path" in ini[s]]
    for p in paths:
        full = p if os.path.isabs(p) else os.path.join(root, p)
        if os.path.exists(os.path.join(full, "cookies.sqlite")):
            return full
    return None


def same_site(v):
    return {0: "None", 1: "Lax", 2: "Strict"}.get(v)


def to_cdp(host, name, value, path, secure, http_only, samesite, expiry_ms):
    c = {"name": name, "value": value, "path": path or "/", "secure": bool(secure), "httpOnly": bool(http_only)}
    if host.startswith("."):
        c["domain"] = host
    else:
        # Host-only cookie: give a URL and no domain.
        c["url"] = ("https://" if secure else "http://") + host + c["path"]
    ss = same_site(samesite)
    if ss and not (ss == "None" and not secure):
        c["sameSite"] = ss
    if expiry_ms:
        c["expires"] = expiry_ms / 1000 if expiry_ms > 1e11 else expiry_ms
    return c


def read_firefox(profile, workdir):
    cookies, used = {}, {}
    # Session cookies (Canvas, Microsoft ESTSAUTH, KTH ADFS) only exist in the
    # session store, which Firefox rewrites every ~15 s.
    store = os.path.join(profile, "sessionstore-backups", "recovery.jsonlz4")
    if os.path.exists(store):
        with open(store, "rb") as f:
            data = f.read()
        if data[:8] == b"mozLz40\0":
            for c in json.loads(lz4.block.decompress(data[8:])).get("cookies", []):
                oa = c.get("originAttributes") or {}
                if oa.get("partitionKey") or oa.get("userContextId") or oa.get("privateBrowsingId"):
                    continue
                host = c.get("host", "")
                cookies[(host, c["name"], c.get("path", "/"))] = to_cdp(
                    host, c["name"], c.get("value", ""), c.get("path", "/"),
                    c.get("secure"), c.get("httponly"), c.get("sameSite"), None,
                )
    # Firefox keeps cookies.sqlite open in WAL mode: read a private copy.
    for suffix in ("", "-wal"):
        src = os.path.join(profile, "cookies.sqlite" + suffix)
        if os.path.exists(src):
            shutil.copyfile(src, os.path.join(workdir, "cookies.sqlite" + suffix))
    db = sqlite3.connect(os.path.join(workdir, "cookies.sqlite"))
    try:
        now_ms = time.time() * 1000
        rows = db.execute(
            "SELECT host, name, value, path, isSecure, isHttpOnly, sameSite, expiry, lastAccessed "
            "FROM moz_cookies WHERE originAttributes = ''"
        ).fetchall()
    finally:
        db.close()
    for host, name, value, path, secure, http_only, samesite, expiry, last in rows:
        site = site_of(host)
        used[site] = max(used.get(site, 0), last / 1e6)
        exp_ms = expiry if expiry > 1e11 else expiry * 1000
        if exp_ms < now_ms:
            continue
        cookies[(host, name, path)] = to_cdp(host, name, value, path, secure, http_only, samesite, expiry)
    return cookies, used


class Cdp:
    def __init__(self, port, wait):
        deadline = time.time() + wait
        while True:
            try:
                with urllib.request.urlopen(f"http://127.0.0.1:{port}/json/version", timeout=3) as r:
                    url = json.load(r)["webSocketDebuggerUrl"]
                break
            except OSError:
                if time.time() > deadline:
                    raise SystemExit(f"agent Chromium is not reachable on 127.0.0.1:{port}")
                time.sleep(1)
        self.ws = websocket.create_connection(url, timeout=30, suppress_origin=True)
        self.next_id = 0

    def call(self, method, **params):
        self.next_id += 1
        self.ws.send(json.dumps({"id": self.next_id, "method": method, "params": params}))
        while True:
            msg = json.loads(self.ws.recv())
            if msg.get("id") == self.next_id:
                if "error" in msg:
                    raise RuntimeError(msg["error"].get("message", msg["error"]))
                return msg.get("result", {})


def digest(cookies):
    h = hashlib.sha256()
    for c in sorted(cookies, key=lambda c: (c.get("domain") or c.get("url"), c["name"], c["path"])):
        h.update(json.dumps(c, sort_keys=True).encode())
    return h.hexdigest()


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--firefox-root", default=os.path.expanduser("~/.mozilla/firefox"))
    ap.add_argument("--port", type=int, default=9222)
    ap.add_argument("--state", default=os.path.join(
        os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state")), "agent-cookie-sync", "state.json"))
    ap.add_argument("--exclude", action="append", default=[], help="site to never sync (repeatable)")
    ap.add_argument("--days", type=int, default=30, help="only sites used in Firefox this recently")
    ap.add_argument("--full", action="store_true", help="push every site, changed or not")
    ap.add_argument("--wait", type=int, default=0, help="seconds to wait for the agent Chromium")
    ap.add_argument("-v", "--verbose", action="store_true", help="list the sites pushed")
    args = ap.parse_args()

    profile = firefox_profile(args.firefox_root)
    if not profile:
        print("no Firefox profile with cookies; nothing to sync")
        return
    runtime = os.environ.get("XDG_RUNTIME_DIR") or None
    workdir = tempfile.mkdtemp(prefix="agent-cookie-sync-", dir=runtime)
    try:
        firefox, used = read_firefox(profile, workdir)
    finally:
        shutil.rmtree(workdir, ignore_errors=True)

    excluded = {s.lower() for s in args.exclude}
    since = time.time() - args.days * 86400
    by_site = {}
    for c in firefox.values():
        host = c.get("domain") or c["url"].split("/")[2]
        site = site_of(host)
        if used.get(site, 0) >= since and site not in excluded and not any(host.lstrip(".").endswith("." + e) for e in excluded):
            by_site.setdefault(site, []).append(c)

    try:
        with open(args.state) as f:
            state = json.load(f)
    except (OSError, ValueError):
        state = {}

    cdp = Cdp(args.port, args.wait)
    agent = {(c["domain"], c["name"], c["path"]) for c in cdp.call("Storage.getCookies").get("cookies", [])}

    pushed, failed, new_state = [], [], {}
    for site, cookies in sorted(by_site.items()):
        h = digest(cookies)
        new_state[site] = h
        missing = any(
            ((c.get("domain") or c["url"].split("/")[2]), c["name"], c["path"]) not in agent for c in cookies
        )
        if not (args.full or missing or state.get(site) != h):
            continue
        try:
            cdp.call("Storage.setCookies", cookies=cookies)
        except RuntimeError:
            # One malformed cookie fails the batch: retry one by one.
            ok = 0
            for c in cookies:
                try:
                    cdp.call("Storage.setCookies", cookies=[c])
                    ok += 1
                except RuntimeError:
                    pass
            if ok < len(cookies):
                failed.append(f"{site} ({len(cookies) - ok})")
                new_state.pop(site)
        pushed.append(site)

    os.makedirs(os.path.dirname(args.state), mode=0o700, exist_ok=True)
    tmp = args.state + ".tmp"
    with open(tmp, "w") as f:
        json.dump(new_state, f)
    os.replace(tmp, args.state)

    print(f"Firefox {os.path.basename(profile)}: {len(firefox)} cookies, {len(by_site)} sites; "
          f"pushed {len(pushed)} sites to the agent Chromium")
    if args.verbose and pushed:
        print("pushed: " + " ".join(pushed))
    if failed:
        print("cookies Chromium rejected: " + ", ".join(failed), file=sys.stderr)


if __name__ == "__main__":
    main()
