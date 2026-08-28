#!/usr/bin/env bash
# Per-boot entrypoint for the Maybe Cloud Agent environment.
# Starts PostgreSQL and Redis, reconciles the database, then runs the Rails
# development stack with the Puma web server as the foreground (anchor) process
# and Sidekiq + a Tailwind CSS rebuild loop decoupled in the background.
#
# We deliberately avoid `bin/dev` (foreman) here: foreman terminates every
# process when any one exits, and the Tailwind v4 `--watch` process does not
# stay alive in a detached, TTY-less start context. Decoupling keeps the web
# server and worker running reliably.
set -euo pipefail

export PATH="$HOME/.local/share/mise/shims:$HOME/.local/bin:$PATH"

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Start infrastructure and prepare the database (idempotent).
./.cursor/start.sh

mkdir -p log
export PORT="${PORT:-3000}"

# Build CSS once so the app is styled immediately.
echo "== Building Tailwind CSS =="
bin/rails tailwindcss:build || true

# Sidekiq worker (background).
echo "== Starting Sidekiq worker (background, log/sidekiq.log) =="
bundle exec sidekiq >> log/sidekiq.log 2>&1 &
SIDEKIQ_PID=$!

# Tailwind CSS rebuild loop (background). The standalone v4 watcher does not
# persist without an interactive TTY, so we poll-rebuild instead. A rebuild is
# cheap (~200ms) and keeps styles current as templates change.
echo "== Starting Tailwind CSS rebuild loop (background, log/tailwind.log) =="
(
  while true; do
    bin/rails tailwindcss:build >> log/tailwind.log 2>&1 || true
    sleep 3
  done
) &
CSS_PID=$!

trap 'kill "$SIDEKIQ_PID" "$CSS_PID" 2>/dev/null || true' EXIT INT TERM

# Puma web server (foreground anchor). Keeps this script attached for the life
# of the environment; if it exits, background helpers are cleaned up above.
echo "== Starting Puma web server on 0.0.0.0:$PORT =="
bin/rails server -b 0.0.0.0 -p "$PORT" &
WEB_PID=$!
wait "$WEB_PID"
