"""cliproxy-login: sign a Claude or Codex account into CLIProxyAPI on the homelab.

The hub asks for an OAuth URL (management API), this opens it in the browser,
catches the provider's redirect to localhost (Claude 54545, Codex 1455) on
this machine and hands it to the hub, which exchanges the code and stores the
login. Nothing is copied or pasted, and no token ever lands on this machine.

Usage: cliproxy-login claude|codex [--no-browser]
       cliproxy-login list
"""

import http.server
import json
import os
import subprocess
import sys
import threading
import time
import urllib.parse
import urllib.request

HUB = os.environ.get("CLIPROXY_URL", "https://cliproxy.erikfrankling.duckdns.org")
KEY_FILE = os.environ["CLIPROXY_MANAGEMENT_KEY_FILE"]
PROVIDERS = {
    "claude": ("anthropic", "anthropic-auth-url", 54545),
    "codex": ("codex", "codex-auth-url", 1455),
}


def api(method, path, body=None):
    key = open(KEY_FILE).read().strip()
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        HUB + "/v0/management/" + path,
        data=data,
        method=method,
        headers={"Authorization": "Bearer " + key, "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read() or b"{}")


def list_accounts():
    # Only named fields: auth file entries can carry upstream tokens.
    files = api("GET", "auth-files").get("files", [])
    for f in files:
        print(
            "{:<10} {:<34} {:<10} {}".format(
                str(f.get("provider") or f.get("type") or "?"),
                str(f.get("email") or f.get("label") or f.get("name") or "?"),
                str(f.get("status") or ""),
                "disabled" if f.get("disabled") else "",
            )
        )
    if not files:
        print("no accounts signed in")


def login(kind, open_browser):
    provider, endpoint, port = PROVIDERS[kind]
    got = {}
    done = threading.Event()

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            if not self.path.startswith(("/callback", "/auth/callback")):
                self.send_response(404)
                self.end_headers()
                return
            got["url"] = "http://localhost:%d%s" % (port, self.path)
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            self.wfile.write(
                "<h2>Handed to the homelab proxy.</h2><p>You can close this tab; "
                "the terminal says whether it worked.</p>".encode()
            )
            done.set()

        def log_message(self, *a):
            pass

    server = http.server.HTTPServer(("127.0.0.1", port), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()

    start = api("GET", endpoint)
    url, state = start["url"], start["state"]
    print("Sign in to the account you want to add, then click Authorize:\n\n  %s\n" % url)
    if open_browser:
        subprocess.Popen(["xdg-open", url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    if not done.wait(300):
        sys.exit("No redirect within 5 minutes; run it again.")
    server.shutdown()
    api("POST", "oauth-callback", {"provider": provider, "redirect_url": got["url"], "state": state})

    for _ in range(60):
        st = api("GET", "get-auth-status?state=" + urllib.parse.quote(state))
        status = st.get("status")
        if status in ("ok", "success", "completed", "done"):
            print("Signed in.\n")
            list_accounts()
            return
        if status == "error":
            sys.exit("Hub refused the login: %s" % st.get("error"))
        time.sleep(1)
    sys.exit("Hub did not confirm the login; check `cliproxy-login list`.")


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("-")]
    if not args or args[0] not in ("claude", "codex", "list"):
        sys.exit(__doc__)
    if args[0] == "list":
        list_accounts()
    else:
        login(args[0], "--no-browser" not in sys.argv)


main()
