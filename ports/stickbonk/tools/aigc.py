
import json, sys, time, urllib.request, base64, os

URL = "http://18.143.229.110:8782/mcp"

class MCP:
    def __init__(self):
        self.sid = None
        self.n = 0
        r = self.rpc("initialize", {"protocolVersion": "2025-03-26", "capabilities": {}, "clientInfo": {"name": "dsh", "version": "1"}})
        self.notify("notifications/initialized")

    def _post(self, body):
        h = {"Accept": "application/json, text/event-stream", "Content-Type": "application/json"}
        if self.sid:
            h["Mcp-Session-Id"] = self.sid
        req = urllib.request.Request(URL, data=json.dumps(body).encode(), headers=h, method="POST")
        with urllib.request.urlopen(req, timeout=180) as resp:
            if resp.headers.get("Mcp-Session-Id"):
                self.sid = resp.headers.get("Mcp-Session-Id")
            raw = resp.read().decode("utf-8", "replace")
        if not raw.strip():
            return None
        if raw.lstrip().startswith("{"):
            return json.loads(raw)
        out = None
        for line in raw.splitlines():
            if line.startswith("data:"):
                d = line[5:].strip()
                if d:
                    out = json.loads(d)
        return out

    def rpc(self, method, params):
        self.n += 1
        return self._post({"jsonrpc": "2.0", "id": self.n, "method": method, "params": params})

    def notify(self, method):
        self._post({"jsonrpc": "2.0", "method": method})

    def call(self, name, args):
        r = self.rpc("tools/call", {"name": name, "arguments": args})
        res = r.get("result", r)
        sc = res.get("structuredContent")
        if sc is not None:
            return sc
        txt = "".join(c.get("text", "") for c in res.get("content", []) if c.get("type") == "text")
        try:
            return json.loads(txt)
        except Exception:
            return txt

if __name__ == "__main__":
    m = MCP()
    if sys.argv[1] == "call":
        with open(sys.argv[3], encoding="utf-8") as f:
            args = json.load(f)
        print(json.dumps(m.call(sys.argv[2], args), ensure_ascii=False)[:4000])