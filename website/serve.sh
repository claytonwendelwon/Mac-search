#!/usr/bin/env bash
# Serve the Beacon marketing site locally.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${PORT:-8080}"
echo "Beacon site → http://localhost:${PORT}"
echo "  Home:   http://localhost:${PORT}/index.html"
echo "  Beacon: http://localhost:${PORT}/beacon/index.html"
cd "$ROOT"
python3 -m http.server "$PORT"
