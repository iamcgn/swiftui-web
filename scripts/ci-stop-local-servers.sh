#!/usr/bin/env bash
# Stops the local file and fixture servers an earlier CI job left listening on the browser job's
# ports. A self-hosted runner keeps the machine between jobs, and a server a step started with `&`
# can outlive its job: it then answers on the port in place of this job's own server (whose bind
# fails silently) and 404s the bundle it doesn't have. Only a `python3 -m http.server` or the
# Playwright fixture server whose working directory is under the runner's work directory is
# stopped; anything else on a port is named and left alone.
set -uo pipefail
PORTS="${PORTS:-$(seq 8765 8790)}"
WORK="${RUNNER_WORKSPACE:+$(dirname "$RUNNER_WORKSPACE")}"
if ! command -v lsof >/dev/null 2>&1 || [ -z "$WORK" ]; then echo "no lsof or no runner work directory; nothing to do"; exit 0; fi
for port in $PORTS; do
  for pid in $(lsof -nP -t -iTCP:"$port" -sTCP:LISTEN 2>/dev/null | sort -u); do
    cmd="$(ps -o command= -p "$pid" 2>/dev/null || true)"
    cwd="$(lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -1)"
    case "$cmd" in
      *"-m http.server"*|*"fixture-server.mjs"*) ;;
      *) echo "port $port: leaving pid $pid alone ($cmd)"; continue ;;
    esac
    case "$cwd" in
      "$WORK"/*) kill "$pid" 2>/dev/null && echo "port $port: stopped pid $pid ($cmd, in $cwd)" ;;
      *) echo "port $port: leaving pid $pid alone (not under $WORK: $cwd)" ;;
    esac
  done
done
exit 0
