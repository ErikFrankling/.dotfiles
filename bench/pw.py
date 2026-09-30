import json, subprocess, sys, time, os
env = dict(os.environ, PLAYWRIGHT_MCP_USER_DATA_DIR="/home/erikf/.local/share/agent-desktop/chromium")
p = subprocess.Popen(["/nix/store/v8y774jg8payvvalqn0bnrjh5h857jhq-playwright-mcp-0.0.80/bin/playwright-mcp", "--cdp-endpoint", "http://127.0.0.1:9222", "--output-dir", "/home/erikf/.cache/playwright-mcp", "--caps", "vision"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, env=env)
def send(m): p.stdin.write(json.dumps(m) + "\n"); p.stdin.flush()
def recv(i):
    while True:
        r = json.loads(p.stdout.readline())
        if r.get("id") == i: return r
send({"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"x","version":"0"}}}); recv(1)
send({"jsonrpc":"2.0","method":"notifications/initialized"})
calls = json.load(open(sys.argv[1]))
for i, (n, a) in enumerate(calls, 10):
    send({"jsonrpc":"2.0","id":i,"method":"tools/call","params":{"name":n,"arguments":a}}); r = recv(i)
    print(n, r["result"]["content"][0]["text"][:250].replace("\n"," "), "\n")
p.stdin.close(); p.wait(timeout=10)
