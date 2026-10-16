#!/usr/bin/env python3
import sys
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

handler = partial(SimpleHTTPRequestHandler, directory=sys.argv[1])
server = ThreadingHTTPServer(("127.0.0.1", 0), handler)
print(f"READY {server.server_port}", flush=True)
server.serve_forever()
