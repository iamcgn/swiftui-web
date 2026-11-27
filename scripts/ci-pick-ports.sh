#!/usr/bin/env bash
# Picks the browser job's local server ports and writes them to $GITHUB_ENV as PORT_<usual>.
# Each step's server takes its usual port when nothing answers there, else a free one: on a
# self-hosted runner, servers outside CI (a local checkout's own, say) can hold the usual ports,
# and a step's server then fails to bind and the page 404s its bundle from the other server.
# 8767 stays as it is: the AsyncImage fixture names its URL.
set -euo pipefail
OUT="${GITHUB_ENV:-/dev/stdout}"
python3 - "$@" >> "$OUT" <<'PY'
import socket, sys
taken = []
def answers(port):
    with socket.socket() as s:
        s.settimeout(0.5)
        return s.connect_ex(("127.0.0.1", port)) == 0
for usual in map(int, sys.argv[1:]):
    port = usual
    if answers(usual) or usual in taken:
        with socket.socket() as s:
            s.bind(("127.0.0.1", 0))
            port = s.getsockname()[1]
        print(f"port {usual} is taken; using {port}", file=sys.stderr)
    taken.append(port)
    print(f"PORT_{usual}={port}")
PY
