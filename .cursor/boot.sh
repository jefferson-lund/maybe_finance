#!/usr/bin/env bash
# Per-boot entrypoint for the Maybe Cloud Agent environment.
# Starts PostgreSQL and Redis, reconciles the database, then runs the Rails
# development processes (web, css watcher, Sidekiq worker) in the foreground so
# their logs stay attached for the lifetime of the environment.
set -euo pipefail

export PATH="$HOME/.local/share/mise/shims:$HOME/.local/bin:$PATH"

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Start infrastructure and prepare the database (idempotent).
./.cursor/start.sh

echo "== Starting Rails development processes (Procfile.dev) =="
exec bin/dev
