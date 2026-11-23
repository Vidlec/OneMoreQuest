import http.server, os, sys, re, importlib.util
ROOT, MODERN, RAW = sys.argv[1], sys.argv[2], sys.argv[3]
src = open(os.path.join(os.path.dirname(__file__), "build2.py")).read()
tables = {}
for name in ("NEW", "KEPT", "CLASSIC"):
    block = re.search(name + r" = \{(.*?)\n\}", src, re.S).group(1)
    tables[name] = dict(re.findall(r'"([^"]+\.png)": "([0-9a-f]{32})"', block))
blob = {}
for name, table in tables.items():
    for path, bid in table.items():
        blob[bid] = os.path.join(MODERN if name == "NEW" else RAW, path)
class H(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **k): super().__init__(*a, directory=ROOT, **k)
    def do_GET(self):
        m = re.match(r"/_blob/([0-9a-f]{32})", self.path)
        if m:
            data = open(blob[m.group(1)], "rb").read()
            self.send_response(200); self.send_header("Content-Type", "image/png"); self.end_headers(); self.wfile.write(data); return
        if self.path.endswith("preview.html"):
            page = open(ROOT + self.path.split("?")[0], encoding="utf-8").read()
            page = page.replace("</head>", '<link rel="stylesheet" href="/project/tokens.css"></head>', 1)
            data = page.encode(); self.send_response(200); self.send_header("Content-Type", "text/html"); self.end_headers(); self.wfile.write(data); return
        super().do_GET()
    def log_message(self, *a): pass
http.server.ThreadingHTTPServer(("127.0.0.1", 8797), H).serve_forever()
